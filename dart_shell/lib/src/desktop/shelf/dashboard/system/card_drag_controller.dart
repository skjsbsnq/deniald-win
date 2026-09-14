import 'package:flutter/widgets.dart' show ChangeNotifier, Offset, Rect;

import 'card_catalog.dart';
import 'card_grid_layout.dart';

/// Phases of a system card drag session.
///
/// Ported from clavis `Services/SystemCardDragState.js`, reduced to the
/// phases a single-surface canvas needs: clavis splits `dragging` into
/// sidebar/presentation halves and adds `frozenTransfer` for the cross
/// surface handoff; denial drags stay inside one widget tree so `dragging`
/// covers the whole gesture and `finishing` covers the settle animation.
enum SystemCardDragPhase { idle, dragging, finishing }

/// Everything a gesture callback needs to recompute the preview: the
/// committed layout, the grid metrics, and the catalog ordering. Bundled so
/// drag frames pass one value instead of four.
class SystemCardDragContext {
  const SystemCardDragContext({
    required this.geometry,
    required this.catalog,
    required this.activeIds,
    required this.committed,
  });

  final CardGridGeometry geometry;
  final SystemCardCatalog catalog;
  final List<String> activeIds;
  final List<CardTile> committed;
}

/// Drag session state machine for the system card canvas.
///
/// Owned by the grid view widget (not a provider) so drag frames notify only
/// the canvas subtree — the committed layout provider stays untouched until
/// [end] returns a layout to commit (constraint E6).
///
/// As in clavis `SystemCardDragSession`: the source-local grab point is
/// recorded once at drag start and never re-derived from the pointer.
class SystemCardDragController extends ChangeNotifier {
  SystemCardDragPhase _phase = SystemCardDragPhase.idle;
  String? _tileId;
  Offset _grabLocal = Offset.zero;
  Offset _pointerCanvas = Offset.zero;
  double _ghostWidth = 0;
  double _ghostHeight = 0;
  List<CardTile>? _previewLayout;
  CardTile? _previewTarget;
  bool _previewValid = true;
  bool _keyboardMode = false;
  Rect? _finishingTarget;

  SystemCardDragPhase get phase => _phase;
  String? get tileId => _tileId;
  bool get isActive => _phase != SystemCardDragPhase.idle;
  bool get isKeyboardSession =>
      _phase == SystemCardDragPhase.dragging && _keyboardMode;

  /// Ghost rectangle in canvas coordinates: pointer minus the immutable
  /// grab point, following the finger every frame.
  Rect? get ghostRect =>
      _phase == SystemCardDragPhase.dragging && !_keyboardMode
      ? Rect.fromLTWH(
          _pointerCanvas.dx - _grabLocal.dx,
          _pointerCanvas.dy - _grabLocal.dy,
          _ghostWidth,
          _ghostHeight,
        )
      : null;

  /// Preview layout for every *other* card; the dragged card keeps its
  /// committed slot while the ghost tracks the pointer.
  List<CardTile>? get previewLayout => _previewLayout;

  /// Where the dragged card lands if released now.
  CardTile? get previewTarget => _previewTarget;
  bool get previewValid => _previewValid;

  /// Ghost destination while [phase] is [SystemCardDragPhase.finishing].
  Rect? get finishingTarget => _finishingTarget;

  /// Begins a pointer drag. [grabLocal] is the pointer position inside the
  /// card at grab time; it stays immutable until the gesture ends.
  bool beginDrag({
    required String id,
    required Offset grabLocal,
    required Offset pointerCanvas,
    required SystemCardDragContext context,
  }) {
    if (_phase != SystemCardDragPhase.idle) {
      return false;
    }
    _phase = SystemCardDragPhase.dragging;
    _keyboardMode = false;
    _tileId = id;
    _grabLocal = grabLocal;
    _pointerCanvas = pointerCanvas;
    final tile = placementFor(context.committed, id);
    _ghostWidth = tile?.width ?? 0;
    _ghostHeight = tile?.height ?? 0;
    _applyMove(context);
    notifyListeners();
    return true;
  }

  void updateDrag(Offset canvasPoint, SystemCardDragContext context) {
    if (_phase != SystemCardDragPhase.dragging || _keyboardMode) {
      return;
    }
    _pointerCanvas = canvasPoint;
    _applyMove(context);
    notifyListeners();
  }

  /// Begins a keyboard adjust session on a focused tile: arrow keys nudge
  /// the card 8 px at a time through the same preview pipeline.
  bool beginKeyboard({
    required String id,
    required SystemCardDragContext context,
  }) {
    if (_phase != SystemCardDragPhase.idle) {
      return false;
    }
    _phase = SystemCardDragPhase.dragging;
    _keyboardMode = true;
    _tileId = id;
    _grabLocal = Offset.zero;
    _pointerCanvas = Offset.zero;
    _previewLayout = context.committed;
    _previewTarget = placementFor(context.committed, id);
    _previewValid = _previewTarget != null;
    notifyListeners();
    return true;
  }

  /// Moves the keyboard-adjusted card by [delta] canvas pixels.
  void nudge(Offset delta, SystemCardDragContext context) {
    if (_phase != SystemCardDragPhase.dragging || !_keyboardMode) {
      return;
    }
    final current = placementFor(
      _previewLayout ?? context.committed,
      _tileId ?? '',
    );
    if (current == null) {
      return;
    }
    _applyMove(
      context,
      targetX: current.x + delta.dx,
      targetY: current.y + delta.dy,
    );
    notifyListeners();
  }

  /// Ends the active session. Returns the preview layout to commit, or null
  /// when the session is idle — or when the last target was invalid, which
  /// is how clavis `finishDrag` drops an unresolvable release without
  /// committing anything.
  ///
  /// Pointer sessions enter [SystemCardDragPhase.finishing] so the ghost can
  /// settle onto the landing slot — the committed slot when the drop was
  /// rejected, so an invalid release visibly flies home; keyboard sessions
  /// return to idle directly because they never show a ghost.
  List<CardTile>? end(SystemCardDragContext context) {
    if (_phase != SystemCardDragPhase.dragging) {
      return null;
    }
    final result = _previewValid ? _previewLayout ?? context.committed : null;
    if (_keyboardMode) {
      _clear();
      return result;
    }
    _phase = SystemCardDragPhase.finishing;
    final target = placementFor(result ?? context.committed, _tileId ?? '');
    _finishingTarget = target == null
        ? null
        : Rect.fromLTWH(target.x, target.y, target.width, target.height);
    notifyListeners();
    return result;
  }

  /// Cancels the active session without committing (Esc or gesture cancel).
  void cancel() {
    if (_phase == SystemCardDragPhase.idle) {
      return;
    }
    _clear();
    notifyListeners();
  }

  /// Called by the ghost settle animation's `onEnd`: finishing → idle.
  void settleComplete() {
    if (_phase != SystemCardDragPhase.finishing) {
      return;
    }
    _clear();
    notifyListeners();
  }

  void _clear() {
    _phase = SystemCardDragPhase.idle;
    _tileId = null;
    _grabLocal = Offset.zero;
    _pointerCanvas = Offset.zero;
    _ghostWidth = 0;
    _ghostHeight = 0;
    _previewLayout = null;
    _previewTarget = null;
    _previewValid = true;
    _keyboardMode = false;
    _finishingTarget = null;
  }

  void _applyMove(
    SystemCardDragContext context, {
    double? targetX,
    double? targetY,
  }) {
    final id = _tileId;
    if (id == null) {
      return;
    }
    final ghost = ghostRect;
    var x = targetX;
    var y = targetY;
    if (x == null || y == null) {
      if (ghost == null) {
        return;
      }
      // The drop target is the ghost's snapped top-left; compaction decides
      // the final slot from there.
      x = ghost.left;
      y = ghost.top;
    }
    final moved = moveCardLayout(
      context.committed,
      id,
      x,
      y,
      geometry: context.geometry,
      catalog: context.catalog,
      activeIds: context.activeIds,
    );
    if (moved == null) {
      // clavis `updateDrag`: `previewLayout = solved || []` — an
      // unresolvable target clears the preview so siblings fall back to the
      // committed layout instead of freezing mid-shuffle, and the release
      // commits nothing. The frame still shows the raw snapped target in
      // error color so the rejected spot is visible.
      _previewLayout = null;
      _previewValid = false;
      final tile = placementFor(context.committed, id);
      if (tile != null) {
        _previewTarget = tile.copyWith(
          x: gridSnap(
            x,
            context.geometry.canvasWidth - tile.width,
            step: context.geometry.snapStep,
          ),
          y: gridSnap(y, double.maxFinite, step: context.geometry.snapStep),
        );
      }
      return;
    }
    _previewValid = true;
    _previewLayout = moved;
    _previewTarget = placementFor(moved, id);
  }
}
