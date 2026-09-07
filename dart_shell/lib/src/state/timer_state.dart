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
  });

  static const Duration _focusDuration = Duration(minutes: 25);
  static const Duration _breakDuration = Duration(minutes: 5);

  final TimerMode mode;
  final bool running;

  /// Accumulated time for the stopwatch, or remaining time for pomodoro.
  final Duration elapsed;
  final Duration target;
  final List<Duration> laps;

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
/// elapsed time. The ticker only runs while [running], so an idle timer costs
/// nothing.
class TimerToolController extends Notifier<TimerToolState>
    with NotifierLifecycle<TimerToolState> {
  Timer? _timer;

  @override
  TimerToolState build() {
    beginBuildGeneration();
    ref.onDispose(() {
      _timer?.cancel();
      _timer = null;
    });
    return const TimerToolState();
  }

  void start() {
    if (state.running) {
      return;
    }
    final generation = currentBuildGeneration;
    state = state.copyWith(running: true);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!isBuildGenerationActive(generation)) {
        return;
      }
      _tick();
    });
  }

  void pause() {
    if (!state.running) {
      return;
    }
    _timer?.cancel();
    _timer = null;
    state = state.copyWith(running: false);
  }

  void reset() {
    _timer?.cancel();
    _timer = null;
    state = TimerToolState(mode: state.mode, target: state.target);
  }

  void switchMode(TimerMode mode) {
    _timer?.cancel();
    _timer = null;
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
    state = state.copyWith(laps: <Duration>[...state.laps, state.elapsed]);
  }

  void _tick() {
    if (!state.running) {
      return;
    }
    switch (state.mode) {
      case TimerMode.stopwatch:
        state = state.copyWith(
          elapsed: state.elapsed + const Duration(seconds: 1),
        );
      case TimerMode.pomodoroFocus:
      case TimerMode.pomodoroBreak:
        final next = state.elapsed + const Duration(seconds: 1);
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
