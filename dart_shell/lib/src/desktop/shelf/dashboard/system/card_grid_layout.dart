import 'dart:math' as math;

import 'package:flutter/widgets.dart' show Offset;

import 'card_catalog.dart';

/// Pixel grid metrics for the system card canvas.
///
/// Ported from clavis `SystemCardGrid.js` / `SystemCardGeometry.js` /
/// `DrawerGridLayout.js`. Clavis fixes the canvas at 472 px (152 px cells);
/// denial derives the cell width from the measured dashboard width — three
/// columns, one 8 px snap step, one 24 px guide step.
const double cardGridSnapStep = 8;
const double cardGridGuideStep = 24;
const double cardCellHeight = 160;
const double cardCellGap = 8;
const int cardGridColumns = 3;

/// Immutable grid metrics derived from the measured canvas width.
class CardGridGeometry {
  const CardGridGeometry._({
    required this.cellWidth,
    this.cellHeight = cardCellHeight,
    this.gap = cardCellGap,
    this.columns = cardGridColumns,
    this.snapStep = cardGridSnapStep,
  });

  /// Divides [canvasWidth] into [cardGridColumns] equal cells separated by
  /// [cardCellGap]. Heights stay fixed; only column width follows the panel.
  factory CardGridGeometry.forWidth(
    double canvasWidth, {
    double cellHeight = cardCellHeight,
    double gap = cardCellGap,
    int columns = cardGridColumns,
    double snapStep = cardGridSnapStep,
  }) {
    final cellWidth = (canvasWidth - (columns - 1) * gap) / columns;
    return CardGridGeometry._(
      cellWidth: cellWidth,
      cellHeight: cellHeight,
      gap: gap,
      columns: columns,
      snapStep: snapStep,
    );
  }

  final double cellWidth;
  final double cellHeight;
  final double gap;
  final int columns;
  final double snapStep;

  double get canvasWidth => columns * cellWidth + (columns - 1) * gap;

  /// clavis `widthForSpan`: span cells plus the gaps between them.
  double widthForSpan(int columnSpan) {
    final span = math.max(1, columnSpan.round());
    return span * cellWidth + (span - 1) * gap;
  }

  /// clavis `heightForSpan`.
  double heightForSpan(int rowSpan) {
    final span = math.max(1, rowSpan.round());
    return span * cellHeight + (span - 1) * gap;
  }

  /// Default anchor converted from cells to snapped canvas pixels.
  Offset anchorPixels(int column, int row) =>
      Offset(column * (cellWidth + gap), row * (cellHeight + gap));
}

/// One placed card rectangle in canvas pixels.
class CardTile {
  const CardTile({
    required this.id,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final String id;
  final double x;
  final double y;
  final double width;
  final double height;

  Offset get origin => Offset(x, y);
  double get area => width * height;

  CardTile copyWith({double? x, double? y}) => CardTile(
    id: id,
    x: x ?? this.x,
    y: y ?? this.y,
    width: width,
    height: height,
  );

  @override
  bool operator ==(Object other) =>
      other is CardTile &&
      other.id == id &&
      other.x == x &&
      other.y == y &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(id, x, y, width, height);

  @override
  String toString() => 'CardTile($id, $x, $y, ${width}x$height)';
}

/// clavis `gridSnap`: round to the nearest [step] multiple inside [0, limit]
/// where the limit itself snaps down to the step grid.
double gridSnap(
  double value,
  double maximum, {
  double step = cardGridSnapStep,
}) {
  final limit = math.max(0, (maximum / step).floor() * step);
  return math.max(0, math.min(limit, (value / step).round() * step)).toDouble();
}

/// clavis `gridOverlaps`: rectangles separated by [gap] still count as
/// touching.
bool tilesOverlap(CardTile first, CardTile second, double gap) {
  return first.x < second.x + second.width + gap &&
      first.x + first.width + gap > second.x &&
      first.y < second.y + second.height + gap &&
      first.y + first.height + gap > second.y;
}

/// clavis `gridEdgeCandidates`: a free rectangle can slide to any occupied
/// edge or canvas boundary. Both sides of a rounded edge are kept so
/// fractional inputs cannot remove a legal snapped candidate. O(n²) in card
/// count, independent of canvas resolution.
List<Offset> gridEdgeCandidates(
  CardTile card,
  List<CardTile> occupied, {
  required double width,
  required double height,
  required double gap,
  double step = cardGridSnapStep,
}) {
  final maxX = math.max(0.0, width - card.width);
  final maxY = math.max(0.0, height - card.height);
  final xs = <double>[];
  final ys = <double>[];

  void add(List<double> values, double value, double maximum) {
    final options = step > 0
        ? <double>[
            ((value / step).floor() * step).toDouble(),
            ((value / step).ceil() * step).toDouble(),
          ]
        : <double>[value];
    final limit = step > 0 ? (maximum / step).floor() * step : maximum;
    for (final option in options) {
      final bounded = math.max(0, math.min(limit, option)).toDouble();
      if (!values.contains(bounded)) {
        values.add(bounded);
      }
    }
  }

  add(xs, card.x, maxX);
  add(ys, card.y, maxY);
  add(xs, 0, maxX);
  add(ys, 0, maxY);
  add(xs, maxX, maxX);
  add(ys, maxY, maxY);
  for (final rect in occupied) {
    add(xs, rect.x - card.width - gap, maxX);
    add(xs, rect.x + rect.width + gap, maxX);
    add(ys, rect.y - card.height - gap, maxY);
    add(ys, rect.y + rect.height + gap, maxY);
  }
  return <Offset>[
    for (final y in ys)
      for (final x in xs) Offset(x, y),
  ];
}

/// clavis `gridNearestFree`: the edge candidate nearest the desired position
/// that does not overlap any occupied tile.
CardTile? nearestFreeTile(
  CardTile card,
  List<CardTile> occupied, {
  required double width,
  required double height,
  required double gap,
  double step = cardGridSnapStep,
}) {
  if (card.width > width || card.height > height) {
    return null;
  }
  final candidates = gridEdgeCandidates(
    card,
    occupied,
    width: width,
    height: height,
    gap: gap,
    step: step,
  );
  candidates.sort((a, b) {
    final delta =
        (a.dx - card.x) * (a.dx - card.x) +
        (a.dy - card.y) * (a.dy - card.y) -
        (b.dx - card.x) * (b.dx - card.x) -
        (b.dy - card.y) * (b.dy - card.y);
    if (delta != 0) {
      return delta.sign.toInt();
    }
    final dy = a.dy.compareTo(b.dy);
    return dy != 0 ? dy : a.dx.compareTo(b.dx);
  });
  for (final point in candidates) {
    final rect = card.copyWith(x: point.dx, y: point.dy);
    final blocked = occupied.any((other) => tilesOverlap(rect, other, gap));
    if (!blocked) {
      return rect;
    }
  }
  return null;
}

CardTile? placementFor(List<CardTile> layout, String id) {
  for (final tile in layout) {
    if (tile.id == id) {
      return tile;
    }
  }
  return null;
}

CardTile _tileAt(
  SystemCardCatalog catalog,
  CardGridGeometry geometry,
  String id,
  Offset point,
) {
  return CardTile(
    id: id,
    x: point.dx,
    y: point.dy,
    width: geometry.widthForSpan(catalog.columnSpanFor(id)),
    height: geometry.heightForSpan(catalog.rowSpanFor(id)),
  );
}

Offset _clampAnchor(
  SystemCardCatalog catalog,
  CardGridGeometry geometry,
  String id,
  double x,
  double y,
) {
  return Offset(
    gridSnap(
      x,
      geometry.canvasWidth - geometry.widthForSpan(catalog.columnSpanFor(id)),
      step: geometry.snapStep,
    ),
    gridSnap(y, double.maxFinite, step: geometry.snapStep),
  );
}

/// clavis `withinBounds`: finite, snapped, and inside the canvas width.
/// The vertical extent stays unbounded — the canvas scrolls.
bool _withinBounds(CardTile tile, CardGridGeometry geometry) {
  final step = geometry.snapStep;
  return tile.x.isFinite &&
      tile.y.isFinite &&
      tile.x >= 0 &&
      tile.y >= 0 &&
      tile.x % step == 0 &&
      tile.y % step == 0 &&
      tile.x + tile.width <= geometry.canvasWidth;
}

/// clavis `validateLayout`: exactly the expected ids, catalog sizes, snapped
/// inside the canvas, and pairwise non-overlapping.
bool cardLayoutIsValid(
  List<CardTile> layout,
  List<String> expected,
  CardGridGeometry geometry,
  SystemCardCatalog catalog,
) {
  if (layout.length != expected.length) {
    return false;
  }
  final seen = <String>{};
  for (var i = 0; i < layout.length; i += 1) {
    final tile = layout[i];
    if (!expected.contains(tile.id) ||
        !seen.add(tile.id) ||
        !catalog.hasCard(tile.id) ||
        tile.width != geometry.widthForSpan(catalog.columnSpanFor(tile.id)) ||
        tile.height != geometry.heightForSpan(catalog.rowSpanFor(tile.id)) ||
        !_withinBounds(tile, geometry)) {
      return false;
    }
    for (var j = 0; j < i; j += 1) {
      if (tilesOverlap(tile, layout[j], geometry.gap)) {
        return false;
      }
    }
  }
  return true;
}

/// clavis `compactLayout`: packs every card upward while preserving its x
/// and the relative vertical order of x-intersecting cards. Returns null
/// when the input is not a valid layout.
List<CardTile>? compactCardLayout(
  List<CardTile> layout,
  List<String> expected,
  CardGridGeometry geometry,
  SystemCardCatalog catalog,
) {
  if (!cardLayoutIsValid(layout, expected, geometry, catalog)) {
    return null;
  }
  final ordered = layout.toList()
    ..sort((a, b) {
      final dy = a.y.compareTo(b.y);
      if (dy != 0) {
        return dy;
      }
      final dx = a.x.compareTo(b.x);
      if (dx != 0) {
        return dx;
      }
      return expected.indexOf(a.id).compareTo(expected.indexOf(b.id));
    });
  final placed = <CardTile>[];
  for (final tile in ordered) {
    var y = 0.0;
    for (final above in placed) {
      if (tile.x < above.x + above.width + geometry.gap &&
          tile.x + tile.width + geometry.gap > above.x) {
        y = math.max(y, above.y + above.height + geometry.gap);
      }
    }
    placed.add(tile.copyWith(y: y));
  }
  return <CardTile>[for (final id in expected) placementFor(placed, id)!];
}

/// clavis `place`: nearest free slot for [id] around [anchor] (or the
/// catalog default anchor), bounded below by the occupied bottom.
CardTile _place(
  SystemCardCatalog catalog,
  CardGridGeometry geometry,
  List<String> expected,
  String id,
  Offset? anchor,
  List<CardTile> occupied,
) {
  final fallback = catalog.defaultAnchorFor(id, expected);
  final fallbackPixels = geometry.anchorPixels(fallback.column, fallback.row);
  final point = _clampAnchor(
    catalog,
    geometry,
    id,
    anchor?.dx ?? fallbackPixels.dx,
    anchor?.dy ?? fallbackPixels.dy,
  );
  final card = _tileAt(catalog, geometry, id, point);
  final bottom = occupied.fold<double>(
    point.dy,
    (value, tile) => math.max(value, tile.y + tile.height),
  );
  return nearestFreeTile(
        card,
        occupied,
        width: geometry.canvasWidth,
        height: bottom + geometry.gap + card.height,
        gap: geometry.gap,
        step: geometry.snapStep,
      ) ??
      card;
}

/// clavis `buildLayout`: every persisted position is reserved before new or
/// returning cards are placed, then the result is compacted.
List<CardTile> buildCardLayout(
  List<String> activeIds,
  Map<String, ({double x, double y})> anchors,
  CardGridGeometry geometry,
  SystemCardCatalog catalog,
) {
  final expected = catalog.orderedIds(activeIds);
  final occupied = <CardTile>[];
  for (final id in expected) {
    final anchor = anchors[id];
    if (anchor != null) {
      occupied.add(_tileAt(catalog, geometry, id, Offset(anchor.x, anchor.y)));
    }
  }
  for (final id in expected.where((id) => !anchors.containsKey(id))) {
    occupied.add(_place(catalog, geometry, expected, id, null, occupied));
  }
  return compactCardLayout(
        <CardTile>[for (final id in expected) placementFor(occupied, id)!],
        expected,
        geometry,
        catalog,
      ) ??
      <CardTile>[for (final id in expected) placementFor(occupied, id)!];
}

/// Hydration for persisted anchors (clavis `hydrateSaved`): any unknown id,
/// unsnapped coordinate, out-of-bounds tile, or overlap rejects the whole
/// saved layout and falls back to the default anchors.
List<CardTile> resolveCardLayout({
  required List<String> activeIds,
  required Map<String, ({double x, double y})> anchors,
  required CardGridGeometry geometry,
  required SystemCardCatalog catalog,
}) {
  final expected = catalog.orderedIds(activeIds);
  if (anchors.isEmpty) {
    return buildCardLayout(expected, const {}, geometry, catalog);
  }
  final accepted = <String, ({double x, double y})>{};
  final occupied = <CardTile>[];
  for (final entry in anchors.entries) {
    if (!catalog.hasCard(entry.key)) {
      return buildCardLayout(expected, const {}, geometry, catalog);
    }
    final tile = _tileAt(
      catalog,
      geometry,
      entry.key,
      Offset(entry.value.x, entry.value.y),
    );
    if (!_withinBounds(tile, geometry)) {
      return buildCardLayout(expected, const {}, geometry, catalog);
    }
    if (!expected.contains(entry.key)) {
      continue;
    }
    if (occupied.any((other) => tilesOverlap(tile, other, geometry.gap))) {
      return buildCardLayout(expected, const {}, geometry, catalog);
    }
    occupied.add(tile);
    accepted[entry.key] = entry.value;
  }
  return buildCardLayout(expected, accepted, geometry, catalog);
}

/// clavis `moveLayout`: the dragged card is authoritative — cards it
/// collides with relocate by descending area, then everything compacts.
/// Returns null when the committed layout is invalid or the id is unknown.
List<CardTile>? moveCardLayout(
  List<CardTile> layout,
  String tileId,
  double targetX,
  double targetY, {
  required CardGridGeometry geometry,
  required SystemCardCatalog catalog,
  List<String>? activeIds,
}) {
  final expected = catalog.orderedIds(
    activeIds ?? <String>[for (final tile in layout) tile.id],
  );
  if (!cardLayoutIsValid(layout, expected, geometry, catalog) ||
      !expected.contains(tileId)) {
    return null;
  }
  final moving = _tileAt(
    catalog,
    geometry,
    tileId,
    _clampAnchor(catalog, geometry, tileId, targetX, targetY),
  );
  final occupied = <CardTile>[moving];
  final displaced = <CardTile>[];
  for (final tile in layout) {
    if (tile.id == tileId) {
      continue;
    }
    if (tilesOverlap(tile, moving, geometry.gap)) {
      displaced.add(tile);
    } else {
      occupied.add(tile.copyWith());
    }
  }
  // Resolve collisions first, then compact all cards into the final
  // preview. Larger displaced cards get first pick of the free slots.
  displaced.sort((a, b) {
    final area = b.area.compareTo(a.area);
    if (area != 0) {
      return area;
    }
    return expected.indexOf(a.id).compareTo(expected.indexOf(b.id));
  });
  for (final tile in displaced) {
    occupied.add(
      _place(catalog, geometry, expected, tile.id, tile.origin, occupied),
    );
  }
  return compactCardLayout(
    <CardTile>[for (final id in expected) placementFor(occupied, id)!],
    expected,
    geometry,
    catalog,
  );
}

/// clavis `contentHeight`: the lowest occupied edge (never below one row).
double cardContentHeight(
  List<CardTile> layout, {
  double minimum = cardCellHeight,
}) {
  return layout.fold<double>(
    minimum,
    (bottom, tile) => math.max(bottom, tile.y + tile.height),
  );
}

/// Whether two layouts place the same ids at identical rectangles.
bool cardLayoutsEqual(List<CardTile> first, List<CardTile> second) {
  if (first.length != second.length) {
    return false;
  }
  for (var i = 0; i < first.length; i += 1) {
    if (first[i] != second[i]) {
      return false;
    }
  }
  return true;
}

/// Serializable `{id: (x, y)}` anchors for a committed layout.
Map<String, ({double x, double y})> cardAnchorsFromLayout(
  List<CardTile> layout,
) {
  return <String, ({double x, double y})>{
    for (final tile in layout) tile.id: (x: tile.x, y: tile.y),
  };
}
