import 'package:denial_dart_shell/src/desktop/shelf/dashboard/system/card_catalog.dart';
import 'package:denial_dart_shell/src/desktop/shelf/dashboard/system/card_drag_controller.dart';
import 'package:denial_dart_shell/src/desktop/shelf/dashboard/system/card_grid_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const catalog = SystemCardCatalog.instance;
  final geometry = CardGridGeometry.forWidth(412);
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
          pointerCanvas: const Offset(340, 20),
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
      expect(ghost.width, 132);
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
      // memory starts at x=280; one 8 px nudge left.
      expect(target.x, 272);
      expect(target.y, 0);

      final result = controller.end(context)!;
      // Keyboard sessions skip finishing — no ghost to settle.
      expect(controller.phase, SystemCardDragPhase.idle);
      expect(placementFor(result, 'memory')!.x, 272);
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
