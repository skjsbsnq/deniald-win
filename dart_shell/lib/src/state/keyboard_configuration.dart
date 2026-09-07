import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/keyboard_configuration.dart';
import '../platform/denial_bridge.dart';
import 'shell_controller.dart';
import 'notifier_lifecycle.dart';

class KeyboardConfigurationState {
  const KeyboardConfigurationState({
    this.configuration,
    this.busy = false,
    this.error,
  });

  final DenialKeyboardConfiguration? configuration;
  final bool busy;
  final String? error;

  KeyboardConfigurationState copyWith({
    DenialKeyboardConfiguration? configuration,
    bool? busy,
    String? error,
    bool clearError = false,
  }) {
    return KeyboardConfigurationState(
      configuration: configuration ?? this.configuration,
      busy: busy ?? this.busy,
      error: clearError ? null : error ?? this.error,
    );
  }
}

final keyboardConfigurationProvider =
    NotifierProvider<
      KeyboardConfigurationController,
      KeyboardConfigurationState
    >(KeyboardConfigurationController.new);

class KeyboardConfigurationController
    extends Notifier<KeyboardConfigurationState>
    with NotifierLifecycle<KeyboardConfigurationState> {
  late DenialBridge _bridge;
  StreamSubscription<DenialKeyboardConfiguration>? _subscription;

  @override
  KeyboardConfigurationState build() {
    _bridge = ref.watch(denialBridgeProvider);
    _subscription?.cancel();
    final generation = beginBuildGeneration();
    _subscription = _bridge.keyboardConfigurations.listen((configuration) {
      if (isBuildGenerationActive(generation)) {
        state = state.copyWith(
          configuration: configuration,
          busy: false,
          clearError: true,
        );
      }
    });
    ref.onDispose(() {
      unawaited(_subscription?.cancel());
      _subscription = null;
    });
    scheduleMicrotask(() => unawaited(refresh()));
    return const KeyboardConfigurationState();
  }

  Future<void> refresh() async {
    final generation = currentBuildGeneration;
    try {
      final configuration = await _bridge.readKeyboardConfiguration();
      if (isBuildGenerationActive(generation)) {
        state = state.copyWith(
          configuration: configuration,
          busy: false,
          clearError: true,
        );
      }
    } on Object catch (error) {
      if (isBuildGenerationActive(generation)) {
        state = state.copyWith(busy: false, error: error.toString());
      }
    }
  }

  Future<bool> configure(DenialKeyboardConfiguration requested) async {
    if (state.busy) {
      return false;
    }
    state = state.copyWith(busy: true, clearError: true);
    try {
      var current = requested;
      DenialKeyboardConfiguration applied;
      try {
        applied = await _bridge.configureKeyboard(current);
      } on StateError {
        // Shell preferences share the same revisioned document. If one landed
        // between editing and Apply, rebase this typed keyboard request once.
        final latest = await _bridge.readKeyboardConfiguration();
        current = requested.copyWith(revision: latest.revision);
        applied = await _bridge.configureKeyboard(current);
      }
      state = state.copyWith(
        configuration: applied,
        busy: false,
        clearError: true,
      );
      return true;
    } on Object catch (error) {
      state = state.copyWith(busy: false, error: error.toString());
      return false;
    }
  }
}
