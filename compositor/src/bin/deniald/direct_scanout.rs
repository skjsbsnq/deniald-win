//! P8-08 seamless entry and fallback state machine.
//!
//! P8-07 proved one minimal promotion path with success booleans threaded
//! through the runtime.  P8-08 owns the full per-output contract
//!
//! ```text
//! Composed -> Armed -> Promoted -> FallbackArmed -> Composed
//! ```
//!
//! and requires every asynchronous event, KMS error and timeout to converge on
//! a known-good composed scene without restarting the compositor.
//!
//! The reducer below never touches DRM, Smithay or Flutter.  It consumes one
//! event plus the current state and returns the next state together with the
//! explicit actions the caller must perform.  Keeping the decision logic free
//! of I/O is what makes the transition and fault matrix in the tests
//! meaningful: every state, trigger, timeout and backoff path is exercised
//! without a GPU.  It is also why the state is a single enum rather than a set
//! of `Option` and `bool` fields: an unrepresentable combination cannot be
//! reached by a caller that forgets one flag.

use std::collections::BTreeMap;
use std::time::{Duration, Instant};

use super::kms_state::PrimeFramebuffer;
use super::wire::CompositionCertificate;
use smithay::backend::allocator::dmabuf::Dmabuf;
use smithay::backend::renderer::utils::Buffer as RendererBufferGuard;
use smithay::utils::{Buffer, Physical, Rectangle, Transform};

/// Bounded step deadlines.  Every asynchronous step owns one so a stuck
/// import, fence, probe, commit, flip or fallback render cannot park an output
/// in a non-composed state forever.
const IMPORT_TIMEOUT: Duration = Duration::from_millis(200);
const FENCE_TIMEOUT: Duration = Duration::from_millis(120);
const TEST_ONLY_TIMEOUT: Duration = Duration::from_millis(120);
const VERIFY_TIMEOUT: Duration = Duration::from_millis(120);
const COMMIT_TIMEOUT: Duration = Duration::from_millis(120);
const ENTRY_FLIP_TIMEOUT: Duration = Duration::from_millis(400);
const FALLBACK_SAMPLE_TIMEOUT: Duration = Duration::from_millis(300);
const FALLBACK_HANDBACK_TIMEOUT: Duration = Duration::from_millis(300);
const FALLBACK_FLIP_TIMEOUT: Duration = Duration::from_millis(400);

/// Repeated failures of the same arrangement back off exponentially instead of
/// retrying every frame.
const BACKOFF_BASE: Duration = Duration::from_millis(250);
const BACKOFF_MAX: Duration = Duration::from_secs(8);

/// After this many failed fallback preparations the output keeps composition
/// and permanently disables promotion until its configuration epoch changes.
const MAX_FALLBACK_ATTEMPTS: u32 = 3;

/// Actions emitted for a single event.  Five is the widest transition
/// (fallback entry and threshold handling); the list is fixed capacity so the
/// reducer performs no allocation on the render path.
const MAX_ACTIONS: usize = 5;

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
    /// The real commit was rejected after its own `TEST_ONLY` passed, so the
    /// probe result for this output can no longer be trusted.
    CommitInvalid,
    /// A commit was accepted but its page flip never arrived.
    PageFlipLost,
    /// Fallback preparation stalled repeatedly.
    FallbackRenderFailed,
    PromotionDisabled,
    BackoffActive,
    AwaitingAtlasSettle,
    /// A native screencopy or screenshot request is outstanding for this
    /// output. Capture is a visual consumer and outranks promotion (C1 §C1).
    CaptureActive,
    /// A cursor is visible and not owned by a hardware cursor plane, so the
    /// shell still has pixels to compose (C1 §K8).
    CursorVisible,
    /// The output has no active KMS pipeline, for example while DPMS-off.
    OutputUnpowered,
    /// A source rectangle cannot be represented by the DRM 16.16 fields or
    /// falls outside the imported client buffer.
    InvalidPlaneGeometry,
    /// Connector colorspace or HDR metadata cannot be preserved by the
    /// current per-plane color contract.
    ColorIncompatible,
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
            Self::CommitInvalid => "commit_invalid",
            Self::PageFlipLost => "page_flip_lost",
            Self::FallbackRenderFailed => "fallback_render_failed",
            Self::PromotionDisabled => "promotion_disabled",
            Self::BackoffActive => "backoff_active",
            Self::AwaitingAtlasSettle => "awaiting_atlas_settle",
            Self::CaptureActive => "capture_active",
            Self::CursorVisible => "cursor_visible",
            Self::OutputUnpowered => "output_unpowered",
            Self::InvalidPlaneGeometry => "invalid_plane_geometry",
            Self::ColorIncompatible => "color_incompatible",
        }
    }
}

/// Why a promoted client primary must return to composition.  The cause is
/// carried through the fallback so logs and audit records name the trigger
/// rather than reporting an anonymous state change.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(super) enum InvalidationCause {
    CertificateRevoked,
    EpochChanged,
    ShellOverlayVisible,
    CaptureRequested,
    CursorVisible,
    ColorPolicyChanged,
    BufferConfigurationChanged,
    OutputConfigurationChanged,
    ClientGone,
    FlutterEngineReplaced,
    SessionSuspended,
    ImportFailed,
    FenceTimeout,
    TestOnlyFailed,
    /// The CRTC already owned an in-flight request. The arrangement is still
    /// valid; only this attempt was too early.
    CommitBusy,
    /// KMS rejected an arrangement its own `TEST_ONLY` had accepted.
    CommitFailed,
    PageFlipLost,
}

impl InvalidationCause {
    pub(super) const fn code(self) -> &'static str {
        match self {
            Self::CertificateRevoked => "certificate_revoked",
            Self::EpochChanged => "epoch_changed",
            Self::ShellOverlayVisible => "shell_overlay_visible",
            Self::CaptureRequested => "capture_requested",
            Self::CursorVisible => "cursor_visible",
            Self::ColorPolicyChanged => "color_policy_changed",
            Self::BufferConfigurationChanged => "buffer_configuration_changed",
            Self::OutputConfigurationChanged => "output_configuration_changed",
            Self::ClientGone => "client_gone",
            Self::FlutterEngineReplaced => "flutter_engine_replaced",
            Self::SessionSuspended => "session_suspended",
            Self::ImportFailed => "import_failed",
            Self::FenceTimeout => "fence_timeout",
            Self::TestOnlyFailed => "test_only_failed",
            Self::CommitBusy => "commit_busy",
            Self::CommitFailed => "commit_failed",
            Self::PageFlipLost => "page_flip_lost",
        }
    }

    /// A cause that describes a broken arrangement rather than a scene change
    /// must also arm the failure backoff.
    const fn is_fault(self) -> bool {
        matches!(
            self,
            Self::ImportFailed
                | Self::FenceTimeout
                | Self::TestOnlyFailed
                | Self::CommitBusy
                | Self::CommitFailed
                | Self::PageFlipLost
        )
    }
}

/// The identity a promotion is bound to.  Any change in these fields makes the
/// prepared arrangement stale, so the state machine re-validates from
/// `Composed` instead of committing a candidate that no longer describes the
/// scene.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(super) struct CandidateKey {
    pub(super) output: u64,
    pub(super) surface: u64,
    pub(super) revision: u64,
    pub(super) certificate_epoch: u64,
    /// Mode, scale, transform, VRR and connector generation of the output.
    pub(super) output_epoch: u64,
    /// Format, modifier and pixel size fingerprint of the client buffer.
    pub(super) buffer_epoch: u64,
}

impl CandidateKey {
    /// A buffer replacement keeps the whole arrangement and only advances the
    /// client revision.  The certificate epoch moves with every publication and
    /// is therefore not part of the arrangement identity.
    const fn replaces(self, active: Self) -> bool {
        self.output == active.output
            && self.surface == active.surface
            && self.output_epoch == active.output_epoch
            && self.buffer_epoch == active.buffer_epoch
            && self.revision > active.revision
    }

    /// The KMS arrangement fingerprint.  A cached `TEST_ONLY` result and a
    /// failure backoff apply to this tuple, never to a single revision.
    const fn arrangement(self) -> (u64, u64, u64, u64) {
        (
            self.output,
            self.surface,
            self.output_epoch,
            self.buffer_epoch,
        )
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(super) enum TimeoutStep {
    Import,
    Fence,
    TestOnly,
    Verify,
    Commit,
    EntryFlip,
    FallbackSample,
    FallbackHandback,
    FallbackFlip,
}

impl TimeoutStep {
    pub(super) const fn code(self) -> &'static str {
        match self {
            Self::Import => "import",
            Self::Fence => "fence",
            Self::TestOnly => "test_only",
            Self::Verify => "verify",
            Self::Commit => "commit",
            Self::EntryFlip => "entry_flip",
            Self::FallbackSample => "fallback_sample",
            Self::FallbackHandback => "fallback_handback",
            Self::FallbackFlip => "fallback_flip",
        }
    }

    const fn duration(self) -> Duration {
        match self {
            Self::Import => IMPORT_TIMEOUT,
            Self::Fence => FENCE_TIMEOUT,
            Self::TestOnly => TEST_ONLY_TIMEOUT,
            Self::Verify => VERIFY_TIMEOUT,
            Self::Commit => COMMIT_TIMEOUT,
            Self::EntryFlip => ENTRY_FLIP_TIMEOUT,
            Self::FallbackSample => FALLBACK_SAMPLE_TIMEOUT,
            Self::FallbackHandback => FALLBACK_HANDBACK_TIMEOUT,
            Self::FallbackFlip => FALLBACK_FLIP_TIMEOUT,
        }
    }

    /// The invalidation cause a timeout on this step reports.
    const fn cause(self) -> InvalidationCause {
        match self {
            Self::Import => InvalidationCause::ImportFailed,
            Self::Fence => InvalidationCause::FenceTimeout,
            Self::TestOnly | Self::Verify => InvalidationCause::TestOnlyFailed,
            Self::Commit => InvalidationCause::CommitFailed,
            Self::EntryFlip | Self::FallbackFlip | Self::FallbackHandback => {
                InvalidationCause::PageFlipLost
            }
            Self::FallbackSample => InvalidationCause::ClientGone,
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(super) enum ArmStep {
    /// Importing the client DMA-BUF into a PRIME framebuffer.
    Importing,
    /// Waiting for the acquire fence of the imported revision.
    AwaitingFence,
    /// Running `TEST_ONLY` for the exact arrangement about to be committed.
    Testing,
    /// Last validation of certificate, output and surface epoch before the
    /// real commit.  A change here must never commit the prepared candidate.
    Verifying,
    /// The atomic commit has been issued.
    Committing,
    /// Waiting for the page flip that puts the client buffer on screen.
    AwaitingFlip,
}

impl ArmStep {
    const fn timeout(self) -> TimeoutStep {
        match self {
            Self::Importing => TimeoutStep::Import,
            Self::AwaitingFence => TimeoutStep::Fence,
            Self::Testing => TimeoutStep::TestOnly,
            Self::Verifying => TimeoutStep::Verify,
            Self::Committing => TimeoutStep::Commit,
            Self::AwaitingFlip => TimeoutStep::EntryFlip,
        }
    }

    pub(super) const fn code(self) -> &'static str {
        match self {
            Self::Importing => "importing",
            Self::AwaitingFence => "awaiting_fence",
            Self::Testing => "testing",
            Self::Verifying => "verifying",
            Self::Committing => "committing",
            Self::AwaitingFlip => "awaiting_flip",
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(super) enum FallbackStep {
    /// Client sampling is restored and Flutter is preparing an atlas frame
    /// that carries the latest safe client revision together with the new
    /// shell state.  The last client buffer keeps scanning out meanwhile.
    SamplingClient,
    /// The prepared frame exists; the output has been handed back to the atlas
    /// pipeline for a single atomic client-primary to atlas-primary commit.
    HandingBack,
    /// Waiting for the replacing page flip.  Client leases stay alive.
    Flipping,
}

impl FallbackStep {
    const fn timeout(self) -> TimeoutStep {
        match self {
            Self::SamplingClient => TimeoutStep::FallbackSample,
            Self::HandingBack => TimeoutStep::FallbackHandback,
            Self::Flipping => TimeoutStep::FallbackFlip,
        }
    }

    pub(super) const fn code(self) -> &'static str {
        match self {
            Self::SamplingClient => "sampling_client",
            Self::HandingBack => "handing_back",
            Self::Flipping => "flipping",
        }
    }
}

/// An entry or replacement in progress.  `invalidated` records a trigger that
/// arrived while a commit was already in flight: KMS owns that request, so the
/// machine must wait for its flip and only then fall back.  Holding the cause
/// in the state keeps that deferral visible instead of hiding it in a flag.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(super) struct ArmProgress {
    pub(super) candidate: CandidateKey,
    pub(super) step: ArmStep,
    pub(super) invalidated: Option<InvalidationCause>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(super) enum PromotionState {
    /// The Flutter atlas owns the primary plane and clients are sampled.
    Composed,
    /// The atlas still scans out while a client arrangement is prepared.
    Armed(ArmProgress),
    /// A client buffer is scanning out on the primary plane.
    Promoted {
        active: CandidateKey,
        replacement: Option<ArmProgress>,
    },
    /// The last client buffer still scans out while the atlas replacement is
    /// prepared.  The plane is never cleared first.
    FallbackArmed {
        active: CandidateKey,
        cause: InvalidationCause,
        step: FallbackStep,
    },
}

impl PromotionState {
    /// The sub-step within the current state, for the runtime's audit log.
    pub(super) const fn step_code(self) -> &'static str {
        match self {
            Self::Composed => "composed",
            Self::Armed(progress) => progress.step.code(),
            Self::Promoted {
                replacement: Some(progress),
                ..
            } => progress.step.code(),
            Self::Promoted { .. } => "scanning",
            Self::FallbackArmed { step, .. } => step.code(),
        }
    }

    pub(super) const fn code(self) -> &'static str {
        match self {
            Self::Composed => "composed",
            Self::Armed(_) => "armed",
            Self::Promoted { .. } => "promoted",
            Self::FallbackArmed { .. } => "fallback_armed",
        }
    }

    /// True while a client buffer is on screen or queued for the plane, which
    /// is exactly when the client leases must stay alive.
    pub(super) const fn holds_client_scanout(self) -> bool {
        match self {
            Self::Composed => false,
            Self::Armed(progress) => matches!(progress.step, ArmStep::AwaitingFlip),
            Self::Promoted { .. } | Self::FallbackArmed { .. } => true,
        }
    }

    /// The surface whose Flutter sampling is suppressed in this state.
    pub(super) const fn promoted_surface(self) -> Option<u64> {
        match self {
            Self::Promoted { active, .. } => Some(active.surface),
            // Fallback deliberately restores sampling before the atlas frame is
            // prepared, and an armed entry has not stopped sampling yet.
            Self::Composed | Self::Armed(_) | Self::FallbackArmed { .. } => None,
        }
    }
}

/// Work the caller must perform for a transition.  Every lease, request,
/// probe, commit, feedback and timeout is named explicitly so no side effect
/// depends on the caller re-deriving the state.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(super) enum PromotionAction {
    /// Import the candidate buffer into a PRIME framebuffer and retain its
    /// DMA-BUF, framebuffer and renderer guard as the pending lease.
    ImportCandidate(CandidateKey),
    /// Run `TEST_ONLY` on the exact arrangement that will be committed.
    TestDirect(CandidateKey),
    /// Re-read the live candidate and confirm it still matches before the real
    /// commit.
    VerifyCandidate(CandidateKey),
    /// Issue the atomic commit for the prepared client primary.
    CommitDirect(CandidateKey),
    /// Drop a pending lease that was never committed.
    ReleasePendingLease,
    /// Retire every client lease of this output after the replacing flip.
    RetireDirectLeases,
    /// Stop Flutter from sampling the promoted surface.
    SuppressClientSampling(u64),
    /// Restore the Flutter texture consumer for the surface.
    RestoreClientSampling(u64),
    /// Ask Flutter for a full atlas frame carrying this client revision plus
    /// the current shell state.
    RequestFallbackFrame { surface: u64, revision: u64 },
    /// Return the output to the atlas pipeline so its next ready frame
    /// atomically replaces the client primary.
    HandBackToAtlas,
    /// Deliver presentation feedback and buffer release for the revision that
    /// this flip actually put on screen.
    SendPresentationFeedback { surface: u64, revision: u64 },
    /// Arm the bounded deadline for the step just entered.
    ArmTimeout {
        step: TimeoutStep,
        deadline: Instant,
    },
    /// Keep composition and stop promoting on this output until its
    /// configuration epoch changes.
    DisablePromotion(RejectReason),
}

#[derive(Clone, Copy, Debug, Default)]
pub(super) struct ActionList {
    actions: [Option<PromotionAction>; MAX_ACTIONS],
    len: usize,
}

impl ActionList {
    fn push(&mut self, action: PromotionAction) {
        // The reducer never emits more than `MAX_ACTIONS`; a debug assertion
        // catches a future transition that grows past the fixed capacity
        // instead of silently dropping the work in a release build.
        debug_assert!(self.len < MAX_ACTIONS, "promotion action list overflow");
        if let Some(slot) = self.actions.get_mut(self.len) {
            *slot = Some(action);
            self.len += 1;
        }
    }

    pub(super) fn iter(&self) -> impl Iterator<Item = PromotionAction> + '_ {
        self.actions.iter().take(self.len).flatten().copied()
    }

    #[cfg(test)]
    fn contains(&self, action: PromotionAction) -> bool {
        self.iter().any(|candidate| candidate == action)
    }

    #[cfg(test)]
    const fn len(&self) -> usize {
        self.len
    }
}

#[derive(Clone, Copy, Debug)]
pub(super) enum PromotionEvent {
    /// Static eligibility passed this iteration.  `atlas_settled` is true once
    /// a composed atlas frame has been presented while this exact candidate
    /// stayed unchanged, which is what keeps entry from racing the first
    /// certificate of a still-changing scene.
    CandidateEligible {
        candidate: CandidateKey,
        atlas_settled: bool,
    },
    /// Static eligibility failed this iteration.
    CandidateRejected(RejectReason),
    ImportSucceeded,
    ImportFailed,
    /// The acquire fence of the imported revision has signalled.
    FenceReady,
    TestOnlyPassed,
    TestOnlyFailed,
    CommitAccepted,
    /// KMS reported the CRTC busy; the arrangement itself is still valid.
    CommitBusy,
    /// KMS rejected an arrangement that passed `TEST_ONLY`.
    CommitInvalid,
    PageFlipCompleted,
    /// Flutter has sampled a client revision at least as new as the fallback
    /// target, or the client is gone and no further sample can arrive.
    ClientSampleReady,
    /// The atlas pipeline owns the output again.
    OutputHandedBack,
    Invalidated(InvalidationCause),
    /// Deadline check.  Carries no state of its own.
    Tick,
}

#[derive(Clone, Copy, Debug, Default)]
struct Backoff {
    arrangement: Option<(u64, u64, u64, u64)>,
    failures: u32,
    blocked_until: Option<Instant>,
}

impl Backoff {
    fn record_failure(&mut self, arrangement: (u64, u64, u64, u64), now: Instant) {
        if self.arrangement != Some(arrangement) {
            self.arrangement = Some(arrangement);
            self.failures = 0;
        }
        self.failures = self.failures.saturating_add(1);
        let delay = BACKOFF_BASE
            .saturating_mul(1u32 << self.failures.saturating_sub(1).min(6))
            .min(BACKOFF_MAX);
        self.blocked_until = Some(now + delay);
    }

    fn clear(&mut self) {
        *self = Self::default();
    }

    fn allows(&self, arrangement: (u64, u64, u64, u64), now: Instant) -> bool {
        match (self.arrangement, self.blocked_until) {
            (Some(blocked), Some(until)) if blocked == arrangement => now >= until,
            _ => true,
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum Capability {
    Available,
    /// Promotion is disabled for this output until its configuration epoch
    /// changes.  Other outputs are untouched.
    Disabled {
        reason: RejectReason,
        output_epoch: u64,
    },
}

/// One output's promotion state machine.  Instances are independent: a KMS
/// error, fallback or capability loss on one output cannot alter another.
/// One line of the audit log: what the machine is doing and why.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(super) struct AuditSummary {
    pub(super) state: &'static str,
    pub(super) step: &'static str,
    pub(super) reject: Option<&'static str>,
    pub(super) holds_client_scanout: bool,
    pub(super) promotion_disabled: bool,
}

#[derive(Clone, Copy, Debug)]
pub(super) struct OutputMachine {
    state: PromotionState,
    capability: Capability,
    backoff: Backoff,
    step_deadline: Option<Instant>,
    fallback_attempts: u32,
    fallback_target_revision: u64,
    last_reject: Option<RejectReason>,
    last_audit: Option<AuditSummary>,
}

impl Default for OutputMachine {
    fn default() -> Self {
        Self {
            state: PromotionState::Composed,
            capability: Capability::Available,
            backoff: Backoff::default(),
            step_deadline: None,
            fallback_attempts: 0,
            fallback_target_revision: 0,
            last_reject: None,
            last_audit: None,
        }
    }
}

impl OutputMachine {
    pub(super) const fn state(&self) -> PromotionState {
        self.state
    }

    /// The reason the last observation was refused. The runtime reads this
    /// through `take_audit_change`; tests assert on the typed reason.
    #[cfg(test)]
    const fn last_reject(&self) -> Option<RejectReason> {
        self.last_reject
    }

    pub(super) const fn promotion_disabled(&self) -> bool {
        matches!(self.capability, Capability::Disabled { .. })
    }

    /// Deadline of the step currently in progress, for the caller's audit log.
    pub(super) const fn step_deadline(&self) -> Option<Instant> {
        self.step_deadline
    }

    /// The client revision the prepared fallback atlas frame must carry.
    pub(super) const fn fallback_target_revision(&self) -> u64 {
        self.fallback_target_revision
    }

    /// The audit summary, but only when it differs from the one last returned.
    ///
    /// The runtime calls this once per render iteration, which is hundreds of
    /// times a second. Reporting an unchanged machine every time would bury
    /// the transitions the audit exists to show, and the logging itself would
    /// cost more than the work being measured.
    pub(super) fn take_audit_change(&mut self) -> Option<AuditSummary> {
        let summary = AuditSummary {
            state: self.state.code(),
            step: self.state.step_code(),
            reject: self.last_reject.map(RejectReason::code),
            holds_client_scanout: self.state.holds_client_scanout(),
            promotion_disabled: self.promotion_disabled(),
        };
        (self.last_audit != Some(summary)).then(|| {
            self.last_audit = Some(summary);
            summary
        })
    }

    fn enter_arm(&mut self, mut progress: ArmProgress, step: ArmStep, now: Instant) -> ActionList {
        progress.step = step;
        self.state = PromotionState::Armed(progress);
        let mut actions = ActionList::default();
        self.arm_step_timeout(&mut actions, step.timeout(), now);
        actions
    }

    fn arm_step_timeout(&mut self, actions: &mut ActionList, step: TimeoutStep, now: Instant) {
        let deadline = now + step.duration();
        self.step_deadline = Some(deadline);
        actions.push(PromotionAction::ArmTimeout { step, deadline });
    }

    /// Abandon an uncommitted preparation and return to composition.  Nothing
    /// has reached the plane, so releasing the pending lease is safe here and
    /// only here.
    fn abandon_preparation(
        &mut self,
        candidate: CandidateKey,
        cause: InvalidationCause,
        now: Instant,
    ) -> ActionList {
        let mut actions = ActionList::default();
        actions.push(PromotionAction::ReleasePendingLease);
        if cause.is_fault() {
            self.backoff.record_failure(candidate.arrangement(), now);
        }
        if cause == InvalidationCause::CommitFailed {
            // A real commit that fails after its own `TEST_ONLY` passed means
            // the probe cache cannot be trusted for this output.
            self.disable(RejectReason::CommitInvalid, candidate, &mut actions);
        }
        self.state = PromotionState::Composed;
        self.step_deadline = None;
        actions
    }

    /// Abandon a replacement while the active promotion keeps scanning out.
    fn abandon_replacement(
        &mut self,
        active: CandidateKey,
        candidate: CandidateKey,
        cause: InvalidationCause,
        now: Instant,
    ) -> ActionList {
        let mut actions = ActionList::default();
        actions.push(PromotionAction::ReleasePendingLease);
        if cause.is_fault() {
            self.backoff.record_failure(candidate.arrangement(), now);
        }
        self.state = PromotionState::Promoted {
            active,
            replacement: None,
        };
        self.step_deadline = None;
        actions
    }

    fn begin_fallback(
        &mut self,
        active: CandidateKey,
        cause: InvalidationCause,
        now: Instant,
    ) -> ActionList {
        let mut actions = ActionList::default();
        self.state = PromotionState::FallbackArmed {
            active,
            cause,
            step: FallbackStep::SamplingClient,
        };
        self.fallback_attempts = 0;
        self.fallback_target_revision = active.revision;
        if cause.is_fault() {
            self.backoff.record_failure(active.arrangement(), now);
        }
        // Restore the consumer first: the prepared atlas frame must carry the
        // client content, otherwise the handback shows the desktop without the
        // client window for one flip.
        actions.push(PromotionAction::RestoreClientSampling(active.surface));
        actions.push(PromotionAction::RequestFallbackFrame {
            surface: active.surface,
            revision: active.revision,
        });
        self.arm_step_timeout(&mut actions, FallbackStep::SamplingClient.timeout(), now);
        actions
    }

    fn disable(&mut self, reason: RejectReason, candidate: CandidateKey, actions: &mut ActionList) {
        self.capability = Capability::Disabled {
            reason,
            output_epoch: candidate.output_epoch,
        };
        actions.push(PromotionAction::DisablePromotion(reason));
    }

    /// A new output configuration epoch invalidates every cached capability
    /// decision for this output, including a promotion disabled by a fault.
    fn refresh_capability(&mut self, output_epoch: u64) {
        if let Capability::Disabled {
            output_epoch: disabled_at,
            ..
        } = self.capability
            && disabled_at != output_epoch
        {
            self.capability = Capability::Available;
            self.backoff.clear();
        }
    }

    fn reject(&mut self, reason: RejectReason) -> ActionList {
        self.last_reject = Some(reason);
        ActionList::default()
    }

    #[allow(clippy::too_many_lines)]
    pub(super) fn advance(&mut self, event: PromotionEvent, now: Instant) -> ActionList {
        match (self.state, event) {
            // ---------------------------------------------------------------
            // Composed
            // ---------------------------------------------------------------
            (
                PromotionState::Composed,
                PromotionEvent::CandidateEligible {
                    candidate,
                    atlas_settled,
                },
            ) => {
                self.refresh_capability(candidate.output_epoch);
                if self.promotion_disabled() {
                    return self.reject(RejectReason::PromotionDisabled);
                }
                if !self.backoff.allows(candidate.arrangement(), now) {
                    return self.reject(RejectReason::BackoffActive);
                }
                if !atlas_settled {
                    return self.reject(RejectReason::AwaitingAtlasSettle);
                }
                self.last_reject = None;
                let mut actions = self.enter_arm(
                    ArmProgress {
                        candidate,
                        step: ArmStep::Importing,
                        invalidated: None,
                    },
                    ArmStep::Importing,
                    now,
                );
                actions.push(PromotionAction::ImportCandidate(candidate));
                actions
            }
            (PromotionState::Composed, PromotionEvent::CandidateRejected(reason)) => {
                self.reject(reason)
            }
            // A trigger while already composed only needs to clear a stale
            // capability decision when the output itself changed.
            (
                PromotionState::Composed,
                PromotionEvent::Invalidated(InvalidationCause::OutputConfigurationChanged),
            ) => {
                self.capability = Capability::Available;
                self.backoff.clear();
                self.step_deadline = None;
                ActionList::default()
            }

            // ---------------------------------------------------------------
            // Armed: preparing an entry behind the composed atlas
            // ---------------------------------------------------------------
            (PromotionState::Armed(progress), PromotionEvent::ImportSucceeded)
                if progress.step == ArmStep::Importing =>
            {
                self.enter_arm(progress, ArmStep::AwaitingFence, now)
            }
            (PromotionState::Armed(progress), PromotionEvent::ImportFailed)
                if progress.step == ArmStep::Importing =>
            {
                self.abandon_preparation(progress.candidate, InvalidationCause::ImportFailed, now)
            }
            (PromotionState::Armed(progress), PromotionEvent::FenceReady)
                if progress.step == ArmStep::AwaitingFence =>
            {
                let candidate = progress.candidate;
                let mut actions = self.enter_arm(progress, ArmStep::Testing, now);
                actions.push(PromotionAction::TestDirect(candidate));
                actions
            }
            (PromotionState::Armed(progress), PromotionEvent::TestOnlyPassed)
                if progress.step == ArmStep::Testing =>
            {
                let candidate = progress.candidate;
                let mut actions = self.enter_arm(progress, ArmStep::Verifying, now);
                actions.push(PromotionAction::VerifyCandidate(candidate));
                actions
            }
            (PromotionState::Armed(progress), PromotionEvent::TestOnlyFailed)
                if progress.step == ArmStep::Testing =>
            {
                self.abandon_preparation(progress.candidate, InvalidationCause::TestOnlyFailed, now)
            }
            // Final validation. Only an unchanged candidate may be committed.
            (
                PromotionState::Armed(progress),
                PromotionEvent::CandidateEligible { candidate, .. },
            ) if progress.step == ArmStep::Verifying => {
                if candidate != progress.candidate {
                    return self.abandon_preparation(
                        progress.candidate,
                        InvalidationCause::EpochChanged,
                        now,
                    );
                }
                let mut actions = self.enter_arm(progress, ArmStep::Committing, now);
                actions.push(PromotionAction::CommitDirect(candidate));
                actions
            }
            (PromotionState::Armed(progress), PromotionEvent::CandidateRejected(reason))
                if progress.step == ArmStep::Verifying =>
            {
                self.last_reject = Some(reason);
                self.abandon_preparation(
                    progress.candidate,
                    InvalidationCause::CertificateRevoked,
                    now,
                )
            }
            (PromotionState::Armed(progress), PromotionEvent::CommitAccepted)
                if progress.step == ArmStep::Committing =>
            {
                self.enter_arm(progress, ArmStep::AwaitingFlip, now)
            }
            (PromotionState::Armed(progress), PromotionEvent::CommitBusy)
                if progress.step == ArmStep::Committing =>
            {
                // The CRTC already owns an in-flight request. That is ordinary
                // contention with the atlas pipeline, not a broken
                // arrangement: keep composition, back off, and retry. Treating
                // it as a probe failure would cost the output its promotion
                // capability for the rest of the session.
                self.abandon_preparation(progress.candidate, InvalidationCause::CommitBusy, now)
            }
            (PromotionState::Armed(progress), PromotionEvent::CommitInvalid)
                if progress.step == ArmStep::Committing =>
            {
                self.abandon_preparation(progress.candidate, InvalidationCause::CommitFailed, now)
            }
            (PromotionState::Armed(progress), PromotionEvent::PageFlipCompleted)
                if progress.step == ArmStep::AwaitingFlip =>
            {
                let candidate = progress.candidate;
                let mut actions = ActionList::default();
                actions.push(PromotionAction::SendPresentationFeedback {
                    surface: candidate.surface,
                    revision: candidate.revision,
                });
                self.step_deadline = None;
                self.backoff.clear();
                if let Some(cause) = progress.invalidated {
                    // A trigger arrived while the entry commit was in flight.
                    // The client is on screen now, so leave through the
                    // fallback path instead of clearing the plane.
                    let fallback = self.begin_fallback(candidate, cause, now);
                    for action in fallback.iter() {
                        actions.push(action);
                    }
                    return actions;
                }
                self.state = PromotionState::Promoted {
                    active: candidate,
                    replacement: None,
                };
                // Sampling stops only after the client is actually on screen.
                actions.push(PromotionAction::SuppressClientSampling(candidate.surface));
                actions
            }
            (PromotionState::Armed(progress), PromotionEvent::Invalidated(cause)) => {
                if progress.step == ArmStep::AwaitingFlip {
                    // KMS owns the request; record the trigger and act at the
                    // flip rather than racing a second commit.
                    self.state = PromotionState::Armed(ArmProgress {
                        invalidated: progress.invalidated.or(Some(cause)),
                        ..progress
                    });
                    return ActionList::default();
                }
                self.abandon_preparation(progress.candidate, cause, now)
            }

            // ---------------------------------------------------------------
            // Promoted: client buffer on the primary plane
            // ---------------------------------------------------------------
            (
                PromotionState::Promoted {
                    active,
                    replacement: None,
                },
                PromotionEvent::CandidateEligible { candidate, .. },
            ) => {
                if candidate == active {
                    return ActionList::default();
                }
                if !candidate.replaces(active) {
                    // Anything but a newer revision of the same arrangement is
                    // a scene change and must leave through the fallback.
                    return self.begin_fallback(active, InvalidationCause::EpochChanged, now);
                }
                if !self.backoff.allows(candidate.arrangement(), now) {
                    return self.reject(RejectReason::BackoffActive);
                }
                let mut actions = ActionList::default();
                self.state = PromotionState::Promoted {
                    active,
                    replacement: Some(ArmProgress {
                        candidate,
                        step: ArmStep::Importing,
                        invalidated: None,
                    }),
                };
                self.arm_step_timeout(&mut actions, ArmStep::Importing.timeout(), now);
                actions.push(PromotionAction::ImportCandidate(candidate));
                actions
            }
            (
                PromotionState::Promoted {
                    active,
                    replacement: None,
                },
                PromotionEvent::CandidateRejected(reason),
            ) => {
                self.last_reject = Some(reason);
                let cause = match reason {
                    RejectReason::ClientSamplingRequired | RejectReason::MissingCertificate => {
                        InvalidationCause::CertificateRevoked
                    }
                    RejectReason::PopupOrSubsurface | RejectReason::ShellVisible => {
                        InvalidationCause::ShellOverlayVisible
                    }
                    RejectReason::CaptureActive => InvalidationCause::CaptureRequested,
                    RejectReason::CursorVisible => InvalidationCause::CursorVisible,
                    RejectReason::NotOpaque => InvalidationCause::ColorPolicyChanged,
                    RejectReason::SizeMismatch | RejectReason::NotDmaBuf => {
                        InvalidationCause::BufferConfigurationChanged
                    }
                    RejectReason::UnsupportedTransform
                    | RejectReason::MultipleOutputs
                    | RejectReason::OutputUnpowered => {
                        InvalidationCause::OutputConfigurationChanged
                    }
                    _ => InvalidationCause::EpochChanged,
                };
                self.begin_fallback(active, cause, now)
            }
            (PromotionState::Promoted { active, .. }, PromotionEvent::Invalidated(cause)) => {
                self.begin_fallback(active, cause, now)
            }
            (
                PromotionState::Promoted {
                    active,
                    replacement: None,
                },
                PromotionEvent::PageFlipCompleted,
            ) => {
                let mut actions = ActionList::default();
                actions.push(PromotionAction::SendPresentationFeedback {
                    surface: active.surface,
                    revision: active.revision,
                });
                actions
            }

            // Replacement of the scanning client buffer.
            (
                PromotionState::Promoted {
                    active,
                    replacement: Some(progress),
                },
                event,
            ) => self.advance_replacement(active, progress, event, now),

            // ---------------------------------------------------------------
            // FallbackArmed: last client buffer holds the plane
            // ---------------------------------------------------------------
            (
                PromotionState::FallbackArmed {
                    active,
                    cause,
                    step: FallbackStep::SamplingClient,
                },
                PromotionEvent::ClientSampleReady,
            ) => {
                let mut actions = ActionList::default();
                self.state = PromotionState::FallbackArmed {
                    active,
                    cause,
                    step: FallbackStep::HandingBack,
                };
                actions.push(PromotionAction::HandBackToAtlas);
                self.arm_step_timeout(&mut actions, FallbackStep::HandingBack.timeout(), now);
                actions
            }
            (
                PromotionState::FallbackArmed {
                    active,
                    cause,
                    step: FallbackStep::HandingBack,
                },
                PromotionEvent::OutputHandedBack,
            ) => {
                let mut actions = ActionList::default();
                self.state = PromotionState::FallbackArmed {
                    active,
                    cause,
                    step: FallbackStep::Flipping,
                };
                self.arm_step_timeout(&mut actions, FallbackStep::Flipping.timeout(), now);
                actions
            }
            (
                PromotionState::FallbackArmed {
                    active,
                    step: FallbackStep::Flipping,
                    ..
                },
                PromotionEvent::PageFlipCompleted,
            ) => {
                let mut actions = ActionList::default();
                // The atlas is on screen; only now may the client leases go.
                actions.push(PromotionAction::SendPresentationFeedback {
                    surface: active.surface,
                    revision: self.fallback_target_revision,
                });
                actions.push(PromotionAction::RetireDirectLeases);
                self.state = PromotionState::Composed;
                self.step_deadline = None;
                self.fallback_attempts = 0;
                actions
            }
            // Newer client revisions during fallback only raise the target the
            // prepared atlas frame must carry; they never reach the plane.
            (
                PromotionState::FallbackArmed {
                    active,
                    step: FallbackStep::SamplingClient,
                    ..
                },
                PromotionEvent::CandidateEligible { candidate, .. },
            ) if candidate.surface == active.surface
                && candidate.revision > self.fallback_target_revision =>
            {
                self.fallback_target_revision = candidate.revision;
                ActionList::default()
            }
            // A further trigger during fallback changes nothing: the machine is
            // already converging on composition.
            (PromotionState::FallbackArmed { .. }, PromotionEvent::Invalidated(_)) => {
                ActionList::default()
            }

            // ---------------------------------------------------------------
            // Deadlines
            // ---------------------------------------------------------------
            (_, PromotionEvent::Tick) => self.advance_deadline(now),

            // Everything else is an event that does not apply to the current
            // state.  Ignoring it keeps the machine total without inventing a
            // transition the contract does not define.
            _ => ActionList::default(),
        }
    }

    fn advance_replacement(
        &mut self,
        active: CandidateKey,
        progress: ArmProgress,
        event: PromotionEvent,
        now: Instant,
    ) -> ActionList {
        let promoted = |machine: &mut Self, progress: ArmProgress, step: ArmStep| {
            let mut progress = progress;
            progress.step = step;
            machine.state = PromotionState::Promoted {
                active,
                replacement: Some(progress),
            };
            let mut actions = ActionList::default();
            machine.arm_step_timeout(&mut actions, step.timeout(), now);
            actions
        };
        match (progress.step, event) {
            (ArmStep::Importing, PromotionEvent::ImportSucceeded) => {
                promoted(self, progress, ArmStep::AwaitingFence)
            }
            (ArmStep::Importing, PromotionEvent::ImportFailed) => self.abandon_replacement(
                active,
                progress.candidate,
                InvalidationCause::ImportFailed,
                now,
            ),
            (ArmStep::AwaitingFence, PromotionEvent::FenceReady) => {
                let candidate = progress.candidate;
                let mut actions = promoted(self, progress, ArmStep::Testing);
                actions.push(PromotionAction::TestDirect(candidate));
                actions
            }
            (ArmStep::Testing, PromotionEvent::TestOnlyPassed) => {
                let candidate = progress.candidate;
                let mut actions = promoted(self, progress, ArmStep::Verifying);
                actions.push(PromotionAction::VerifyCandidate(candidate));
                actions
            }
            (ArmStep::Testing, PromotionEvent::TestOnlyFailed) => self.abandon_replacement(
                active,
                progress.candidate,
                InvalidationCause::TestOnlyFailed,
                now,
            ),
            (ArmStep::Verifying, PromotionEvent::CandidateEligible { candidate, .. }) => {
                if candidate != progress.candidate {
                    return self.abandon_replacement(
                        active,
                        progress.candidate,
                        InvalidationCause::EpochChanged,
                        now,
                    );
                }
                let mut actions = promoted(self, progress, ArmStep::Committing);
                actions.push(PromotionAction::CommitDirect(candidate));
                actions
            }
            (ArmStep::Verifying, PromotionEvent::CandidateRejected(_)) => self.abandon_replacement(
                active,
                progress.candidate,
                InvalidationCause::CertificateRevoked,
                now,
            ),
            (ArmStep::Committing, PromotionEvent::CommitAccepted) => {
                promoted(self, progress, ArmStep::AwaitingFlip)
            }
            (ArmStep::Committing, PromotionEvent::CommitBusy) => self.abandon_replacement(
                active,
                progress.candidate,
                InvalidationCause::CommitBusy,
                now,
            ),
            (ArmStep::Committing, PromotionEvent::CommitInvalid) => self.abandon_replacement(
                active,
                progress.candidate,
                InvalidationCause::CommitFailed,
                now,
            ),
            (ArmStep::AwaitingFlip, PromotionEvent::PageFlipCompleted) => {
                let candidate = progress.candidate;
                let mut actions = ActionList::default();
                // Feedback and buffer release name the revision this flip
                // actually presented, never the one merely queued.
                actions.push(PromotionAction::SendPresentationFeedback {
                    surface: candidate.surface,
                    revision: candidate.revision,
                });
                // The replaced lease is retired here because its successor is
                // now scanning out.
                actions.push(PromotionAction::RetireDirectLeases);
                self.step_deadline = None;
                self.backoff.clear();
                if let Some(cause) = progress.invalidated {
                    let fallback = self.begin_fallback(candidate, cause, now);
                    for action in fallback.iter() {
                        actions.push(action);
                    }
                    return actions;
                }
                self.state = PromotionState::Promoted {
                    active: candidate,
                    replacement: None,
                };
                actions
            }
            (ArmStep::AwaitingFlip, PromotionEvent::Invalidated(cause)) => {
                self.state = PromotionState::Promoted {
                    active,
                    replacement: Some(ArmProgress {
                        invalidated: progress.invalidated.or(Some(cause)),
                        ..progress
                    }),
                };
                ActionList::default()
            }
            (_, PromotionEvent::Invalidated(cause)) => {
                // Drop the uncommitted replacement, then fall back from the
                // buffer that is actually on screen.
                let mut actions = ActionList::default();
                actions.push(PromotionAction::ReleasePendingLease);
                let fallback = self.begin_fallback(active, cause, now);
                for action in fallback.iter() {
                    actions.push(action);
                }
                actions
            }
            _ => ActionList::default(),
        }
    }

    fn advance_deadline(&mut self, now: Instant) -> ActionList {
        let Some(deadline) = self.step_deadline else {
            return ActionList::default();
        };
        if now < deadline {
            return ActionList::default();
        }
        match self.state {
            PromotionState::Armed(progress) => {
                let step = progress.step;
                if step == ArmStep::AwaitingFlip {
                    // The entry commit was accepted but never flipped. The
                    // client may already own the plane, so leave through the
                    // fallback and stop promoting on this output.
                    let candidate = progress.candidate;
                    let mut actions = ActionList::default();
                    self.disable(RejectReason::PageFlipLost, candidate, &mut actions);
                    let fallback =
                        self.begin_fallback(candidate, InvalidationCause::PageFlipLost, now);
                    for action in fallback.iter() {
                        actions.push(action);
                    }
                    return actions;
                }
                self.abandon_preparation(progress.candidate, step.timeout().cause(), now)
            }
            PromotionState::Promoted {
                active,
                replacement: Some(progress),
            } => {
                if progress.step == ArmStep::AwaitingFlip {
                    let mut actions = ActionList::default();
                    self.disable(RejectReason::PageFlipLost, progress.candidate, &mut actions);
                    let fallback =
                        self.begin_fallback(active, InvalidationCause::PageFlipLost, now);
                    for action in fallback.iter() {
                        actions.push(action);
                    }
                    return actions;
                }
                self.abandon_replacement(
                    active,
                    progress.candidate,
                    progress.step.timeout().cause(),
                    now,
                )
            }
            PromotionState::Promoted {
                replacement: None, ..
            }
            | PromotionState::Composed => {
                self.step_deadline = None;
                ActionList::default()
            }
            PromotionState::FallbackArmed {
                active,
                cause,
                step,
            } => self.advance_fallback_deadline(active, cause, step, now),
        }
    }

    /// Fallback preparation must never clear the plane or show a blank frame.
    /// A stalled step therefore retries, and only after `MAX_FALLBACK_ATTEMPTS`
    /// does the output keep composition with promotion disabled and an
    /// explicit warning.  The session is never terminated.
    fn advance_fallback_deadline(
        &mut self,
        active: CandidateKey,
        cause: InvalidationCause,
        step: FallbackStep,
        now: Instant,
    ) -> ActionList {
        self.fallback_attempts = self.fallback_attempts.saturating_add(1);
        let exhausted = self.fallback_attempts >= MAX_FALLBACK_ATTEMPTS;
        let mut actions = ActionList::default();
        if exhausted && !self.promotion_disabled() {
            self.disable(RejectReason::FallbackRenderFailed, active, &mut actions);
        }
        match step {
            FallbackStep::SamplingClient => {
                if exhausted {
                    // Flutter never reported the client sample. Composition is
                    // still the correctness path, so hand back and let the
                    // atlas own the plane again rather than freeze forever.
                    self.state = PromotionState::FallbackArmed {
                        active,
                        cause,
                        step: FallbackStep::HandingBack,
                    };
                    actions.push(PromotionAction::HandBackToAtlas);
                    self.arm_step_timeout(&mut actions, FallbackStep::HandingBack.timeout(), now);
                    return actions;
                }
                actions.push(PromotionAction::RestoreClientSampling(active.surface));
                actions.push(PromotionAction::RequestFallbackFrame {
                    surface: active.surface,
                    revision: self.fallback_target_revision,
                });
                self.arm_step_timeout(&mut actions, FallbackStep::SamplingClient.timeout(), now);
                actions
            }
            FallbackStep::HandingBack => {
                actions.push(PromotionAction::HandBackToAtlas);
                self.arm_step_timeout(&mut actions, FallbackStep::HandingBack.timeout(), now);
                actions
            }
            FallbackStep::Flipping => {
                // The atlas commit is queued in the output pipeline. Re-arm the
                // deadline and keep the last client frame on screen; the
                // scheduler's own presentation-stall recovery owns the case
                // where KMS stops delivering flips entirely.
                self.arm_step_timeout(&mut actions, FallbackStep::Flipping.timeout(), now);
                actions
            }
        }
    }
}

/// Per-output machines plus the experiment switch.  Promotion is opt-in and
/// every lookup is keyed by output so one output's faults stay local.
#[derive(Debug, Default)]
pub(super) struct PromotionRegistry {
    enabled: bool,
    machines: BTreeMap<u64, OutputMachine>,
}

impl PromotionRegistry {
    pub(super) fn new(enabled: bool) -> Self {
        Self {
            enabled,
            machines: BTreeMap::new(),
        }
    }

    pub(super) const fn enabled(&self) -> bool {
        self.enabled
    }

    pub(super) fn machine(&mut self, output: u64) -> &mut OutputMachine {
        self.machines.entry(output).or_default()
    }

    pub(super) fn state(&self, output: u64) -> PromotionState {
        self.machines
            .get(&output)
            .map_or(PromotionState::Composed, OutputMachine::state)
    }

    /// Outputs that currently hold a client buffer on or queued for the plane.
    pub(super) fn outputs_holding_client_scanout(&self) -> impl Iterator<Item = u64> + '_ {
        self.machines
            .iter()
            .filter(|(_, machine)| machine.state().holds_client_scanout())
            .map(|(output, _)| *output)
    }

    /// All surfaces whose Flutter sampling is suppressed, one per promoted
    /// output. A set keeps multi-output promotion isolated.
    pub(super) fn suppressed_surfaces(&self) -> impl Iterator<Item = u64> + '_ {
        self.machines
            .values()
            .filter_map(|machine| machine.state().promoted_surface())
    }

    pub(super) fn forget_output(&mut self, output: u64) {
        self.machines.remove(&output);
    }

    /// Every machine, for the audit sweep.
    pub(super) fn machines_mut(&mut self) -> impl Iterator<Item = (u64, &mut OutputMachine)> {
        self.machines
            .iter_mut()
            .map(|(output, machine)| (*output, machine))
    }

    /// Outputs waiting for a page flip this module committed itself. Only
    /// these may consume a completion from the direct path; every other
    /// completion belongs to the atlas pipeline.
    pub(super) fn outputs_awaiting_direct_flip(&self) -> impl Iterator<Item = u64> + '_ {
        self.machines
            .iter()
            .filter(|(_, machine)| {
                matches!(
                    machine.state(),
                    PromotionState::Armed(ArmProgress {
                        step: ArmStep::AwaitingFlip,
                        ..
                    }) | PromotionState::Promoted {
                        replacement: Some(ArmProgress {
                            step: ArmStep::AwaitingFlip,
                            ..
                        }),
                        ..
                    }
                )
            })
            .map(|(output, _)| *output)
    }

    /// Outputs whose prepared buffer is waiting for its acquire fence, with
    /// the arrangement the pending lease must still match.
    pub(super) fn outputs_awaiting_fence(&self) -> impl Iterator<Item = (u64, CandidateKey)> + '_ {
        self.machines
            .iter()
            .filter_map(|(output, machine)| match machine.state() {
                PromotionState::Armed(ArmProgress {
                    candidate,
                    step: ArmStep::AwaitingFence,
                    ..
                })
                | PromotionState::Promoted {
                    replacement:
                        Some(ArmProgress {
                            candidate,
                            step: ArmStep::AwaitingFence,
                            ..
                        }),
                    ..
                } => Some((*output, candidate)),
                _ => None,
            })
    }

    /// Outputs whose fallback is waiting for the client revision to be
    /// sampled, with the surface and revision the atlas frame must carry.
    pub(super) fn outputs_awaiting_client_sample(
        &self,
    ) -> impl Iterator<Item = (u64, u64, u64)> + '_ {
        self.machines
            .iter()
            .filter_map(|(output, machine)| match machine.state() {
                PromotionState::FallbackArmed {
                    active,
                    step: FallbackStep::SamplingClient,
                    ..
                } => Some((*output, active.surface, machine.fallback_target_revision())),
                _ => None,
            })
    }

    /// Outputs whose fallback atlas commit is queued in the output pipeline
    /// and waiting for its replacing flip.
    pub(super) fn outputs_awaiting_fallback_flip(&self) -> impl Iterator<Item = u64> + '_ {
        self.machines
            .iter()
            .filter(|(_, machine)| {
                matches!(
                    machine.state(),
                    PromotionState::FallbackArmed {
                        step: FallbackStep::Flipping,
                        ..
                    }
                )
            })
            .map(|(output, _)| *output)
    }

    /// Deliver a trigger to every output.  Used for global events such as a
    /// Flutter engine replacement or session suspend.
    pub(super) fn invalidate_all(
        &mut self,
        cause: InvalidationCause,
        now: Instant,
    ) -> Vec<(u64, ActionList)> {
        self.machines
            .iter_mut()
            .map(|(output, machine)| {
                (
                    *output,
                    machine.advance(PromotionEvent::Invalidated(cause), now),
                )
            })
            .collect()
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

/// The exact source/destination arrangement which passed static validation
/// and will be repeated by both TEST_ONLY and the real atomic commit. Keeping
/// this beside the lease prevents a later re-derivation from accidentally
/// testing one arrangement and committing another (C1 §K3).
#[derive(Clone, Copy, Debug, PartialEq)]
pub(super) struct DirectPlaneGeometry {
    pub(super) source: Rectangle<f64, Buffer>,
    pub(super) destination: Rectangle<i32, Physical>,
    pub(super) transform: Transform,
}

pub(super) fn plane_geometry(
    source_rect: (f64, f64, f64, f64),
    source_size: (u32, u32),
    output_size: (u32, u32),
    transform: u32,
) -> Result<DirectPlaneGeometry, RejectReason> {
    let (x, y, width, height) = source_rect;
    let finite_positive = |value: f64| value.is_finite() && value > 0.0;
    if ![x, y]
        .iter()
        .all(|value| value.is_finite() && *value >= 0.0)
        || ![width, height].iter().copied().all(finite_positive)
        || x + width > f64::from(source_size.0)
        || y + height > f64::from(source_size.1)
        || output_size.0 == 0
        || output_size.1 == 0
    {
        return Err(RejectReason::InvalidPlaneGeometry);
    }
    let transform = match transform {
        0 => Transform::Normal,
        1 => Transform::_90,
        2 => Transform::_180,
        3 => Transform::_270,
        4 => Transform::Flipped,
        5 => Transform::Flipped90,
        6 => Transform::Flipped180,
        7 => Transform::Flipped270,
        _ => return Err(RejectReason::UnsupportedTransform),
    };
    let fixed16 = |value: f64| {
        let scaled = value * 65_536.0;
        (scaled.is_finite() && scaled >= 0.0 && scaled <= u32::MAX as f64)
            .then_some(())
            .ok_or(RejectReason::InvalidPlaneGeometry)
    };
    fixed16(x)?;
    fixed16(y)?;
    fixed16(width)?;
    fixed16(height)?;
    Ok(DirectPlaneGeometry {
        source: Rectangle::new((x, y).into(), (width, height).into()),
        destination: Rectangle::from_size(
            (
                i32::try_from(output_size.0).map_err(|_| RejectReason::InvalidPlaneGeometry)?,
                i32::try_from(output_size.1).map_err(|_| RejectReason::InvalidPlaneGeometry)?,
            )
                .into(),
        ),
        transform,
    })
}

pub(super) fn geometry_fingerprint(geometry: DirectPlaneGeometry) -> u64 {
    const FNV_OFFSET: u64 = 0xcbf2_9ce4_8422_2325;
    const FNV_PRIME: u64 = 0x0000_0100_0000_01b3;
    let mut hash = FNV_OFFSET;
    for value in [
        geometry.source.loc.x.to_bits(),
        geometry.source.loc.y.to_bits(),
        geometry.source.size.w.to_bits(),
        geometry.source.size.h.to_bits(),
        geometry.destination.loc.x as i64 as u64,
        geometry.destination.loc.y as i64 as u64,
        geometry.destination.size.w as i64 as u64,
        geometry.destination.size.h as i64 as u64,
        geometry.transform as u64,
    ] {
        for byte in value.to_le_bytes() {
            hash ^= u64::from(byte);
            hash = hash.wrapping_mul(FNV_PRIME);
        }
    }
    hash
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(super) enum CapturePath {
    CurrentAtlas,
    PreparedComposition,
}

pub(super) const fn capture_path(has_direct_plane: bool) -> CapturePath {
    if has_direct_plane {
        CapturePath::PreparedComposition
    } else {
        CapturePath::CurrentAtlas
    }
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

/// The static contract a candidate must satisfy before the state machine may
/// prepare it.  Kept separate from the reducer: this answers "may this scene
/// ever be promoted", the reducer answers "what happens next".
pub(super) fn evaluate_candidate(
    candidate: CandidateMetadata<'_>,
    surface_revision: u64,
) -> Option<RejectReason> {
    if !candidate.single_output {
        return Some(RejectReason::MultipleOutputs);
    }
    let Some(certificate) = candidate.certificate else {
        return Some(RejectReason::MissingCertificate);
    };
    if candidate.certificate_epoch == 0
        || candidate.certificate_epoch != candidate.visibility_epoch
        || certificate.certificate_epoch != candidate.certificate_epoch
        || certificate.buffer_revision == 0
        || surface_revision != certificate.buffer_revision
    {
        return Some(RejectReason::StaleCertificate);
    }
    if !certificate.known_opaque {
        return Some(RejectReason::NotOpaque);
    }
    if !certificate.shell_fully_transparent
        && !(certificate.overlay_compatible && certificate.overlay_rendering)
    {
        return Some(RejectReason::ShellVisible);
    }
    if certificate.requires_client_sampling {
        return Some(RejectReason::ClientSamplingRequired);
    }
    if certificate.has_popup
        || certificate.has_subsurface
        || certificate.has_drag_icon
        || certificate.has_ime
        || certificate.has_preview
        || certificate.has_capture
        || certificate.has_effect
    {
        return Some(RejectReason::PopupOrSubsurface);
    }
    let geometry = candidate.geometry;
    if geometry.transform > 7 {
        return Some(RejectReason::UnsupportedTransform);
    }
    if geometry.output_width == 0
        || geometry.output_height == 0
        || geometry.source_width == 0
        || geometry.source_height == 0
        || geometry.destination_width == 0
        || geometry.destination_height == 0
    {
        return Some(RejectReason::SizeMismatch);
    }
    if !candidate.dma_buf {
        return Some(RejectReason::NotDmaBuf);
    }
    if !candidate.sync_proven {
        return Some(RejectReason::SyncUnknown);
    }
    None
}

/// A client buffer lease held for the plane: the imported framebuffer, the
/// DMA-BUF and the renderer guard that keeps the client buffer alive.  Every
/// field must outlive the page flip that replaces it (C1 §K5), so the runtime
/// only drops a lease when the reducer emits `RetireDirectLeases`.
pub(super) struct DirectLease {
    pub(super) framebuffer: PrimeFramebuffer,
    pub(super) dmabuf: Dmabuf,
    /// Held, never read: dropping this guard would let the renderer recycle a
    /// buffer the CRTC is still scanning out.
    #[allow(dead_code)]
    pub(super) buffer_guard: RendererBufferGuard,
    pub(super) key: CandidateKey,
    pub(super) geometry: DirectPlaneGeometry,
}

/// The leases of one output.  `pending` is an entry or replacement that has not
/// reached its page flip; `active` is what the plane is scanning out.
#[derive(Default)]
pub(super) struct OutputLeases {
    pub(super) active: Option<DirectLease>,
    pub(super) pending: Option<DirectLease>,
}

impl OutputLeases {
    pub(super) fn is_empty(&self) -> bool {
        self.active.is_none() && self.pending.is_none()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn base() -> Instant {
        Instant::now()
    }

    const fn key(revision: u64) -> CandidateKey {
        CandidateKey {
            output: 1,
            surface: 11,
            revision,
            certificate_epoch: 100 + revision,
            output_epoch: 5,
            buffer_epoch: 7,
        }
    }

    /// Drive a machine from `Composed` to `Promoted` through the full entry
    /// contract, asserting the ordering the state machine promises.
    fn promote(machine: &mut OutputMachine, candidate: CandidateKey, now: Instant) {
        let actions = machine.advance(
            PromotionEvent::CandidateEligible {
                candidate,
                atlas_settled: true,
            },
            now,
        );
        assert!(actions.contains(PromotionAction::ImportCandidate(candidate)));
        machine.advance(PromotionEvent::ImportSucceeded, now);
        let actions = machine.advance(PromotionEvent::FenceReady, now);
        assert!(actions.contains(PromotionAction::TestDirect(candidate)));
        let actions = machine.advance(PromotionEvent::TestOnlyPassed, now);
        assert!(actions.contains(PromotionAction::VerifyCandidate(candidate)));
        let actions = machine.advance(
            PromotionEvent::CandidateEligible {
                candidate,
                atlas_settled: true,
            },
            now,
        );
        assert!(actions.contains(PromotionAction::CommitDirect(candidate)));
        machine.advance(PromotionEvent::CommitAccepted, now);
        let actions = machine.advance(PromotionEvent::PageFlipCompleted, now);
        assert!(actions.contains(PromotionAction::SuppressClientSampling(candidate.surface)));
        assert!(actions.contains(PromotionAction::SendPresentationFeedback {
            surface: candidate.surface,
            revision: candidate.revision,
        }));
        assert_eq!(
            machine.state(),
            PromotionState::Promoted {
                active: candidate,
                replacement: None
            }
        );
    }

    #[test]
    fn entry_requires_a_settled_atlas_before_importing() {
        let now = base();
        let mut machine = OutputMachine::default();
        let actions = machine.advance(
            PromotionEvent::CandidateEligible {
                candidate: key(9),
                atlas_settled: false,
            },
            now,
        );
        assert_eq!(actions.len(), 0);
        assert_eq!(machine.state(), PromotionState::Composed);
        assert_eq!(
            machine.last_reject(),
            Some(RejectReason::AwaitingAtlasSettle)
        );
        promote(&mut machine, key(9), now);
    }

    #[test]
    fn sampling_stops_only_after_the_client_reaches_the_screen() {
        let now = base();
        let mut machine = OutputMachine::default();
        let candidate = key(9);
        machine.advance(
            PromotionEvent::CandidateEligible {
                candidate,
                atlas_settled: true,
            },
            now,
        );
        machine.advance(PromotionEvent::ImportSucceeded, now);
        machine.advance(PromotionEvent::FenceReady, now);
        machine.advance(PromotionEvent::TestOnlyPassed, now);
        machine.advance(
            PromotionEvent::CandidateEligible {
                candidate,
                atlas_settled: true,
            },
            now,
        );
        let actions = machine.advance(PromotionEvent::CommitAccepted, now);
        assert!(!actions.contains(PromotionAction::SuppressClientSampling(candidate.surface)));
        assert_eq!(machine.state().promoted_surface(), None);
        let actions = machine.advance(PromotionEvent::PageFlipCompleted, now);
        assert!(actions.contains(PromotionAction::SuppressClientSampling(candidate.surface)));
        assert_eq!(machine.state().promoted_surface(), Some(candidate.surface));
    }

    #[test]
    fn certificate_loss_between_test_only_and_commit_never_commits() {
        let now = base();
        let mut machine = OutputMachine::default();
        let candidate = key(9);
        machine.advance(
            PromotionEvent::CandidateEligible {
                candidate,
                atlas_settled: true,
            },
            now,
        );
        machine.advance(PromotionEvent::ImportSucceeded, now);
        machine.advance(PromotionEvent::FenceReady, now);
        machine.advance(PromotionEvent::TestOnlyPassed, now);
        let actions = machine.advance(
            PromotionEvent::CandidateRejected(RejectReason::ClientSamplingRequired),
            now,
        );
        assert!(actions.contains(PromotionAction::ReleasePendingLease));
        assert!(
            !actions
                .iter()
                .any(|action| matches!(action, PromotionAction::CommitDirect(_)))
        );
        assert_eq!(machine.state(), PromotionState::Composed);
    }

    #[test]
    fn a_changed_candidate_at_verification_is_not_committed() {
        let now = base();
        let mut machine = OutputMachine::default();
        let candidate = key(9);
        machine.advance(
            PromotionEvent::CandidateEligible {
                candidate,
                atlas_settled: true,
            },
            now,
        );
        machine.advance(PromotionEvent::ImportSucceeded, now);
        machine.advance(PromotionEvent::FenceReady, now);
        machine.advance(PromotionEvent::TestOnlyPassed, now);
        let actions = machine.advance(
            PromotionEvent::CandidateEligible {
                candidate: key(10),
                atlas_settled: true,
            },
            now,
        );
        assert!(
            !actions
                .iter()
                .any(|action| matches!(action, PromotionAction::CommitDirect(_)))
        );
        assert_eq!(machine.state(), PromotionState::Composed);
    }

    #[test]
    fn test_only_success_with_a_rejected_real_commit_disables_the_output() {
        let now = base();
        let mut machine = OutputMachine::default();
        let candidate = key(9);
        machine.advance(
            PromotionEvent::CandidateEligible {
                candidate,
                atlas_settled: true,
            },
            now,
        );
        machine.advance(PromotionEvent::ImportSucceeded, now);
        machine.advance(PromotionEvent::FenceReady, now);
        machine.advance(PromotionEvent::TestOnlyPassed, now);
        machine.advance(
            PromotionEvent::CandidateEligible {
                candidate,
                atlas_settled: true,
            },
            now,
        );
        let actions = machine.advance(PromotionEvent::CommitInvalid, now);
        assert!(actions.contains(PromotionAction::DisablePromotion(
            RejectReason::CommitInvalid
        )));
        assert_eq!(machine.state(), PromotionState::Composed);
        assert!(machine.promotion_disabled());
        // A disabled output keeps composing and never arms again.
        let actions = machine.advance(
            PromotionEvent::CandidateEligible {
                candidate,
                atlas_settled: true,
            },
            now,
        );
        assert_eq!(actions.len(), 0);
        assert_eq!(machine.last_reject(), Some(RejectReason::PromotionDisabled));
    }

    /// A busy CRTC is contention with the atlas pipeline, not evidence that
    /// the arrangement is wrong. Real-machine testing found this: entry raced
    /// an in-flight atlas flip, the output lost its promotion capability, and
    /// every later attempt in that session was refused.
    #[test]
    fn a_busy_crtc_retries_instead_of_disabling_the_output() {
        let now = base();
        let mut machine = OutputMachine::default();
        let candidate = key(9);
        let arm = |machine: &mut OutputMachine, now| {
            machine.advance(
                PromotionEvent::CandidateEligible {
                    candidate,
                    atlas_settled: true,
                },
                now,
            );
            machine.advance(PromotionEvent::ImportSucceeded, now);
            machine.advance(PromotionEvent::FenceReady, now);
            machine.advance(PromotionEvent::TestOnlyPassed, now);
            machine.advance(
                PromotionEvent::CandidateEligible {
                    candidate,
                    atlas_settled: true,
                },
                now,
            );
        };
        arm(&mut machine, now);
        let actions = machine.advance(PromotionEvent::CommitBusy, now);
        assert!(actions.contains(PromotionAction::ReleasePendingLease));
        assert!(
            !actions
                .iter()
                .any(|action| matches!(action, PromotionAction::DisablePromotion(_))),
            "a busy CRTC must not cost the output its promotion capability"
        );
        assert_eq!(machine.state(), PromotionState::Composed);
        assert!(!machine.promotion_disabled());

        // The backoff still applies, and the same arrangement may promote once
        // it expires.
        assert_eq!(
            machine
                .advance(
                    PromotionEvent::CandidateEligible {
                        candidate,
                        atlas_settled: true,
                    },
                    now,
                )
                .len(),
            0
        );
        let later = now + BACKOFF_BASE + Duration::from_millis(1);
        arm(&mut machine, later);
        machine.advance(PromotionEvent::CommitAccepted, later);
        machine.advance(PromotionEvent::PageFlipCompleted, later);
        assert_eq!(
            machine.state(),
            PromotionState::Promoted {
                active: candidate,
                replacement: None
            }
        );
    }

    /// The replacement path must make the same distinction.
    #[test]
    fn a_busy_crtc_during_replacement_keeps_the_active_promotion() {
        let now = base();
        let mut machine = OutputMachine::default();
        let active = key(9);
        promote(&mut machine, active, now);
        let next = key(10);
        machine.advance(
            PromotionEvent::CandidateEligible {
                candidate: next,
                atlas_settled: false,
            },
            now,
        );
        machine.advance(PromotionEvent::ImportSucceeded, now);
        machine.advance(PromotionEvent::FenceReady, now);
        machine.advance(PromotionEvent::TestOnlyPassed, now);
        machine.advance(
            PromotionEvent::CandidateEligible {
                candidate: next,
                atlas_settled: false,
            },
            now,
        );
        let actions = machine.advance(PromotionEvent::CommitBusy, now);
        assert!(actions.contains(PromotionAction::ReleasePendingLease));
        assert!(!actions.contains(PromotionAction::RetireDirectLeases));
        assert!(!machine.promotion_disabled());
        assert_eq!(
            machine.state(),
            PromotionState::Promoted {
                active,
                replacement: None
            }
        );
    }

    #[test]
    fn a_new_output_epoch_restores_a_disabled_capability() {
        let now = base();
        let mut machine = OutputMachine::default();
        let candidate = key(9);
        machine.advance(
            PromotionEvent::CandidateEligible {
                candidate,
                atlas_settled: true,
            },
            now,
        );
        machine.advance(PromotionEvent::ImportSucceeded, now);
        machine.advance(PromotionEvent::FenceReady, now);
        machine.advance(PromotionEvent::TestOnlyPassed, now);
        machine.advance(
            PromotionEvent::CandidateEligible {
                candidate,
                atlas_settled: true,
            },
            now,
        );
        machine.advance(PromotionEvent::CommitInvalid, now);
        assert!(machine.promotion_disabled());
        let rescanned = CandidateKey {
            output_epoch: 6,
            ..candidate
        };
        let actions = machine.advance(
            PromotionEvent::CandidateEligible {
                candidate: rescanned,
                atlas_settled: true,
            },
            now,
        );
        assert!(!machine.promotion_disabled());
        assert!(actions.contains(PromotionAction::ImportCandidate(rescanned)));
    }

    #[test]
    fn import_failure_backs_off_instead_of_retrying_every_frame() {
        let now = base();
        let mut machine = OutputMachine::default();
        let candidate = key(9);
        machine.advance(
            PromotionEvent::CandidateEligible {
                candidate,
                atlas_settled: true,
            },
            now,
        );
        let actions = machine.advance(PromotionEvent::ImportFailed, now);
        assert!(actions.contains(PromotionAction::ReleasePendingLease));
        assert_eq!(machine.state(), PromotionState::Composed);
        let blocked = machine.advance(
            PromotionEvent::CandidateEligible {
                candidate,
                atlas_settled: true,
            },
            now,
        );
        assert_eq!(blocked.len(), 0);
        assert_eq!(machine.last_reject(), Some(RejectReason::BackoffActive));
        let later = now + BACKOFF_BASE + Duration::from_millis(1);
        let allowed = machine.advance(
            PromotionEvent::CandidateEligible {
                candidate,
                atlas_settled: true,
            },
            later,
        );
        assert!(allowed.contains(PromotionAction::ImportCandidate(candidate)));
    }

    #[test]
    fn backoff_grows_and_is_capped() {
        let now = base();
        let mut backoff = Backoff::default();
        let arrangement = key(1).arrangement();
        let mut previous = Duration::ZERO;
        for _ in 0..12 {
            backoff.record_failure(arrangement, now);
            let until = backoff.blocked_until.expect("armed backoff");
            let delay = until - now;
            assert!(delay >= previous);
            assert!(delay <= BACKOFF_MAX);
            previous = delay;
        }
        assert_eq!(previous, BACKOFF_MAX);
    }

    #[test]
    fn a_never_signalling_fence_times_out_into_composition() {
        let now = base();
        let mut machine = OutputMachine::default();
        let candidate = key(9);
        machine.advance(
            PromotionEvent::CandidateEligible {
                candidate,
                atlas_settled: true,
            },
            now,
        );
        machine.advance(PromotionEvent::ImportSucceeded, now);
        assert_eq!(
            machine.state(),
            PromotionState::Armed(ArmProgress {
                candidate,
                step: ArmStep::AwaitingFence,
                invalidated: None
            })
        );
        assert_eq!(machine.advance(PromotionEvent::Tick, now).len(), 0);
        let actions = machine.advance(PromotionEvent::Tick, now + FENCE_TIMEOUT);
        assert!(actions.contains(PromotionAction::ReleasePendingLease));
        assert_eq!(machine.state(), PromotionState::Composed);
    }

    #[test]
    fn a_late_fence_after_the_timeout_does_not_resurrect_the_candidate() {
        let now = base();
        let mut machine = OutputMachine::default();
        let candidate = key(9);
        machine.advance(
            PromotionEvent::CandidateEligible {
                candidate,
                atlas_settled: true,
            },
            now,
        );
        machine.advance(PromotionEvent::ImportSucceeded, now);
        machine.advance(PromotionEvent::Tick, now + FENCE_TIMEOUT);
        assert_eq!(machine.state(), PromotionState::Composed);
        let actions = machine.advance(PromotionEvent::FenceReady, now + FENCE_TIMEOUT);
        assert_eq!(actions.len(), 0);
        assert_eq!(machine.state(), PromotionState::Composed);
    }

    #[test]
    fn a_lost_entry_flip_falls_back_and_disables_the_output() {
        let now = base();
        let mut machine = OutputMachine::default();
        let candidate = key(9);
        machine.advance(
            PromotionEvent::CandidateEligible {
                candidate,
                atlas_settled: true,
            },
            now,
        );
        machine.advance(PromotionEvent::ImportSucceeded, now);
        machine.advance(PromotionEvent::FenceReady, now);
        machine.advance(PromotionEvent::TestOnlyPassed, now);
        machine.advance(
            PromotionEvent::CandidateEligible {
                candidate,
                atlas_settled: true,
            },
            now,
        );
        machine.advance(PromotionEvent::CommitAccepted, now);
        let actions = machine.advance(PromotionEvent::Tick, now + ENTRY_FLIP_TIMEOUT);
        assert!(actions.contains(PromotionAction::DisablePromotion(
            RejectReason::PageFlipLost
        )));
        assert!(actions.contains(PromotionAction::RestoreClientSampling(candidate.surface)));
        assert!(matches!(
            machine.state(),
            PromotionState::FallbackArmed {
                step: FallbackStep::SamplingClient,
                ..
            }
        ));
    }

    #[test]
    fn invalidation_during_the_entry_flip_defers_to_the_fallback() {
        let now = base();
        let mut machine = OutputMachine::default();
        let candidate = key(9);
        machine.advance(
            PromotionEvent::CandidateEligible {
                candidate,
                atlas_settled: true,
            },
            now,
        );
        machine.advance(PromotionEvent::ImportSucceeded, now);
        machine.advance(PromotionEvent::FenceReady, now);
        machine.advance(PromotionEvent::TestOnlyPassed, now);
        machine.advance(
            PromotionEvent::CandidateEligible {
                candidate,
                atlas_settled: true,
            },
            now,
        );
        machine.advance(PromotionEvent::CommitAccepted, now);
        // A popup opens while KMS still owns the entry request. No second
        // commit may be issued for this CRTC.
        let actions = machine.advance(
            PromotionEvent::Invalidated(InvalidationCause::ShellOverlayVisible),
            now,
        );
        assert_eq!(actions.len(), 0);
        let actions = machine.advance(PromotionEvent::PageFlipCompleted, now);
        assert!(actions.contains(PromotionAction::RestoreClientSampling(candidate.surface)));
        assert!(matches!(
            machine.state(),
            PromotionState::FallbackArmed {
                cause: InvalidationCause::ShellOverlayVisible,
                ..
            }
        ));
        // Sampling was restored, so the promoted-surface suppression is gone.
        assert_eq!(machine.state().promoted_surface(), None);
        assert!(machine.state().holds_client_scanout());
    }

    #[test]
    fn a_full_fallback_retires_leases_only_after_the_atlas_flip() {
        let now = base();
        let mut machine = OutputMachine::default();
        let candidate = key(9);
        promote(&mut machine, candidate, now);
        let actions = machine.advance(
            PromotionEvent::Invalidated(InvalidationCause::CaptureRequested),
            now,
        );
        assert!(actions.contains(PromotionAction::RestoreClientSampling(candidate.surface)));
        assert!(actions.contains(PromotionAction::RequestFallbackFrame {
            surface: candidate.surface,
            revision: candidate.revision,
        }));
        assert!(!actions.contains(PromotionAction::RetireDirectLeases));
        assert!(!actions.contains(PromotionAction::HandBackToAtlas));

        let actions = machine.advance(PromotionEvent::ClientSampleReady, now);
        assert!(actions.contains(PromotionAction::HandBackToAtlas));
        assert!(!actions.contains(PromotionAction::RetireDirectLeases));
        assert!(machine.state().holds_client_scanout());

        let actions = machine.advance(PromotionEvent::OutputHandedBack, now);
        assert!(!actions.contains(PromotionAction::RetireDirectLeases));

        let actions = machine.advance(PromotionEvent::PageFlipCompleted, now);
        assert!(actions.contains(PromotionAction::RetireDirectLeases));
        assert_eq!(machine.state(), PromotionState::Composed);
        assert!(!machine.state().holds_client_scanout());
    }

    #[test]
    fn a_stalled_fallback_render_retries_then_disables_promotion() {
        let now = base();
        let mut machine = OutputMachine::default();
        let candidate = key(9);
        promote(&mut machine, candidate, now);
        machine.advance(
            PromotionEvent::Invalidated(InvalidationCause::ShellOverlayVisible),
            now,
        );
        let mut clock = now;
        for _ in 0..(MAX_FALLBACK_ATTEMPTS - 1) {
            clock += FALLBACK_SAMPLE_TIMEOUT;
            let actions = machine.advance(PromotionEvent::Tick, clock);
            // Retrying must never clear the plane or retire the lease.
            assert!(actions.contains(PromotionAction::RequestFallbackFrame {
                surface: candidate.surface,
                revision: candidate.revision,
            }));
            assert!(!actions.contains(PromotionAction::RetireDirectLeases));
            assert!(machine.state().holds_client_scanout());
        }
        clock += FALLBACK_SAMPLE_TIMEOUT;
        let actions = machine.advance(PromotionEvent::Tick, clock);
        assert!(actions.contains(PromotionAction::DisablePromotion(
            RejectReason::FallbackRenderFailed
        )));
        assert!(actions.contains(PromotionAction::HandBackToAtlas));
        assert!(!actions.contains(PromotionAction::RetireDirectLeases));
        let actions = machine.advance(PromotionEvent::OutputHandedBack, clock);
        assert!(!actions.contains(PromotionAction::RetireDirectLeases));
        let actions = machine.advance(PromotionEvent::PageFlipCompleted, clock);
        assert!(actions.contains(PromotionAction::RetireDirectLeases));
        assert_eq!(machine.state(), PromotionState::Composed);
        assert!(machine.promotion_disabled());
    }

    /// C1 §K5: a lease may only be retired by the page flip that replaces it.
    /// Every other step of entry, replacement and fallback must leave it
    /// alone, including the moment KMS accepts the commit -- acceptance only
    /// means the request was queued, not that the old frame has retired.
    #[test]
    fn no_lease_is_retired_before_its_replacing_flip() {
        let now = base();
        let mut machine = OutputMachine::default();
        let first = key(9);

        let step = |machine: &mut OutputMachine, event, label: &str| {
            let actions = machine.advance(event, now);
            assert!(
                !actions.contains(PromotionAction::RetireDirectLeases),
                "{label} retired a lease before its replacing page flip"
            );
            actions
        };

        // Entry: nothing is on screen yet, so no step may retire anything.
        step(
            &mut machine,
            PromotionEvent::CandidateEligible {
                candidate: first,
                atlas_settled: true,
            },
            "entry:eligible",
        );
        step(
            &mut machine,
            PromotionEvent::ImportSucceeded,
            "entry:import",
        );
        step(&mut machine, PromotionEvent::FenceReady, "entry:fence");
        step(
            &mut machine,
            PromotionEvent::TestOnlyPassed,
            "entry:test_only",
        );
        step(
            &mut machine,
            PromotionEvent::CandidateEligible {
                candidate: first,
                atlas_settled: true,
            },
            "entry:verify",
        );
        step(
            &mut machine,
            PromotionEvent::CommitAccepted,
            "entry:commit_accepted",
        );
        step(
            &mut machine,
            PromotionEvent::PageFlipCompleted,
            "entry:flip",
        );

        // Replacement: the first buffer holds the plane until the second one
        // actually flips, so only that flip may retire it.
        let second = key(10);
        step(
            &mut machine,
            PromotionEvent::CandidateEligible {
                candidate: second,
                atlas_settled: false,
            },
            "replace:eligible",
        );
        step(
            &mut machine,
            PromotionEvent::ImportSucceeded,
            "replace:import",
        );
        step(&mut machine, PromotionEvent::FenceReady, "replace:fence");
        step(
            &mut machine,
            PromotionEvent::TestOnlyPassed,
            "replace:test_only",
        );
        step(
            &mut machine,
            PromotionEvent::CandidateEligible {
                candidate: second,
                atlas_settled: false,
            },
            "replace:verify",
        );
        step(
            &mut machine,
            PromotionEvent::CommitAccepted,
            "replace:commit_accepted",
        );
        let actions = machine.advance(PromotionEvent::PageFlipCompleted, now);
        assert!(
            actions.contains(PromotionAction::RetireDirectLeases),
            "the replacing flip must retire the superseded lease"
        );

        // Fallback: the last client buffer keeps scanning out until the atlas
        // frame that replaces it reaches the screen.
        step(
            &mut machine,
            PromotionEvent::Invalidated(InvalidationCause::CaptureRequested),
            "fallback:invalidated",
        );
        step(
            &mut machine,
            PromotionEvent::ClientSampleReady,
            "fallback:sample_ready",
        );
        step(
            &mut machine,
            PromotionEvent::OutputHandedBack,
            "fallback:handed_back",
        );
        let actions = machine.advance(PromotionEvent::PageFlipCompleted, now);
        assert!(
            actions.contains(PromotionAction::RetireDirectLeases),
            "the fallback flip must retire the client leases"
        );
        assert_eq!(machine.state(), PromotionState::Composed);
    }

    #[test]
    fn a_replacement_retires_the_old_lease_at_its_own_flip() {
        let now = base();
        let mut machine = OutputMachine::default();
        let active = key(9);
        promote(&mut machine, active, now);
        let next = key(10);
        let actions = machine.advance(
            PromotionEvent::CandidateEligible {
                candidate: next,
                atlas_settled: false,
            },
            now,
        );
        assert!(actions.contains(PromotionAction::ImportCandidate(next)));
        machine.advance(PromotionEvent::ImportSucceeded, now);
        machine.advance(PromotionEvent::FenceReady, now);
        machine.advance(PromotionEvent::TestOnlyPassed, now);
        let actions = machine.advance(
            PromotionEvent::CandidateEligible {
                candidate: next,
                atlas_settled: false,
            },
            now,
        );
        assert!(actions.contains(PromotionAction::CommitDirect(next)));
        machine.advance(PromotionEvent::CommitAccepted, now);
        // The old lease is still on screen until this flip retires it.
        assert!(machine.state().holds_client_scanout());
        let actions = machine.advance(PromotionEvent::PageFlipCompleted, now);
        assert!(actions.contains(PromotionAction::SendPresentationFeedback {
            surface: next.surface,
            revision: next.revision,
        }));
        assert!(actions.contains(PromotionAction::RetireDirectLeases));
        assert_eq!(
            machine.state(),
            PromotionState::Promoted {
                active: next,
                replacement: None
            }
        );
    }

    #[test]
    fn one_hundred_revisions_stay_promoted_without_leaking_state() {
        let now = base();
        let mut machine = OutputMachine::default();
        promote(&mut machine, key(1), now);
        for revision in 2..=100 {
            let next = key(revision);
            machine.advance(
                PromotionEvent::CandidateEligible {
                    candidate: next,
                    atlas_settled: false,
                },
                now,
            );
            machine.advance(PromotionEvent::ImportSucceeded, now);
            machine.advance(PromotionEvent::FenceReady, now);
            machine.advance(PromotionEvent::TestOnlyPassed, now);
            machine.advance(
                PromotionEvent::CandidateEligible {
                    candidate: next,
                    atlas_settled: false,
                },
                now,
            );
            machine.advance(PromotionEvent::CommitAccepted, now);
            let actions = machine.advance(PromotionEvent::PageFlipCompleted, now);
            assert!(actions.contains(PromotionAction::RetireDirectLeases));
        }
        assert_eq!(
            machine.state(),
            PromotionState::Promoted {
                active: key(100),
                replacement: None
            }
        );
        assert!(!machine.promotion_disabled());
    }

    #[test]
    fn a_failed_replacement_keeps_the_active_promotion() {
        let now = base();
        let mut machine = OutputMachine::default();
        let active = key(9);
        promote(&mut machine, active, now);
        let next = key(10);
        machine.advance(
            PromotionEvent::CandidateEligible {
                candidate: next,
                atlas_settled: false,
            },
            now,
        );
        machine.advance(PromotionEvent::ImportSucceeded, now);
        machine.advance(PromotionEvent::FenceReady, now);
        let actions = machine.advance(PromotionEvent::TestOnlyFailed, now);
        assert!(actions.contains(PromotionAction::ReleasePendingLease));
        assert!(!actions.contains(PromotionAction::RetireDirectLeases));
        assert_eq!(
            machine.state(),
            PromotionState::Promoted {
                active,
                replacement: None
            }
        );
    }

    #[test]
    fn client_loss_in_each_state_converges_to_composition() {
        let now = base();
        // Armed.
        let mut machine = OutputMachine::default();
        let candidate = key(9);
        machine.advance(
            PromotionEvent::CandidateEligible {
                candidate,
                atlas_settled: true,
            },
            now,
        );
        machine.advance(PromotionEvent::ImportSucceeded, now);
        let actions = machine.advance(
            PromotionEvent::Invalidated(InvalidationCause::ClientGone),
            now,
        );
        assert!(actions.contains(PromotionAction::ReleasePendingLease));
        assert_eq!(machine.state(), PromotionState::Composed);

        // Promoted.
        let mut machine = OutputMachine::default();
        promote(&mut machine, candidate, now);
        machine.advance(
            PromotionEvent::Invalidated(InvalidationCause::ClientGone),
            now,
        );
        // No further sample can arrive from a destroyed client, so the caller
        // reports the sample gate as satisfied immediately.
        machine.advance(PromotionEvent::ClientSampleReady, now);
        machine.advance(PromotionEvent::OutputHandedBack, now);
        let actions = machine.advance(PromotionEvent::PageFlipCompleted, now);
        assert!(actions.contains(PromotionAction::RetireDirectLeases));
        assert_eq!(machine.state(), PromotionState::Composed);

        // FallbackArmed already converging.
        let mut machine = OutputMachine::default();
        promote(&mut machine, candidate, now);
        machine.advance(
            PromotionEvent::Invalidated(InvalidationCause::CaptureRequested),
            now,
        );
        let actions = machine.advance(
            PromotionEvent::Invalidated(InvalidationCause::ClientGone),
            now,
        );
        assert_eq!(actions.len(), 0);
        assert!(machine.state().holds_client_scanout());
    }

    #[test]
    fn every_trigger_from_promoted_reaches_composition() {
        let now = base();
        for cause in [
            InvalidationCause::CertificateRevoked,
            InvalidationCause::EpochChanged,
            InvalidationCause::ShellOverlayVisible,
            InvalidationCause::CaptureRequested,
            InvalidationCause::CursorVisible,
            InvalidationCause::ColorPolicyChanged,
            InvalidationCause::BufferConfigurationChanged,
            InvalidationCause::OutputConfigurationChanged,
            InvalidationCause::ClientGone,
            InvalidationCause::FlutterEngineReplaced,
            InvalidationCause::SessionSuspended,
            InvalidationCause::PageFlipLost,
        ] {
            let mut machine = OutputMachine::default();
            let candidate = key(9);
            promote(&mut machine, candidate, now);
            let actions = machine.advance(PromotionEvent::Invalidated(cause), now);
            assert!(
                actions.contains(PromotionAction::RestoreClientSampling(candidate.surface)),
                "{} must restore sampling before the atlas frame",
                cause.code()
            );
            assert!(
                !actions.contains(PromotionAction::RetireDirectLeases),
                "{} must not retire the lease before the replacing flip",
                cause.code()
            );
            machine.advance(PromotionEvent::ClientSampleReady, now);
            machine.advance(PromotionEvent::OutputHandedBack, now);
            let actions = machine.advance(PromotionEvent::PageFlipCompleted, now);
            assert!(actions.contains(PromotionAction::RetireDirectLeases));
            assert_eq!(
                machine.state(),
                PromotionState::Composed,
                "{} did not converge",
                cause.code()
            );
        }
    }

    #[test]
    fn a_scene_change_that_is_not_a_replacement_leaves_through_the_fallback() {
        let now = base();
        let mut machine = OutputMachine::default();
        let active = key(9);
        promote(&mut machine, active, now);
        // A different surface is a scene change, never an in-place swap.
        let other = CandidateKey {
            surface: 12,
            ..key(10)
        };
        let actions = machine.advance(
            PromotionEvent::CandidateEligible {
                candidate: other,
                atlas_settled: true,
            },
            now,
        );
        assert!(actions.contains(PromotionAction::RestoreClientSampling(active.surface)));
        assert!(matches!(
            machine.state(),
            PromotionState::FallbackArmed { .. }
        ));
    }

    #[test]
    fn a_stale_revision_is_never_accepted_as_a_replacement() {
        let now = base();
        let mut machine = OutputMachine::default();
        let active = key(9);
        promote(&mut machine, active, now);
        let older = key(8);
        let actions = machine.advance(
            PromotionEvent::CandidateEligible {
                candidate: older,
                atlas_settled: true,
            },
            now,
        );
        assert!(
            !actions
                .iter()
                .any(|action| matches!(action, PromotionAction::ImportCandidate(_)))
        );
        assert!(matches!(
            machine.state(),
            PromotionState::FallbackArmed { .. }
        ));
    }

    #[test]
    fn a_newer_revision_during_fallback_raises_the_prepared_target() {
        let now = base();
        let mut machine = OutputMachine::default();
        let active = key(9);
        promote(&mut machine, active, now);
        machine.advance(
            PromotionEvent::Invalidated(InvalidationCause::ShellOverlayVisible),
            now,
        );
        let actions = machine.advance(
            PromotionEvent::CandidateEligible {
                candidate: key(12),
                atlas_settled: false,
            },
            now,
        );
        assert_eq!(actions.len(), 0);
        machine.advance(PromotionEvent::ClientSampleReady, now);
        machine.advance(PromotionEvent::OutputHandedBack, now);
        let actions = machine.advance(PromotionEvent::PageFlipCompleted, now);
        assert!(actions.contains(PromotionAction::SendPresentationFeedback {
            surface: active.surface,
            revision: 12,
        }));
    }

    #[test]
    fn one_output_failure_leaves_other_outputs_untouched() {
        let now = base();
        let mut registry = PromotionRegistry::new(true);
        let first = key(9);
        let second = CandidateKey {
            output: 2,
            surface: 21,
            ..key(9)
        };
        promote(registry.machine(first.output), first, now);
        promote(registry.machine(second.output), second, now);

        let actions = registry
            .machine(first.output)
            .advance(PromotionEvent::Tick, now + ENTRY_FLIP_TIMEOUT);
        assert_eq!(actions.len(), 0, "a promoted output has no armed deadline");

        registry.machine(first.output).advance(
            PromotionEvent::Invalidated(InvalidationCause::CommitFailed),
            now,
        );
        assert!(matches!(
            registry.state(first.output),
            PromotionState::FallbackArmed { .. }
        ));
        assert_eq!(
            registry.state(second.output),
            PromotionState::Promoted {
                active: second,
                replacement: None
            }
        );
        assert_eq!(
            registry.suppressed_surfaces().collect::<Vec<_>>(),
            vec![second.surface]
        );
    }

    #[test]
    fn a_global_trigger_invalidates_every_output_independently() {
        let now = base();
        let mut registry = PromotionRegistry::new(true);
        let first = key(9);
        let second = CandidateKey {
            output: 2,
            surface: 21,
            ..key(9)
        };
        promote(registry.machine(first.output), first, now);
        promote(registry.machine(second.output), second, now);
        let results = registry.invalidate_all(InvalidationCause::FlutterEngineReplaced, now);
        assert_eq!(results.len(), 2);
        for (output, actions) in results {
            let surface = if output == 1 {
                first.surface
            } else {
                second.surface
            };
            assert!(actions.contains(PromotionAction::RestoreClientSampling(surface)));
            assert!(!actions.contains(PromotionAction::RetireDirectLeases));
        }
        assert!(registry.suppressed_surfaces().next().is_none());
        assert_eq!(registry.outputs_holding_client_scanout().count(), 2);
    }

    #[test]
    fn the_static_contract_rejects_every_non_minimal_scene() {
        let certificate = CompositionCertificate {
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
            shell_damage: super::super::wire::InputRect {
                x: 0.0,
                y: 0.0,
                width: 0.0,
                height: 0.0,
            },
            shell_visible_bounds: super::super::wire::InputRect {
                x: 0.0,
                y: 0.0,
                width: 0.0,
                height: 0.0,
            },
            shell_revision: 1,
            overlay_compatible: true,
            overlay_rendering: false,
        };
        let metadata = CandidateMetadata {
            single_output: true,
            dma_buf: true,
            sync_proven: true,
            certificate_epoch: 7,
            visibility_epoch: 7,
            certificate: Some(&certificate),
            geometry: CandidateGeometry {
                output_width: 1920,
                output_height: 1080,
                source_width: 1920,
                source_height: 1080,
                destination_width: 1920,
                destination_height: 1080,
                transform: 0,
            },
        };
        assert_eq!(evaluate_candidate(metadata, 9), None);

        let cases: [(fn(&mut CandidateMetadata), RejectReason); 6] = [
            (|c| c.single_output = false, RejectReason::MultipleOutputs),
            (|c| c.dma_buf = false, RejectReason::NotDmaBuf),
            (|c| c.sync_proven = false, RejectReason::SyncUnknown),
            (
                |c| c.geometry.destination_width = 0,
                RejectReason::SizeMismatch,
            ),
            (
                |c| c.geometry.transform = 8,
                RejectReason::UnsupportedTransform,
            ),
            (|c| c.visibility_epoch = 8, RejectReason::StaleCertificate),
        ];
        for (mutate, expected) in cases {
            let mut broken = metadata;
            mutate(&mut broken);
            assert_eq!(evaluate_candidate(broken, 9), Some(expected));
        }

        let sampled = CompositionCertificate {
            requires_client_sampling: true,
            ..certificate.clone()
        };
        let mut candidate = metadata;
        candidate.certificate = Some(&sampled);
        assert_eq!(
            evaluate_candidate(candidate, 9),
            Some(RejectReason::ClientSamplingRequired)
        );

        let mut missing = metadata;
        missing.certificate = None;
        assert_eq!(
            evaluate_candidate(missing, 9),
            Some(RejectReason::MissingCertificate)
        );

        // The revision the certificate names must be the revision the native
        // compositor observed in the same snapshot.
        assert_eq!(
            evaluate_candidate(metadata, 10),
            Some(RejectReason::StaleCertificate)
        );
    }

    #[test]
    fn plane_geometry_accepts_fractional_crop_and_maps_transform() {
        let geometry =
            plane_geometry((1.25, 2.5, 1278.75, 719.5), (1920, 1080), (1280, 720), 1).unwrap();
        assert_eq!(geometry.source.loc.x, 1.25);
        assert_eq!(geometry.source.size.h, 719.5);
        assert_eq!(geometry.transform, Transform::_90);
        assert_eq!(geometry.destination.size.w, 1280);
    }

    #[test]
    fn plane_geometry_rejects_nan_overflow_and_out_of_bounds_crop() {
        for source in [
            (f64::NAN, 0.0, 10.0, 10.0),
            (0.0, 0.0, f64::INFINITY, 10.0),
            (0.0, 0.0, 200.0, 10.0),
            (0.0, 0.0, 1.0e20, 1.0),
        ] {
            assert_eq!(
                plane_geometry(source, (100, 100), (100, 100), 0),
                Err(RejectReason::InvalidPlaneGeometry)
            );
        }
    }

    #[test]
    fn plane_geometry_rejects_unknown_transform() {
        assert_eq!(
            plane_geometry((0.0, 0.0, 10.0, 10.0), (10, 10), (10, 10), 8),
            Err(RejectReason::UnsupportedTransform)
        );
    }

    #[test]
    fn capture_never_reads_the_old_atlas_while_a_direct_plane_is_live() {
        assert_eq!(capture_path(false), CapturePath::CurrentAtlas);
        assert_eq!(capture_path(true), CapturePath::PreparedComposition);
        assert_ne!(capture_path(true), CapturePath::CurrentAtlas);
    }
}
