import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../desktop/desktop_workspace.dart';
import '../../input/shell_interaction_registry.dart';
import '../../models/display_layout.dart';
import '../../models/ime_frame.dart';
import '../../state/display_layout.dart';
import '../../state/ime_panel.dart';
import '../../state/shell_controller.dart';
import '../../theme/shell_theme.dart';
import '../../theme/tokens.dart';
import 'ime_candidate_panel.dart';
import 'ime_panel_placement.dart';

/// Desktop scene mount for the input-engine candidate panel.
///
/// Registered as a child-bounds pointer region so taps reach the panel
/// (T06 routes them into `ImeCommand`s) while
/// [ShellKeyboardPolicy.none] keeps every key in the focused editor.
///
/// Anchor resolution follows the input-engine contract: the validated frame
/// may carry the caret's global rect (native supplies it once T03 wires it
/// through); on `Legacy` endpoints, which cannot report caret geometry, the
/// last pointer position stands in — the same rectangle native hands the
/// engine as `cursor_rectangle`. Without either, the focused window's
/// content rect anchors the panel, and failing that it rests near the
/// bottom of the containing output.
class ImeCandidatePanelLayer extends ConsumerStatefulWidget {
  const ImeCandidatePanelLayer({
    this.layout = ImePanelLayout.vertical,
    super.key,
  });

  final ImePanelLayout layout;

  @override
  ConsumerState<ImeCandidatePanelLayer> createState() =>
      _ImeCandidatePanelLayerState();
}

class _ImeCandidatePanelLayerState
    extends ConsumerState<ImeCandidatePanelLayer> {
  Size? _panelSize;
  StreamSubscription<Offset>? _cursorSubscription;

  /// Latest pointer position, kept outside provider state because it changes
  /// at pointer-event frequency and must not rebuild the scene.
  ///
  /// On `Legacy` endpoints the editor cannot report caret geometry; the
  /// input-engine contract places the panel from pointer position there
  /// (native fills `cursor_rectangle` with a small rect at the pointer).
  Offset? _lastPointerPosition;

  @override
  void initState() {
    super.initState();
    _cursorSubscription = ref
        .read(denialBridgeProvider)
        .cursorPositions
        .listen((position) => _lastPointerPosition = position);
  }

  @override
  void dispose() {
    unawaited(_cursorSubscription?.cancel());
    super.dispose();
  }

  void _handlePanelSize(Size size) {
    if (!mounted || size == _panelSize) {
      return;
    }
    // The placement depends on the measured size (above/below flipping and
    // edge clamping need real extents), so size changes re-resolve the
    // position on the next frame. Both call sites — the reporter's
    // post-frame measure and the SizeChangedLayoutNotification dispatched
    // during layout — may call setState directly, and must: deferring the
    // update would leave the panel parked at the bounds-sized guess until
    // some unrelated repaint happened to schedule a frame.
    setState(() => _panelSize = size);
  }

  Rect _caretHeightRect(Offset topLeft) {
    final lineHeight =
        context.shellTheme.text.titleMedium.fontSize ?? ShellSpacing.lg;
    return Rect.fromLTWH(topLeft.dx, topLeft.dy, 1, lineHeight);
  }

  Rect _resolveCaret(
    DenialImeFrame frame,
    DenialImeEndpointKind endpoint,
    Rect canvas,
  ) {
    final delivered = frame.caret;
    if (delivered != null && delivered.isFinite) {
      // Zero-extent caret rects are legal: text-input-v3 cursor rectangles
      // may carry a zero width or height. Trust the delivered position and
      // normalize the extent so the anchor keeps its place instead of
      // degrading to the pointer fallback.
      return Rect.fromLTWH(
        delivered.left,
        delivered.top,
        math.max(1.0, delivered.width),
        math.max(1.0, delivered.height),
      );
    }
    final pointer = _lastPointerPosition;
    if (endpoint == DenialImeEndpointKind.legacy && pointer != null) {
      return _caretHeightRect(pointer);
    }
    final foregroundId = ref.watch(
      shellControllerProvider.select((state) => state.foregroundObjectId),
    );
    if (foregroundId != null) {
      final contentRect = ref.watch(
        desktopWorkspaceProvider.select(
          (workspace) => workspace.placements[foregroundId]?.contentRect,
        ),
      );
      if (contentRect != null && !contentRect.isEmpty) {
        return _caretHeightRect(contentRect.bottomLeft);
      }
    }
    if (pointer != null) {
      return _caretHeightRect(pointer);
    }
    // No anchor information at all: rest near the bottom of the canvas,
    // where a virtual-keyboard-adjacent surface would sit.
    return _caretHeightRect(
      Offset(canvas.center.dx, canvas.bottom - canvas.height / 3),
    );
  }

  /// The output holding the caret anchor, intersected with the canvas —
  /// `place_input_method_popup`'s `output_for_geometry(anchor)` fallback to
  /// the desktop bounds.
  Rect _outputBounds(Rect caret, Rect canvas) {
    final anchor = Offset(caret.left, caret.bottom);
    for (final output
        in ref.watch(displayLayoutProvider)?.outputs ??
            const <DisplayOutput>[]) {
      final rect = output.logicalRect.intersect(canvas);
      if (!rect.isEmpty && rect.contains(anchor)) {
        return rect;
      }
    }
    return canvas;
  }

  @override
  Widget build(BuildContext context) {
    final panel = ref.watch(imePanelProvider);
    final frame = panel.visibleFrame;
    if (frame == null) {
      // Drop the measurement with the panel: reusing the previous show's
      // extents would flash the next frame at a stale position before it
      // is re-measured. Serial changes always pass through here — a frame
      // whose serial no longer matches the activation is not visible.
      _panelSize = null;
      return const SizedBox.shrink();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final canvas = Offset.zero & constraints.biggest;
        if (canvas.isEmpty) {
          return const SizedBox.shrink();
        }
        final caret = _resolveCaret(frame, panel.engine.endpoint, canvas);
        final bounds = _outputBounds(caret, canvas);
        final placement = resolveImePanelPlacement(
          caret: caret,
          panelSize: _panelSize ?? bounds.size,
          bounds: bounds,
          gap: ShellSpacing.xs,
        );
        return Stack(
          children: <Widget>[
            Positioned(
              left: placement.rect.left,
              top: placement.rect.top,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: bounds.width,
                  maxHeight: bounds.height,
                ),
                child: ShellInputRegion(
                  debugLabel: 'IME candidate panel',
                  // During the invisible first-measure frame the placement
                  // is a bounds-sized guess; publishing that rect would
                  // claim a tap the panel cannot answer (IgnorePointer
                  // drops it). Only a measured panel registers a region.
                  active: _panelSize != null,
                  pointerPolicy: ShellPointerPolicy.childBounds,
                  keyboardPolicy: ShellKeyboardPolicy.none,
                  child: _ImePanelSizeReporter(
                    onSizeChange: _handlePanelSize,
                    // Until the first measurement lands the placement uses a
                    // bounds-sized guess; keep the panel transparent and
                    // untargetable for that frame rather than flashing at
                    // the wrong spot.
                    child: IgnorePointer(
                      ignoring: _panelSize == null,
                      child: Opacity(
                        opacity: _panelSize == null ? 0.0 : 1.0,
                        child: ImeCandidatePanel(
                          frame: frame,
                          layout: widget.layout,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Reports [child]'s laid-out size through [onSizeChange].
///
/// [SizeChangedLayoutNotifier] deliberately skips the initial layout, so the
/// reporter also measures once after the first frame.
class _ImePanelSizeReporter extends StatefulWidget {
  const _ImePanelSizeReporter({
    required this.onSizeChange,
    required this.child,
  });

  final ValueChanged<Size> onSizeChange;
  final Widget child;

  @override
  State<_ImePanelSizeReporter> createState() => _ImePanelSizeReporterState();
}

class _ImePanelSizeReporterState extends State<_ImePanelSizeReporter> {
  final GlobalKey _childKey = GlobalKey();

  void _measure() {
    final size = _childKey.currentContext?.size;
    if (size != null) {
      widget.onSizeChange(size);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (notification) {
        _measure();
        return false;
      },
      child: SizeChangedLayoutNotifier(
        child: KeyedSubtree(key: _childKey, child: widget.child),
      ),
    );
  }
}
