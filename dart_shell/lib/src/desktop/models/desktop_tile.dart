import 'package:flutter/foundation.dart';

import '../../launcher/models/desktop_app.dart';
import '../../launcher/models/home_grid_item.dart';

/// The four tile sizes Windows 10 offers, in pin-board cells.
///
/// Six columns is what makes the set coherent: a wide tile plus a medium tile
/// fill one row exactly, which is the proportion the reference screenshot
/// shows.
enum DesktopTileSize {
  small(1, 1),
  medium(2, 2),
  wide(4, 2),
  large(4, 4);

  const DesktopTileSize(this.colSpan, this.rowSpan);

  final int colSpan;
  final int rowSpan;

  /// The named size [item] currently occupies, or null for a span combination
  /// no menu entry can produce.
  static DesktopTileSize? of(HomeGridItem item) {
    for (final size in values) {
      if (size.colSpan == item.colSpan && size.rowSpan == item.rowSpan) {
        return size;
      }
    }
    return null;
  }
}

/// One persisted pin-board slot.
///
/// [app] carries the whole application record and not just an id because the
/// board deliberately never reads the installed-application scan: resolving
/// ids against that list is what would make the board either empty until the
/// first scan finished or full of tiles the user never pinned. Shell-hosted
/// applications carry no record — they are compiled into the bundle, so the
/// registry stays authoritative for them.
@immutable
class DesktopTileSlot {
  const DesktopTileSlot({
    required this.id,
    this.colSpan,
    this.rowSpan,
    this.app,
  });

  final String id;
  final int? colSpan;
  final int? rowSpan;
  final DesktopApp? app;
}

/// One persisted group: a heading plus its slots.
@immutable
class DesktopTileGroupLayout {
  const DesktopTileGroupLayout({required this.name, required this.slots});

  final String name;
  final List<DesktopTileSlot?> slots;
}

/// A named group of live tiles.
@immutable
class DesktopTileGroup {
  const DesktopTileGroup({required this.name, required this.slots});

  static const DesktopTileGroup unnamed = DesktopTileGroup(
    name: '',
    slots: <HomeGridItem?>[],
  );

  /// The heading the user typed. Empty means the board shows a placeholder,
  /// which is how a freshly created group starts.
  final String name;
  final List<HomeGridItem?> slots;

  int get tileCount => slots.whereType<HomeGridItem>().length;

  DesktopTileGroup copyWith({String? name, List<HomeGridItem?>? slots}) {
    return DesktopTileGroup(
      name: name ?? this.name,
      slots: slots ?? this.slots,
    );
  }

  /// Slots compare by identity rather than by value.
  ///
  /// [HomeGridItem] has no `==`, and giving it one would mean giving
  /// [DesktopApp] one too — a change to shared mobile-side models this task has
  /// no reason to make. Identity errs in the safe direction: every mutator
  /// reuses the item instances it did not touch, so a real edit always compares
  /// unequal, and the worst an unnecessary rebuild costs is one frame.
  @override
  bool operator ==(Object other) {
    if (other is! DesktopTileGroup || other.name != name) {
      return false;
    }
    if (other.slots.length != slots.length) {
      return false;
    }
    for (var index = 0; index < slots.length; index += 1) {
      if (!identical(other.slots[index], slots[index])) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(name, slots.length);
}

/// The whole pin board.
@immutable
class DesktopTileState {
  const DesktopTileState({required this.groups});

  static const DesktopTileState empty = DesktopTileState(
    groups: <DesktopTileGroup>[],
  );

  final List<DesktopTileGroup> groups;

  bool get hasTiles => groups.any((group) => group.tileCount > 0);

  /// Whether [id] is already on the board, which is what turns the application
  /// list's menu entry from pin into unpin.
  bool contains(String id) {
    return groups.any((group) => group.slots.any((slot) => slot?.id == id));
  }

  DesktopTileState copyWith({List<DesktopTileGroup>? groups}) {
    return DesktopTileState(groups: groups ?? this.groups);
  }

  @override
  bool operator ==(Object other) {
    return other is DesktopTileState && listEquals(other.groups, groups);
  }

  @override
  int get hashCode => Object.hashAll(groups);
}
