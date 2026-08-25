import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../platform/denial_bridge.dart';
import 'notifier_lifecycle.dart';
import 'shell_controller.dart';

final systemLevelHudVisibleDurationProvider = Provider<Duration>(
  (ref) => const Duration(milliseconds: 1200),
);

typedef SystemLevelHudSignals = ({
  Stream<DenialAudioState> audio,
  Stream<DenialBrightnessState> brightness,
  Stream<DenialKeyboardLedState> keyboard,
});

final systemLevelHudSignalsProvider = Provider<SystemLevelHudSignals>((ref) {
  final bridge = ref.watch(denialBridgeProvider);
  return (
    audio: bridge.audioStates,
    brightness: bridge.brightnessStates,
    keyboard: bridge.keyboardLedStates,
  );
});

final systemLevelHudProvider =
    NotifierProvider<SystemLevelHudController, SystemLevelHudState?>(
      SystemLevelHudController.new,
    );

enum SystemLevelHudKind { brightness, audio, keyboard }

@immutable
class SystemLevelHudState {
  const SystemLevelHudState({
    required this.kind,
    required this.level,
    required this.visible,
    required this.revision,
    this.monitorId,
    this.muted = false,
    this.capsLocked = false,
  });

  final SystemLevelHudKind kind;
  final int? monitorId;
  final double level;
  final bool visible;

  /// Whether the output is muted. Only meaningful for the audio kind.
  final bool muted;

  /// Whether Caps Lock is engaged. Only meaningful for the keyboard kind.
  final bool capsLocked;

  /// Changes every time a native update is presented in the HUD.
  final int revision;

  SystemLevelHudState copyWith({bool? visible}) {
    return SystemLevelHudState(
      kind: kind,
      monitorId: monitorId,
      level: level,
      visible: visible ?? this.visible,
      revision: revision,
      muted: muted,
      capsLocked: capsLocked,
    );
  }
}

/// Presents the most recent native brightness, output-volume, or keyboard
/// lock-light update.
///
/// Keeping all signals in one controller ensures that rapid changes across
/// the controls replace one another instead of painting overlapping HUDs.
class SystemLevelHudController extends Notifier<SystemLevelHudState?>
    with NotifierLifecycle<SystemLevelHudState?> {
  @override
  SystemLevelHudState? build() {
    final signals = ref.watch(systemLevelHudSignalsProvider);
    _visibleDuration = ref.watch(systemLevelHudVisibleDurationProvider);
    _hideTimer = null;
    _revision = 0;
    _lastAudioLevel = null;
    _lastAudioMuted = null;
    _lastCapsLock = null;
    _buildGeneration = beginBuildGeneration();
    final generation = _buildGeneration;
    final brightnessSubscription = signals.brightness.listen(
      (update) => _handleBrightnessState(update, generation),
    );
    final audioSubscription = signals.audio.listen(
      (update) => _handleAudioState(update, generation),
    );
    final keyboardSubscription = signals.keyboard.listen(
      (update) => _handleKeyboardLedState(update, generation),
    );
    cancelOnDispose(brightnessSubscription);
    cancelOnDispose(audioSubscription);
    cancelOnDispose(keyboardSubscription);
    ref.onDispose(() {
      _hideTimer?.cancel();
      _hideTimer = null;
    });
    return null;
  }

  late Duration _visibleDuration;
  late int _buildGeneration;
  Timer? _hideTimer;
  int _revision = 0;
  double? _lastAudioLevel;
  bool? _lastAudioMuted;
  bool? _lastCapsLock;

  void _handleBrightnessState(DenialBrightnessState update, int generation) {
    if (!isBuildGenerationActive(generation)) {
      return;
    }
    _show(
      kind: SystemLevelHudKind.brightness,
      monitorId: update.monitorId,
      level: update.level,
    );
  }

  void _handleAudioState(DenialAudioState update, int generation) {
    if (!isBuildGenerationActive(generation)) {
      return;
    }
    final level = update.level.clamp(0.0, 1.0).toDouble();
    final previousLevel = _lastAudioLevel;
    _lastAudioLevel = level;
    final previousMuted = _lastAudioMuted;
    _lastAudioMuted = update.muted;
    // PulseAudio republishes the sink level for stream lifecycle events.
    // Reconciliation reads establish the baseline without presenting the HUD.
    if (update.completesRead) {
      return;
    }
    // Present when the level moves or the mute state flips. A mute toggle
    // leaves the level untouched, so it must be detected on its own.
    if (previousLevel == level && previousMuted == update.muted) {
      return;
    }
    _show(kind: SystemLevelHudKind.audio, level: level, muted: update.muted);
  }

  void _handleKeyboardLedState(DenialKeyboardLedState update, int generation) {
    if (!isBuildGenerationActive(generation)) {
      return;
    }
    final previousCaps = _lastCapsLock;
    _lastCapsLock = update.caps;
    // The first pushed state is the session baseline, not a user gesture. It
    // reflects whichever Caps Lock state the keyboard starts in, so presenting
    // it would fake a toggle on every login.
    if (previousCaps == null || previousCaps == update.caps) {
      return;
    }
    // Only Caps Lock drives an on-screen indicator today; NumLock and
    // ScrollLock are delivered so the shell could render them later without
    // another wire change.
    _show(
      kind: SystemLevelHudKind.keyboard,
      level: update.caps ? 1.0 : 0.0,
      capsLocked: update.caps,
    );
  }

  void _show({
    required SystemLevelHudKind kind,
    required double level,
    int? monitorId,
    bool muted = false,
    bool capsLocked = false,
  }) {
    _hideTimer?.cancel();
    _revision += 1;
    state = SystemLevelHudState(
      kind: kind,
      monitorId: monitorId,
      level: level.clamp(0.0, 1.0).toDouble(),
      visible: true,
      revision: _revision,
      muted: muted,
      capsLocked: capsLocked,
    );
    final generation = _buildGeneration;
    _hideTimer = Timer(_visibleDuration, () {
      if (!isBuildGenerationActive(generation)) {
        return;
      }
      final current = state;
      if (current != null) {
        state = current.copyWith(visible: false);
      }
    });
  }
}
