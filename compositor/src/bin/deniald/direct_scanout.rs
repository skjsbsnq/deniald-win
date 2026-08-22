//! P8-07 primary-plane promotion policy.
//!
//! The policy is intentionally independent from Smithay objects.  KMS owns
//! the actual framebuffer import and atomic ioctl, while this module owns the
//! safety contract: the experiment is opt-in, candidates are exact fullscreen
//! opaque DMA-BUF roots, every new arrangement is tested before commit, and a
//! failed probe can only return to composition.

use super::kms_state::PrimeFramebuffer;
use super::wire::CompositionCertificate;
use smithay::backend::allocator::dmabuf::Dmabuf;
use smithay::backend::renderer::utils::Buffer as RendererBufferGuard;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(super) enum PromotionState {
    Composed,
    Armed,
    Promoted,
    Fallback,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(super) enum RejectReason {
    FeatureDisabled,
    MultipleOutputs,
    MissingCertificate,
    StaleCertificate,
    NotOpaque,
    ShellVisible,
    ClientSamplingRequired,
    PopupOrSubsurface,
    UnsupportedTransform,
    SizeMismatch,
    NotDmaBuf,
    SyncUnknown,
    TestOnlyFailed,
}

impl RejectReason {
    pub(super) const fn code(self) -> &'static str {
        match self {
            Self::FeatureDisabled => "feature_disabled",
            Self::MultipleOutputs => "multiple_outputs",
            Self::MissingCertificate => "missing_certificate",
            Self::StaleCertificate => "stale_certificate",
            Self::NotOpaque => "not_opaque",
            Self::ShellVisible => "shell_visible",
            Self::ClientSamplingRequired => "client_sampling_required",
            Self::PopupOrSubsurface => "popup_or_subsurface",
            Self::UnsupportedTransform => "unsupported_transform",
            Self::SizeMismatch => "size_mismatch",
            Self::NotDmaBuf => "not_dmabuf",
            Self::SyncUnknown => "sync_unknown",
            Self::TestOnlyFailed => "test_only_failed",
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(super) struct CandidateGeometry {
    pub(super) output_width: u32,
    pub(super) output_height: u32,
    pub(super) source_width: u32,
    pub(super) source_height: u32,
    pub(super) destination_width: u32,
    pub(super) destination_height: u32,
    pub(super) transform: u32,
}

#[derive(Clone, Copy, Debug)]
pub(super) struct CandidateMetadata<'a> {
    pub(super) single_output: bool,
    pub(super) dma_buf: bool,
    pub(super) sync_proven: bool,
    pub(super) certificate_epoch: u64,
    pub(super) visibility_epoch: u64,
    pub(super) certificate: Option<&'a CompositionCertificate>,
    pub(super) geometry: CandidateGeometry,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(super) struct PromotionDecision {
    pub(super) state: PromotionState,
    pub(super) reason: Option<RejectReason>,
}

#[derive(Clone, Copy, Debug)]
pub(super) struct PromotionController {
    enabled: bool,
    state: PromotionState,
    last_certificate_epoch: u64,
    last_surface_revision: u64,
}

pub(super) struct DirectPromotion {
    pub(super) framebuffer: PrimeFramebuffer,
    pub(super) dmabuf: Dmabuf,
    pub(super) buffer_guard: RendererBufferGuard,
    pub(super) output: u64,
    pub(super) surface: u64,
    pub(super) revision: u64,
    pub(super) certificate_epoch: u64,
    pub(super) confirmed: bool,
    pub(super) fallback_pending: bool,
}

impl Default for PromotionController {
    fn default() -> Self {
        Self::new(false)
    }
}

impl PromotionController {
    pub(super) const fn new(enabled: bool) -> Self {
        Self {
            enabled,
            state: PromotionState::Composed,
            last_certificate_epoch: 0,
            last_surface_revision: 0,
        }
    }

    pub(super) const fn enabled(self) -> bool {
        self.enabled
    }

    pub(super) const fn state(self) -> PromotionState {
        self.state
    }

    pub(super) fn eligibility(
        &self,
        candidate: CandidateMetadata<'_>,
        surface_revision: u64,
    ) -> PromotionDecision {
        if !self.enabled {
            return self.reject(RejectReason::FeatureDisabled);
        }
        if !candidate.single_output {
            return self.reject(RejectReason::MultipleOutputs);
        }
        let Some(certificate) = candidate.certificate else {
            return self.reject(RejectReason::MissingCertificate);
        };
        if candidate.certificate_epoch == 0
            || candidate.certificate_epoch != candidate.visibility_epoch
            || certificate.certificate_epoch != candidate.certificate_epoch
            || certificate.buffer_revision == 0
            || surface_revision != certificate.buffer_revision
        {
            return self.reject(RejectReason::StaleCertificate);
        }
        if !certificate.known_opaque {
            return self.reject(RejectReason::NotOpaque);
        }
        if !certificate.shell_fully_transparent {
            return self.reject(RejectReason::ShellVisible);
        }
        if certificate.requires_client_sampling {
            return self.reject(RejectReason::ClientSamplingRequired);
        }
        if certificate.has_popup
            || certificate.has_subsurface
            || certificate.has_drag_icon
            || certificate.has_ime
            || certificate.has_preview
            || certificate.has_capture
            || certificate.has_effect
        {
            return self.reject(RejectReason::PopupOrSubsurface);
        }
        let geometry = candidate.geometry;
        if geometry.transform != 0
            || geometry.source_width != geometry.output_width
            || geometry.source_height != geometry.output_height
            || geometry.destination_width != geometry.output_width
            || geometry.destination_height != geometry.output_height
        {
            return self.reject(if geometry.transform != 0 {
                RejectReason::UnsupportedTransform
            } else {
                RejectReason::SizeMismatch
            });
        }
        if !candidate.dma_buf {
            return self.reject(RejectReason::NotDmaBuf);
        }
        if !candidate.sync_proven {
            return self.reject(RejectReason::SyncUnknown);
        }
        PromotionDecision {
            state: PromotionState::Armed,
            reason: None,
        }
    }

    pub(super) fn test_only_result(&mut self, passed: bool) -> PromotionDecision {
        if !passed {
            return self.reject(RejectReason::TestOnlyFailed);
        }
        self.state = PromotionState::Armed;
        PromotionDecision {
            state: self.state,
            reason: None,
        }
    }

    pub(super) fn real_commit_result(
        &mut self,
        committed: bool,
        certificate_epoch: u64,
        surface_revision: u64,
    ) -> PromotionDecision {
        if !committed {
            return self.reject(RejectReason::TestOnlyFailed);
        }
        self.state = PromotionState::Promoted;
        self.last_certificate_epoch = certificate_epoch;
        self.last_surface_revision = surface_revision;
        PromotionDecision {
            state: self.state,
            reason: None,
        }
    }

    pub(super) fn fallback(&mut self) -> PromotionDecision {
        self.state = PromotionState::Fallback;
        PromotionDecision {
            state: self.state,
            reason: None,
        }
    }

    pub(super) fn compose(&mut self) -> PromotionDecision {
        self.state = PromotionState::Composed;
        PromotionDecision {
            state: self.state,
            reason: None,
        }
    }

    fn reject(&self, reason: RejectReason) -> PromotionDecision {
        PromotionDecision {
            state: PromotionState::Composed,
            reason: Some(reason),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn certificate() -> CompositionCertificate {
        CompositionCertificate {
            certificate_epoch: 7,
            layout_epoch: 7,
            output_id: 1,
            output_configuration_epoch: 2,
            sole_root_surface_id: 11,
            surface_tree_revision: 3,
            buffer_revision: 9,
            source_rect: super::super::wire::InputRect {
                x: 0.0,
                y: 0.0,
                width: 1920.0,
                height: 1080.0,
            },
            destination_rect: super::super::wire::InputRect {
                x: 0.0,
                y: 0.0,
                width: 1920.0,
                height: 1080.0,
            },
            output_pixel_size: (1920.0, 1080.0),
            scale: 1.0,
            transform: 0,
            known_opaque: true,
            shell_fully_transparent: true,
            requires_client_sampling: false,
            has_popup: false,
            has_subsurface: false,
            has_drag_icon: false,
            has_ime: false,
            has_preview: false,
            has_capture: false,
            has_effect: false,
            color_class: super::super::wire::CompositionColorClass::SdrCompatible,
            reason_flags: 0,
            engine_generation: 1,
        }
    }

    fn candidate(cert: &'static CompositionCertificate) -> CandidateMetadata {
        CandidateMetadata {
            single_output: true,
            dma_buf: true,
            sync_proven: true,
            certificate_epoch: 7,
            visibility_epoch: 7,
            certificate: Some(cert),
            geometry: CandidateGeometry {
                output_width: 1920,
                output_height: 1080,
                source_width: 1920,
                source_height: 1080,
                destination_width: 1920,
                destination_height: 1080,
                transform: 0,
            },
        }
    }

    #[test]
    fn feature_is_disabled_by_default_and_never_commits() {
        let controller = PromotionController::new(false);
        let cert = Box::leak(Box::new(certificate()));
        assert_eq!(
            controller.eligibility(candidate(cert), 9).reason,
            Some(RejectReason::FeatureDisabled)
        );
        assert_eq!(controller.state(), PromotionState::Composed);
    }

    #[test]
    fn exact_candidate_requires_test_only_before_promotion() {
        let mut controller = PromotionController::new(true);
        let cert = Box::leak(Box::new(certificate()));
        assert_eq!(
            controller.eligibility(candidate(cert), 9).state,
            PromotionState::Armed
        );
        assert_eq!(
            controller.test_only_result(false).reason,
            Some(RejectReason::TestOnlyFailed)
        );
        assert_eq!(controller.state(), PromotionState::Composed);
        assert_eq!(
            controller.test_only_result(true).state,
            PromotionState::Armed
        );
        assert_eq!(
            controller.real_commit_result(true, 7, 9).state,
            PromotionState::Promoted
        );
    }

    #[test]
    fn all_non_minimal_inputs_are_rejected() {
        let cert = Box::leak(Box::new(certificate()));
        for mutate in [
            |c: &mut CandidateMetadata| c.dma_buf = false,
            |c: &mut CandidateMetadata| c.sync_proven = false,
            |c: &mut CandidateMetadata| c.geometry.destination_width = 1919,
            |c: &mut CandidateMetadata| c.geometry.transform = 1,
            |c: &mut CandidateMetadata| c.single_output = false,
        ] {
            let mut c = candidate(cert);
            mutate(&mut c);
            assert!(
                PromotionController::new(true)
                    .eligibility(c, 9)
                    .reason
                    .is_some()
            );
        }
    }

    #[test]
    fn stale_certificate_and_client_sampling_are_rejected() {
        let cert = Box::leak(Box::new(certificate()));
        let mut stale = candidate(cert);
        stale.visibility_epoch = 8;
        assert_eq!(
            PromotionController::new(true).eligibility(stale, 9).reason,
            Some(RejectReason::StaleCertificate)
        );
        let mut sampled = candidate(cert);
        sampled.certificate = Some(Box::leak(Box::new(CompositionCertificate {
            requires_client_sampling: true,
            ..(*cert).clone()
        })));
        assert_eq!(
            PromotionController::new(true)
                .eligibility(sampled, 9)
                .reason,
            Some(RejectReason::ClientSamplingRequired)
        );
    }
}
