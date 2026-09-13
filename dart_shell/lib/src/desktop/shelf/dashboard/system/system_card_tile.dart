import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' show Tooltip;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../../localization/denial_localizations.dart';
import '../../../../theme/shell_theme.dart';
import '../../../../theme/tokens.dart';
import 'card_grid_layout.dart' show cardGridSnapStep;

typedef CardDragBeginCallback =
    void Function(Offset grabLocal, Offset globalPosition);
typedef CardDragMoveCallback = void Function(Offset globalPosition);

/// Drag-and-keyboard shell around one system card.
///
/// Cards stay draggable at all times (no edit mode, like clavis). Moving
/// the pointer starts the drag — clavis uses an immediate `DragHandler`
/// that can take the grab over from the surrounding scroll view, so the
/// recognizer here claims the pointer on down and the session itself opens
/// on the first real move — then every move updates only the drag
/// controller's preview while the committed layout stays untouched until
/// release.
///
/// Keyboard parity (constraint D8): the focused tile nudges 8 px per arrow
/// key, Enter commits and Esc cancels; Esc stays unbound outside a keyboard
/// session so the dashboard-level dismiss shortcut keeps working.
class SystemCardTile extends StatefulWidget {
  const SystemCardTile({
    super.key,
    required this.child,
    required this.dragged,
    required this.keyboardSession,
    required this.motionScale,
    required this.onDragBegin,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onDragCancel,
    required this.onNudge,
    required this.onKeyConfirm,
    required this.onKeyCancel,
  });

  /// The card content (one of the dashboard metric cards), laid out at the
  /// tile's exact rectangle.
  final Widget child;

  /// Whether this tile is the drag source: it stays in place dimmed while
  /// the ghost follows the pointer.
  final bool dragged;

  /// Whether this tile currently owns a keyboard adjust session; Enter and
  /// Esc bindings only exist while true.
  final bool keyboardSession;

  /// `settings.animations.durationScale`, applied to the local fades.
  final double motionScale;

  final CardDragBeginCallback onDragBegin;
  final CardDragMoveCallback onDragUpdate;
  final VoidCallback onDragEnd;
  final VoidCallback onDragCancel;
  final ValueChanged<Offset> onNudge;
  final VoidCallback onKeyConfirm;
  final VoidCallback onKeyCancel;

  @override
  State<SystemCardTile> createState() => _SystemCardTileState();
}

class _SystemCardTileState extends State<SystemCardTile> {
  late final FocusNode _focusNode;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  Duration _scaled(int milliseconds) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return Duration.zero;
    }
    return Duration(milliseconds: (milliseconds * widget.motionScale).round());
  }

  /// Called when the pointer has moved past slop and the recognizer won the
  /// arena — the clavis `DragHandler` equivalent (`CanTakeOverFromAnything`):
  /// `ImmediateMultiDrag` resolves on the first slop-exceeding move and,
  /// sitting deeper than the scroll view, sees the event first, so a card
  /// drag works in every direction even inside the page's scroll view. A
  /// press that never travels past slop never reaches this point and stays
  /// a plain click (focus is armed by the Listener below).
  Drag? _handlePointerDown(Offset globalPosition) {
    _focusNode.requestFocus();
    final box = context.findRenderObject();
    final grabLocal = box is RenderBox
        ? box.globalToLocal(globalPosition)
        : Offset.zero;
    return _TileCardDrag(
      downGlobal: globalPosition,
      onBegin: () => widget.onDragBegin(grabLocal, globalPosition),
      onUpdate: widget.onDragUpdate,
      onEnd: widget.onDragEnd,
      onCancel: widget.onDragCancel,
    );
  }

  Map<ShortcutActivator, VoidCallback> _shortcutBindings() {
    const step = cardGridSnapStep;
    return <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
          widget.onNudge(const Offset(-step, 0)),
      const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
          widget.onNudge(const Offset(step, 0)),
      const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
          widget.onNudge(const Offset(0, -step)),
      const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
          widget.onNudge(const Offset(0, step)),
      if (widget.keyboardSession) ...<ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.enter): widget.onKeyConfirm,
        const SingleActivator(LogicalKeyboardKey.numpadEnter):
            widget.onKeyConfirm,
        const SingleActivator(LogicalKeyboardKey.escape): widget.onKeyCancel,
      },
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final hint = context.l10n.settingsMonitorDragHint;
    return Tooltip(
      message: hint,
      textStyle: ShellText.shelfTooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: Semantics(
        container: true,
        hint: hint,
        child: CallbackShortcuts(
          bindings: _shortcutBindings(),
          child: Focus(
            focusNode: _focusNode,
            onFocusChange: (focused) => setState(() => _focused = focused),
            child: MouseRegion(
              cursor: widget.dragged
                  ? SystemMouseCursors.grabbing
                  : SystemMouseCursors.grab,
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (_) => _focusNode.requestFocus(),
                child: RawGestureDetector(
                  behavior: HitTestBehavior.opaque,
                  gestures: <Type, GestureRecognizerFactory<GestureRecognizer>>{
                    ImmediateMultiDragGestureRecognizer:
                        GestureRecognizerFactoryWithHandlers<
                          ImmediateMultiDragGestureRecognizer
                        >(
                          ImmediateMultiDragGestureRecognizer.new,
                          (recognizer) =>
                              recognizer.onStart = _handlePointerDown,
                        ),
                  },
                  child: AnimatedOpacity(
                    opacity: widget.dragged ? 0.45 : 1,
                    duration: _scaled(150),
                    child: Stack(
                      children: [
                        widget.child,
                        Positioned.fill(
                          child: IgnorePointer(
                            child: AnimatedOpacity(
                              opacity: _focused ? 1 : 0,
                              duration: _scaled(120),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: theme.borderRadius(
                                    ShellShapeScale.large,
                                  ),
                                  border: Border.all(
                                    color: theme.accentPalette.primary,
                                    width: 2,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One pointer session from down to release. `ImmediateMultiDrag` only
/// resolves after the pointer travels past slop, so the controller hears
/// about a session once the pointer has actually moved — a stationary
/// press never flashes the ghost/guide UI or commits a no-op layout.
///
/// The first update the framework delivers carries `globalPosition` of the
/// *down* event while `delta` holds the accumulated pending movement, so
/// the current position is tracked by accumulating deltas instead of
/// trusting `globalPosition`.
class _TileCardDrag extends Drag {
  _TileCardDrag({
    required Offset downGlobal,
    required this.onBegin,
    required this.onUpdate,
    required this.onEnd,
    required this.onCancel,
  }) : _position = downGlobal;

  final VoidCallback onBegin;
  final CardDragMoveCallback onUpdate;
  final VoidCallback onEnd;
  final VoidCallback onCancel;

  Offset _position;
  bool _began = false;

  @override
  void update(DragUpdateDetails details) {
    _position += details.delta;
    if (!_began) {
      _began = true;
      onBegin();
    }
    onUpdate(_position);
  }

  @override
  void end(DragEndDetails details) {
    if (_began) {
      onEnd();
    }
  }

  @override
  void cancel() {
    if (_began) {
      onCancel();
    }
  }
}
