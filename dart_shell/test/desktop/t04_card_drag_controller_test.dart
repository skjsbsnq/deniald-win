import 'package:denial_dart_shell/src/desktop/shelf/dashboard/system/card_catalog.dart';
import 'package:denial_dart_shell/src/desktop/shelf/dashboard/system/card_drag_controller.dart';
import 'package:denial_dart_shell/src/desktop/shelf/dashboard/system/card_grid_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const catalog = SystemCardCatalog.instance;
  const geometry = CardGridGeometry();
  const ids = <String>['cpu', 'memory', 'network', 'storage', 'battery'];

  late List<CardTile> committed;
  late SystemCardDragContext context;
  late SystemCardDragController controller;

  setUp(() {
    committed = resolveCardLayout(
      activeIds: ids,
      anchors: const {},
      geometry: geometry,
      catalog: catalog,
    );
    context = SystemCardDragContext(
      geometry: geometry,
      catalog: catalog,
      activeIds: ids,
      committed: committed,
    );
    controller = SystemCardDragController();
  });

  tearDown(() {
    controller.dispose();
  });

  group('pointer session', () {
    test('idle → dragging → finishing → idle', () {
      expect(controller.phase, SystemCardDragPhase.idle);
      expect(
        controller.beginDrag(
          id: 'memory',
          grabLocal: const Offset(60, 20),
          pointerCanvas: const Offset(380, 20),
          context: context,
        ),
        isTrue,
      );
      expect(controller.phase, SystemCardDragPhase.dragging);
      // A second session cannot start while one is live.
      expect(
        controller.beginDrag(
          id: 'cpu',
          grabLocal: Offset.zero,
          pointerCanvas: Offset.zero,
          context: context,
        ),
        isFalse,
      );

      // Ghost follows pointer minus the immutable grab point.
      controller.updateDrag(const Offset(100, 120), context);
      final ghost = controller.ghostRect!;
      expect(ghost.left, 100 - 60);
      expect(ghost.top, 120 - 20);
      expect(ghost.width, 152);
      expect(ghost.height, 160);

      // The preview shows memory's snapped target near the ghost.
      final target = controller.previewTarget!;
      expect(target.id, 'memory');
      expect(target.x % 8, 0);
      expect(target.y % 8, 0);
      expect(controller.previewValid, isTrue);
      expect(
        cardLayoutIsValid(controller.previewLayout!, ids, geometry, catalog),
        isTrue,
      );

      final result = controller.end(context)!;
      expect(controller.phase, SystemCardDragPhase.finishing);
      expect(controller.finishingTarget, isNotNull);
      expect(cardLayoutIsValid(result, ids, geometry, catalog), isTrue);

      controller.settleComplete();
      expect(controller.phase, SystemCardDragPhase.idle);
      expect(controller.ghostRect, isNull);
      expect(controller.previewLayout, isNull);
    });

    test('an unresolvable preview clears state and commits nothing', () {
      // Begin a session on a tile that is not in the committed layout —
      // the same shape as a gpu vanishing between the id snapshot and the
      // gesture: every move fails to resolve.
      final shrunk = resolveCardLayout(
        activeIds: const ['cpu', 'network'],
        anchors: const {},
        geometry: geometry,
        catalog: catalog,
      );
      final stale = SystemCardDragContext(
        geometry: geometry,
        catalog: catalog,
        activeIds: const ['cpu', 'network'],
        committed: shrunk,
      );
      expect(
        controller.beginDrag(
          id: 'memory',
          grabLocal: const Offset(10, 10),
          pointerCanvas: const Offset(10, 10),
          context: stale,
        ),
        isTrue,
      );
      controller.updateDrag(const Offset(120, 200), stale);
      // The move cannot resolve: preview cleared, frame marked invalid.
      expect(controller.previewValid, isFalse);
      expect(controller.previewLayout, isNull);
      // The dragged id is not in the committed layout at all, so there is
      // no tile rectangle to draw the error frame around.
      expect(controller.previewTarget, isNull);

      // end() must not commit: null result, and the finishing ghost has no
      // target so the view can finish the session immediately.
      expect(controller.end(stale), isNull);
      expect(controller.phase, SystemCardDragPhase.finishing);
      expect(controller.finishingTarget, isNull);
      controller.settleComplete();
      expect(controller.phase, SystemCardDragPhase.idle);
    });

    test('a once-invalid preview recovers on the next resolvable move', () {
      final shrunk = resolveCardLayout(
        activeIds: const ['cpu', 'network'],
        anchors: const {},
        geometry: geometry,
        catalog: catalog,
      );
      final stale = SystemCardDragContext(
        geometry: geometry,
        catalog: catalog,
        activeIds: const ['cpu', 'network'],
        committed: shrunk,
      );
      controller.beginDrag(
        id: 'memory',
        grabLocal: const Offset(10, 10),
        pointerCanvas: const Offset(10, 10),
        context: stale,
      );
      controller.updateDrag(const Offset(120, 200), stale);
      expect(controller.previewValid, isFalse);
      // The tile reappears (provider id set grew back): the next frame in
      // the *new* context resolves normally again.
      controller.updateDrag(const Offset(340, 20), context);
      expect(controller.previewValid, isTrue);
      expect(controller.previewLayout, isNotNull);
      expect(
        cardLayoutIsValid(controller.previewLayout!, ids, geometry, catalog),
        isTrue,
      );
      final result = controller.end(context)!;
      expect(placementFor(result, 'memory'), isNotNull);
      controller.settleComplete();
    });

    test('cancel returns to idle without a result', () {
      controller.beginDrag(
        id: 'cpu',
        grabLocal: const Offset(10, 10),
        pointerCanvas: const Offset(10, 10),
        context: context,
      );
      controller.updateDrag(const Offset(200, 300), context);
      expect(controller.previewLayout, isNotNull);
      controller.cancel();
      expect(controller.phase, SystemCardDragPhase.idle);
      expect(controller.previewLayout, isNull);
      // end() on an idle session is a no-op.
      expect(controller.end(context), isNull);
    });
  });

  group('keyboard session', () {
    test('arrows nudge 8 px through the same preview pipeline', () {
      expect(controller.beginKeyboard(id: 'memory', context: context), isTrue);
      expect(controller.isKeyboardSession, isTrue);
      // No ghost during a keyboard session.
      expect(controller.ghostRect, isNull);

      controller.nudge(const Offset(-8, 0), context);
      final target = controller.previewTarget!;
      // memory starts at x=320; one 8 px nudge left.
      expect(target.x, 312);
      expect(target.y, 0);

      final result = controller.end(context)!;
      // Keyboard sessions skip finishing — no ghost to settle.
      expect(controller.phase, SystemCardDragPhase.idle);
      expect(placementFor(result, 'memory')!.x, 312);
    });

    test('cancel restores the committed layout (Esc semantics)', () {
      controller.beginKeyboard(id: 'memory', context: context);
      controller.nudge(const Offset(-8, 0), context);
      controller.nudge(const Offset(-8, 0), context);
      controller.cancel();
      expect(controller.phase, SystemCardDragPhase.idle);
      expect(controller.previewLayout, isNull);
    });
  });
}
