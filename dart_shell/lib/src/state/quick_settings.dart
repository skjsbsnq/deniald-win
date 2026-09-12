import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../platform/denial_bridge.dart';
import '../services/audio_service.dart';
import '../services/brightness_service.dart';
import '../services/power_profile_service.dart';
import '../services/system_actions_service.dart';
import 'notifier_lifecycle.dart';
import 'shell_controller.dart';
import 'system_level_hud.dart';

/// Immutable state for the quick-settings shade controls.
@immutable
class QuickSettingsState {
  const QuickSettingsState({
    required this.brightness,
    required this.brightnessLoaded,
    required this.volume,
    required this.volumeLoaded,
    required this.rotationLock,
    required this.profile,
    required this.screenshotRunning,
  });

  // The numeric seeds are inert: every in-scope consumer gates on the loaded
  // flags, so they can never surface as real readings.
  factory QuickSettingsState.initial() => const QuickSettingsState(
    brightness: 0.72,
    brightnessLoaded: false,
    volume: 0.46,
    volumeLoaded: false,
    rotationLock: true,
    profile: PowerProfile.balanced,
    screenshotRunning: false,
  );

  /// Last known backlight level in `[0, 1]`. Only meaningful once
  /// [brightnessLoaded] is true; until then consumers must render a neutral
  /// state rather than present the seed as a real reading.
  final double brightness;
  final bool brightnessLoaded;

  /// Last known output volume in `[0, 1]`; see [brightnessLoaded].
  final double volume;
  final bool volumeLoaded;

  final bool rotationLock;
  final String profile;
  final bool screenshotRunning;

  QuickSettingsState copyWith({
    double? brightness,
    bool? brightnessLoaded,
    double? volume,
    bool? volumeLoaded,
    bool? rotationLock,
    String? profile,
    bool? screenshotRunning,
  }) {
    return QuickSettingsState(
      brightness: brightness ?? this.brightness,
      brightnessLoaded: brightnessLoaded ?? this.brightnessLoaded,
      volume: volume ?? this.volume,
      volumeLoaded: volumeLoaded ?? this.volumeLoaded,
      rotationLock: rotationLock ?? this.rotationLock,
      profile: profile ?? this.profile,
      screenshotRunning: screenshotRunning ?? this.screenshotRunning,
    );
  }
}

final quickSettingsProvider =
    NotifierProvider<QuickSettingsController, QuickSettingsState>(
      QuickSettingsController.new,
    );

/// Owns the quick-settings controls: optimistic UI state, debounced hardware
/// writes for the sliders, and the transient guards for one-shot actions.
///
/// Rotation remains a migration placeholder until its authoritative service
/// lands. Connectivity and DND live in their own signal-driven providers so
/// their tiles cannot disagree with the network service, BlueZ, or notification
/// policy.
class QuickSettingsController extends Notifier<QuickSettingsState>
    with NotifierLifecycle<QuickSettingsState> {
  @override
  QuickSettingsState build() {
    _brightness = ref.watch(brightnessServiceProvider);
    _audio = ref.watch(audioServiceProvider);
    _audioHudSuppression = ref.watch(systemLevelHudAudioSuppressionProvider);
    _power = ref.watch(powerProfileServiceProvider);
    _actions = ref.watch(systemActionsServiceProvider);
    _brightnessTimer = null;
    _volumeTimer = null;
    _volumeAcknowledgementTimer = null;
    _pendingBrightness = -1;
    _pendingVolume = -1;
    _pendingVolumeSerial = 0;
    _lastAppliedBrightness = -1;
    _nextVolumeRequestSerial = 1;
    _latestDesiredVolumeSerial = 0;
    _latestDesiredVolumePercent = -1;
    _observedVolumePercent = -1;
    _brightnessApplying = false;
    _volumeApplying = false;
    _brightnessFlushRequested = false;
    _volumeInteracting = false;
    _deferredAudioState = null;
    _brightnessSettledThisBuild = false;
    _buildGeneration = beginBuildGeneration();
    final generation = _buildGeneration;
    final subscription = _audio.states.listen(
      (update) => _handleAudioState(update, generation),
    );
    cancelOnDispose(subscription);
    final brightnessSubscription = _brightness.states.listen(
      (update) => _handleBrightnessState(update, generation),
    );
    cancelOnDispose(brightnessSubscription);
    ref.onDispose(() {
      _brightnessTimer?.cancel();
      _volumeTimer?.cancel();
      _volumeAcknowledgementTimer?.cancel();
      _brightnessTimer = null;
      _volumeTimer = null;
      _volumeAcknowledgementTimer = null;
    });
    scheduleMicrotask(() {
      if (isBuildGenerationActive(generation)) {
        unawaited(_loadInitial(generation));
      }
    });
    // A dependency rebuild (typically displayLayoutProvider landing seconds
    // after boot) re-runs this method on the same notifier instance. Carry
    // over what the previous build already learned so controls never fall
    // back to the not-yet-loaded state while a fresh read is in flight.
    final previous = stateOrNull;
    return QuickSettingsState(
      brightness: previous?.brightness ?? 0.72,
      brightnessLoaded: previous?.brightnessLoaded ?? false,
      volume: previous?.volume ?? 0.46,
      volumeLoaded: previous?.volumeLoaded ?? false,
      rotationLock: previous?.rotationLock ?? true,
      profile: previous?.profile ?? PowerProfile.balanced,
      screenshotRunning: false,
    );
  }

  static const Duration _brightnessCommitInterval = Duration(milliseconds: 90);
  static const Duration _volumeCommitInterval = Duration(milliseconds: 90);
  static const Duration _volumeAcknowledgementTimeout = Duration(seconds: 2);
  static const Duration _screenshotSettleDelay = Duration(milliseconds: 260);
  static const Duration _initialLoadRetryInterval = Duration(milliseconds: 250);
  static const int _initialLoadMaxAttempts = 16;

  late BrightnessService _brightness;
  late AudioService _audio;
  late SystemLevelHudAudioSuppression _audioHudSuppression;
  late PowerProfileService _power;
  late SystemActionsService _actions;
  late int _buildGeneration;

  Timer? _brightnessTimer;
  Timer? _volumeTimer;
  Timer? _volumeAcknowledgementTimer;
  int _pendingBrightness = -1;
  int _pendingVolume = -1;
  int _pendingVolumeSerial = 0;
  int _lastAppliedBrightness = -1;
  int _nextVolumeRequestSerial = 1;
  int _latestDesiredVolumeSerial = 0;
  int _latestDesiredVolumePercent = -1;
  int _observedVolumePercent = -1;
  bool _brightnessApplying = false;
  bool _volumeApplying = false;
  bool _brightnessFlushRequested = false;
  bool _volumeInteracting = false;
  AudioLevelState? _deferredAudioState;

  /// Brightness events observed while the display layout had not named a
  /// default monitor yet, keyed by monitorId. Survives dependency rebuilds;
  /// the first build whose service can resolve a target consumes its entry.
  final Map<int, double> _earlyBrightnessLevels = <int, double>{};

  /// Whether this generation already published a brightness level from a
  /// live event or user input. A stashed pre-layout event is older than both
  /// and must not regress them.
  bool _brightnessSettledThisBuild = false;

  Future<void> _loadInitial(int generation) async {
    await Future.wait<void>(<Future<void>>[
      _loadInitialBrightness(generation),
      _loadInitialVolume(generation),
      _loadInitialPowerProfile(generation),
    ]);
  }

  Future<void> _loadInitialBrightness(int generation) async {
    // A brightness event can land before the layout names a default monitor;
    // the cached level is real hardware state, so apply it before polling —
    // unless this generation already published a newer level.
    final defaultMonitorId = _brightness.defaultMonitorId;
    if (defaultMonitorId != null) {
      final cached = _earlyBrightnessLevels.remove(defaultMonitorId);
      // Only the default monitor's level is ever shown; once it is known,
      // entries for other monitors can never be consumed.
      _earlyBrightnessLevels.clear();
      if (cached != null && !_brightnessSettledThisBuild) {
        _applyObservedBrightness(cached);
      }
    }
    // readLevel() returns null while the service has no target output; retry
    // briefly instead of leaving the control in its not-yet-loaded state. A
    // layout-driven rebuild is itself another attempt under a new generation.
    for (var attempt = 0; attempt < _initialLoadMaxAttempts; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(_initialLoadRetryInterval);
      }
      if (!isBuildGenerationActive(generation)) {
        return;
      }
      final level = await _brightness.readLevel();
      if (!isBuildGenerationActive(generation)) {
        return;
      }
      if (level != null) {
        _applyObservedBrightness(level);
        return;
      }
    }
  }

  Future<void> _loadInitialVolume(int generation) async {
    for (var attempt = 0; attempt < _initialLoadMaxAttempts; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(_initialLoadRetryInterval);
      }
      if (!isBuildGenerationActive(generation)) {
        return;
      }
      final volume = await _audio.readLevel();
      if (!isBuildGenerationActive(generation)) {
        return;
      }
      if (volume != null) {
        _handleAudioState(
          AudioLevelState(level: volume, requestSerial: 0),
          generation,
        );
        return;
      }
    }
  }

  Future<void> _loadInitialPowerProfile(int generation) async {
    final profile = await _power.read();
    if (isBuildGenerationActive(generation) && profile != null) {
      state = state.copyWith(profile: profile);
    }
  }

  void _applyObservedBrightness(double rawLevel) {
    final level = rawLevel.clamp(0.01, 1.0).toDouble();
    _lastAppliedBrightness = (level * 100).round().clamp(1, 100);
    if (state.brightness != level || !state.brightnessLoaded) {
      state = state.copyWith(brightness: level, brightnessLoaded: true);
    }
  }

  void _handleBrightnessState(DenialBrightnessState update, int generation) {
    if (!isBuildGenerationActive(generation)) {
      return;
    }
    final defaultMonitorId = _brightness.defaultMonitorId;
    if (defaultMonitorId == null) {
      // Without a layout there is no way to tell which output this event
      // belongs to; stash it keyed by monitorId for a later build instead of
      // dropping what may be the only real level seen so far.
      _earlyBrightnessLevels[update.monitorId] = update.level;
      return;
    }
    if (update.monitorId != defaultMonitorId) {
      return;
    }
    _applyObservedBrightness(update.level);
    _brightnessSettledThisBuild = true;
  }

  void setBrightness(double value) {
    final clamped = value.clamp(0.01, 1.0).toDouble();
    final percent = (clamped * 100).round().clamp(1, 100);
    state = state.copyWith(brightness: clamped, brightnessLoaded: true);
    _brightnessSettledThisBuild = true;
    _pendingBrightness = percent;
    _scheduleBrightnessApply();
  }

  void commitBrightness(double value) {
    final clamped = value.clamp(0.01, 1.0).toDouble();
    final percent = (clamped * 100).round().clamp(1, 100);
    state = state.copyWith(brightness: clamped, brightnessLoaded: true);
    _brightnessSettledThisBuild = true;
    _pendingBrightness = percent;
    _scheduleBrightnessApply(immediate: true);
  }

  void _scheduleBrightnessApply({bool immediate = false}) {
    final generation = _buildGeneration;
    if (immediate) {
      _brightnessFlushRequested = true;
      _brightnessTimer?.cancel();
      _brightnessTimer = null;
      unawaited(_drainBrightnessApplies(generation));
      return;
    }
    _brightnessTimer ??= Timer(_brightnessCommitInterval, () {
      _brightnessTimer = null;
      unawaited(_drainBrightnessApplies(generation));
    });
  }

  Future<void> _drainBrightnessApplies(int generation) async {
    if (_brightnessApplying) {
      return;
    }
    _brightnessApplying = true;
    try {
      while (isBuildGenerationActive(generation)) {
        final pending = _pendingBrightness;
        if (pending <= 0 || pending == _lastAppliedBrightness) {
          _pendingBrightness = -1;
          _brightnessFlushRequested = false;
          return;
        }
        _pendingBrightness = -1;
        await _brightness.apply(pending);
        if (!isBuildGenerationActive(generation)) {
          return;
        }
        _lastAppliedBrightness = pending;
        if (_pendingBrightness <= 0 ||
            _pendingBrightness == _lastAppliedBrightness) {
          _brightnessFlushRequested = false;
          return;
        }
        if (_brightnessFlushRequested) {
          _brightnessFlushRequested = false;
          continue;
        }
        await Future<void>.delayed(_brightnessCommitInterval);
      }
    } finally {
      if (isBuildGenerationActive(generation)) {
        _brightnessApplying = false;
      }
    }
  }

  void beginVolumeInteraction() {
    _volumeInteracting = true;
    _deferredAudioState = null;
  }

  void setVolume(double value) {
    _recordVolumeIntent(value);
    _scheduleVolumeApply();
  }

  void setDashboardVolume(double value) {
    _recordVolumeIntent(value, suppressHud: true);
    _scheduleVolumeApply();
  }

  void commitVolume(double value) {
    _recordVolumeIntent(value, force: true);
    _volumeInteracting = false;
    _scheduleVolumeApply(immediate: true);
    _applyDeferredAudioStateIfIdle();
  }

  void commitDashboardVolume(double value) {
    _recordVolumeIntent(value, force: true, suppressHud: true);
    _volumeInteracting = false;
    _scheduleVolumeApply(immediate: true);
    _applyDeferredAudioStateIfIdle();
  }

  void _recordVolumeIntent(
    double value, {
    bool force = false,
    bool suppressHud = false,
  }) {
    final clamped = value.clamp(0.0, 1.0).toDouble();
    final percent = (clamped * 100).round().clamp(0, 100);
    state = state.copyWith(volume: clamped, volumeLoaded: true);

    if (_latestDesiredVolumeSerial != 0 &&
        _latestDesiredVolumePercent == percent) {
      return;
    }
    if (!force &&
        _latestDesiredVolumeSerial == 0 &&
        _observedVolumePercent == percent) {
      return;
    }

    final requestSerial = _allocateVolumeRequestSerial();
    if (suppressHud) {
      _audioHudSuppression.suppress(requestSerial);
    }
    _pendingVolume = percent;
    _pendingVolumeSerial = requestSerial;
    _latestDesiredVolumePercent = percent;
    _latestDesiredVolumeSerial = requestSerial;
  }

  int _allocateVolumeRequestSerial() {
    final serial = _nextVolumeRequestSerial;
    _nextVolumeRequestSerial = serial >= 0xffffffff ? 1 : serial + 1;
    return serial;
  }

  void _scheduleVolumeApply({bool immediate = false}) {
    final generation = _buildGeneration;
    if (immediate) {
      _volumeTimer?.cancel();
      _volumeTimer = null;
      unawaited(_drainVolumeApplies(generation));
      return;
    }
    _volumeTimer ??= Timer(_volumeCommitInterval, () {
      _volumeTimer = null;
      unawaited(_drainVolumeApplies(generation));
    });
  }

  Future<void> _drainVolumeApplies(int generation) async {
    if (_volumeApplying) {
      return;
    }
    _volumeApplying = true;
    try {
      while (isBuildGenerationActive(generation)) {
        final pending = _pendingVolume;
        if (pending < 0) {
          return;
        }
        final requestSerial = _pendingVolumeSerial;
        _pendingVolume = -1;
        _pendingVolumeSerial = 0;
        try {
          await _audio.apply(pending, requestSerial: requestSerial);
          if (!isBuildGenerationActive(generation)) {
            return;
          }
          if (_latestDesiredVolumeSerial == requestSerial) {
            _armVolumeAcknowledgementTimeout(requestSerial);
          }
        } on Object catch (error) {
          debugPrint('Unable to apply output volume: $error');
        }
      }
    } finally {
      if (isBuildGenerationActive(generation)) {
        _volumeApplying = false;
        // A pointer event can enqueue a final value while the previous write
        // is completing. Always start a fresh drain in that narrow race
        // window.
        if (_pendingVolume >= 0) {
          unawaited(_drainVolumeApplies(generation));
        }
      }
    }
  }

  void _handleAudioState(AudioLevelState update, int generation) {
    if (!isBuildGenerationActive(generation)) {
      return;
    }

    final matchesLatestRequest =
        _latestDesiredVolumeSerial != 0 &&
        update.requestSerial == _latestDesiredVolumeSerial;
    if (matchesLatestRequest) {
      _volumeAcknowledgementTimer?.cancel();
      _volumeAcknowledgementTimer = null;
      _latestDesiredVolumeSerial = 0;
      _latestDesiredVolumePercent = -1;
      _deferredAudioState = null;
      _acceptAudioState(update);
      return;
    }

    // A non-zero serial is an acknowledgement for an older coalesced write.
    // It must never pull the thumb behind the user's latest intent.
    if (update.requestSerial != 0) {
      return;
    }

    if (_volumeInteracting || _latestDesiredVolumeSerial != 0) {
      _deferredAudioState = update;
      return;
    }

    _acceptAudioState(update);
  }

  void _acceptAudioState(AudioLevelState update) {
    final level = update.level.clamp(0.0, 1.0).toDouble();
    _observedVolumePercent = (level * 100).round().clamp(0, 100);
    if (!_volumeInteracting) {
      state = state.copyWith(volume: level, volumeLoaded: true);
    }
  }

  void _applyDeferredAudioStateIfIdle() {
    if (_volumeInteracting || _latestDesiredVolumeSerial != 0) {
      return;
    }
    final deferred = _deferredAudioState;
    _deferredAudioState = null;
    if (deferred != null) {
      _acceptAudioState(deferred);
    }
  }

  void _armVolumeAcknowledgementTimeout(int requestSerial) {
    _volumeAcknowledgementTimer?.cancel();
    final generation = _buildGeneration;
    _volumeAcknowledgementTimer = Timer(_volumeAcknowledgementTimeout, () {
      if (!isBuildGenerationActive(generation) ||
          _latestDesiredVolumeSerial != requestSerial) {
        return;
      }
      _latestDesiredVolumeSerial = 0;
      _latestDesiredVolumePercent = -1;
      _applyDeferredAudioStateIfIdle();
      unawaited(_audio.readLevel());
    });
  }

  void toggleRotation() =>
      state = state.copyWith(rotationLock: !state.rotationLock);

  void cycleProfile() {
    final next = PowerProfile.next(state.profile);
    state = state.copyWith(profile: next);
    unawaited(_power.write(next));
  }

  void openKeyboard() =>
      ref.read(shellControllerProvider.notifier).openEdgePanel();

  /// Captures a screenshot. The caller is expected to dismiss the shade first;
  /// the settle delay gives that animation time to clear the frame.
  Future<void> takeScreenshot() async {
    if (state.screenshotRunning) {
      return;
    }
    final generation = _buildGeneration;
    state = state.copyWith(screenshotRunning: true);
    try {
      await Future<void>.delayed(_screenshotSettleDelay);
      await _actions.takeScreenshot();
    } finally {
      if (isBuildGenerationActive(generation)) {
        state = state.copyWith(screenshotRunning: false);
      }
    }
  }
}
