import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../launcher/controllers/home_grid_layout.dart';
import '../../launcher/launcher_providers.dart';
import '../../launcher/models/desktop_app.dart';
import '../../launcher/models/home_grid_item.dart';
import '../../local_apps/local_flutter_application.dart';
import '../models/desktop_tile.dart';
import '../repositories/desktop_tile_repository.dart';

final desktopTileRepositoryProvider = Provider<DesktopTileRepository>((ref) {
  return DesktopTileRepository(paths: ref.watch(runtimePathsProvider));
});

final desktopTileControllerProvider =
    AsyncNotifierProvider<DesktopTileController, DesktopTileState>(
      DesktopTileController.new,
    );

/// The desktop start menu's pin board.
///
/// This is deliberately not [HomeGridController]. That controller means "every
/// installed application": it seeds itself from the desktop scan, re-runs on a
/// timer, appends whatever was installed since, and writes the result back to
/// disk. A pin board with those habits would fill itself with all 100-odd
/// installed applications minutes after the user emptied it. It is also a
/// global singleton, so sharing it would make the start menu and the mobile
/// home screen the same grid.
///
/// What is shared is the geometry: [HomeGridLayout] does the cell arithmetic
/// for both boards, with [columns] passed explicitly so neither can compute
/// cells for the other's shape.
class DesktopTileController extends AsyncNotifier<DesktopTileState> {
  /// Windows 10 files tiles into six-column groups, and six is exactly what
  /// the four tile sizes need: a wide tile (4) beside a medium one (2) fills a
  /// row with nothing left over.
  static const int columns = 6;

  /// The board scrolls rather than pages. [HomeGridLayout]'s page argument
  /// exists to stop a tile straddling a page break, so the board hands it a
  /// page taller than any board can grow instead of a real page height.
  static const int pageSize = columns * 512;

  @override
  Future<DesktopTileState> build() async {
    final repository = ref.watch(desktopTileRepositoryProvider);
    // The local-application registry is the compile-time catalog of shell-hosted
    // windows, not the scanned .desktop list: watching it cannot make tiles
    // appear on their own.
    final registry = ref.watch(localFlutterApplicationRegistryProvider);

    final saved = await repository.readSavedLayout();
    if (saved == null) {
      return DesktopTileState.empty;
    }
    return DesktopTileState(
      groups: <DesktopTileGroup>[
        for (final group in saved) _resolveGroup(group, registry),
      ],
    );
  }

  /// Adds [app] to the board, or does nothing if it is already there.
  void pinApp(DesktopApp app) => _pin(HomeGridItem.pinnedApp(app));

  void pinLocalApp(LocalFlutterApplication app) =>
      _pin(HomeGridItem.pinnedLocalApp(app));

  /// Removes the tile with [itemId] and closes the gap it left.
  ///
  /// Windows 10 reflows a group when a tile leaves it, so the remaining tiles
  /// are re-placed in order rather than left around a hole. An unnamed group
  /// that ends up empty is dropped so the board can return to its empty state;
  /// a named one survives, because the user asked for it by name.
  void unpin(String itemId) {
    final current = state.asData?.value;
    if (current == null) {
      return;
    }

    final groups = <DesktopTileGroup>[];
    var removed = false;
    for (final group in current.groups) {
      if (removed || !group.slots.any((slot) => slot?.id == itemId)) {
        groups.add(group);
        continue;
      }
      removed = true;
      final slots = _repack(group.slots.where((slot) => slot?.id != itemId));
      if (slots.isEmpty && group.name.isEmpty) {
        continue;
      }
      groups.add(group.copyWith(slots: slots));
    }
    if (!removed) {
      return;
    }
    _commit(current.copyWith(groups: groups));
  }

  void renameGroup(int groupIndex, String name) {
    final current = state.asData?.value;
    if (current == null || !_validGroup(current, groupIndex)) {
      return;
    }
    if (current.groups[groupIndex].name == name) {
      return;
    }
    final groups = [...current.groups];
    groups[groupIndex] = groups[groupIndex].copyWith(name: name);
    _commit(current.copyWith(groups: groups));
  }

  void addGroup(String name) {
    final current = state.asData?.value;
    if (current == null) {
      return;
    }
    _commit(
      current.copyWith(
        groups: [
          ...current.groups,
          DesktopTileGroup(name: name, slots: const <HomeGridItem?>[]),
        ],
      ),
    );
  }

  void removeGroupIfEmpty(int groupIndex) {
    final current = state.asData?.value;
    if (current == null || !_validGroup(current, groupIndex)) {
      return;
    }
    if (current.groups[groupIndex].tileCount > 0) {
      return;
    }
    final groups = [...current.groups]..removeAt(groupIndex);
    _commit(current.copyWith(groups: groups));
  }

  bool canMoveSlot(int groupIndex, int fromIndex, int toIndex) {
    final group = _groupAt(groupIndex);
    if (group == null) {
      return false;
    }
    return HomeGridLayout.canMoveSlot(
      group.slots,
      fromIndex,
      toIndex,
      pageSize,
      columns: columns,
    );
  }

  /// Swaps the tile at [fromIndex] with whatever anchors [toIndex], returning
  /// where it landed, or null when the move would overlap another tile.
  int? moveSlot(int groupIndex, int fromIndex, int toIndex) {
    final current = state.asData?.value;
    final group = _groupAt(groupIndex);
    if (current == null || group == null) {
      return null;
    }

    final result = HomeGridLayout.moveSlot(
      group.slots,
      fromIndex,
      toIndex,
      pageSize,
      columns: columns,
    );
    if (result == null) {
      return null;
    }
    _commit(_withGroupSlots(current, groupIndex, result.slots));
    return result.movedToIndex;
  }

  /// Resizes the tile at [index], or does nothing when the larger footprint
  /// would overlap a neighbour or run past the sixth column.
  void resizeSlot(int groupIndex, int index, DesktopTileSize size) {
    final current = state.asData?.value;
    final group = _groupAt(groupIndex);
    if (current == null || group == null) {
      return;
    }

    final result = HomeGridLayout.resizeSlot(
      group.slots,
      index,
      size.colSpan,
      size.rowSpan,
      pageSize,
      columns: columns,
    );
    if (result == null) {
      return;
    }
    _commit(_withGroupSlots(current, groupIndex, result.slots));
  }

  void _pin(HomeGridItem item) {
    final current = state.asData?.value;
    if (current == null || current.contains(item.id)) {
      return;
    }

    final groups = [...current.groups];
    if (groups.isEmpty) {
      groups.add(DesktopTileGroup.unnamed);
    }
    final targetIndex = groups.length - 1;
    groups[targetIndex] = groups[targetIndex].copyWith(
      slots: HomeGridLayout.placeItemInFirstFreeSlot(
        groups[targetIndex].slots,
        item,
        columns: columns,
      ),
    );
    _commit(current.copyWith(groups: groups));
  }

  DesktopTileState _withGroupSlots(
    DesktopTileState current,
    int groupIndex,
    List<HomeGridItem?> slots,
  ) {
    final groups = [...current.groups];
    groups[groupIndex] = groups[groupIndex].copyWith(slots: slots);
    return current.copyWith(groups: groups);
  }

  void _commit(DesktopTileState next) {
    state = AsyncData(next);
    unawaited(ref.read(desktopTileRepositoryProvider).saveLayout(next.groups));
  }

  DesktopTileGroup? _groupAt(int groupIndex) {
    final current = state.asData?.value;
    if (current == null || !_validGroup(current, groupIndex)) {
      return null;
    }
    return current.groups[groupIndex];
  }

  static bool _validGroup(DesktopTileState state, int groupIndex) =>
      groupIndex >= 0 && groupIndex < state.groups.length;

  static DesktopTileGroup _resolveGroup(
    DesktopTileGroupLayout layout,
    LocalFlutterApplicationRegistry registry,
  ) {
    var slots = <HomeGridItem?>[];
    for (var index = 0; index < layout.slots.length; index += 1) {
      final item = _resolveSlot(layout.slots[index], registry);
      if (item == null) {
        continue;
      }
      final placed = HomeGridLayout.placeItemAt(
        slots,
        index,
        item,
        columns: columns,
      );
      // A slot the saved index cannot hold — a hand-edited overlap, or a local
      // application whose default span differs from the stored one — is placed
      // at the next free cell rather than dropped.
      slots = identical(placed, slots)
          ? HomeGridLayout.placeItemInFirstFreeSlot(
              slots,
              item,
              columns: columns,
            )
          : placed;
    }
    return DesktopTileGroup(name: layout.name, slots: slots);
  }

  static HomeGridItem? _resolveSlot(
    DesktopTileSlot? slot,
    LocalFlutterApplicationRegistry registry,
  ) {
    if (slot == null) {
      return null;
    }
    if (slot.app case final app?) {
      return HomeGridItem.pinnedApp(
        app,
        colSpan: slot.colSpan ?? HomeGridItem.pinnedDefaultColSpan,
        rowSpan: slot.rowSpan ?? HomeGridItem.pinnedDefaultRowSpan,
      );
    }
    if (slot.id.startsWith(DesktopTileRepository.localAppIdPrefix)) {
      final localId = slot.id.substring(
        DesktopTileRepository.localAppIdPrefix.length,
      );
      // A shell-hosted application that is no longer in the bundle can never
      // come back, so its tile goes rather than rendering as a dead cell.
      final app = registry[localId];
      if (app == null) {
        return null;
      }
      return HomeGridItem.pinnedLocalApp(
        app,
        colSpan: slot.colSpan ?? HomeGridItem.pinnedDefaultColSpan,
        rowSpan: slot.rowSpan ?? HomeGridItem.pinnedDefaultRowSpan,
      );
    }
    return null;
  }

  /// Re-places [items] from the first cell, closing gaps while keeping order.
  static List<HomeGridItem?> _repack(Iterable<HomeGridItem?> items) {
    var slots = <HomeGridItem?>[];
    for (final item in items) {
      if (item == null) {
        continue;
      }
      slots = HomeGridLayout.placeItemInFirstFreeSlot(
        slots,
        item,
        columns: columns,
      );
    }
    return slots;
  }
}
