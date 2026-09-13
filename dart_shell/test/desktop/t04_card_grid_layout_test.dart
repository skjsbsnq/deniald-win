import 'package:denial_dart_shell/src/desktop/shelf/dashboard/system/card_catalog.dart';
import 'package:denial_dart_shell/src/desktop/shelf/dashboard/system/card_grid_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const catalog = SystemCardCatalog.instance;
  // 412 px canvas → 132 px cells: 3 * 132 + 2 * 8 = 412.
  final geometry = CardGridGeometry.forWidth(412);

  const ids = <String>['cpu', 'memory', 'network', 'storage', 'battery'];

  List<CardTile> defaultLayout() => resolveCardLayout(
    activeIds: ids,
    anchors: const {},
    geometry: geometry,
    catalog: catalog,
  );

  group('gridSnap', () {
    test('rounds to the nearest step inside [0, snapped limit]', () {
      expect(gridSnap(0, 412), 0);
      expect(gridSnap(10, 412), 8);
      expect(gridSnap(13, 412), 16);
      expect(gridSnap(-5, 412), 0);
      // The limit snaps down: a 272-wide card in a 412 canvas may not pass
      // 140 raw but only 136 is on the 8 px grid.
      expect(gridSnap(140, 140), 136);
      expect(gridSnap(139, 140), 136);
    });
  });

  group('tilesOverlap', () {
    test('cards separated by exactly the gap do not overlap', () {
      const a = CardTile(id: 'a', x: 0, y: 0, width: 272, height: 160);
      const b = CardTile(id: 'b', x: 280, y: 0, width: 132, height: 160);
      expect(tilesOverlap(a, b, 8), isFalse);
      expect(tilesOverlap(a, b.copyWith(x: 276), 8), isTrue);
    });
  });

  group('nearestFreeTile', () {
    test('slides to the nearest free edge candidate', () {
      const card = CardTile(id: 'm', x: 0, y: 0, width: 132, height: 160);
      const occupied = <CardTile>[
        CardTile(id: 'c', x: 0, y: 0, width: 272, height: 160),
      ];
      final free = nearestFreeTile(
        card,
        occupied,
        width: 412,
        height: 500,
        gap: 8,
      );
      // Edge candidates are occupied edges + canvas bounds: the closest
      // non-overlapping one is the snapped row below the occupied tile.
      expect(free, isNotNull);
      expect(free!.x, 0);
      expect(free.y, 168);
    });

    test('returns null when the card cannot fit the canvas', () {
      const card = CardTile(id: 'x', x: 0, y: 0, width: 500, height: 160);
      expect(
        nearestFreeTile(card, const [], width: 412, height: 500, gap: 8),
        isNull,
      );
    });
  });

  group('resolveCardLayout', () {
    test('empty anchors produce the default anchor arrangement', () {
      final layout = defaultLayout();
      expect(
        placementFor(layout, 'cpu'),
        const CardTile(id: 'cpu', x: 0, y: 0, width: 272, height: 160),
      );
      expect(
        placementFor(layout, 'memory'),
        const CardTile(id: 'memory', x: 280, y: 0, width: 132, height: 160),
      );
      expect(
        placementFor(layout, 'network'),
        const CardTile(id: 'network', x: 0, y: 168, width: 272, height: 160),
      );
      expect(
        placementFor(layout, 'battery'),
        const CardTile(id: 'battery', x: 280, y: 168, width: 132, height: 328),
      );
      expect(
        placementFor(layout, 'storage'),
        const CardTile(id: 'storage', x: 0, y: 336, width: 272, height: 160),
      );
    });

    test('gpu tiles stack under cpu and shift the rows below', () {
      final layout = resolveCardLayout(
        activeIds: const ['cpu', 'gpu:card0', 'gpu:card1', 'memory'],
        anchors: const {},
        geometry: geometry,
        catalog: catalog,
      );
      expect(
        placementFor(layout, 'gpu:card0'),
        const CardTile(id: 'gpu:card0', x: 0, y: 168, width: 272, height: 160),
      );
      expect(
        placementFor(layout, 'gpu:card1'),
        const CardTile(id: 'gpu:card1', x: 0, y: 336, width: 272, height: 160),
      );
      expect(placementFor(layout, 'memory')!.y, 0);
    });

    test('honors valid saved anchors', () {
      final layout = resolveCardLayout(
        activeIds: ids,
        anchors: const {'memory': (x: 144, y: 0)},
        geometry: geometry,
        catalog: catalog,
      );
      expect(placementFor(layout, 'memory')!.x, 144);
      // The remaining cards are placed around the saved slot without
      // overlap — the result must still be a fully valid layout.
      expect(
        cardLayoutIsValid(layout, catalog.orderedIds(ids), geometry, catalog),
        isTrue,
      );
    });

    test('rejects saved layouts wholesale on any invalid tile', () {
      // Unknown id.
      expect(
        resolveCardLayout(
          activeIds: ids,
          anchors: const {'bogus': (x: 0, y: 0)},
          geometry: geometry,
          catalog: catalog,
        ),
        defaultLayout(),
      );
      // Unsnapped x (137 % 8 != 0).
      expect(
        resolveCardLayout(
          activeIds: ids,
          anchors: const {'memory': (x: 137, y: 0)},
          geometry: geometry,
          catalog: catalog,
        ),
        defaultLayout(),
      );
      // Out of bounds.
      expect(
        resolveCardLayout(
          activeIds: ids,
          anchors: const {'memory': (x: 288, y: 0)},
          geometry: geometry,
          catalog: catalog,
        ),
        defaultLayout(),
      );
      // Overlapping pair: cpu at 0..272, memory forced onto it.
      expect(
        resolveCardLayout(
          activeIds: ids,
          anchors: const {'cpu': (x: 0, y: 0), 'memory': (x: 16, y: 0)},
          geometry: geometry,
          catalog: catalog,
        ),
        defaultLayout(),
      );
    });
  });

  group('compactCardLayout', () {
    test('packs upward, keeps x, keeps relative vertical order', () {
      const a = CardTile(id: 'memory', x: 0, y: 400, width: 132, height: 160);
      const b = CardTile(id: 'cpu', x: 0, y: 200, width: 272, height: 160);
      // 'cpu'/'memory' are the only actives here so the layout validates.
      final compacted = compactCardLayout(
        const [a, b],
        const ['cpu', 'memory'],
        geometry,
        catalog,
      )!;
      expect(placementFor(compacted, 'cpu')!.y, 0);
      expect(placementFor(compacted, 'memory')!.y, 168);
      expect(placementFor(compacted, 'memory')!.x, 0);
    });

    test('non-intersecting columns compact independently', () {
      const a = CardTile(id: 'cpu', x: 0, y: 400, width: 272, height: 160);
      const b = CardTile(id: 'memory', x: 280, y: 400, width: 132, height: 160);
      final compacted = compactCardLayout(
        const [a, b],
        const ['cpu', 'memory'],
        geometry,
        catalog,
      )!;
      expect(placementFor(compacted, 'cpu')!.y, 0);
      expect(placementFor(compacted, 'memory')!.y, 0);
    });

    test('returns null for an invalid input layout', () {
      const a = CardTile(id: 'cpu', x: 0, y: 0, width: 272, height: 160);
      const b = CardTile(id: 'memory', x: 16, y: 0, width: 132, height: 160);
      expect(
        compactCardLayout(
          const [a, b],
          const ['cpu', 'memory'],
          geometry,
          catalog,
        ),
        isNull,
      );
    });
  });

  group('moveCardLayout', () {
    test('moving onto a sibling displaces it downward', () {
      final committed = defaultLayout();
      // Drag memory (280,0) onto the cpu slot.
      final moved = moveCardLayout(
        committed,
        'memory',
        0,
        0,
        geometry: geometry,
        catalog: catalog,
        activeIds: ids,
      )!;
      expect(placementFor(moved, 'memory')!.x, 0);
      expect(placementFor(moved, 'memory')!.y, 0);
      // cpu was pushed somewhere below and the result still validates.
      final cpu = placementFor(moved, 'cpu')!;
      expect(cpu.y, greaterThan(0));
      expect(
        cardLayoutIsValid(moved, catalog.orderedIds(ids), geometry, catalog),
        isTrue,
      );
    });

    test(
      'the dragged card is authoritative and stays at the snapped target',
      () {
        final committed = defaultLayout();
        // Drop storage into the empty column-2 gap at row 3 (x=280, y=504)
        // does not fit (storage is 272 wide: 280+272>412) → clamped.
        final moved = moveCardLayout(
          committed,
          'storage',
          280,
          504,
          geometry: geometry,
          catalog: catalog,
          activeIds: ids,
        )!;
        final storage = placementFor(moved, 'storage')!;
        expect(storage.x + storage.width, lessThanOrEqualTo(412));
        expect(storage.x % 8, 0);
        expect(storage.y % 8, 0);
        expect(
          cardLayoutIsValid(moved, catalog.orderedIds(ids), geometry, catalog),
          isTrue,
        );
      },
    );

    test('returns null for an unknown tile id or invalid base layout', () {
      final committed = defaultLayout();
      expect(
        moveCardLayout(
          committed,
          'nope',
          0,
          0,
          geometry: geometry,
          catalog: catalog,
          activeIds: ids,
        ),
        isNull,
      );
      const broken = <CardTile>[
        CardTile(id: 'cpu', x: 0, y: 0, width: 272, height: 160),
        CardTile(id: 'memory', x: 8, y: 0, width: 132, height: 160),
      ];
      expect(
        moveCardLayout(
          broken,
          'cpu',
          0,
          0,
          geometry: geometry,
          catalog: catalog,
          activeIds: const ['cpu', 'memory'],
        ),
        isNull,
      );
    });
  });

  group('cardContentHeight / cardLayoutsEqual / cardAnchorsFromLayout', () {
    test('content height covers the lowest tile', () {
      expect(cardContentHeight(defaultLayout()), 496);
      expect(cardContentHeight(const []), cardCellHeight);
    });

    test('round-trips anchors through the resolver', () {
      final committed = moveCardLayout(
        defaultLayout(),
        'memory',
        0,
        0,
        geometry: geometry,
        catalog: catalog,
        activeIds: ids,
      )!;
      final anchors = cardAnchorsFromLayout(committed);
      final resolved = resolveCardLayout(
        activeIds: ids,
        anchors: anchors,
        geometry: geometry,
        catalog: catalog,
      );
      expect(cardLayoutsEqual(resolved, committed), isTrue);
    });
  });
}
