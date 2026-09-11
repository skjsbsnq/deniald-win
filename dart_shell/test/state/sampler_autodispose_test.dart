import 'package:denial_dart_shell/src/state/system_extended_status.dart';
import 'package:denial_dart_shell/src/state/system_status.dart';
import 'package:denial_dart_shell/src/state/timer_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records every provider disposal so tests can assert that a sampler is torn
/// down once its last listener leaves.
final class _DisposeRecorder extends ProviderObserver {
  final List<Object> disposed = <Object>[];

  @override
  void didDisposeProvider(ProviderObserverContext context) {
    disposed.add(context.provider);
  }
}

void main() {
  test('telemetry selectors dispose with their last listener', () async {
    final recorder = _DisposeRecorder();
    final container = ProviderContainer(observers: [recorder]);
    addTearDown(container.dispose);

    final cpu = container.listen(cpuUsageProvider, (_, _) {});
    final gpu = container.listen(gpuUsageProvider, (_, _) {});
    cpu.close();
    gpu.close();
    // autoDispose disposal is scheduled on a zero-length timer — let the real
    // event loop run it.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(recorder.disposed, contains(cpuUsageProvider));
    expect(recorder.disposed, contains(gpuUsageProvider));
    // The shared 2 s sampler is private; provider toString carries the
    // notifier type arguments, so match on the controller name to prove the
    // underlying sampler — not just its selector facades — was torn down.
    expect(
      recorder.disposed
          .map((provider) => provider.toString())
          .any((name) => name.contains('SystemTelemetryController')),
      isTrue,
    );
  });

  test(
    'extended status and battery samplers dispose with last listener',
    () async {
      final recorder = _DisposeRecorder();
      final container = ProviderContainer(observers: [recorder]);
      addTearDown(container.dispose);

      final extended = container.listen(
        systemExtendedStatusProvider,
        (_, _) {},
      );
      final battery = container.listen(batteryProvider, (_, _) {});
      extended.close();
      battery.close();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Both providers are the samplers themselves: their disposal cancels
      // the 2 s / 15 s timers via ref.onDispose.
      expect(recorder.disposed, contains(systemExtendedStatusProvider));
      expect(recorder.disposed, contains(batteryProvider));
    },
  );

  test('clock provider disposes with its last listener', () async {
    final recorder = _DisposeRecorder();
    final container = ProviderContainer(observers: [recorder]);
    addTearDown(container.dispose);

    final subscription = container.listen(clockProvider, (_, _) {});
    subscription.close();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(recorder.disposed, contains(clockProvider));
  });

  test('clock provider emits a fresh value when listened again', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    var subscription = container.listen(clockProvider, (_, _) {});
    final first = await container.read(clockProvider.future);
    subscription.close();
    await Future<void>.delayed(const Duration(milliseconds: 30));

    // After dispose (or resume) the timer-driven stream emits the current
    // time immediately rather than replaying a stale buffered event.
    subscription = container.listen(clockProvider, (_, _) {});
    addTearDown(subscription.close);
    final second = await container.read(clockProvider.future);
    expect(second.isAfter(first), isTrue);
  });

  testWidgets('timer tool parks its ticker while unlistened', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    var subscription = container.listen(timerToolProvider, (_, _) {});
    addTearDown(subscription.close);
    final controller = container.read(timerToolProvider.notifier);

    // FakeAsync fakes Timer but not DateTime.now, so the suspend anchor uses
    // an injected clock the test can advance independently.
    var fakeNow = DateTime(2026, 9, 11, 12);
    controller.now = () => fakeNow;

    controller.switchMode(TimerMode.stopwatch);
    controller.start();
    await tester.pump(const Duration(seconds: 3));
    expect(
      container.read(timerToolProvider).elapsed,
      const Duration(seconds: 3),
    );
    expect(controller.debugTickerActive, isTrue);

    // Closing the dashboard removes the last listener: the ticker parks, so
    // fake-time pumps can no longer tick, but the wall clock still advances.
    subscription.close();
    await tester.pump();
    expect(controller.debugTickerActive, isFalse);

    await tester.pump(const Duration(seconds: 10));
    fakeNow = fakeNow.add(const Duration(seconds: 10));
    expect(container.read(timerToolProvider).elapsed.inSeconds, 3);

    // Reopening folds the ten hidden seconds into elapsed and restarts the
    // ticker.
    subscription = container.listen(timerToolProvider, (_, _) {});
    await tester.pump();
    expect(
      container.read(timerToolProvider).elapsed,
      const Duration(seconds: 13),
    );
    expect(controller.debugTickerActive, isTrue);

    await tester.pump(const Duration(seconds: 2));
    expect(
      container.read(timerToolProvider).elapsed,
      const Duration(seconds: 15),
    );

    controller.pause();
    await tester.pump();
  });

  testWidgets('a lap recorded while hidden still anchors the hidden span', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    var subscription = container.listen(timerToolProvider, (_, _) {});
    addTearDown(subscription.close);
    final controller = container.read(timerToolProvider.notifier);

    var fakeNow = DateTime(2026, 9, 11, 12);
    controller.now = () => fakeNow;

    controller.switchMode(TimerMode.stopwatch);
    controller.start();
    await tester.pump(const Duration(seconds: 5));
    subscription.close();
    await tester.pump();
    expect(controller.debugTickerActive, isFalse);

    // Ten hidden seconds, a lap, then ten more hidden seconds: the lap must
    // include the first span and the resumed clock the second.
    fakeNow = fakeNow.add(const Duration(seconds: 10));
    controller.lap();
    fakeNow = fakeNow.add(const Duration(seconds: 10));

    subscription = container.listen(timerToolProvider, (_, _) {});
    await tester.pump();
    final state = container.read(timerToolProvider);
    expect(state.elapsed, const Duration(seconds: 25));
    expect(state.laps.single, const Duration(seconds: 15));

    controller.pause();
    await tester.pump();
  });

  testWidgets('a pomodoro that ends while unlistened still completes', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    var subscription = container.listen(timerToolProvider, (_, _) {});
    addTearDown(subscription.close);
    final controller = container.read(timerToolProvider.notifier);

    var fakeNow = DateTime(2026, 9, 11, 12);
    controller.now = () => fakeNow;

    controller.switchMode(TimerMode.pomodoroBreak);
    controller.start();
    await tester.pump(const Duration(seconds: 60));
    expect(
      container.read(timerToolProvider).elapsed,
      const Duration(seconds: 60),
    );

    // The five-minute break ends while the panel is closed: the ticker is
    // parked but the countdown still finishes on schedule.
    subscription.close();
    await tester.pump();
    expect(controller.debugTickerActive, isFalse);
    fakeNow = fakeNow.add(const Duration(minutes: 5));
    await tester.pump(const Duration(minutes: 1));

    subscription = container.listen(timerToolProvider, (_, _) {});
    await tester.pump();
    final state = container.read(timerToolProvider);
    expect(state.running, isFalse);
    expect(state.elapsed, const Duration(minutes: 5));
    expect(controller.debugTickerActive, isFalse);
  });
}
