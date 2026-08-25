//! The mixed-refresh frame pipeline.
//!
//! App buffers and Flutter only set pending state. They never create a frame.
//! Every powered output owns a clock for its Wayland frame callbacks. The
//! fastest output is the sole render clock and chooses exactly one action:
//!
//! `output clocks -> client callbacks`
//! `render clock -> pending state -> Skip | RequestFlutter | Render`

use std::time::{Duration, Instant};

use denial_core::topology::OutputId;
use smithay::output::Mode as OutputMode;

use super::PresentedOutput;
use super::kms_state::Scanout;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(super) struct FrameTick {
    pub(super) output: OutputId,
    pub(super) interval: Duration,
    pub(super) observed_at: Instant,
    pub(super) presented_at: Option<Duration>,
}

pub(super) const IDLE_HEARTBEAT_TIMEOUT: Duration = Duration::from_millis(100);

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub(super) struct PendingFrame {
    pub(super) flutter_requested: bool,
    pub(super) app_textures_updated: bool,
    pub(super) producer_available: bool,
}

impl PendingFrame {
    pub(super) fn has_work(self) -> bool {
        self.flutter_requested || self.app_textures_updated
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(super) enum FrameAction {
    Skip,
    RequestFlutter,
    Render(FrameTick),
}

#[derive(Debug)]
pub(super) struct FrameScheduler {
    outputs: OutputClocks,
    waiting_for_flutter: Option<FrameTick>,
    work_output: Option<OutputId>,
    work_aware: bool,
}

impl FrameScheduler {
    pub(super) fn new(scanouts: &[Scanout], now: Instant) -> Self {
        Self {
            outputs: OutputClocks::new(scanouts, now),
            waiting_for_flutter: None,
            work_output: None,
            work_aware: false,
        }
    }

    pub(super) fn reconfigure(&mut self, scanouts: &[Scanout], now: Instant) {
        self.outputs.reconfigure(scanouts, now);
        if self.outputs.is_parked() {
            // A texture-only tick may have been waiting for Flutter when the
            // final output powered down. Keep any eventual AwaitVSync baton
            // pending for the first fresh output tick after wake instead of
            // rendering against a clock edge which is no longer visible.
            self.waiting_for_flutter = None;
        }
    }

    pub(super) fn observe_presentation(&mut self, presentation: PresentedOutput) {
        self.outputs.observe_presentation(presentation);
    }

    /// Selects the output whose shell damage owns the next Flutter frame.
    /// Direct client page flips never set this bit, so a fast game cannot
    /// pull an idle shell on another output up to its refresh rate.
    pub(super) fn set_work_output(&mut self, output: Option<OutputId>) {
        self.work_output = output;
    }

    pub(super) fn set_work_aware(&mut self, enabled: bool) {
        self.work_aware = enabled;
        if !enabled {
            self.work_output = None;
        }
    }

    pub(super) fn step(&mut self, now: Instant, pending: PendingFrame) -> FrameAction {
        let render_tick = self.outputs.advance(now);
        let work_tick = self.work_output.and_then(|output| {
            self.outputs
                .ticks()
                .iter()
                .copied()
                .find(|tick| tick.output == output)
        });
        let authorized_tick = if self.work_aware {
            work_tick
        } else {
            render_tick
        };
        if let Some(waiting_tick) = self.waiting_for_flutter {
            // AwaitVSync is asynchronous. If Flutter returns its baton after
            // one or more display edges, authorize it against the newest
            // edge instead of feeding Dart an old animation timestamp. The
            // imported texture already contains its latest contents, so the
            // physical authorization must be a latest-value mailbox too.
            let authorized_tick = authorized_tick.unwrap_or(waiting_tick);
            self.waiting_for_flutter = Some(authorized_tick);
            if pending.flutter_requested {
                self.waiting_for_flutter = None;
                return FrameAction::Render(authorized_tick);
            }
            return FrameAction::Skip;
        }

        let Some(authorized_tick) = authorized_tick else {
            return FrameAction::Skip;
        };
        if !pending.producer_available || !pending.has_work() {
            return FrameAction::Skip;
        }
        if pending.flutter_requested {
            return FrameAction::Render(authorized_tick);
        }

        self.waiting_for_flutter = Some(authorized_tick);
        FrameAction::RequestFlutter
    }

    pub(super) fn output_ticks(&self) -> &[FrameTick] {
        self.outputs.ticks()
    }

    pub(super) fn cancel_flutter_request(&mut self) {
        self.waiting_for_flutter = None;
    }

    pub(super) fn limit_dispatch_timeout(
        &self,
        now: Instant,
        timeout: Duration,
        has_pending_work: bool,
    ) -> Duration {
        if self.outputs.has_presented_tick() {
            return Duration::ZERO;
        }
        if has_pending_work || self.waiting_for_flutter.is_some() {
            self.outputs.limit_dispatch_timeout(now, timeout)
        } else {
            timeout.min(IDLE_HEARTBEAT_TIMEOUT)
        }
    }

    pub(super) fn render_interval(&self) -> Option<Duration> {
        let selected_output = if self.work_aware {
            self.work_output
        } else {
            self.outputs.render_output
        };
        self.outputs
            .clocks
            .iter()
            .find(|clock| Some(clock.source.output) == selected_output)
            .map(|clock| clock.interval)
    }
}

#[derive(Debug)]
struct OutputClocks {
    clocks: Vec<DisplayClock>,
    ticks: Vec<FrameTick>,
    render_output: Option<OutputId>,
}

impl OutputClocks {
    fn new(scanouts: &[Scanout], now: Instant) -> Self {
        let mut clocks = Self {
            clocks: Vec::with_capacity(scanouts.len()),
            ticks: Vec::with_capacity(scanouts.len()),
            render_output: None,
        };
        clocks.replace(scanouts, now);
        clocks
    }

    fn reconfigure(&mut self, scanouts: &[Scanout], now: Instant) {
        let render_output = render_source(scanouts).map(|source| source.output);
        let powered_outputs = scanouts.iter().filter(|scanout| scanout.powered).count();
        let sources_match = self.clocks.len() == powered_outputs
            && scanouts
                .iter()
                .filter(|scanout| scanout.powered)
                .map(clock_source)
                .all(|source| self.clocks.iter().any(|clock| clock.source == source));
        if sources_match && self.render_output == render_output {
            return;
        }
        self.replace(scanouts, now);
    }

    fn replace(&mut self, scanouts: &[Scanout], now: Instant) {
        self.clocks.clear();
        self.clocks.extend(
            scanouts
                .iter()
                .filter(|scanout| scanout.powered)
                .map(|scanout| DisplayClock::new(clock_source(scanout), now)),
        );
        self.ticks.clear();
        self.render_output = render_source(scanouts).map(|source| source.output);
    }

    fn observe_presentation(&mut self, presentation: PresentedOutput) {
        if let Some(clock) = self
            .clocks
            .iter_mut()
            .find(|clock| clock.source.output == presentation.id)
        {
            clock.observe_presentation(presentation);
        }
    }

    /// Advances every physical clock while returning only the tick allowed to
    /// authorize Flutter. Secondary ticks remain visible through `ticks()`.
    fn advance(&mut self, now: Instant) -> Option<FrameTick> {
        self.ticks.clear();
        for clock in &mut self.clocks {
            if let Some(tick) = clock.take_tick(now) {
                self.ticks.push(tick);
            }
        }
        let render_output = self.render_output?;
        self.ticks
            .iter()
            .copied()
            .find(|tick| tick.output == render_output)
    }

    fn ticks(&self) -> &[FrameTick] {
        &self.ticks
    }

    fn is_parked(&self) -> bool {
        self.render_output.is_none()
    }

    fn has_presented_tick(&self) -> bool {
        self.clocks
            .iter()
            .any(|clock| clock.presented_tick.is_some())
    }

    fn limit_dispatch_timeout(&self, now: Instant, timeout: Duration) -> Duration {
        if self.has_presented_tick() {
            return Duration::ZERO;
        }
        self.clocks.iter().fold(timeout, |timeout, clock| {
            timeout.min(clock.next_tick.saturating_duration_since(now))
        })
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
struct ClockSource {
    output: OutputId,
    interval: Duration,
    variable_refresh: bool,
}

#[derive(Debug)]
struct DisplayClock {
    source: ClockSource,
    interval: Duration,
    next_tick: Instant,
    last_tick: Option<Instant>,
    last_presentation: Option<(Instant, u64)>,
    presented_tick: Option<FrameTick>,
}

impl DisplayClock {
    fn new(source: ClockSource, now: Instant) -> Self {
        Self {
            source,
            interval: source.interval,
            next_tick: now,
            last_tick: None,
            last_presentation: None,
            presented_tick: None,
        }
    }

    fn observe_presentation(&mut self, presentation: PresentedOutput) {
        if presentation.id != self.source.output {
            return;
        }

        let observed_at = presentation.observed_at;
        let mut sequence_matched_previous = false;
        if let Some(sequence) = presentation.sequence {
            if let Some((previous_at, previous_sequence)) = self.last_presentation {
                let sequence_delta = sequence.wrapping_sub(previous_sequence);
                if sequence_delta == 0 {
                    sequence_matched_previous = true;
                } else if self.source.variable_refresh {
                    if let Some(interval) = measured_interval(
                        previous_at,
                        observed_at,
                        sequence_delta,
                        self.source.interval,
                    ) {
                        self.interval = interval;
                    }
                }
            }
            self.last_presentation = Some((observed_at, sequence));
        }
        let same_edge = sequence_matched_previous
            || self.last_tick.is_some_and(|last_tick| {
                observed_at <= last_tick
                    || observed_at.duration_since(last_tick) <= self.interval / 2
            });
        let observed_next = observed_at + self.interval;

        // A DRM event may reach the compositor after the timer has already
        // issued that physical edge. Rephase from its kernel timestamp, but
        // never move the synthetic clock behind the edge already delivered.
        // Otherwise the next `take_tick` replays the stale presentation as a
        // second vsync, producing a device-latency-dependent cadence.
        self.next_tick = if same_edge {
            self.last_tick.map_or(observed_next, |last_tick| {
                observed_next.max(last_tick + self.interval)
            })
        } else {
            observed_next
        };

        if !same_edge {
            self.presented_tick = Some(FrameTick {
                output: self.source.output,
                interval: self.interval,
                observed_at,
                presented_at: presentation.presented_at,
            });
        }
    }

    fn take_tick(&mut self, now: Instant) -> Option<FrameTick> {
        if let Some(tick) = self.presented_tick.take() {
            self.last_tick = Some(tick.observed_at);
            return Some(tick);
        }
        if now < self.next_tick {
            return None;
        }

        let interval_nanos = self.interval.as_nanos().max(1);
        let elapsed_periods =
            now.saturating_duration_since(self.next_tick).as_nanos() / interval_nanos;
        let observed_at = if let Ok(elapsed_periods) = u32::try_from(elapsed_periods) {
            self.next_tick + self.interval * elapsed_periods
        } else {
            // A very long suspend has no useful historical phase. Resume
            // with one current edge instead of replaying missed frames.
            now
        };
        self.next_tick = observed_at + self.interval;
        self.last_tick = Some(observed_at);
        Some(FrameTick {
            output: self.source.output,
            interval: self.interval,
            observed_at,
            presented_at: None,
        })
    }
}

fn measured_interval(
    previous_at: Instant,
    observed_at: Instant,
    sequence_delta: u64,
    nominal: Duration,
) -> Option<Duration> {
    if sequence_delta == 0 || observed_at <= previous_at {
        return None;
    }
    let elapsed = observed_at.duration_since(previous_at);
    let nanos = elapsed.as_nanos().checked_div(u128::from(sequence_delta))?;
    let interval = Duration::from_nanos(u64::try_from(nanos).ok()?);
    // VRR displays have a physical maximum refresh rate bounded by the nominal
    // interval (with up to 10% tolerance for driver/jitter timing variation).
    // Clamping to nominal * 9 / 10 prevents anomalous DRM timestamps from
    // runaway acceleration up to non-physical rates (e.g. 960Hz).
    let minimum = nominal.saturating_mul(9) / 10;
    let maximum = nominal.saturating_mul(8);
    (interval >= minimum && interval <= maximum).then_some(interval)
}

fn render_source(scanouts: &[Scanout]) -> Option<ClockSource> {
    scanouts
        .iter()
        .filter(|scanout| scanout.powered)
        .max_by_key(|scanout| OutputMode::from(scanout.output.mode).refresh)
        .map(clock_source)
}

fn clock_source(scanout: &Scanout) -> ClockSource {
    ClockSource {
        output: scanout.output.id,
        interval: refresh_interval(scanout),
        variable_refresh: scanout.output.vrr_enabled,
    }
}

fn refresh_interval(scanout: &Scanout) -> Duration {
    let refresh_millihz = u64::try_from(OutputMode::from(scanout.output.mode).refresh)
        .ok()
        .filter(|refresh| *refresh > 0)
        .unwrap_or(60_000);
    Duration::from_nanos(1_000_000_000_000 / refresh_millihz)
}

#[cfg(test)]
mod tests {
    use super::*;

    const INTERVAL: Duration = Duration::from_millis(10);
    const FAST_INTERVAL: Duration = Duration::from_millis(5);
    const FAST_OUTPUT: OutputId = OutputId(1);
    const SLOW_OUTPUT: OutputId = OutputId(2);

    fn scheduler(now: Instant) -> FrameScheduler {
        scheduler_with_clocks(now, &[(FAST_OUTPUT, INTERVAL)], FAST_OUTPUT)
    }

    fn mixed_scheduler(now: Instant) -> FrameScheduler {
        scheduler_with_clocks(
            now,
            &[(FAST_OUTPUT, FAST_INTERVAL), (SLOW_OUTPUT, INTERVAL)],
            FAST_OUTPUT,
        )
    }

    fn scheduler_with_clocks(
        now: Instant,
        sources: &[(OutputId, Duration)],
        render_output: OutputId,
    ) -> FrameScheduler {
        FrameScheduler {
            outputs: OutputClocks {
                clocks: sources
                    .iter()
                    .map(|(output, interval)| {
                        DisplayClock::new(
                            ClockSource {
                                output: *output,
                                interval: *interval,
                                variable_refresh: false,
                            },
                            now,
                        )
                    })
                    .collect(),
                ticks: Vec::with_capacity(sources.len()),
                render_output: Some(render_output),
            },
            waiting_for_flutter: None,
            work_output: None,
            work_aware: false,
        }
    }

    fn pending(
        flutter_requested: bool,
        app_textures_updated: bool,
        producer_available: bool,
    ) -> PendingFrame {
        PendingFrame {
            flutter_requested,
            app_textures_updated,
            producer_available,
        }
    }

    #[test]
    fn idle_display_ticks_without_rendering() {
        let now = Instant::now();
        let mut scheduler = scheduler(now);

        let action = scheduler.step(now, pending(false, false, true));

        assert_eq!(scheduler.output_ticks().len(), 1);
        assert_eq!(action, FrameAction::Skip);
    }

    #[test]
    fn app_or_flutter_events_cannot_create_an_early_tick() {
        let now = Instant::now();
        let mut scheduler = scheduler(now);
        scheduler.step(now, pending(false, false, true));

        let action = scheduler.step(now + Duration::from_millis(1), pending(true, true, true));

        assert!(scheduler.output_ticks().is_empty());
        assert_eq!(action, FrameAction::Skip);
    }

    #[test]
    fn a_texture_tick_waits_for_flutter_then_renders_the_same_authorization() {
        let now = Instant::now();
        let mut scheduler = scheduler(now);
        let request = scheduler.step(now, pending(false, true, true));
        let authorized_tick = scheduler.output_ticks()[0];
        assert_eq!(request, FrameAction::RequestFlutter);

        let render = scheduler.step(now + Duration::from_millis(1), pending(true, false, false));

        assert!(scheduler.output_ticks().is_empty());
        assert_eq!(render, FrameAction::Render(authorized_tick));
    }

    #[test]
    fn flutter_and_texture_damage_share_one_tick() {
        let now = Instant::now();
        let mut scheduler = scheduler(now);

        let action = scheduler.step(now, pending(true, true, true));

        assert_eq!(action, FrameAction::Render(scheduler.output_ticks()[0]));
    }

    #[test]
    fn the_clock_keeps_ticking_while_every_producer_is_idle() {
        let now = Instant::now();
        let mut scheduler = scheduler(now);
        scheduler.step(now, pending(false, false, true));

        let action = scheduler.step(now + INTERVAL, pending(false, false, true));

        assert_eq!(scheduler.output_ticks()[0].observed_at, now + INTERVAL);
        assert_eq!(action, FrameAction::Skip);
    }

    #[test]
    fn a_real_kms_edge_rephases_but_does_not_duplicate_a_timer_tick() {
        let now = Instant::now();
        let mut scheduler = scheduler(now);
        scheduler.step(now, pending(false, false, true));
        let observed_at = now + Duration::from_millis(1);

        scheduler.observe_presentation(PresentedOutput {
            id: FAST_OUTPUT,
            observed_at,
            presented_at: Some(Duration::from_secs(7)),
            sequence: Some(42),
        });

        scheduler.step(observed_at, pending(false, false, true));
        assert!(scheduler.output_ticks().is_empty());

        scheduler.step(observed_at + INTERVAL, pending(false, false, true));
        assert_eq!(
            scheduler.output_ticks()[0].observed_at,
            observed_at + INTERVAL
        );
    }

    #[test]
    fn delayed_physical_edge_older_than_the_last_timer_tick_is_not_replayed() {
        let now = Instant::now();
        let mut scheduler = scheduler(now);
        scheduler.step(now, pending(false, false, true));
        scheduler.step(now + INTERVAL, pending(false, false, true));

        scheduler.observe_presentation(PresentedOutput {
            id: FAST_OUTPUT,
            observed_at: now + Duration::from_millis(1),
            presented_at: Some(Duration::from_secs(7)),
            sequence: Some(42),
        });

        scheduler.step(
            now + INTERVAL + Duration::from_millis(4),
            pending(false, false, true),
        );
        assert!(scheduler.output_ticks().is_empty());

        scheduler.step(now + INTERVAL * 2, pending(false, false, true));
        assert_eq!(scheduler.output_ticks()[0].observed_at, now + INTERVAL * 2);
    }

    #[test]
    fn missed_intervals_collapse_to_the_latest_tick() {
        let now = Instant::now();
        let mut scheduler = scheduler(now);
        scheduler.step(now, pending(false, false, true));

        scheduler.step(
            now + INTERVAL * 4 + Duration::from_millis(1),
            pending(false, false, true),
        );

        assert_eq!(scheduler.output_ticks()[0].observed_at, now + INTERVAL * 4);
    }

    #[test]
    fn mixed_refresh_outputs_tick_at_their_own_rates() {
        let now = Instant::now();
        let mut scheduler = mixed_scheduler(now);
        let mut fast_ticks = 0;
        let mut slow_ticks = 0;

        for step in 0..=4 {
            scheduler.step(now + FAST_INTERVAL * step, pending(false, false, true));
            fast_ticks += scheduler
                .output_ticks()
                .iter()
                .filter(|tick| tick.output == FAST_OUTPUT)
                .count();
            slow_ticks += scheduler
                .output_ticks()
                .iter()
                .filter(|tick| tick.output == SLOW_OUTPUT)
                .count();
        }

        assert_eq!(fast_ticks, 5);
        assert_eq!(slow_ticks, 3);
    }

    #[test]
    fn work_aware_clock_ignores_an_idle_faster_direct_output() {
        let now = Instant::now();
        let mut scheduler = mixed_scheduler(now);
        scheduler.set_work_aware(true);
        scheduler.set_work_output(Some(SLOW_OUTPUT));

        let first = scheduler.step(now, pending(true, false, true));
        assert!(matches!(first, FrameAction::Render(tick) if tick.output == SLOW_OUTPUT));

        let fast_only = scheduler.step(now + FAST_INTERVAL, pending(true, false, true));
        assert_eq!(fast_only, FrameAction::Skip);
        assert_eq!(scheduler.output_ticks().len(), 1);
        assert_eq!(scheduler.output_ticks()[0].output, FAST_OUTPUT);

        let slow_deadline = scheduler.step(now + INTERVAL, pending(true, false, true));
        assert!(matches!(slow_deadline, FrameAction::Render(tick) if tick.output == SLOW_OUTPUT));
        assert_eq!(scheduler.render_interval(), Some(INTERVAL));
    }

    #[test]
    fn work_aware_clock_needs_damage_but_not_a_game_presentation() {
        let now = Instant::now();
        let mut scheduler = mixed_scheduler(now);
        scheduler.set_work_aware(true);
        scheduler.set_work_output(Some(SLOW_OUTPUT));

        assert_eq!(
            scheduler.step(now, pending(false, false, true)),
            FrameAction::Skip,
            "an idle overlay must not render merely because its clock ticked"
        );
        assert_eq!(
            scheduler.step(now + INTERVAL, pending(true, false, true)),
            FrameAction::Render(FrameTick {
                output: SLOW_OUTPUT,
                interval: INTERVAL,
                observed_at: now + INTERVAL,
                presented_at: None,
            }),
            "synthetic output deadline must service UI even when the game is stalled"
        );
    }

    #[test]
    fn a_secondary_tick_cannot_authorize_flutter() {
        let now = Instant::now();
        let mut scheduler = mixed_scheduler(now);
        scheduler.step(now, pending(false, false, true));
        scheduler.observe_presentation(PresentedOutput {
            id: SLOW_OUTPUT,
            observed_at: now + Duration::from_millis(2),
            presented_at: None,
            sequence: Some(1),
        });
        scheduler.step(now + FAST_INTERVAL, pending(false, false, true));
        scheduler.step(now + FAST_INTERVAL * 2, pending(false, false, true));

        let action = scheduler.step(now + Duration::from_millis(12), pending(false, true, true));

        assert_eq!(
            scheduler.output_ticks(),
            &[FrameTick {
                output: SLOW_OUTPUT,
                interval: INTERVAL,
                observed_at: now + Duration::from_millis(12),
                presented_at: None,
            }]
        );
        assert_eq!(action, FrameAction::Skip);

        let render_action = scheduler.step(now + FAST_INTERVAL * 3, pending(true, true, true));
        assert!(matches!(render_action, FrameAction::Render(tick) if tick.output == FAST_OUTPUT));
    }

    #[test]
    fn a_secondary_presentation_rephases_only_its_clock() {
        let now = Instant::now();
        let mut scheduler = mixed_scheduler(now);
        scheduler.step(now, pending(false, false, true));
        scheduler.observe_presentation(PresentedOutput {
            id: SLOW_OUTPUT,
            observed_at: now + Duration::from_millis(2),
            presented_at: Some(Duration::from_secs(3)),
            sequence: Some(9),
        });

        scheduler.step(now + FAST_INTERVAL, pending(false, false, true));
        assert_eq!(scheduler.output_ticks()[0].output, FAST_OUTPUT);

        scheduler.step(now + FAST_INTERVAL * 2, pending(false, false, true));
        assert_eq!(scheduler.output_ticks()[0].output, FAST_OUTPUT);

        scheduler.step(now + Duration::from_millis(12), pending(false, false, true));
        assert_eq!(scheduler.output_ticks()[0].output, SLOW_OUTPUT);
    }

    #[test]
    fn output_clocks_keep_ticking_while_flutter_is_late() {
        let now = Instant::now();
        let mut scheduler = mixed_scheduler(now);
        assert_eq!(
            scheduler.step(now, pending(false, true, true)),
            FrameAction::RequestFlutter
        );

        assert_eq!(
            scheduler.step(now + FAST_INTERVAL * 2, pending(false, false, false)),
            FrameAction::Skip
        );
        assert_eq!(scheduler.output_ticks().len(), 2);

        let render = scheduler.step(
            now + FAST_INTERVAL * 2 + Duration::from_millis(1),
            pending(true, false, false),
        );
        assert!(matches!(
            render,
            FrameAction::Render(tick)
                if tick.output == FAST_OUTPUT
                    && tick.observed_at == now + FAST_INTERVAL * 2
        ));
        assert!(scheduler.output_ticks().is_empty());
    }

    #[test]
    fn powering_off_every_output_cancels_stale_frame_authorization() {
        let now = Instant::now();
        let mut scheduler = scheduler(now);
        assert_eq!(
            scheduler.step(now, pending(false, true, true)),
            FrameAction::RequestFlutter
        );

        scheduler.reconfigure(&[], now + Duration::from_millis(1));

        assert_eq!(
            scheduler.step(now + Duration::from_millis(2), pending(true, false, true)),
            FrameAction::Skip
        );
        assert!(scheduler.output_ticks().is_empty());
        assert!(scheduler.waiting_for_flutter.is_none());
    }

    #[test]
    fn measured_interval_uses_sequence_delta_to_ignore_missed_vblanks() {
        let now = Instant::now();
        assert_eq!(
            measured_interval(now, now + Duration::from_millis(30), 3, INTERVAL),
            Some(INTERVAL)
        );
    }

    #[test]
    fn measured_interval_rejects_implausible_samples() {
        let now = Instant::now();
        assert_eq!(
            measured_interval(now, now + Duration::from_millis(1), 1, INTERVAL),
            None
        );
        assert_eq!(
            measured_interval(now, now + Duration::from_secs(1), 1, INTERVAL),
            None
        );
    }

    #[test]
    fn vrr_presentation_updates_tick_interval() {
        let now = Instant::now();
        let mut scheduler = scheduler(now);
        scheduler.outputs.clocks[0].source.variable_refresh = true;
        scheduler.observe_presentation(PresentedOutput {
            id: FAST_OUTPUT,
            observed_at: now + Duration::from_millis(12),
            presented_at: None,
            sequence: Some(1),
        });
        scheduler.observe_presentation(PresentedOutput {
            id: FAST_OUTPUT,
            observed_at: now + Duration::from_millis(24),
            presented_at: None,
            sequence: Some(2),
        });
        scheduler.step(now + Duration::from_millis(24), pending(false, false, true));
        assert_eq!(
            scheduler.output_ticks()[0].interval,
            Duration::from_millis(12)
        );
    }

    #[test]
    fn idle_scheduler_relaxes_poll_timeout_with_bounded_heartbeat() {
        let now = Instant::now();
        let mut scheduler = scheduler(now);
        scheduler.step(now, pending(false, false, true));

        // When completely idle without work, timeout is relaxed to heartbeat (100ms)
        // rather than nominal interval (10ms).
        let idle_timeout = scheduler.limit_dispatch_timeout(now, Duration::from_secs(1), false);
        assert_eq!(idle_timeout, IDLE_HEARTBEAT_TIMEOUT);

        // When work/damage arrives, it immediately clamps to the physical display interval (<=10ms).
        let active_timeout = scheduler.limit_dispatch_timeout(now, Duration::from_secs(1), true);
        assert!(active_timeout <= INTERVAL);
    }

    #[test]
    fn input_or_animation_interrupts_idle_state_immediately() {
        let now = Instant::now();
        let mut scheduler = scheduler(now);
        scheduler.step(now, pending(false, true, true)); // Request Flutter

        // Waiting for Flutter must keep the clock edge active even if has_pending_work is false.
        let dispatch_timeout = scheduler.limit_dispatch_timeout(now, Duration::from_secs(1), false);
        assert!(dispatch_timeout <= INTERVAL);
    }

    #[test]
    fn vrr_same_vblank_produces_at_most_one_flip_and_rejects_duplicate_sequence() {
        let now = Instant::now();
        let mut scheduler = scheduler(now);
        scheduler.outputs.clocks[0].source.variable_refresh = true;

        // First flip in sequence 100
        scheduler.observe_presentation(PresentedOutput {
            id: FAST_OUTPUT,
            observed_at: now + Duration::from_millis(10),
            presented_at: Some(Duration::from_millis(10)),
            sequence: Some(100),
        });
        assert_eq!(
            scheduler.limit_dispatch_timeout(now, Duration::from_secs(1), false),
            Duration::ZERO,
            "presented tick must wake dispatch immediately"
        );

        // Take the tick
        scheduler.step(now + Duration::from_millis(10), pending(false, false, true));
        assert_eq!(scheduler.output_ticks().len(), 1);

        // Inject duplicate presentation within the same vblank sequence 100
        // (even if arrival jitter exceeds half interval)
        scheduler.observe_presentation(PresentedOutput {
            id: FAST_OUTPUT,
            observed_at: now + Duration::from_millis(16),
            presented_at: Some(Duration::from_millis(16)),
            sequence: Some(100),
        });

        // The duplicate sequence must NOT generate a second presented tick
        scheduler.step(now + Duration::from_millis(16), pending(false, false, true));
        assert!(
            scheduler.output_ticks().is_empty(),
            "same vblank presentation must never produce a second tick"
        );
    }

    #[test]
    fn measured_interval_clamps_to_physically_reasonable_lower_bound() {
        let now = Instant::now();
        // 1ms for 10ms nominal display (1000Hz vs 100Hz max) is rejected
        assert_eq!(
            measured_interval(now, now + Duration::from_millis(1), 1, INTERVAL),
            None
        );
        // 5ms for 10ms nominal display (200Hz vs 100Hz max) is rejected
        assert_eq!(
            measured_interval(now, now + Duration::from_millis(5), 1, INTERVAL),
            None
        );
        // 9.5ms for 10ms nominal display (within 10% physical tolerance) is accepted
        assert_eq!(
            measured_interval(now, now + Duration::from_nanos(9_500_000), 1, INTERVAL),
            Some(Duration::from_nanos(9_500_000))
        );
        // 12ms for 10ms nominal display is accepted
        assert_eq!(
            measured_interval(now, now + Duration::from_millis(12), 1, INTERVAL),
            Some(Duration::from_millis(12))
        );
    }

    #[test]
    fn work_aware_governance_with_and_without_direct_scanout() {
        let now = Instant::now();
        let mut scheduler = mixed_scheduler(now);

        // Direct scanout closed, but shell work is on SLOW_OUTPUT:
        scheduler.set_work_output(Some(SLOW_OUTPUT));
        scheduler.set_work_aware(true);

        assert_eq!(scheduler.render_interval(), Some(INTERVAL));

        // When work clears on both:
        scheduler.set_work_output(None);
        scheduler.set_work_aware(false);

        // Falls back to global render output (FAST_OUTPUT)
        assert_eq!(scheduler.render_interval(), Some(FAST_INTERVAL));
    }
}
