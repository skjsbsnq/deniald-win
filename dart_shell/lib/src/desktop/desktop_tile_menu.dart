import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/motion.dart';
import '../theme/shell_theme.dart';
import '../theme/tokens.dart';
import '../widgets/shell_surface_host.dart';
import 'models/desktop_tile.dart';

/// One row of a tile context menu.
///
/// The window menu next door hardcodes its three rows as widget literals, so
/// adding a fourth means editing its layout. This menu carries its rows as
/// data because it has two very different call sites — an application row and
/// a tile — and a third would otherwise mean a third copy of the card.
@immutable
class DesktopTileMenuEntry {
  const DesktopTileMenuEntry.item({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.tileSize,
    this.selected = false,
  }) : _kind = _DesktopTileMenuEntryKind.item;

  const DesktopTileMenuEntry.heading(this.label)
    : _kind = _DesktopTileMenuEntryKind.heading,
      icon = null,
      onPressed = null,
      tileSize = null,
      selected = false;

  const DesktopTileMenuEntry.divider()
    : _kind = _DesktopTileMenuEntryKind.divider,
      label = '',
      icon = null,
      onPressed = null,
      tileSize = null,
      selected = false;

  final _DesktopTileMenuEntryKind _kind;
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  /// Set on the four size rows, which draw their own footprint instead of a
  /// Material glyph so the proportions themselves say what the row does.
  final DesktopTileSize? tileSize;
  final bool selected;

  double get _extent {
    return switch (_kind) {
      _DesktopTileMenuEntryKind.item => DesktopTileMenu.itemExtent,
      _DesktopTileMenuEntryKind.heading => DesktopTileMenu.headingExtent,
      _DesktopTileMenuEntryKind.divider => DesktopTileMenu.dividerExtent,
    };
  }
}

enum _DesktopTileMenuEntryKind { item, divider, heading }

/// Prefix shared by every menu this file opens.
///
/// The start menu closes itself when the pointer leaves it, and a menu surface
/// covers the whole scene — which reads as the pointer leaving. The panel
/// recognises its own menus by this prefix so it can hold still while one is up.
const String desktopTileMenuKeyPrefix = 'desktop-tile-menu-';

/// Shows [entries] as a context menu anchored near [position].
///
/// [keySuffix] distinguishes one target from another; the prefix is added here
/// so a caller cannot leave it off and have the start menu close underneath its
/// own menu. Reusing a suffix returns the surface already on screen rather than
/// stacking a second one, so a second right-click on the same target is a no-op.
ShellSurfaceHandle showDesktopTileMenu({
  required WidgetRef ref,
  required String keySuffix,
  required Offset position,
  required List<DesktopTileMenuEntry> entries,
}) {
  final keyName = '$desktopTileMenuKeyPrefix$keySuffix';
  return ref
      .read(shellSurfaceControllerProvider.notifier)
      .show(
        keyName: keyName,
        debugLabel: 'Desktop tile menu $keySuffix',
        barrierColor: const Color(0x00000000),
        dismissPolicy: ShellDismissPolicy.outsideTapAndEscape,
        transitionDuration: Motion.cardSettle,
        builder: (context, handle) => DesktopTileMenu(
          handle: handle,
          position: position,
          entries: entries,
        ),
      );
}

/// Whether a menu opened by [showDesktopTileMenu] is currently on screen.
bool desktopTileMenuIsOpen(List<ManagedShellSurface> surfaces) {
  return surfaces.any(
    (surface) =>
        !surface.closing &&
        (surface.keyName?.startsWith(desktopTileMenuKeyPrefix) ?? false),
  );
}

class DesktopTileMenu extends StatelessWidget {
  const DesktopTileMenu({
    super.key,
    required this.handle,
    required this.position,
    required this.entries,
  });

  /// Wide enough for the longest entry in either language; Chinese
  /// "从“开始”屏幕取消固定" is the one that sets the floor.
  static const double menuWidth = 200.0;
  static const double itemExtent = 32.0;
  static const double headingExtent = 26.0;
  static const double dividerExtent = 7.0;
  static const double verticalPadding = 8.0;
  static const double margin = 8.0;

  final ShellSurfaceHandle handle;
  final Offset position;
  final List<DesktopTileMenuEntry> entries;

  /// Height derived from the rows themselves.
  ///
  /// The window menu's equivalent is a constant filled in by hand for exactly
  /// three rows, which silently mispositions any menu with a different count.
  static double heightFor(List<DesktopTileMenuEntry> entries) {
    var height = verticalPadding;
    for (final entry in entries) {
      height += entry._extent;
    }
    return height;
  }

  @override
  Widget build(BuildContext context) {
    final height = heightFor(entries);
    return LayoutBuilder(
      builder: (context, constraints) {
        final screen = Size(constraints.maxWidth, constraints.maxHeight);

        var left = position.dx;
        if (left + menuWidth + margin > screen.width) {
          left = position.dx - menuWidth;
        }
        left = left.clamp(
          margin,
          math.max(margin, screen.width - menuWidth - margin),
        );

        var top = position.dy;
        if (top + height + margin > screen.height) {
          top = position.dy - height;
        }
        top = top.clamp(
          margin,
          math.max(margin, screen.height - height - margin),
        );

        return Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              width: menuWidth,
              child: _DesktopTileMenuCard(handle: handle, entries: entries),
            ),
          ],
        );
      },
    );
  }
}

class _DesktopTileMenuCard extends StatelessWidget {
  const _DesktopTileMenuCard({required this.handle, required this.entries});

  final ShellSurfaceHandle handle;
  final List<DesktopTileMenuEntry> entries;

  @override
  Widget build(BuildContext context) {
    final theme = ShellTheme.of(context);
    var firstItem = true;

    final rows = <Widget>[];
    for (final entry in entries) {
      switch (entry._kind) {
        case _DesktopTileMenuEntryKind.divider:
          rows.add(const _DesktopTileMenuDivider());
        case _DesktopTileMenuEntryKind.heading:
          rows.add(_DesktopTileMenuHeading(label: entry.label));
        case _DesktopTileMenuEntryKind.item:
          rows.add(
            _DesktopTileMenuItem(
              entry: entry,
              autofocus: firstItem,
              onPressed: () {
                handle.close();
                entry.onPressed!();
              },
            ),
          );
          firstItem = false;
      }
    }

    return FocusTraversalGroup(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.panelColor(ShellColors.surfaceContainerHigh),
          borderRadius: BorderRadius.circular(theme.panelRadius),
          border: Border.all(color: ShellColors.hairline),
          boxShadow: const [
            BoxShadow(
              color: ShellColors.shadow,
              blurRadius: 16.0,
              spreadRadius: 1.0,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 4.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: rows,
          ),
        ),
      ),
    );
  }
}

class _DesktopTileMenuHeading extends StatelessWidget {
  const _DesktopTileMenuHeading({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: DesktopTileMenu.headingExtent,
      child: Padding(
        padding: const EdgeInsets.only(left: 10.0, top: 8.0),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: ShellColors.textTertiary,
            fontFamily: ShellText.uiFontFamily,
            fontFamilyFallback: ShellText.fallbackFontFamilies,
            fontSize: 11.0,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }
}

class _DesktopTileMenuItem extends StatefulWidget {
  const _DesktopTileMenuItem({
    required this.entry,
    required this.autofocus,
    required this.onPressed,
  });

  final DesktopTileMenuEntry entry;
  final bool autofocus;
  final VoidCallback onPressed;

  @override
  State<_DesktopTileMenuItem> createState() => _DesktopTileMenuItemState();
}

class _DesktopTileMenuItemState extends State<_DesktopTileMenuItem> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = ShellTheme.of(context);
    final entry = widget.entry;
    final highlighted = _hovered || _focused || entry.selected;
    final tileSize = entry.tileSize;

    return Semantics(
      button: true,
      selected: entry.selected,
      label: entry.label,
      child: Focus(
        autofocus: widget.autofocus,
        onFocusChange: (focused) => setState(() => _focused = focused),
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.enter ||
                  event.logicalKey == LogicalKeyboardKey.space)) {
            widget.onPressed();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onPressed,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: highlighted
                    ? ShellColors.panelHighlight
                    : const Color(0x00000000),
                borderRadius: BorderRadius.circular(
                  math.max(0.0, theme.panelRadius - 4.0),
                ),
              ),
              child: SizedBox(
                height: DesktopTileMenu.itemExtent,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10.0),
                  // The row repeats its own label as text, so leaving both in
                  // the tree would have a screen reader read it twice.
                  child: ExcludeSemantics(
                    child: Row(
                      children: [
                        SizedBox.square(
                          dimension: 14.0,
                          child: tileSize != null
                              ? CustomPaint(
                                  painter: DesktopTileSizeGlyphPainter(
                                    size: tileSize,
                                    color: ShellColors.textPrimary,
                                  ),
                                )
                              : Icon(
                                  entry.icon,
                                  size: 14.0,
                                  color: ShellColors.textPrimary,
                                ),
                        ),
                        const SizedBox(width: 10.0),
                        Expanded(
                          child: Text(
                            entry.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: ShellColors.textPrimary,
                              fontFamily: ShellText.uiFontFamily,
                              fontFamilyFallback:
                                  ShellText.fallbackFontFamilies,
                              fontSize: 12.0,
                              fontWeight: FontWeight.w500,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Draws a tile size as its own footprint, scaled into the glyph box.
///
/// A Material icon would have to stand for "wide" or "large" by convention;
/// the outline of the tile itself needs no convention.
class DesktopTileSizeGlyphPainter extends CustomPainter {
  const DesktopTileSizeGlyphPainter({required this.size, required this.color});

  final DesktopTileSize size;
  final Color color;

  @override
  void paint(Canvas canvas, Size canvasSize) {
    const cells = 4.0;
    final unit = canvasSize.shortestSide / cells;
    final width = unit * size.colSpan;
    final height = unit * size.rowSpan;
    final rect = Rect.fromCenter(
      center: canvasSize.center(Offset.zero),
      width: width,
      height: height,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(1.5)),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(covariant DesktopTileSizeGlyphPainter oldDelegate) {
    return oldDelegate.size != size || oldDelegate.color != color;
  }
}

class _DesktopTileMenuDivider extends StatelessWidget {
  const _DesktopTileMenuDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 8.0, vertical: 3.0),
      child: SizedBox(
        height: 1.0,
        child: ColoredBox(color: ShellColors.hairlineSoft),
      ),
    );
  }
}
