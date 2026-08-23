import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../platform/denial_bridge.dart';
import 'shell_controller.dart';

@immutable
class ShellRenderModeState {
  const ShellRenderModeState({
    this.outputs = const <int, DenialShellRenderMode>{},
  });

  final Map<int, DenialShellRenderMode> outputs;

  bool overlayEnabledFor(int outputId) =>
      outputs[outputId]?.overlayEnabled ?? false;

  bool get anyOverlayEnabled =>
      outputs.values.any((mode) => mode.overlayEnabled);
}

final shellRenderModeProvider =
    NotifierProvider<ShellRenderModeController, ShellRenderModeState>(
      ShellRenderModeController.new,
    );

class ShellRenderModeController extends Notifier<ShellRenderModeState> {
  StreamSubscription<DenialShellRenderMode>? _subscription;

  @override
  ShellRenderModeState build() {
    _subscription?.cancel();
    _subscription = ref
        .watch(denialBridgeProvider)
        .shellRenderModes
        .listen(_handleMode);
    ref.onDispose(() {
      unawaited(_subscription?.cancel());
      _subscription = null;
    });
    return const ShellRenderModeState();
  }

  void _handleMode(DenialShellRenderMode mode) {
    final previous = state.outputs[mode.outputId];
    if (previous != null && mode.generation <= previous.generation) {
      return;
    }
    state = ShellRenderModeState(
      outputs: Map<int, DenialShellRenderMode>.unmodifiable(
        <int, DenialShellRenderMode>{...state.outputs, mode.outputId: mode},
      ),
    );
  }
}
