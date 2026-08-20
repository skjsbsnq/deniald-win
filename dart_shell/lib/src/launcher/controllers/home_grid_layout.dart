import 'dart:math' as math;
import 'dart:ui';

import '../../local_apps/local_flutter_application.dart';
import '../models/desktop_app.dart';
import '../models/home_grid_item.dart';

class HomeGridMoveResult {
  const HomeGridMoveResult({required this.slots, required this.movedToIndex});

  final List<HomeGridItem?> slots;
  final int movedToIndex;
}

class HomeGridResizeResult {
  const HomeGridResizeResult({required this.slots, required this.resizedIndex});

  final List<HomeGridItem?> slots;
  final int resizedIndex;
}

class HomeGridLayout {
  const HomeGridLayout._();

  /// Column count for the current viewport. 4 is the phone-tuned baseline;
  /// [columnsForViewport] raises it on wide panels (set once per layout pass
  /// by HomeSurface) so pages stay full-bleed instead of overflowing rows.
  static int columns = 4;
  static const double gridGap = 22;
  static const int minPages = 2;

  /// Tile content is fixed-size (92px icon + label ~= 131 tall), so cells
  /// gain nothing from growing: cap their footprint and let wide panels get
  /// more columns/rows instead. Phone-width viewports stay at 4 columns
  /// with uncapped-equivalent sizes.
  static const double maxTileWidth = 224;
  static const double maxTileHeight = 240;

  /// Column count so tiles stay at or under [maxTileWidth].
  static int columnsForViewport(double width) {
    final cols = ((width + gridGap) / (maxTileWidth + gridGap)).ceil();
    return cols.clamp(4, 14).toInt();
  }

  static int rowsForHeight(double height, double tileHeight) {
    const minRows = 3;
    const maxRows = 7;
    final rows = ((height + gridGap) / (tileHeight + gridGap)).floor();
    return rows.clamp(minRows, maxRows).toInt();
  }

  static int pageCountForSlots(List<HomeGridItem?> slots, int pageSize) {
    if (pageSize <= 0) {
      return minPages;
    }
    return math.max(minPages, (slots.length / pageSize).ceil());
  }

  static List<HomeGridItem?> ensureSlotCapacity(
    List<HomeGridItem?> slots,
    int pageSize,
  ) {
    if (pageSize <= 0) {
      return slots;
    }

    final minSlots = pageSize * minPages;
    final roundedSlots = ((slots.length + pageSize - 1) ~/ pageSize) * pageSize;
    final wantedSlots = math.max(minSlots, roundedSlots);
    if (slots.length >= wantedSlots) {
      return slots;
    }

    return [...slots, for (var i = slots.length; i < wantedSlots; i += 1) null];
  }

  static List<HomeGridItem?> initialSlotsForApps(
    List<DesktopApp> apps,
    Iterable<LocalFlutterApplication> localApps,
    List<HomeLayoutSlot?>? savedLayout,
  ) {
    final itemsById = <String, HomeGridItem>{
      'widget:clock': HomeGridItem.clock(),
      'widget:battery-discharge': HomeGridItem.batteryDischarge(),
      for (final app in apps) 'app:${app.id}': HomeGridItem.app(app),
      for (final app in localApps)
        'local:${app.id}': HomeGridItem.localApp(app),
    };
    final used = <String>{};
    var slots = <HomeGridItem?>[];

    if (savedLayout != null) {
      for (var index = 0; index < savedLayout.length; index += 1) {
        final slot = savedLayout[index];
        if (slot == null || used.contains(slot.id)) {
          continue;
        }

        var item = itemsById[slot.id];
        if (item == null) {
          continue;
        }
        if (item.resizable) {
          item = item.resize(
            colSpan: slot.colSpan ?? item.colSpan,
            rowSpan: slot.rowSpan ?? item.rowSpan,
          );
        }

        final placed = placeItemAt(slots, index, item);
        if (identical(placed, slots)) {
          continue;
        }
        slots = placed;
        used.add(slot.id);
      }
    }

    for (final item in itemsById.values) {
      if (used.contains(item.id)) {
        continue;
      }
      if (savedLayout != null && item.type == HomeGridItemType.app) {
        slots = placeItemAfter(slots, savedLayout.length, item);
      } else {
        slots = placeItemInFirstFreeSlot(slots, item);
      }
    }
    return slots;
  }

  static List<HomeGridItem?> refreshSlotsForApps(
    List<HomeGridItem?> currentSlots,
    List<DesktopApp> apps,
    Iterable<LocalFlutterApplication> localApps,
  ) {
    final appItemsById = <String, HomeGridItem>{
      for (final app in apps) 'app:${app.id}': HomeGridItem.app(app),
      for (final app in localApps)
        'local:${app.id}': HomeGridItem.localApp(app),
    };
    final placedIds = <String>{};
    var next = <HomeGridItem?>[];

    for (var index = 0; index < currentSlots.length; index += 1) {
      final current = currentSlots[index];
      if (current == null || placedIds.contains(current.id)) {
        continue;
      }

      final item = current.type == HomeGridItemType.app
          ? appItemsById[current.id]
          : current;
      if (item == null) {
        continue;
      }

      final placed = placeItemAt(next, index, item);
      next = identical(placed, next)
          ? placeItemInFirstFreeSlot(next, item)
          : placed;
      placedIds.add(item.id);
    }

    for (final item in appItemsById.values) {
      if (placedIds.contains(item.id)) {
        continue;
      }
      next = placeItemAfter(next, currentSlots.length, item);
      placedIds.add(item.id);
    }
    return next;
  }

  static List<HomeGridItem?> placeItemAt(
    List<HomeGridItem?> slots,
    int index,
    HomeGridItem item, {
    int? columns,
  }) {
    if (!itemFitsAtColumn(item, index, columns: columns)) {
      return slots;
    }

    final cells = cellsFor(index, item, columns: columns);
    final blocked = cells.any(
      (cell) => anchorForCell(cell, slots, columns: columns) != null,
    );
    if (blocked) {
      return slots;
    }

    final next = ensureListLength([...slots], cells.last + 1);
    next[index] = item;
    return next;
  }

  static List<HomeGridItem?> placeItemInFirstFreeSlot(
    List<HomeGridItem?> slots,
    HomeGridItem item, {
    int? columns,
  }) {
    return placeItemAfter(slots, 0, item, columns: columns);
  }

  static List<HomeGridItem?> placeItemAfter(
    List<HomeGridItem?> slots,
    int startIndex,
    HomeGridItem item, {
    int? columns,
  }) {
    var next = [...slots];
    for (var index = math.max(0, startIndex); ; index += 1) {
      if (!itemFitsAtColumn(item, index, columns: columns)) {
        continue;
      }
      final cells = cellsFor(index, item, columns: columns);
      final blocked = cells.any(
        (cell) => anchorForCell(cell, next, columns: columns) != null,
      );
      if (blocked) {
        continue;
      }
      next = ensureListLength(next, cells.last + 1);
      next[index] = item;
      return next;
    }
  }

  static bool itemFitsAtColumn(HomeGridItem item, int index, {int? columns}) {
    final effectiveColumns = columns ?? HomeGridLayout.columns;
    final column = index % effectiveColumns;
    return column + item.colSpan <= effectiveColumns;
  }

  static bool itemFitsInPage(
    int index,
    HomeGridItem item,
    int pageSize, {
    int? columns,
  }) {
    if (pageSize <= 0 || !itemFitsAtColumn(item, index, columns: columns)) {
      return false;
    }
    final pageStart = (index ~/ pageSize) * pageSize;
    final pageEnd = pageStart + pageSize;
    return cellsFor(
      index,
      item,
      columns: columns,
    ).every((cell) => cell >= pageStart && cell < pageEnd);
  }

  static List<int> cellsFor(int index, HomeGridItem item, {int? columns}) {
    columns ??= HomeGridLayout.columns;
    final baseRow = index ~/ columns;
    final baseColumn = index % columns;
    return [
      for (var row = 0; row < item.rowSpan; row += 1)
        for (var column = 0; column < item.colSpan; column += 1)
          (baseRow + row) * columns + baseColumn + column,
    ];
  }

  static int? anchorForCell(
    int cell,
    List<HomeGridItem?> slots, {
    int? columns,
  }) {
    for (var index = 0; index < slots.length; index += 1) {
      final item = slots[index];
      if (item == null) {
        continue;
      }
      if (cellsFor(index, item, columns: columns).contains(cell)) {
        return index;
      }
    }
    return null;
  }

  static List<HomeGridItem?> ensureListLength(
    List<HomeGridItem?> slots,
    int length,
  ) {
    if (slots.length >= length) {
      return slots;
    }
    return [...slots, for (var i = slots.length; i < length; i += 1) null];
  }

  static bool canPlaceAt(
    List<HomeGridItem?> slots,
    int index,
    HomeGridItem item,
    int pageSize, {
    required Set<int> ignoreAnchors,
    int? columns,
  }) {
    if (!itemFitsInPage(index, item, pageSize, columns: columns)) {
      return false;
    }

    for (final cell in cellsFor(index, item, columns: columns)) {
      final occupant = anchorForCell(cell, slots, columns: columns);
      if (occupant != null && !ignoreAnchors.contains(occupant)) {
        return false;
      }
    }
    return true;
  }

  static bool canMoveSlot(
    List<HomeGridItem?> slots,
    int fromIndex,
    int toIndex,
    int pageSize, {
    int? columns,
  }) {
    if (fromIndex == toIndex ||
        fromIndex < 0 ||
        toIndex < 0 ||
        fromIndex >= slots.length) {
      return false;
    }

    final source = slots[fromIndex];
    if (source == null) {
      return false;
    }

    final targetAnchor =
        anchorForCell(toIndex, slots, columns: columns) ?? toIndex;
    if (targetAnchor == fromIndex) {
      return false;
    }
    final target = targetAnchor < slots.length ? slots[targetAnchor] : null;
    if (target == null) {
      return canPlaceAt(
        slots,
        toIndex,
        source,
        pageSize,
        ignoreAnchors: {fromIndex},
        columns: columns,
      );
    }

    return canPlaceAt(
          slots,
          targetAnchor,
          source,
          pageSize,
          ignoreAnchors: {fromIndex, targetAnchor},
          columns: columns,
        ) &&
        canPlaceAt(
          slots,
          fromIndex,
          target,
          pageSize,
          ignoreAnchors: {fromIndex, targetAnchor},
          columns: columns,
        );
  }

  static HomeGridMoveResult? moveSlot(
    List<HomeGridItem?> slots,
    int fromIndex,
    int toIndex,
    int pageSize, {
    int? columns,
  }) {
    if (!canMoveSlot(slots, fromIndex, toIndex, pageSize, columns: columns)) {
      return null;
    }

    final source = slots[fromIndex];
    if (source == null) {
      return null;
    }

    final targetAnchor =
        anchorForCell(toIndex, slots, columns: columns) ?? toIndex;
    final target = targetAnchor < slots.length ? slots[targetAnchor] : null;
    final requiredLength = [
      ...cellsFor(targetAnchor, source, columns: columns),
      if (target != null) ...cellsFor(fromIndex, target, columns: columns),
    ].reduce(math.max);

    final next = ensureListLength([...slots], requiredLength + 1);
    next[fromIndex] = target;
    next[targetAnchor] = source;
    return HomeGridMoveResult(slots: next, movedToIndex: targetAnchor);
  }

  static bool canResizeSlot(
    List<HomeGridItem?> slots,
    int index,
    int colSpan,
    int rowSpan,
    int pageSize, {
    int? columns,
  }) {
    if (index < 0 || index >= slots.length) {
      return false;
    }

    final source = slots[index];
    if (source == null || !source.resizable) {
      return false;
    }

    final resized = source.resize(colSpan: colSpan, rowSpan: rowSpan);
    return canPlaceAt(
      slots,
      index,
      resized,
      pageSize,
      ignoreAnchors: {index},
      columns: columns,
    );
  }

  static HomeGridResizeResult? resizeSlot(
    List<HomeGridItem?> slots,
    int index,
    int colSpan,
    int rowSpan,
    int pageSize, {
    int? columns,
  }) {
    if (!canResizeSlot(
      slots,
      index,
      colSpan,
      rowSpan,
      pageSize,
      columns: columns,
    )) {
      return null;
    }

    final source = slots[index];
    if (source == null) {
      return null;
    }

    final resized = source.resize(colSpan: colSpan, rowSpan: rowSpan);
    final cells = cellsFor(index, resized, columns: columns);
    final next = ensureListLength([...slots], cells.last + 1);
    next[index] = resized;
    return HomeGridResizeResult(slots: next, resizedIndex: index);
  }

  static double rectOverlapArea(Rect a, Rect b) {
    final left = math.max(a.left, b.left);
    final right = math.min(a.right, b.right);
    final top = math.max(a.top, b.top);
    final bottom = math.min(a.bottom, b.bottom);
    if (right <= left || bottom <= top) {
      return 0;
    }
    return (right - left) * (bottom - top);
  }
}
