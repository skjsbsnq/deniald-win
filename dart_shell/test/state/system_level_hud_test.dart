import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:denial_dart_shell/src/platform/denial_bridge.dart';
import 'package:denial_dart_shell/src/state/system_level_hud.dart';

void main() {
  test(
    'system level HUD shows changed levels and rearms its timeout',
    () async {
      final brightnessUpdates =
          StreamController<DenialBrightnessState>.broadcast(sync: true);
      final audioUpdates = StreamController<DenialAudioState>.broadcast(
        sync: true,
      );
      final keyboardUpdates =
          StreamController<DenialKeyboardLedState>.broadcast(sync: true);
      addTearDown(brightnessUpdates.close);
      addTearDown(audioUpdates.close);
      addTearDown(keyboardUpdates.close);
      final container = ProviderContainer.test(
        overrides: [
          systemLevelHudSignalsProvider.overrideWithValue((
            audio: audioUpdates.stream,
            brightness: brightnessUpdates.stream,
            keyboard: keyboardUpdates.stream,
          )),
          systemLevelHudVisibleDurationProvider.overrideWithValue(
            const Duration(milliseconds: 30),
          ),
        ],
      );
      container.read(systemLevelHudProvider.notifier);
      audioUpdates.add(
        const DenialAudioState(
          level: 0.20,
          requestSerial: 0,
          completesRead: true,
        ),
      );
      expect(
        container.read(systemLevelHudProvider),
        isNull,
        reason: 'a reconciliation read must not look like a volume gesture',
      );

      brightnessUpdates.add(
        const DenialBrightnessState(monitorId: 4, level: 0.35),
      );
      expect(
        container.read(systemLevelHudProvider)?.kind,
        SystemLevelHudKind.brightness,
      );
      expect(container.read(systemLevelHudProvider)?.monitorId, 4);
      expect(container.read(systemLevelHudProvider)?.level, 0.35);
      expect(container.read(systemLevelHudProvider)?.visible, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 20));
      audioUpdates.add(const DenialAudioState(level: 0.60, requestSerial: 17));
      expect(
        container.read(systemLevelHudProvider)?.kind,
        SystemLevelHudKind.audio,
      );
      expect(container.read(systemLevelHudProvider)?.monitorId, isNull);
      expect(container.read(systemLevelHudProvider)?.level, 0.60);
      expect(container.read(systemLevelHudProvider)?.visible, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        container.read(systemLevelHudProvider)?.visible,
        isTrue,
        reason: 'the audio update must replace the brightness hide deadline',
      );

      final audioRevision = container.read(systemLevelHudProvider)!.revision;
      audioUpdates.add(const DenialAudioState(level: 0.60, requestSerial: 0));
      expect(
        container.read(systemLevelHudProvider)?.revision,
        audioRevision,
        reason: 'an unchanged level must not present or rearm the volume HUD',
      );
      await Future<void>.delayed(const Duration(milliseconds: 25));
      expect(container.read(systemLevelHudProvider)?.visible, isFalse);

      audioUpdates.add(const DenialAudioState(level: 0.65, requestSerial: 0));
      expect(container.read(systemLevelHudProvider)?.visible, isTrue);
      expect(container.read(systemLevelHudProvider)?.level, 0.65);
      expect(
        container.read(systemLevelHudProvider)?.revision,
        audioRevision + 1,
      );
    },
  );

  test(
    'a mute toggle presents the audio HUD even when the level is unchanged',
    () async {
      final brightnessUpdates =
          StreamController<DenialBrightnessState>.broadcast(sync: true);
      final audioUpdates = StreamController<DenialAudioState>.broadcast(
        sync: true,
      );
      final keyboardUpdates =
          StreamController<DenialKeyboardLedState>.broadcast(sync: true);
      addTearDown(brightnessUpdates.close);
      addTearDown(audioUpdates.close);
      addTearDown(keyboardUpdates.close);
      final container = ProviderContainer.test(
        overrides: [
          systemLevelHudSignalsProvider.overrideWithValue((
            audio: audioUpdates.stream,
            brightness: brightnessUpdates.stream,
            keyboard: keyboardUpdates.stream,
          )),
          systemLevelHudVisibleDurationProvider.overrideWithValue(
            const Duration(minutes: 1),
          ),
        ],
      );
      container.read(systemLevelHudProvider.notifier);

      // Baseline read establishes the muted state without presenting.
      audioUpdates.add(
        const DenialAudioState(
          level: 0.50,
          requestSerial: 0,
          completesRead: true,
          muted: false,
        ),
      );
      expect(container.read(systemLevelHudProvider), isNull);

      // Same level, muted flips: the HUD must appear.
      audioUpdates.add(
        const DenialAudioState(level: 0.50, requestSerial: 0, muted: true),
      );
      final state = container.read(systemLevelHudProvider);
      expect(state?.kind, SystemLevelHudKind.audio);
      expect(state?.visible, isTrue);
      expect(state?.muted, isTrue);
      expect(state?.level, 0.50);

      // An identical republish must not rearm the HUD.
      final revision = state!.revision;
      audioUpdates.add(
        const DenialAudioState(level: 0.50, requestSerial: 0, muted: true),
      );
      expect(container.read(systemLevelHudProvider)?.revision, revision);
    },
  );

  test('a Caps Lock toggle presents the keyboard HUD once per flip', () async {
    final brightnessUpdates = StreamController<DenialBrightnessState>.broadcast(
      sync: true,
    );
    final audioUpdates = StreamController<DenialAudioState>.broadcast(
      sync: true,
    );
    final keyboardUpdates = StreamController<DenialKeyboardLedState>.broadcast(
      sync: true,
    );
    addTearDown(brightnessUpdates.close);
    addTearDown(audioUpdates.close);
    addTearDown(keyboardUpdates.close);
    final container = ProviderContainer.test(
      overrides: [
        systemLevelHudSignalsProvider.overrideWithValue((
          audio: audioUpdates.stream,
          brightness: brightnessUpdates.stream,
          keyboard: keyboardUpdates.stream,
        )),
        systemLevelHudVisibleDurationProvider.overrideWithValue(
          const Duration(minutes: 1),
        ),
      ],
    );
    container.read(systemLevelHudProvider.notifier);

    keyboardUpdates.add(
      const DenialKeyboardLedState(caps: false, num: false, scroll: false),
    );
    expect(
      container.read(systemLevelHudProvider),
      isNull,
      reason: 'the initial off state is a baseline, not a gesture',
    );

    keyboardUpdates.add(
      const DenialKeyboardLedState(caps: true, num: false, scroll: false),
    );
    final on = container.read(systemLevelHudProvider);
    expect(on?.kind, SystemLevelHudKind.keyboard);
    expect(on?.capsLocked, isTrue);
    expect(on?.visible, isTrue);
    final onRevision = on!.revision;

    // Repeated pushes of the same caps state must not re-present.
    keyboardUpdates.add(
      const DenialKeyboardLedState(caps: true, num: false, scroll: false),
    );
    expect(container.read(systemLevelHudProvider)?.revision, onRevision);

    keyboardUpdates.add(
      const DenialKeyboardLedState(caps: false, num: true, scroll: false),
    );
    final off = container.read(systemLevelHudProvider);
    expect(off?.kind, SystemLevelHudKind.keyboard);
    expect(off?.capsLocked, isFalse);
    expect(off?.revision, onRevision + 1);
  });
}
