import 'package:denial_dart_shell/src/desktop/shelf/dashboard/system/card_catalog.dart';
import 'package:denial_dart_shell/src/desktop/shelf/dashboard/system/card_grid_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const catalog = SystemCardCatalog.instance;
  // The canvas is fixed like clavis: 3 x 152 px cells + 2 x 8 px gaps = 472.
  const geometry = CardGridGeometry();

  const ids = <String>['cpu', 'memory', 'network', 'storage', 'battery'];

  List<CardTile> defaultLayout() => resolveCardLayout(
    activeIds: ids,
    anchors: const {},
    geometry: geometry,
    catalog: catalog,
  );

  group('fixed canvas geometry', () {
    test('canvas is 472 px of 152 px cells with 8 px gaps', () {
      expect(cardCellWidth, 152);
      expect(cardCellHeight, 160);
      expect(cardCellGap, 8);
      expect(cardGridSnapStep, 8);
      expect(cardGridGuideStep, 24);
      expect(geometry.canvasWidth, 472);
      expect(cardCanvasWidth, 472);
      expect(geometry.widthForSpan(1), 152);
      expect(geometry.widthForSpan(2), 312);
      expect(geometry.widthForSpan(3), 472);
      // Every column boundary lands on the 8 px snap grid — this is what
      // makes drag snapping align with column anchors.
      for (var column = 0; column < 3; column++) {
        expect(geometry.anchorPixels(column, 0).dx % cardGridSnapStep, 0);
      }
      expect(geometry.anchorPixels(1, 0), const Offset(160, 0));
      expect(geometry.anchorPixels(2, 0), const Offset(320, 0));
    });

    test('a 1-wide card lands in any column and a 2-wide card reaches 472', () {
      for (var column = 0; column < cardGridColumns; column++) {
        final slotX = column * (cardCellWidth + cardCellGap);
        final layout = resolveCardLayout(
          activeIds: const ['memory'],
          anchors: <String, ({double x, double y})>{'memory': (x: slotX, y: 0)},
          geometry: geometry,
          catalog: catalog,
        );
        expect(placementFor(layout, 'memory')!.x, slotX);
      }
      // A 2-wide card parked in column 1 ends flush with the canvas edge:
      // 160 + 312 = 472, which is why the column pitch must stay on the
      // 8 px grid (160 % 8 == 0).
      final wide = resolveCardLayout(
        activeIds: const ['cpu', 'memory'],
        anchors: const {'cpu': (x: 160, y: 0)},
        geometry: geometry,
        catalog: catalog,
      );
      final cpu = placementFor(wide, 'cpu')!;
      expect(cpu.x + cpu.width, cardCanvasWidth);
      expect(
        cardLayoutIsValid(
          wide,
          catalog.orderedIds(const ['cpu', 'memory']),
          geometry,
          catalog,
        ),
        isTrue,
      );
    });
  });

  group('catalog spans and default anchors', () {
    test('network and storage are full-row, battery is a 1x1 mini tank', () {
      expect(catalog.columnSpanFor('network'), 3);
      expect(catalog.columnSpanFor('storage'), 3);
      expect(catalog.rowSpanFor('network'), 1);
      expect(catalog.rowSpanFor('storage'), 1);
      expect(catalog.columnSpanFor('battery'), 1);
      expect(catalog.rowSpanFor('battery'), 1);
      expect(catalog.columnSpanFor('cpu'), 2);
      expect(catalog.columnSpanFor('gpu:x'), 2);
    });

    test('default anchors pair cpu+memory and gpu+battery', () {
      const withGpu = <String>[
        'cpu',
        'gpu:card0',
        'memory',
        'network',
        'storage',
        'battery',
      ];
      expect(catalog.defaultAnchorFor('cpu', withGpu), (column: 0, row: 0));
      expect(catalog.defaultAnchorFor('memory', withGpu), (column: 2, row: 0));
      expect(catalog.defaultAnchorFor('gpu:card0', withGpu), (
        column: 0,
        row: 1,
      ));
      expect(catalog.defaultAnchorFor('battery', withGpu), (column: 2, row: 1));
      expect(catalog.defaultAnchorFor('network', withGpu), (column: 0, row: 2));
      expect(catalog.defaultAnchorFor('storage', withGpu), (column: 0, row: 3));
    });
  });

  group('gridSnap', () {
    test('rounds to the nearest step inside [0, snapped limit]', () {
      expect(gridSnap(0, 472), 0);
      expect(gridSnap(10, 472), 8);
      expect(gridSnap(13, 472), 16);
      expect(gridSnap(-5, 472), 0);
      // The limit snaps down: a 312-wide card in a 472 canvas may not pass
      // 160 raw but only 160 is on the 8 px grid — the same value here
      // because 160 % 8 == 0.
      expect(gridSnap(164, 160), 160);
      expect(gridSnap(140, 140), 136);
      expect(gridSnap(139, 140), 136);
    });
  });

  group('tilesOverlap', () {
    test('cards separated by exactly the gap do not overlap', () {
      const a = CardTile(id: 'a', x: 0, y: 0, width: 312, height: 160);
      const b = CardTile(id: 'b', x: 320, y: 0, width: 152, height: 160);
      expect(tilesOverlap(a, b, 8), isFalse);
      expect(tilesOverlap(a, b.copyWith(x: 316), 8), isTrue);
    });
  });

  group('nearestFreeTile', () {
    test('slides to the nearest free edge candidate', () {
      const card = CardTile(id: 'm', x: 0, y: 0, width: 152, height: 160);
      const occupied = <CardTile>[
        CardTile(id: 'c', x: 0, y: 0, width: 312, height: 160),
      ];
      final free = nearestFreeTile(
        card,
        occupied,
        width: 472,
        height: 500,
        gap: 8,
      );
      // Edge candidates are occupied edges + canvas bounds: the closest
      // non-overlapping ones are right of the occupied tile or below it.
      expect(free, isNotNull);
      expect(
        free!.x == 320 && free.y == 0 || free.x == 0 && free.y == 168,
        isTrue,
      );
    });

    test('returns null when the card cannot fit the canvas', () {
      const card = CardTile(id: 'x', x: 0, y: 0, width: 500, height: 160);
      expect(
        nearestFreeTile(card, const [], width: 472, height: 500, gap: 8),
        isNull,
      );
    });
  });

  group('resolveCardLayout', () {
    test('empty anchors produce the default anchor arrangement', () {
      final layout = defaultLayout();
      expect(
        placementFor(layout, 'cpu'),
        const CardTile(id: 'cpu', x: 0, y: 0, width: 312, height: 160),
      );
      expect(
        placementFor(layout, 'memory'),
        const CardTile(id: 'memory', x: 320, y: 0, width: 152, height: 160),
      );
      expect(
        placementFor(layout, 'network'),
        const CardTile(id: 'network', x: 0, y: 168, width: 472, height: 160),
      );
      expect(
        placementFor(layout, 'storage'),
        const CardTile(id: 'storage', x: 0, y: 336, width: 472, height: 160),
      );
      // No gpu: the mini tank lands on the partial bottom row — the
      // full-width rows block compaction past them.
      expect(
        placementFor(layout, 'battery'),
        const CardTile(id: 'battery', x: 320, y: 504, width: 152, height: 160),
      );
    });

    test('a gpu fills row 1 and the battery tucks into its third column', () {
      final layout = resolveCardLayout(
        activeIds: const [
          'cpu',
          'gpu:card0',
          'memory',
          'network',
          'storage',
          'battery',
        ],
        anchors: const {},
        geometry: geometry,
        catalog: catalog,
      );
      expect(
        placementFor(layout, 'gpu:card0'),
        const CardTile(id: 'gpu:card0', x: 0, y: 168, width: 312, height: 160),
      );
      expect(
        placementFor(layout, 'battery'),
        const CardTile(id: 'battery', x: 320, y: 168, width: 152, height: 160),
      );
      expect(
        placementFor(layout, 'network'),
        const CardTile(id: 'network', x: 0, y: 336, width: 472, height: 160),
      );
      expect(
        placementFor(layout, 'storage'),
        const CardTile(id: 'storage', x: 0, y: 504, width: 472, height: 160),
      );
      expect(cardContentHeight(layout), 664);
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
        const CardTile(id: 'gpu:card0', x: 0, y: 168, width: 312, height: 160),
      );
      expect(
        placementFor(layout, 'gpu:card1'),
        const CardTile(id: 'gpu:card1', x: 0, y: 336, width: 312, height: 160),
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
      // Out of bounds: a 1-wide tile may not pass x=320 (152 + 352 > 472).
      expect(
        resolveCardLayout(
          activeIds: ids,
          anchors: const {'memory': (x: 352, y: 0)},
          geometry: geometry,
          catalog: catalog,
        ),
        defaultLayout(),
      );
      // Overlapping pair: cpu at 0..312, memory forced onto it.
      expect(
        resolveCardLayout(
          activeIds: ids,
          anchors: const {'cpu': (x: 0, y: 0), 'memory': (x: 16, y: 0)},
          geometry: geometry,
          catalog: catalog,
        ),
        defaultLayout(),
      );
      // Beyond the scroll-extent ceiling — the canvas scrolls but a
      // corrupt save must not stretch it to absurdity.
      expect(
        resolveCardLayout(
          activeIds: ids,
          anchors: const {'memory': (x: 0, y: 1e9)},
          geometry: geometry,
          catalog: catalog,
        ),
        defaultLayout(),
      );
      // Non-finite coordinates.
      expect(
        resolveCardLayout(
          activeIds: ids,
          anchors: const {'memory': (x: double.nan, y: 0)},
          geometry: geometry,
          catalog: catalog,
        ),
        defaultLayout(),
      );
    });
  });

  group('compactCardLayout', () {
    test('packs upward, keeps x, keeps relative vertical order', () {
      const a = CardTile(id: 'memory', x: 0, y: 400, width: 152, height: 160);
      const b = CardTile(id: 'cpu', x: 0, y: 200, width: 312, height: 160);
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
      const a = CardTile(id: 'cpu', x: 0, y: 400, width: 312, height: 160);
      const b = CardTile(id: 'memory', x: 320, y: 400, width: 152, height: 160);
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
      const a = CardTile(id: 'cpu', x: 0, y: 0, width: 312, height: 160);
      const b = CardTile(id: 'memory', x: 16, y: 0, width: 152, height: 160);
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
    test('moving onto a sibling relocates it to the nearest free slot', () {
      final committed = defaultLayout();
      // Drag memory (320,0) onto the cpu slot.
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
      // cpu was pushed out of its slot — onto the freed right side of row 0
      // (x=160, right edge flush with the canvas) — and the result still
      // validates.
      final cpu = placementFor(moved, 'cpu')!;
      expect(cpu, isNot(placementFor(committed, 'cpu')));
      expect(cpu.x + cpu.width, cardCanvasWidth);
      expect(
        cardLayoutIsValid(moved, catalog.orderedIds(ids), geometry, catalog),
        isTrue,
      );
    });

    test(
      'the dragged card is authoritative and stays at the snapped target',
      () {
        final committed = defaultLayout();
        // Drop the full-width storage row near the battery slot: its x is
        // clamped to 0 (a 472-wide card has nowhere else to go) and the
        // battery is displaced out of the partial bottom row.
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
        expect(storage.x + storage.width, lessThanOrEqualTo(472));
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
        CardTile(id: 'cpu', x: 0, y: 0, width: 312, height: 160),
        CardTile(id: 'memory', x: 8, y: 0, width: 152, height: 160),
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
      expect(cardContentHeight(defaultLayout()), 664);
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
