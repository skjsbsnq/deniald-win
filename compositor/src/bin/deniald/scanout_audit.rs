//! Observe-only producer attribution and Direct Scanout qualification.
//!
//! This module deliberately contains no DRM/KMS handles and no side effects.
//! It is safe to run in the compositor's audit path without changing scene
//! selection, scheduler cadence, or plane state.

use std::collections::BTreeSet;
use std::sync::{Mutex, OnceLock};
use std::time::{Duration, Instant};

use tracing::info;

use super::render_audit_enabled;

#[derive(Clone, Copy, Debug, Eq, Ord, PartialEq, PartialOrd)]
pub(super) enum EligibilityReason {
    VisibleSampled,
    VisibleNotSampledYet,
    FullyOccluded,
    Minimized,
    PreviewConsumer,
    CaptureConsumer,
    ShellEffectConsumer,
    PopupOrSubsurface,
    NotImportable,
    SizeOrTransformMismatch,
    AlphaOrColorMismatch,
    SyncUnknown,
    MultipleSurfaces,
    NoDamage,
}

impl EligibilityReason {
    pub(super) const fn code(self) -> &'static str {
        match self {
            Self::VisibleSampled => "visible_sampled",
            Self::VisibleNotSampledYet => "visible_not_sampled_yet",
            Self::FullyOccluded => "fully_occluded",
            Self::Minimized => "minimized",
            Self::PreviewConsumer => "preview_consumer",
            Self::CaptureConsumer => "capture_consumer",
            Self::ShellEffectConsumer => "shell_effect_consumer",
            Self::PopupOrSubsurface => "popup_or_subsurface",
            Self::NotImportable => "not_importable",
            Self::SizeOrTransformMismatch => "size_or_transform_mismatch",
            Self::AlphaOrColorMismatch => "alpha_or_color_mismatch",
            Self::SyncUnknown => "sync_unknown",
            Self::MultipleSurfaces => "multiple_surfaces",
            Self::NoDamage => "no_damage",
        }
    }
}

#[derive(Clone, Copy, Debug, Default)]
pub(super) struct EligibilitySnapshot {
    pub(super) visible: bool,
    pub(super) sampled: bool,
    pub(super) minimized: bool,
    pub(super) preview_consumer: bool,
    pub(super) capture_consumer: bool,
    pub(super) shell_effect_consumer: bool,
    pub(super) has_popup_or_subsurface: bool,
    pub(super) importable: bool,
    pub(super) exact_geometry: bool,
    pub(super) opaque_and_color_compatible: bool,
    pub(super) sync_proven: bool,
    pub(super) input_visibility_epoch: Option<u64>,
    pub(super) certificate_epoch: Option<u64>,
    pub(super) single_root_surface: bool,
    pub(super) has_damage: bool,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(super) struct EligibilityReport {
    pub(super) eligible: bool,
    pub(super) reasons: Vec<&'static str>,
}

pub(super) struct EligibilityContext<'a> {
    pub(super) output_id: u64,
    pub(super) window_id: u64,
    pub(super) root_surface_id: u64,
    pub(super) buffer_revision: u64,
    pub(super) format: &'a str,
    pub(super) modifier: &'a str,
    pub(super) source_rect: (f64, f64),
    pub(super) destination_rect: (f64, f64),
    pub(super) opacity: f32,
    pub(super) visibility_epoch: Option<u64>,
    pub(super) certificate_epoch: Option<u64>,
}

#[cfg(test)]
#[derive(Debug)]
pub(super) struct AuditWindow {
    events: u64,
    dropped_samples: u64,
    samples: Vec<String>,
}

#[cfg(test)]
impl AuditWindow {
    pub(super) fn new() -> Self {
        Self {
            events: 0,
            dropped_samples: 0,
            samples: Vec::with_capacity(16),
        }
    }

    pub(super) fn record(&mut self, sample: impl Into<String>) {
        self.events = self.events.saturating_add(1);
        if self.samples.len() < 16 {
            self.samples.push(sample.into());
        } else {
            self.dropped_samples = self.dropped_samples.saturating_add(1);
        }
    }
}

pub(super) fn evaluate(snapshot: EligibilitySnapshot) -> EligibilityReport {
    let certificate_current = snapshot
        .input_visibility_epoch
        .zip(snapshot.certificate_epoch)
        .is_some_and(|(visibility, certificate)| visibility == certificate);
    let mut reasons = BTreeSet::new();
    if snapshot.visible && snapshot.sampled {
        reasons.insert(EligibilityReason::VisibleSampled);
    } else if snapshot.visible {
        reasons.insert(EligibilityReason::VisibleNotSampledYet);
    } else {
        reasons.insert(EligibilityReason::FullyOccluded);
    }
    if snapshot.minimized {
        reasons.insert(EligibilityReason::Minimized);
    }
    if snapshot.preview_consumer {
        reasons.insert(EligibilityReason::PreviewConsumer);
    }
    if snapshot.capture_consumer {
        reasons.insert(EligibilityReason::CaptureConsumer);
    }
    if snapshot.shell_effect_consumer {
        reasons.insert(EligibilityReason::ShellEffectConsumer);
    }
    if snapshot.has_popup_or_subsurface {
        reasons.insert(EligibilityReason::PopupOrSubsurface);
    }
    if !snapshot.importable {
        reasons.insert(EligibilityReason::NotImportable);
    }
    if !snapshot.exact_geometry {
        reasons.insert(EligibilityReason::SizeOrTransformMismatch);
    }
    if !snapshot.opaque_and_color_compatible {
        reasons.insert(EligibilityReason::AlphaOrColorMismatch);
    }
    if !snapshot.sync_proven || !certificate_current {
        reasons.insert(EligibilityReason::SyncUnknown);
    }
    if !snapshot.single_root_surface {
        reasons.insert(EligibilityReason::MultipleSurfaces);
    }
    if !snapshot.has_damage {
        reasons.insert(EligibilityReason::NoDamage);
    }

    let eligible = snapshot.visible
        && snapshot.sampled
        && !snapshot.minimized
        && !snapshot.preview_consumer
        && !snapshot.capture_consumer
        && !snapshot.shell_effect_consumer
        && !snapshot.has_popup_or_subsurface
        && snapshot.importable
        && snapshot.exact_geometry
        && snapshot.opaque_and_color_compatible
        && snapshot.sync_proven
        && certificate_current
        && snapshot.single_root_surface;
    EligibilityReport {
        eligible,
        reasons: reasons.into_iter().map(EligibilityReason::code).collect(),
    }
}

#[derive(Debug)]
struct ProducerAudit {
    interval_started: Instant,
    commits: u64,
    visual_updates: u64,
    damage_commits: u64,
    callback_commits: u64,
    buffer_updates: u64,
    texture_updates: u64,
    texture_queued: u64,
    texture_not_sampled: u64,
    flutter_schedules: u64,
    flutter_texture_ids: u64,
    frame_callbacks: u64,
    callback_suppressed: u64,
    eligibility_reports: u64,
    eligible: u64,
    reason_counts: [u64; 14],
    samples: Vec<String>,
}

impl Default for ProducerAudit {
    fn default() -> Self {
        Self {
            interval_started: Instant::now(),
            commits: 0,
            visual_updates: 0,
            damage_commits: 0,
            callback_commits: 0,
            buffer_updates: 0,
            texture_updates: 0,
            texture_queued: 0,
            texture_not_sampled: 0,
            flutter_schedules: 0,
            flutter_texture_ids: 0,
            frame_callbacks: 0,
            callback_suppressed: 0,
            eligibility_reports: 0,
            eligible: 0,
            reason_counts: [0; 14],
            samples: Vec::with_capacity(16),
        }
    }
}

static PRODUCER_AUDIT: OnceLock<Mutex<ProducerAudit>> = OnceLock::new();

fn with_audit(mut update: impl FnMut(&mut ProducerAudit)) {
    if !render_audit_enabled() {
        return;
    }
    let audit = PRODUCER_AUDIT.get_or_init(|| Mutex::new(ProducerAudit::default()));
    let mut audit = audit
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    update(&mut audit);
    if audit.interval_started.elapsed() < Duration::from_secs(1) {
        return;
    }
    let elapsed = audit.interval_started.elapsed();
    info!(
        target: "deniald::render_audit",
        source = "producer_attribution",
        interval_ms = elapsed.as_secs_f64() * 1_000.0,
        commits = audit.commits,
        visual_updates = audit.visual_updates,
        damage_commits = audit.damage_commits,
        callback_commits = audit.callback_commits,
        buffer_updates = audit.buffer_updates,
        texture_updates = audit.texture_updates,
        texture_queued = audit.texture_queued,
        texture_not_sampled = audit.texture_not_sampled,
        flutter_schedules = audit.flutter_schedules,
        flutter_texture_ids = audit.flutter_texture_ids,
        frame_callbacks = audit.frame_callbacks,
        callback_suppressed = audit.callback_suppressed,
        eligibility_reports = audit.eligibility_reports,
        eligible = audit.eligible,
        reason_counts = ?audit.reason_counts,
        samples = ?audit.samples,
        "Wayland producer attribution audit"
    );
    *audit = ProducerAudit::default();
}

fn sample(audit: &mut ProducerAudit, value: String) {
    if audit.samples.len() < 16 {
        audit.samples.push(value);
    }
}

pub(super) fn record_surface_commit(
    surface_id: Option<u64>,
    root_id: Option<u64>,
    visual_update: bool,
    has_damage: bool,
    has_frame_callbacks: bool,
    buffer_update: bool,
) {
    with_audit(|audit| {
        audit.commits = audit.commits.saturating_add(1);
        audit.visual_updates += u64::from(visual_update);
        audit.damage_commits += u64::from(has_damage);
        audit.callback_commits += u64::from(has_frame_callbacks);
        audit.buffer_updates += u64::from(buffer_update);
        sample(
            audit,
            format!(
                "commit surface={:?} root={:?} visual={} damage={} callbacks={} buffer={}",
                surface_id, root_id, visual_update, has_damage, has_frame_callbacks, buffer_update
            ),
        );
    });
}

pub(super) fn record_texture_update(
    texture_id: i64,
    revision: u64,
    expects_sample: bool,
    queued: bool,
) {
    with_audit(|audit| {
        audit.texture_updates = audit.texture_updates.saturating_add(1);
        audit.texture_queued += u64::from(queued);
        audit.texture_not_sampled += u64::from(!expects_sample);
        sample(
            audit,
            format!(
                "texture id={} revision={} expects_sample={} queued={}",
                texture_id, revision, expects_sample, queued
            ),
        );
    });
}

pub(super) fn record_flutter_schedule(texture_ids: usize) {
    with_audit(|audit| {
        audit.flutter_schedules = audit.flutter_schedules.saturating_add(1);
        audit.flutter_texture_ids = audit.flutter_texture_ids.saturating_add(texture_ids as u64);
    });
}

pub(super) fn record_frame_callbacks(output_id: u64, window_id: Option<u64>, sent: usize) {
    with_audit(|audit| {
        audit.frame_callbacks = audit.frame_callbacks.saturating_add(sent as u64);
        if sent > 0 {
            sample(
                audit,
                format!(
                    "frame_callbacks output={} window={:?} sent={}",
                    output_id, window_id, sent
                ),
            );
        }
    });
}

pub(super) fn record_frame_callback_suppressed(
    output_id: u64,
    window_id: Option<u64>,
    reason: &'static str,
    visibility_epoch: Option<u64>,
) {
    with_audit(|audit| {
        audit.callback_suppressed = audit.callback_suppressed.saturating_add(1);
        sample(
            audit,
            format!(
                "frame_callbacks_suppressed output={} window={:?} reason={} epoch={:?}",
                output_id, window_id, reason, visibility_epoch
            ),
        );
    });
}

pub(super) fn record_eligibility(context: EligibilityContext<'_>, report: &EligibilityReport) {
    with_audit(|audit| {
        audit.eligibility_reports = audit.eligibility_reports.saturating_add(1);
        audit.eligible += u64::from(report.eligible);
        for reason in &report.reasons {
            if let Some(index) = [
                "visible_sampled",
                "visible_not_sampled_yet",
                "fully_occluded",
                "minimized",
                "preview_consumer",
                "capture_consumer",
                "shell_effect_consumer",
                "popup_or_subsurface",
                "not_importable",
                "size_or_transform_mismatch",
                "alpha_or_color_mismatch",
                "sync_unknown",
                "multiple_surfaces",
                "no_damage",
            ]
            .iter()
            .position(|candidate| candidate == reason)
            {
                audit.reason_counts[index] = audit.reason_counts[index].saturating_add(1);
            }
        }
        sample(
            audit,
            format!(
                "eligibility output={} window={} root={} revision={} format={} modifier={} src={}x{} dst={}x{} opacity={} visibility_epoch={:?} certificate_epoch={:?} eligible={} reasons={:?}",
                context.output_id,
                context.window_id,
                context.root_surface_id,
                context.buffer_revision,
                context.format,
                context.modifier,
                context.source_rect.0,
                context.source_rect.1,
                context.destination_rect.0,
                context.destination_rect.1,
                context.opacity,
                context.visibility_epoch,
                context.certificate_epoch,
                report.eligible,
                report.reasons
            ),
        );
    });
}

pub(super) fn record_certificate(
    output_id: i64,
    certificate_epoch: u64,
    layout_epoch: u64,
    root_surface_id: u64,
    requires_sampling: bool,
    accepted: bool,
    reason: &'static str,
) {
    with_audit(|audit| {
        sample(
            audit,
            format!(
                "certificate output={} epoch={} layout_epoch={} root={} requires_sampling={} accepted={} reason={}",
                output_id,
                certificate_epoch,
                layout_epoch,
                root_surface_id,
                requires_sampling,
                accepted,
                reason,
            ),
        );
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    fn eligible() -> EligibilitySnapshot {
        EligibilitySnapshot {
            visible: true,
            sampled: true,
            importable: true,
            exact_geometry: true,
            opaque_and_color_compatible: true,
            sync_proven: true,
            input_visibility_epoch: Some(7),
            certificate_epoch: Some(7),
            single_root_surface: true,
            has_damage: true,
            ..EligibilitySnapshot::default()
        }
    }

    #[test]
    fn independent_failures_are_all_reported_in_stable_order() {
        let mut snapshot = eligible();
        snapshot.importable = false;
        snapshot.exact_geometry = false;
        snapshot.sync_proven = false;
        snapshot.opaque_and_color_compatible = false;
        snapshot.has_popup_or_subsurface = true;
        let report = evaluate(snapshot);
        assert!(!report.eligible);
        assert_eq!(
            report.reasons,
            vec![
                "visible_sampled",
                "popup_or_subsurface",
                "not_importable",
                "size_or_transform_mismatch",
                "alpha_or_color_mismatch",
                "sync_unknown",
            ]
        );
    }

    #[test]
    fn preview_and_capture_never_qualify() {
        let mut snapshot = eligible();
        snapshot.preview_consumer = true;
        snapshot.capture_consumer = true;
        let report = evaluate(snapshot);
        assert!(!report.eligible);
        assert!(report.reasons.contains(&"preview_consumer"));
        assert!(report.reasons.contains(&"capture_consumer"));
    }

    #[test]
    fn stale_visibility_epoch_cannot_qualify() {
        let mut snapshot = eligible();
        snapshot.certificate_epoch = Some(6);
        let report = evaluate(snapshot);
        assert!(!report.eligible);
        assert!(report.reasons.contains(&"sync_unknown"));
    }

    #[test]
    fn audit_window_keeps_total_and_limits_samples() {
        let mut audit = AuditWindow::new();
        for index in 0..32 {
            audit.record(format!("sample-{index}"));
        }
        assert_eq!(audit.events, 32);
        assert_eq!(audit.samples.len(), 16);
        assert_eq!(audit.dropped_samples, 16);
    }
}
