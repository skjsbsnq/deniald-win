import 'package:denial_dart_shell/src/state/timer_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Drives the real 1 Hz ticker by pumping fake time one second at a time.
class _Ticker {
  _Ticker(this._tester);

  final WidgetTester _tester;

  Future<void> seconds(int count) async {
    for (var i = 0; i < count; i++) {
      await _tester.pump(const Duration(seconds: 1));
    }
  }
}

void main() {
  Future<void> stopTicker(WidgetTester tester, TimerToolController controller) async {
    // The periodic 1 Hz timer trips the pending-timer invariant at teardown
    // unless it is cancelled while the fake clock is still under test.
    controller.pause();
    await tester.pump();
  }

  testWidgets('stopwatch laps record splits, not cumulative time', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    // A listener keeps the non-autoDispose provider's controller alive and
    // its ticker observable through pump.
    final subscription = container.listen(timerToolProvider, (_, _) {});
    addTearDown(subscription.close);
    final controller = container.read(timerToolProvider.notifier);
    final ticker = _Ticker(tester);

    controller.switchMode(TimerMode.stopwatch);
    controller.start();

    // 3:00 total with laps at 1:00 / 2:00 / 3:00 — each split is 1:00.
    await ticker.seconds(60);
    controller.lap();
    await ticker.seconds(60);
    controller.lap();
    await ticker.seconds(60);
    controller.lap();

    await stopTicker(tester, controller);
    final laps = container.read(timerToolProvider).laps;
    expect(laps, hasLength(3));
    expect(laps[0], const Duration(minutes: 1));
    expect(laps[1], const Duration(minutes: 1));
    expect(laps[2], const Duration(minutes: 1));
  });

  testWidgets('laps are capped at 99; the oldest drops first', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final subscription = container.listen(timerToolProvider, (_, _) {});
    addTearDown(subscription.close);
    final controller = container.read(timerToolProvider.notifier);
    final ticker = _Ticker(tester);

    controller.switchMode(TimerMode.stopwatch);
    controller.start();

    for (var i = 0; i < 100; i++) {
      controller.lap();
      await ticker.seconds(1);
    }

    await stopTicker(tester, controller);
    final state = container.read(timerToolProvider);
    expect(state.laps, hasLength(TimerToolState.lapCapacity));
    // 100 laps taken one second apart; the first (0 s) dropped, so the
    // oldest kept is 1 s and every split is exactly 1 s.
    expect(state.laps.first, const Duration(seconds: 1));
    expect(state.laps.last, const Duration(seconds: 1));
  });

  testWidgets('a lap after pause and resume measures the resumed interval', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final subscription = container.listen(timerToolProvider, (_, _) {});
    addTearDown(subscription.close);
    final controller = container.read(timerToolProvider.notifier);
    final ticker = _Ticker(tester);

    controller.switchMode(TimerMode.stopwatch);
    controller.start();
    await ticker.seconds(10);
    controller.pause();
    // The pause freezes elapsed, so no time accrues while paused.
    await ticker.seconds(10);
    controller.start();
    await ticker.seconds(5);
    controller.lap();

    // Total elapsed 15 s; the lap covers the whole running span (splits do
    // not span paused time), so the split is 15 s.
    final state = container.read(timerToolProvider);
    expect(state.elapsed, const Duration(seconds: 15));
    expect(state.laps.single, const Duration(seconds: 15));

    // The next lap measures only from the previous one.
    await ticker.seconds(7);
    controller.lap();
    await stopTicker(tester, controller);
    expect(container.read(timerToolProvider).laps[1], const Duration(
      seconds: 7,
    ));
  });

  testWidgets('lap is ignored outside stopwatch mode and while paused', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final subscription = container.listen(timerToolProvider, (_, _) {});
    addTearDown(subscription.close);
    final controller = container.read(timerToolProvider.notifier);

    // Pomodoro mode: lap does nothing.
    controller.start();
    controller.lap();
    expect(container.read(timerToolProvider).laps, isEmpty);
    await stopTicker(tester, controller);

    // Stopwatch mode but paused: lap does nothing.
    controller.switchMode(TimerMode.stopwatch);
    controller.lap();
    expect(container.read(timerToolProvider).laps, isEmpty);
  });
}
