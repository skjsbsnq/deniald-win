import 'dart:async';

import 'package:denial_dart_shell/src/models/display_layout.dart';
import 'package:denial_dart_shell/src/platform/denial_bridge.dart';
import 'package:denial_dart_shell/src/state/display_brightness.dart';
import 'package:denial_dart_shell/src/state/display_layout.dart';
import 'package:denial_dart_shell/src/state/quick_settings.dart';
import 'package:denial_dart_shell/src/state/shell_controller.dart';
import 'package:denial_dart_shell/src/widgets/shade/range_bar.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/mobile_motion_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer makeContainer(_Q01Bridge bridge) {
    final container = ProviderContainer(
      overrides: [denialBridgeProvider.overrideWithValue(bridge)],
    );
    addTearDown(container.dispose);
    addTearDown(bridge.dispose);
    return container;
  }

  test(
    'controls stay unloaded instead of exposing placeholder levels',
    () async {
      final bridge = _Q01Bridge()
        ..layout = DisplayLayout.fallback(const Size(1600, 900), 1)
        ..onReadBrightness = (monitorId, connector) {
          return Completer<double?>().future;
        }
        ..onReadAudio = () {
          return Completer<double?>().future;
        };
      final container = makeContainer(bridge);

      final initial = container.read(quickSettingsProvider);
      // The stored numbers are inert seeds; the loaded flags are what mark a
      // value as a real reading, and both start unset.
      expect(initial.brightnessLoaded, isFalse);
      expect(initial.volumeLoaded, isFalse);

      // Reads are still in flight; nothing may pretend to be a real level yet.
      await pumpEventQueue();
      final pending = container.read(quickSettingsProvider);
      expect(pending.brightnessLoaded, isFalse);
      expect(pending.volumeLoaded, isFalse);

      bridge.emitBrightness(0, 0.8);
      bridge.emitAudio(0.55);
      await pumpEventQueue();
      final loaded = container.read(quickSettingsProvider);
      expect(loaded.brightnessLoaded, isTrue);
      expect(loaded.brightness, 0.8);
      expect(loaded.volumeLoaded, isTrue);
      expect(loaded.volume, 0.55);
    },
  );

  test('a dependency rebuild keeps levels that were already loaded', () async {
    final brightnessGate = Completer<double?>();
    final audioGate = Completer<double?>();
    var brightnessReads = 0;
    var audioReads = 0;
    final bridge = _Q01Bridge()
      ..layout = DisplayLayout.fallback(const Size(1600, 900), 1)
      ..onReadBrightness = (monitorId, connector) {
        brightnessReads++;
        return brightnessReads == 1
            ? Future<double?>.value(0.9)
            : brightnessGate.future;
      }
      ..onReadAudio = () {
        audioReads++;
        return audioReads == 1 ? Future<double?>.value(0.55) : audioGate.future;
      };
    final container = makeContainer(bridge);

    container.read(quickSettingsProvider);
    await pumpEventQueue();
    expect(container.read(quickSettingsProvider).brightness, 0.9);
    expect(container.read(quickSettingsProvider).volume, 0.55);

    // A fresh layout instance invalidates the service chain while both
    // re-reads hang on the gates: the only way the levels survive the forced
    // rebuild is stateOrNull carry-over.
    bridge.emitLayout(DisplayLayout.fallback(const Size(1600, 900), 1));
    await pumpEventQueue();
    final state = container.read(quickSettingsProvider);
    expect(state.brightnessLoaded, isTrue);
    expect(state.brightness, 0.9);
    expect(state.volumeLoaded, isTrue);
    expect(state.volume, 0.55);

    // The rebuild did run: its initial-load pass issued a fresh read that is
    // now parked on the gate.
    await pumpEventQueue();
    expect(brightnessReads, greaterThanOrEqualTo(2));
  });

  test(
    'brightness events are cached until the layout names a monitor',
    () async {
      final bridge = _Q01Bridge()
        ..onReadBrightness = (monitorId, connector) =>
            Completer<double?>().future;
      final container = makeContainer(bridge);
      container.read(quickSettingsProvider);
      await pumpEventQueue();

      // The default monitor is still unknown; the event must not be dropped.
      bridge.emitBrightness(0, 0.83);
      bridge.emitBrightness(9, 0.2);
      await pumpEventQueue();
      expect(container.read(quickSettingsProvider).brightnessLoaded, isFalse);

      // Once the layout resolves, the cached level for that monitor is
      // applied even though the fresh read is still pending. The read forces
      // the invalidated rebuild; the following pump lets its load pass run.
      bridge.emitLayout(DisplayLayout.fallback(const Size(1600, 900), 1));
      await pumpEventQueue();
      container.read(quickSettingsProvider);
      await pumpEventQueue();
      final state = container.read(quickSettingsProvider);
      expect(state.brightnessLoaded, isTrue);
      expect(state.brightness, 0.83);
    },
  );

  test('a null initial read retries until a real level arrives', () async {
    var reads = 0;
    final bridge = _Q01Bridge()
      ..layout = DisplayLayout.fallback(const Size(1600, 900), 1)
      ..onReadBrightness = (monitorId, connector) async {
        reads++;
        return reads < 3 ? null : 0.8;
      };
    final container = makeContainer(bridge);
    // Resolve the layout first so every retry reaches the bridge.
    container.read(displayLayoutProvider);
    await pumpEventQueue();
    container.read(quickSettingsProvider);
    await pumpEventQueue();
    expect(container.read(quickSettingsProvider).brightnessLoaded, isFalse);

    await Future<void>.delayed(const Duration(milliseconds: 700));
    await pumpEventQueue();
    final state = container.read(quickSettingsProvider);
    expect(reads, greaterThanOrEqualTo(3));
    expect(state.brightnessLoaded, isTrue);
    expect(state.brightness, 0.8);
  });

  test('null reads give up after a bounded number of attempts', () async {
    var reads = 0;
    final bridge = _Q01Bridge()
      ..layout = DisplayLayout.fallback(const Size(1600, 900), 1)
      ..onReadBrightness = (monitorId, connector) async {
        reads++;
        return null;
      }
      ..onReadAudio = () async {
        return null;
      };
    final container = makeContainer(bridge);
    // Resolve the layout first so every retry reaches the bridge.
    container.read(displayLayoutProvider);
    await pumpEventQueue();
    container.read(quickSettingsProvider);
    await pumpEventQueue();

    // 16 attempts at 250ms spacing: the last attempt lands around 3.75s.
    await Future<void>.delayed(const Duration(milliseconds: 4200));
    await pumpEventQueue();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(reads, 16);
    expect(container.read(quickSettingsProvider).brightnessLoaded, isFalse);
  });

  test(
    'display brightness seeds no placeholder and reset rewrites the known level',
    () async {
      final bridge = _Q01Bridge()
        ..layout = DisplayLayout.fallback(const Size(1600, 900), 1)
        ..onReadBrightness = (monitorId, connector) async => 0.9;
      final container = makeContainer(bridge);

      // Resolve the layout first so the provider's first build already sees
      // the output and can mark it as still loading.
      container.read(displayLayoutProvider);
      await pumpEventQueue();

      final seed = container.read(displayBrightnessProvider);
      expect(seed.levels, isNot(containsValue(0.72)));
      expect(seed.levels, isEmpty);
      expect(seed.loading, contains(0));

      await pumpEventQueue();
      final loaded = container.read(displayBrightnessProvider);
      expect(loaded.levels[0], 0.9);
      expect(loaded.loading, isEmpty);

      container.read(displayBrightnessProvider.notifier).reset();
      await pumpEventQueue();
      expect(bridge.brightnessWrites, hasLength(1));
      final write = bridge.brightnessWrites.single;
      expect(write.monitorId, 0);
      expect(write.level, closeTo(0.9, 0.001));
    },
  );

  test(
    'a transient output read failure retries instead of disabling forever',
    () async {
      var reads = 0;
      final bridge = _Q01Bridge()
        ..layout = DisplayLayout.fallback(const Size(1600, 900), 1)
        ..onReadBrightness = (monitorId, connector) async {
          reads++;
          return reads < 3 ? null : 0.9;
        };
      final container = makeContainer(bridge);
      container.read(displayLayoutProvider);
      await pumpEventQueue();
      container.read(displayBrightnessProvider);
      await pumpEventQueue();
      expect(container.read(displayBrightnessProvider).levels, isEmpty);

      await Future<void>.delayed(const Duration(milliseconds: 700));
      await pumpEventQueue();
      expect(reads, greaterThanOrEqualTo(3));
      final state = container.read(displayBrightnessProvider);
      expect(state.levels[0], 0.9);
      expect(state.loading, isEmpty);
    },
  );

  test('reset skips outputs whose level was never read', () async {
    final bridge = _Q01Bridge()
      ..layout = DisplayLayout.fallback(const Size(1600, 900), 1)
      ..onReadBrightness = (monitorId, connector) async => null;
    final container = makeContainer(bridge);
    container.read(displayLayoutProvider);
    await pumpEventQueue();
    container.read(displayBrightnessProvider);
    await pumpEventQueue();

    final state = container.read(displayBrightnessProvider);
    expect(state.levels, isEmpty);

    container.read(displayBrightnessProvider.notifier).reset();
    await pumpEventQueue();
    expect(bridge.brightnessWrites, isEmpty);

    // A native update still populates the output even though no read ever
    // produced a level for it.
    bridge.emitBrightness(0, 0.66);
    await pumpEventQueue();
    expect(container.read(displayBrightnessProvider).levels[0], 0.66);
  });

  testWidgets('disabling mid-drag reports the interrupted gesture end', (
    tester,
  ) async {
    final ended = <double>[];
    var enabled = true;
    late StateSetter setEnabled;
    await tester.pumpWidget(
      mobileMotionHarness(
        StatefulBuilder(
          builder: (context, setState) {
            setEnabled = setState;
            return RangeBar(
              icon: Icons.volume_up_rounded,
              value: 0.4,
              activeColor: const Color(0xFF111111),
              inactiveColor: const Color(0xFF222222),
              onChanged: (_) {},
              onChangeEnd: ended.add,
              enabled: enabled,
              height: 56,
            );
          },
        ),
      ),
    );

    // Keep the pointer down so the drag is still in flight when the bar is
    // disabled; a silent drop would leave the caller's interaction state on.
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(RangeBar)),
    );
    await gesture.moveBy(const Offset(80, 0));
    await tester.pump();
    expect(ended, isEmpty);

    setEnabled(() => enabled = false);
    await tester.pump();
    await tester.pump();
    expect(ended, hasLength(1));
    await gesture.up();
  });
}

class _Q01Bridge extends DenialBridge {
  DisplayLayout? layout;
  Future<double?> Function(int monitorId, String connector) onReadBrightness =
      (monitorId, connector) async => null;
  Future<double?> Function() onReadAudio = () async => null;
  final List<({int monitorId, String connector, double level})>
  brightnessWrites = <({int monitorId, String connector, double level})>[];

  final StreamController<DenialBrightnessState> _brightnessStates =
      StreamController<DenialBrightnessState>.broadcast();
  final StreamController<DenialAudioState> _audioStates =
      StreamController<DenialAudioState>.broadcast();
  final StreamController<DisplayLayout> _displayLayouts =
      StreamController<DisplayLayout>.broadcast();

  @override
  Stream<DenialBrightnessState> get brightnessStates =>
      _brightnessStates.stream;

  @override
  Stream<DenialAudioState> get audioStates => _audioStates.stream;

  @override
  Stream<DisplayLayout> get displayLayouts => _displayLayouts.stream;

  @override
  Future<DisplayLayout?> getDisplayLayout() async => layout;

  @override
  Future<double?> readBrightnessLevel({
    required int monitorId,
    required String connector,
  }) {
    return onReadBrightness(monitorId, connector);
  }

  @override
  Future<double?> readAudioLevel() => onReadAudio();

  @override
  bool setBrightness({
    required int monitorId,
    required String connector,
    required double level,
  }) {
    brightnessWrites.add((
      monitorId: monitorId,
      connector: connector,
      level: level,
    ));
    return true;
  }

  void emitBrightness(int monitorId, double level) {
    _brightnessStates.add(
      DenialBrightnessState(monitorId: monitorId, level: level),
    );
  }

  void emitAudio(double level, {int requestSerial = 0}) {
    _audioStates.add(
      DenialAudioState(level: level, requestSerial: requestSerial),
    );
  }

  void emitLayout(DisplayLayout next) => _displayLayouts.add(next);

  @override
  void dispose() {
    unawaited(_brightnessStates.close());
    unawaited(_audioStates.close());
    unawaited(_displayLayouts.close());
    super.dispose();
  }
}
