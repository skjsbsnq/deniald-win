import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'notifier_lifecycle.dart';

enum TimerMode { pomodoroFocus, pomodoroBreak, stopwatch }

@immutable
class TimerToolState {
  const TimerToolState({
    this.mode = TimerMode.pomodoroFocus,
    this.running = false,
    this.elapsed = Duration.zero,
    this.target = _focusDuration,
    this.laps = const <Duration>[],
    this._lapAnchor,
  });

  static const Duration _focusDuration = Duration(minutes: 25);
  static const Duration _breakDuration = Duration(minutes: 5);

  final TimerMode mode;
  final bool running;

  /// Accumulated time for the stopwatch, or remaining time for pomodoro.
  final Duration elapsed;
  final Duration target;
  final List<Duration> laps;
  final Duration? _lapAnchor;

  /// Laps kept per stopwatch, oldest first; the oldest is dropped once the
  /// cap is hit (a lap is a tiny value, but an unbounded list never
  /// shrinks). Same ring-buffer shape as [LoadSeries.capacity].
  static const int lapCapacity = 99;

  /// Elapsed time at the last recorded lap; the next lap's split is
  /// `elapsed - lapAnchor`. Untracked in [copyWith] deliberately: internal
  /// only, so callers cannot desynchronize it from [laps].
  Duration get lapAnchor => _lapAnchor ?? Duration.zero;

  double get pomodoroProgress {
    if (target.inMilliseconds <= 0) {
      return 0.0;
    }
    return ((target.inMilliseconds - elapsed.inMilliseconds) /
            target.inMilliseconds)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  TimerToolState copyWith({
    TimerMode? mode,
    bool? running,
    Duration? elapsed,
    Duration? target,
    List<Duration>? laps,
  }) {
    return TimerToolState(
      mode: mode ?? this.mode,
      running: running ?? this.running,
      elapsed: elapsed ?? this.elapsed,
      target: target ?? this.target,
      laps: laps ?? this.laps,
    );
  }
}

final timerToolProvider = NotifierProvider<TimerToolController, TimerToolState>(
  TimerToolController.new,
);

/// One shared 1 Hz ticker for the pomodoro countdown and the stopwatch.
/// The tick advances the clock only while [running], and the pomodoro
/// advances elapsed time toward [target] so the ring drains as work happens.
///
/// Deliberately not autoDispose: a countdown is expected to outlive the panel
/// that started it. The last watcher unsubscribes whenever the dashboard
/// closes, and autoDispose would cancel the ticker and silently drop the
/// elapsed time. The ticker only runs while [running] and a listener exists —
/// losing the last listener suspends it on a wall-clock anchor, so an idle or
/// hidden timer costs nothing.
class TimerToolController extends Notifier<TimerToolState>
    with NotifierLifecycle<TimerToolState> {
  Timer? _timer;

  /// Wall-clock instant the ticker was suspended because the provider lost its
  /// last listener. While set, [TimerToolState.elapsed] trails real time and
  /// is caught up from this anchor when a listener returns, so a countdown
  /// hidden with the dashboard still ends on schedule.
  DateTime? _suspendedAt;

  /// Injectable wall clock for the suspend/resume catch-up; tests substitute a
  /// controllable source because FakeAsync does not fake [DateTime.now].
  @visibleForTesting
  DateTime Function() now = DateTime.now;

  @override
  TimerToolState build() {
    beginBuildGeneration();
    _suspendedAt = null;
    ref.onCancel(_suspendTicker);
    // Lifecycle callbacks may not touch state; the catch-up and ticker
    // restart run in a microtask once the callback returns.
    ref.onResume(() => scheduleMicrotask(_resumeTicker));
    ref.onDispose(() {
      _timer?.cancel();
      _timer = null;
      _suspendedAt = null;
    });
    return const TimerToolState();
  }

  @visibleForTesting
  bool get debugTickerActive => _timer != null;

  void start() {
    if (state.running) {
      return;
    }
    state = state.copyWith(running: true);
    if (ref.isPaused) {
      // Started while no listener can observe the ticker: count the span on
      // the next resume instead of running a timer nobody sees.
      _suspendedAt = now();
      return;
    }
    _startTicker(currentBuildGeneration);
  }

  void pause() {
    if (!state.running) {
      return;
    }
    _timer?.cancel();
    _timer = null;
    _materializeSuspendedElapsed();
    state = state.copyWith(running: false);
  }

  void reset() {
    _timer?.cancel();
    _timer = null;
    _suspendedAt = null;
    state = TimerToolState(mode: state.mode, target: state.target);
  }

  void switchMode(TimerMode mode) {
    _timer?.cancel();
    _timer = null;
    _suspendedAt = null;
    final target = switch (mode) {
      TimerMode.pomodoroFocus => TimerToolState._focusDuration,
      TimerMode.pomodoroBreak => TimerToolState._breakDuration,
      TimerMode.stopwatch => Duration.zero,
    };
    state = TimerToolState(mode: mode, target: target);
  }

  void lap() {
    if (state.mode != TimerMode.stopwatch || !state.running) {
      return;
    }
    _materializeSuspendedElapsed();
    // Materializing cleared the suspension anchor; re-anchor so the span
    // between this lap and the next resume still counts while unlistened.
    if (ref.isPaused) {
      _suspendedAt = now();
    }
    // Record the split since the previous lap, not the cumulative elapsed:
    // the lap list feeds the per-row display directly. The anchor derives
    // from the laps themselves, so a state restored from persistence (no
    // anchor) laps correctly from the current elapsed.
    final anchor = state.laps.isEmpty
        ? state.lapAnchor
        : state.laps.fold<Duration>(
            state.lapAnchor,
            (total, lap) => total + lap,
          );
    final next = <Duration>[...state.laps, state.elapsed - anchor];
    if (next.length > TimerToolState.lapCapacity) {
      next.removeRange(0, next.length - TimerToolState.lapCapacity);
    }
    state = state.copyWith(laps: List<Duration>.unmodifiable(next));
  }

  void _startTicker(int generation) {
    _timer?.cancel();
    _timer = null;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!isBuildGenerationActive(generation)) {
        return;
      }
      _tick();
    });
  }

  /// Parks the 1 Hz ticker while no listener can observe it. The provider is
  /// deliberately not autoDispose — a countdown must outlive the panel that
  /// started it — so elapsed time is anchored to the wall clock and caught up
  /// by [_resumeTicker] instead of being dropped. The anchor is kept (not
  /// re-stamped) when already suspended, so a transient listener that resumes
  /// and immediately cancels again does not truncate the hidden span.
  void _suspendTicker() {
    _timer?.cancel();
    _timer = null;
    _suspendedAt ??= now();
  }

  void _resumeTicker() {
    _materializeSuspendedElapsed();
    if (!ref.mounted || !state.running || _timer != null) {
      return;
    }
    if (ref.isPaused) {
      // The listener that triggered the resume is already gone (a bare read
      // subscribes and closes synchronously): stay suspended on a fresh anchor.
      _suspendedAt = now();
      return;
    }
    _startTicker(currentBuildGeneration);
  }

  /// Folds the time spent suspended into [TimerToolState.elapsed]; a pomodoro
  /// that crossed its target while hidden completes instead of overrunning.
  void _materializeSuspendedElapsed() {
    final suspendedAt = _suspendedAt;
    _suspendedAt = null;
    if (suspendedAt == null || !state.running) {
      return;
    }
    _advance(state.elapsed + now().difference(suspendedAt));
  }

  void _tick() {
    _advance(state.elapsed + const Duration(seconds: 1));
  }

  void _advance(Duration next) {
    if (!state.running) {
      return;
    }
    switch (state.mode) {
      case TimerMode.stopwatch:
        state = state.copyWith(elapsed: next);
      case TimerMode.pomodoroFocus:
      case TimerMode.pomodoroBreak:
        if (next >= state.target) {
          _timer?.cancel();
          _timer = null;
          state = state.copyWith(running: false, elapsed: state.target);
          return;
        }
        state = state.copyWith(elapsed: next);
    }
  }
}
