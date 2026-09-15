import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ime_frame.dart';
import 'notifier_lifecycle.dart';
import 'shell_controller.dart';

final imePanelProvider = NotifierProvider<ImePanelController, ImePanelState>(
  ImePanelController.new,
);

/// Latest validated input-engine state plus the frame the panel renders.
@immutable
class ImePanelState {
  const ImePanelState({this.frame, this.engine = const DenialImeState()});

  /// Newest decoded `ImeFrame`, or null before the first frame arrives.
  final DenialImeFrame? frame;

  /// Newest decoded `ImeState`; defaults to "no engine, no endpoint".
  final DenialImeState engine;

  /// The frame the candidate panel should render right now, or null when it
  /// must stay hidden: empty frames collapse the panel, `endpoint none` or
  /// `engine offline` mean no editor holds text focus, and a frame whose
  /// serial does not match the current activation is stale.
  DenialImeFrame? get visibleFrame {
    final current = frame;
    if (current == null || current.isEmpty) {
      return null;
    }
    if (engine.endpoint == DenialImeEndpointKind.none ||
        engine.engine == DenialImeEngineStatus.offline ||
        engine.serial == 0 ||
        current.serial != engine.serial) {
      return null;
    }
    return current;
  }
}

/// Republishes validated `ImeFrame`/`ImeState` wire payloads to the desktop
/// scene's candidate-panel layer.
class ImePanelController extends Notifier<ImePanelState>
    with NotifierLifecycle<ImePanelState> {
  @override
  ImePanelState build() {
    final bridge = ref.watch(denialBridgeProvider);
    cancelOnDispose(
      bridge.imeFrames.listen(
        (frame) => state = ImePanelState(frame: frame, engine: state.engine),
      ),
    );
    cancelOnDispose(
      bridge.imeStates.listen((engine) {
        // A new activation retires every frame the previous one produced.
        final frame = state.frame;
        state = ImePanelState(
          frame: frame != null && frame.serial == engine.serial ? frame : null,
          engine: engine,
        );
      }),
    );
    return const ImePanelState();
  }
}
