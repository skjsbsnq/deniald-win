import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../services/system_card_store.dart';
import '../../../../theme/shell_theme.dart';
import '../../../../theme/tokens.dart';
import 'card_catalog.dart';
import 'card_drag_controller.dart';
import 'card_grid_layout.dart';
import 'system_card_tile.dart';

/// One tile on the system card canvas: a stable tile id plus its content.
///
/// The child is built once by the parent view and shared by the real tile
/// and the drag ghost, so neither rebuilds on drag frames.
class SystemCardGridItem {
  const SystemCardGridItem({required this.id, required this.child});

  final String id;
  final Widget child;
}

/// clavis-style draggable bento canvas for the dashboard system cards.
///
/// Free x + upward compaction, sibling cards that animate out of the way,
/// a snapped drop-target frame, and a ghost that follows the pointer — all
/// driven by [SystemCardDragController], a widget-local listenable, so drag
/// frames never rebuild providers (constraint E6).
class SystemCardGridView extends ConsumerStatefulWidget {
  const SystemCardGridView({
    super.key,
    required this.items,
    this.motionScale = 1,
  });

  /// Tiles to lay out; every id must resolve in [SystemCardCatalog].
  final List<SystemCardGridItem> items;

  /// `settings.animations.durationScale` forwarded by the view so this
  /// widget stays testable without the settings provider.
  final double motionScale;

  /// clavis sibling-card settle: 650 ms `Cubic(0.39,1.29,0.35,0.98)`.
  static const Cubic settleCurve = Cubic(0.39, 1.29, 0.35, 0.98);

  @override
  ConsumerState<SystemCardGridView> createState() => _SystemCardGridViewState();
}

class _SystemCardGridViewState extends ConsumerState<SystemCardGridView> {
  late final SystemCardDragController _drag;
  final GlobalKey _canvasKey = GlobalKey();
  bool _hydrationSettled = false;
  bool _missingTileResetScheduled = false;

  @override
  void initState() {
    super.initState();
    _drag = SystemCardDragController();
  }

  @override
  void dispose() {
    _drag.dispose();
    super.dispose();
  }

  Duration _motion(int milliseconds) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return Duration.zero;
    }
    return Duration(milliseconds: (milliseconds * widget.motionScale).round());
  }

  Offset _canvasPoint(Offset global) {
    final box = _canvasKey.currentContext?.findRenderObject();
    return box is RenderBox ? box.globalToLocal(global) : global;
  }

  SystemCardGridItem? _itemFor(String? id) {
    for (final item in widget.items) {
      if (item.id == id) {
        return item;
      }
    }
    return null;
  }

  void _nudge(String id, Offset delta, SystemCardDragContext dragContext) {
    if (_drag.phase == SystemCardDragPhase.idle) {
      _drag.beginKeyboard(id: id, context: dragContext);
    }
    _drag.nudge(delta, dragContext);
  }

  /// The dragged card's item can vanish mid-session when the provider id
  /// set shrinks (e.g. a gpu disappears between polls): the tile unmounts
  /// with its gesture callbacks, so `onDragEnd`/`onDragCancel` never fire
  /// and a `finishing` ghost's `onEnd` never runs. Without this reset the
  /// controller would sit in dragging/finishing forever and reject every
  /// later session — the panel stays alive across tabs, so nothing else
  /// would ever clear it.
  void _scheduleMissingTileReset() {
    if (_missingTileResetScheduled) {
      return;
    }
    _missingTileResetScheduled = true;
    // Post-frame: the controller notifies listeners, which must not happen
    // while the canvas subtree is still building.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _missingTileResetScheduled = false;
      if (!mounted || _itemFor(_drag.tileId) != null) {
        // The tile came back, or a new session already started on a live
        // item — either way the stale reset must not clobber it.
        return;
      }
      switch (_drag.phase) {
        case SystemCardDragPhase.dragging:
          // The source is gone: drop the preview instead of settling into
          // a slot that no longer exists.
          _drag.cancel();
        case SystemCardDragPhase.finishing:
          // The drop already committed; only the ghost settle was orphaned.
          _drag.settleComplete();
        case SystemCardDragPhase.idle:
          break;
      }
    });
  }

  void _endSession(SystemCardDragContext dragContext) {
    final result = _drag.end(dragContext);
    if (result != null && !cardLayoutsEqual(result, dragContext.committed)) {
      ref
          .read(systemCardLayoutProvider.notifier)
          .commit(
            cardAnchorsFromLayout(result),
            canvasWidth: dragContext.geometry.canvasWidth,
          );
    }
    // A session that ends without a resolvable target (e.g. its card
    // disappeared mid-gesture) would otherwise wait forever for a ghost
    // animation that never runs.
    if (_drag.phase == SystemCardDragPhase.finishing &&
        _drag.finishingTarget == null) {
      _drag.settleComplete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final layoutState = ref.watch(systemCardLayoutProvider);
    return LayoutBuilder(
      builder: (context, constraints) {
        final geometry = CardGridGeometry.forWidth(constraints.maxWidth);
        final activeIds = <String>[for (final item in widget.items) item.id];
        final committed = resolveCardLayout(
          activeIds: activeIds,
          anchors: layoutState.anchors,
          geometry: geometry,
          catalog: SystemCardCatalog.instance,
        );
        final dragContext = SystemCardDragContext(
          geometry: geometry,
          catalog: SystemCardCatalog.instance,
          activeIds: activeIds,
          committed: committed,
        );
        return AnimatedBuilder(
          animation: _drag,
          builder: (context, _) => _buildCanvas(
            context,
            committed: committed,
            dragContext: dragContext,
            geometry: geometry,
            hydrated: layoutState.hydrated,
          ),
        );
      },
    );
  }

  Widget _buildCanvas(
    BuildContext context, {
    required List<CardTile> committed,
    required SystemCardDragContext dragContext,
    required CardGridGeometry geometry,
    required bool hydrated,
  }) {
    final theme = context.shellTheme;
    final colors = context.shellColors;
    if (_drag.isActive && _itemFor(_drag.tileId) == null) {
      _scheduleMissingTileReset();
    }
    final dragging = _drag.phase == SystemCardDragPhase.dragging;
    final finishing = _drag.phase == SystemCardDragPhase.finishing;
    final effective = _drag.previewLayout ?? committed;
    final moveDuration = _motion(650);
    final frameDuration = _motion(200);
    // Positions snap (never animate) until hydration lands once; after that
    // every change is a deliberate drag/keyboard move worth animating.
    final animatePositions = hydrated && _hydrationSettled;
    if (hydrated) {
      _hydrationSettled = true;
    }
    final target = _drag.previewTarget;
    final frameColor = _drag.previewValid
        ? theme.accentPalette.primary
        : theme.accentPalette.error;

    return AnimatedSize(
      duration: _motion(200),
      curve: Curves.easeOutCubic,
      child: SizedBox(
        key: _canvasKey,
        width: geometry.canvasWidth,
        height: cardContentHeight(effective),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // 24 px reference grid, shown only while a drag is live.
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: dragging ? 1 : 0,
                  duration: _motion(150),
                  child: CustomPaint(
                    painter: _CardGridGuidePainter(
                      color: colors.outlineVariant.withValues(alpha: 0.22),
                      step: cardGridGuideStep,
                    ),
                  ),
                ),
              ),
            ),
            // Snapped drop-target frame: primary fill, error when the
            // preview cannot be resolved.
            if (dragging && target != null)
              AnimatedPositioned(
                left: target.x,
                top: target.y,
                width: target.width,
                height: target.height,
                duration: frameDuration,
                curve: Curves.easeOutCubic,
                child: AnimatedContainer(
                  duration: frameDuration,
                  decoration: BoxDecoration(
                    color: frameColor.withValues(alpha: 0.14),
                    borderRadius: theme.borderRadius(ShellShapeScale.large),
                    border: Border.all(color: frameColor, width: 2),
                  ),
                ),
              ),
            for (final item in widget.items)
              _buildTile(
                item,
                committed: committed,
                effective: effective,
                dragContext: dragContext,
                moveDuration: animatePositions ? moveDuration : Duration.zero,
              ),
            if ((dragging || finishing) && !_drag.isKeyboardSession)
              _buildGhost(dragging: dragging, settleDuration: moveDuration),
          ],
        ),
      ),
    );
  }

  Widget _buildTile(
    SystemCardGridItem item, {
    required List<CardTile> committed,
    required List<CardTile> effective,
    required SystemCardDragContext dragContext,
    required Duration moveDuration,
  }) {
    final isSource = _drag.isActive && _drag.tileId == item.id;
    final pointerDragging =
        isSource &&
        _drag.phase == SystemCardDragPhase.dragging &&
        !_drag.isKeyboardSession;
    // The drag source stays at its committed slot while the ghost follows
    // the pointer; every other card reads the preview layout.
    final placement = pointerDragging
        ? placementFor(committed, item.id)
        : placementFor(effective, item.id);
    assert(
      placement != null,
      'SystemCardGridView received item "${item.id}", which never resolved '
      'to a layout tile — unknown ids are dropped by SystemCardCatalog, so '
      'register the id there or remove the item instead of passing it in.',
    );
    if (placement == null) {
      // Release builds skip the tile entirely instead of painting a silent
      // 0x0 stub at the canvas origin.
      return const SizedBox.shrink();
    }
    return AnimatedPositioned(
      key: ValueKey<String>(item.id),
      left: placement.x,
      top: placement.y,
      width: placement.width,
      height: placement.height,
      duration: moveDuration,
      curve: SystemCardGridView.settleCurve,
      child: SystemCardTile(
        dragged: pointerDragging,
        keyboardSession: isSource && _drag.isKeyboardSession,
        motionScale: widget.motionScale,
        onDragBegin: (grabLocal, global) => _drag.beginDrag(
          id: item.id,
          grabLocal: grabLocal,
          pointerCanvas: _canvasPoint(global),
          context: dragContext,
        ),
        onDragUpdate: (global) =>
            _drag.updateDrag(_canvasPoint(global), dragContext),
        onDragEnd: () => _endSession(dragContext),
        onDragCancel: _drag.cancel,
        onNudge: (delta) => _nudge(item.id, delta, dragContext),
        onKeyConfirm: () => _endSession(dragContext),
        onKeyCancel: _drag.cancel,
        child: item.child,
      ),
    );
  }

  Widget _buildGhost({
    required bool dragging,
    required Duration settleDuration,
  }) {
    final rect = dragging ? _drag.ghostRect : _drag.finishingTarget;
    final item = _itemFor(_drag.tileId);
    if (rect == null || item == null) {
      return const SizedBox.shrink();
    }
    // One widget serves both phases: duration zero tracks the finger every
    // frame while dragging; on release the same AnimatedPositioned retargets
    // to the committed slot and flies there over the settle duration.
    return AnimatedPositioned(
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      duration: dragging ? Duration.zero : settleDuration,
      curve: SystemCardGridView.settleCurve,
      onEnd: dragging ? null : _drag.settleComplete,
      child: IgnorePointer(
        child: Opacity(
          opacity: 0.82,
          child: Transform.scale(
            scale: 0.97,
            child: SizedBox(
              width: rect.width,
              height: rect.height,
              child: item.child,
            ),
          ),
        ),
      ),
    );
  }
}

/// 24 px alignment grid painted behind the tiles while a drag is live.
class _CardGridGuidePainter extends CustomPainter {
  const _CardGridGuidePainter({required this.color, required this.step});

  final Color color;
  final double step;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var x = step; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = step; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CardGridGuidePainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.step != step;
  }
}
