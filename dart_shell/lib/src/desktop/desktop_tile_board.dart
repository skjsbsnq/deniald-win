import 'dart:math' as math;

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/generated/app_localizations.dart';
import '../launcher/controllers/home_grid_layout.dart';
import '../launcher/models/desktop_app.dart';
import '../launcher/models/home_grid_item.dart';
import '../local_apps/local_flutter_application.dart';
import '../localization/denial_localizations.dart';
import '../theme/shell_theme.dart';
import '../theme/tokens.dart';
import '../wallpaper/state/wallpaper_accent.dart';
import '../widgets/shell_cursor.dart';
import 'controllers/desktop_tile_controller.dart';
import 'desktop_tile_cell.dart';
import 'desktop_tile_menu.dart';
import 'models/desktop_tile.dart';

/// Where the pin board's cells fall.
///
/// Kept apart from the widgets because "which slot did this drop land on" has
/// to be answerable without pumping a frame.
@immutable
class DesktopTileGeometry {
  const DesktopTileGeometry({
    required this.columns,
    required this.tileExtent,
    required this.gap,
  });

  /// The thin seam between tiles from the reference screenshot. It is the only
  /// separation there is — tiles carry no outline.
  static const double gapExtent = 4;

  /// Below this a tile is too small to hold a recognisable icon; the board
  /// scrolls horizontally-clipped rather than shrink past it, which cannot
  /// happen at any width the three-column panel actually offers.
  static const double minTileExtent = 36;

  /// Square cells across [width]: a medium tile has to read as a square and a
  /// wide one as two of them side by side.
  factory DesktopTileGeometry.fit(double width, {required int columns}) {
    final usable = width - gapExtent * (columns - 1);
    return DesktopTileGeometry(
      columns: columns,
      tileExtent: math.max(minTileExtent, usable / columns),
      gap: gapExtent,
    );
  }

  final int columns;
  final double tileExtent;
  final double gap;

  double get step => tileExtent + gap;

  Rect rectFor(int index, HomeGridItem item) {
    return Rect.fromLTWH(
      (index % columns) * step,
      (index ~/ columns) * step,
      item.colSpan * tileExtent + (item.colSpan - 1) * gap,
      item.rowSpan * tileExtent + (item.rowSpan - 1) * gap,
    );
  }

  /// The slot index containing [offset], or null when it lands outside the
  /// [rows] the board currently shows.
  int? indexAt(Offset offset, {required int rows}) {
    if (offset.dx < 0 || offset.dy < 0) {
      return null;
    }
    final column = (offset.dx / step).floor();
    final row = (offset.dy / step).floor();
    if (column >= columns || row >= rows) {
      return null;
    }
    return row * columns + column;
  }

  /// Rows to lay out for [slots], including one empty row past the last tile.
  ///
  /// The spare row is what makes a tile draggable to a new bottom row: without
  /// it there is no empty cell below the board to aim at.
  int rowsFor(List<HomeGridItem?> slots) {
    var lastRow = -1;
    for (var index = 0; index < slots.length; index += 1) {
      final item = slots[index];
      if (item == null) {
        continue;
      }
      final cells = HomeGridLayout.cellsFor(index, item, columns: columns);
      lastRow = math.max(lastRow, cells.last ~/ columns);
    }
    return lastRow + 2;
  }

  double heightFor(List<HomeGridItem?> slots) {
    final rows = rowsFor(slots);
    return rows * tileExtent + (rows - 1) * gap;
  }
}

/// A tile in flight. Cross-group dragging is not offered, so the source group
/// travels with the payload only so the target can refuse a foreign tile.
@immutable
class _TileDrag {
  const _TileDrag({
    required this.groupIndex,
    required this.index,
    required this.item,
  });

  final int groupIndex;
  final int index;
  final HomeGridItem item;
}

/// The pin board: named groups of tiles, scrolling vertically.
class DesktopTileBoard extends ConsumerWidget {
  const DesktopTileBoard({
    super.key,
    required this.accent,
    required this.onLaunch,
    required this.onLaunchLocal,
  });

  final WallpaperAccent accent;
  final ValueChanged<DesktopApp> onLaunch;
  final ValueChanged<LocalFlutterApplication> onLaunchLocal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final board =
        ref.watch(desktopTileControllerProvider).asData?.value ??
        DesktopTileState.empty;

    if (board.groups.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: DesktopTileBoardEmptyState(),
      );
    }

    return CustomScrollView(
      slivers: <Widget>[
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          sliver: SliverList.builder(
            itemCount: board.groups.length,
            itemBuilder: (context, index) => _TileGroupSection(
              key: ValueKey<int>(index),
              groupIndex: index,
              group: board.groups[index],
              accent: accent,
              onLaunch: onLaunch,
              onLaunchLocal: onLaunchLocal,
            ),
          ),
        ),
      ],
    );
  }
}

/// Shown while nothing is pinned.
///
/// Windows 10 leaves an unpinned board blank, which here would read as a broken
/// panel because nothing else says tiles exist or how they get there.
class DesktopTileBoardEmptyState extends StatelessWidget {
  const DesktopTileBoardEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.dashboard_customize_outlined,
            size: 34,
            color: ShellColors.textTertiary,
          ),
          const SizedBox(height: 10),
          Text(
            context.l10n.desktopStartMenuTilesHint,
            textAlign: TextAlign.center,
            style: ShellText.cardTitle.copyWith(
              color: ShellColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _TileGroupSection extends ConsumerStatefulWidget {
  const _TileGroupSection({
    super.key,
    required this.groupIndex,
    required this.group,
    required this.accent,
    required this.onLaunch,
    required this.onLaunchLocal,
  });

  final int groupIndex;
  final DesktopTileGroup group;
  final WallpaperAccent accent;
  final ValueChanged<DesktopApp> onLaunch;
  final ValueChanged<LocalFlutterApplication> onLaunchLocal;

  @override
  ConsumerState<_TileGroupSection> createState() => _TileGroupSectionState();
}

class _TileGroupSectionState extends ConsumerState<_TileGroupSection> {
  final GlobalKey _gridKey = GlobalKey();
  int? _draggingIndex;

  void _launch(HomeGridItem item) {
    if (item.app case final app?) {
      widget.onLaunch(app);
      return;
    }
    if (item.localApp case final localApp?) {
      widget.onLaunchLocal(localApp);
    }
  }

  String _labelFor(HomeGridItem item) {
    if (item.app case final app?) {
      return app.name;
    }
    if (item.localApp case final localApp?) {
      return localApp.titleFor(context);
    }
    return '';
  }

  void _showMenu(int index, HomeGridItem item, Offset position) {
    final l10n = context.l10n;
    final controller = ref.read(desktopTileControllerProvider.notifier);
    final currentSize = DesktopTileSize.of(item);

    showDesktopTileMenu(
      ref: ref,
      keySuffix: 'tile-${item.id}',
      position: position,
      entries: <DesktopTileMenuEntry>[
        DesktopTileMenuEntry.item(
          label: l10n.desktopTileUnpinFromStart,
          icon: Icons.remove_circle_outline,
          onPressed: () => controller.unpin(item.id),
        ),
        const DesktopTileMenuEntry.divider(),
        DesktopTileMenuEntry.heading(l10n.desktopTileResize),
        for (final size in DesktopTileSize.values)
          DesktopTileMenuEntry.item(
            label: _sizeLabel(l10n, size),
            icon: null,
            tileSize: size,
            selected: size == currentSize,
            onPressed: () =>
                controller.resizeSlot(widget.groupIndex, index, size),
          ),
      ],
    );
  }

  void _handleDrop(
    DragTargetDetails<_TileDrag> details,
    DesktopTileGeometry geometry,
    int rows,
  ) {
    final box = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) {
      return;
    }
    // details.offset is the dragged tile's own top-left, so the drop is decided
    // by where the tile centre came to rest rather than where the cursor was
    // inside it — grabbing a wide tile by its right edge should not drop it a
    // column over.
    final size = geometry.rectFor(details.data.index, details.data.item).size;
    final local = box.globalToLocal(
      details.offset + Offset(size.width / 2, size.height / 2),
    );
    final target = geometry.indexAt(local, rows: rows);
    if (target == null) {
      return;
    }
    ref
        .read(desktopTileControllerProvider.notifier)
        .moveSlot(widget.groupIndex, details.data.index, target);
  }

  @override
  Widget build(BuildContext context) {
    final slots = widget.group.slots;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TileGroupHeading(
            name: widget.group.name,
            accent: widget.accent,
            onRename: (name) => ref
                .read(desktopTileControllerProvider.notifier)
                .renameGroup(widget.groupIndex, name),
          ),
          const SizedBox(height: 6),
          LayoutBuilder(
            builder: (context, constraints) {
              final geometry = DesktopTileGeometry.fit(
                constraints.maxWidth,
                columns: DesktopTileController.columns,
              );
              final rows = geometry.rowsFor(slots);
              return SizedBox(
                height: geometry.heightFor(slots),
                child: DragTarget<_TileDrag>(
                  onWillAcceptWithDetails: (details) =>
                      details.data.groupIndex == widget.groupIndex,
                  onAcceptWithDetails: (details) =>
                      _handleDrop(details, geometry, rows),
                  builder: (context, _, _) => Stack(
                    key: _gridKey,
                    children: <Widget>[
                      for (final anchor in _anchors(slots))
                        Positioned.fromRect(
                          key: ValueKey<String>('tile:${slots[anchor]!.id}'),
                          rect: geometry.rectFor(anchor, slots[anchor]!),
                          child: _draggableTile(
                            anchor,
                            slots[anchor]!,
                            geometry,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  List<int> _anchors(List<HomeGridItem?> slots) {
    return <int>[
      for (var index = 0; index < slots.length; index += 1)
        if (slots[index] != null) index,
    ];
  }

  Widget _draggableTile(
    int index,
    HomeGridItem item,
    DesktopTileGeometry geometry,
  ) {
    final rect = geometry.rectFor(index, item);
    final cell = DesktopTileCell(
      item: item,
      label: _labelFor(item),
      accent: widget.accent,
      onLaunch: () => _launch(item),
      onShowMenu: (position) => _showMenu(index, item, position),
    );

    return RepaintBoundary(
      child: Draggable<_TileDrag>(
        data: _TileDrag(
          groupIndex: widget.groupIndex,
          index: index,
          item: item,
        ),
        // A mouse drag begins the moment the pointer moves, unlike the mobile
        // home screen's long press: there is no tap-versus-drag ambiguity to
        // disambiguate when the gesture starts with a button already down.
        onDragStarted: () => setState(() => _draggingIndex = index),
        onDragEnd: (_) => setState(() => _draggingIndex = null),
        onDraggableCanceled: (_, _) => setState(() => _draggingIndex = null),
        feedback: SizedBox.fromSize(
          size: rect.size,
          child: Opacity(opacity: 0.85, child: cell),
        ),
        childWhenDragging: DecoratedBox(
          decoration: BoxDecoration(
            color: ShellColors.hairlineSoft,
            borderRadius: BorderRadius.circular(
              ShellTheme.of(context).windowRadius,
            ),
          ),
        ),
        // The tile being dragged must not also be a tab stop.
        child: ExcludeFocus(excluding: _draggingIndex == index, child: cell),
      ),
    );
  }
}

String _sizeLabel(AppLocalizations l10n, DesktopTileSize size) {
  return switch (size) {
    DesktopTileSize.small => l10n.desktopTileSizeSmall,
    DesktopTileSize.medium => l10n.desktopTileSizeMedium,
    DesktopTileSize.wide => l10n.desktopTileSizeWide,
    DesktopTileSize.large => l10n.desktopTileSizeLarge,
  };
}

/// A group heading that becomes an input on double click.
class _TileGroupHeading extends StatefulWidget {
  const _TileGroupHeading({
    required this.name,
    required this.accent,
    required this.onRename,
  });

  final String name;
  final WallpaperAccent accent;
  final ValueChanged<String> onRename;

  @override
  State<_TileGroupHeading> createState() => _TileGroupHeadingState();
}

class _TileGroupHeadingState extends State<_TileGroupHeading> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.name);
    _focusNode = FocusNode(debugLabel: 'desktop-tile-group-name');
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _beginEditing() {
    _controller.text = widget.name;
    setState(() => _editing = true);
    _focusNode.requestFocus();
  }

  void _commit() {
    if (!_editing) {
      return;
    }
    setState(() => _editing = false);
    widget.onRename(_controller.text.trim());
  }

  /// Escape abandons the edit. Clearing the flag first is what keeps the focus
  /// loss that follows from committing the discarded text.
  void _cancel() {
    if (!_editing) {
      return;
    }
    setState(() => _editing = false);
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final style = ShellText.cardTitle.copyWith(
      fontWeight: FontWeight.w700,
      color: widget.accent.captionColor,
    );
    final l10n = context.l10n;

    if (!_editing) {
      final named = widget.name.trim().isNotEmpty;
      return Semantics(
        button: true,
        label: l10n.desktopTileGroupRename,
        value: named ? widget.name : '',
        child: MouseRegion(
          cursor: ShellMouseCursors.text,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onDoubleTap: _beginEditing,
            child: SizedBox(
              height: 24,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  named ? widget.name : l10n.desktopTileGroupUnnamed,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: named
                      ? style
                      : style.copyWith(color: ShellColors.textTertiary),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Semantics(
      textField: true,
      label: l10n.desktopTileGroupRename,
      child: Focus(
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            _cancel();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: SizedBox(
          height: 24,
          child: EditableText(
            controller: _controller,
            focusNode: _focusNode,
            mouseCursor: ShellMouseCursors.text,
            autofocus: true,
            maxLines: 1,
            style: style,
            cursorColor: widget.accent.color,
            backgroundCursorColor: ShellColors.textSecondary,
            selectionColor: ShellTheme.of(context).accentPalette.selection,
            onEditingComplete: _commit,
            onSubmitted: (_) => _commit(),
            onTapOutside: (_) => _commit(),
          ),
        ),
      ),
    );
  }
}
