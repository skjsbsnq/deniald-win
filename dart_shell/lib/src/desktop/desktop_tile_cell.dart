import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../launcher/models/home_grid_item.dart';
import '../localization/denial_localizations.dart';
import '../theme/motion.dart';
import '../theme/shell_theme.dart';
import '../theme/tokens.dart';
import '../wallpaper/state/wallpaper_accent.dart';
import '../widgets/app_icon.dart';
import '../widgets/shell_cursor.dart';

/// One tile on the start menu's pin board.
///
/// Every dimension comes from the incoming constraints, because the same widget
/// has to render a 1×1 cell and a 4×4 one. The mobile home screen's application
/// tile hardcodes its icon and label sizes, which is why it could not be reused
/// here: at one cell its 92px icon overflows the tile it sits in.
///
/// Deliberately no [ShellBackdropBlur]: the start menu panel already blurs
/// everything behind it once, and a per-tile filter would sample the whole
/// screen once per tile per frame.
class DesktopTileCell extends StatefulWidget {
  const DesktopTileCell({
    super.key,
    required this.item,
    required this.label,
    required this.accent,
    required this.onLaunch,
    required this.onShowMenu,
  });

  final HomeGridItem item;

  /// Resolved by the caller: a shell-hosted application's name depends on the
  /// active locale, which a tile has no business knowing about.
  final String label;
  final WallpaperAccent accent;
  final VoidCallback onLaunch;
  final ValueChanged<Offset> onShowMenu;

  @override
  State<DesktopTileCell> createState() => _DesktopTileCellState();
}

class _DesktopTileCellState extends State<DesktopTileCell> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = ShellTheme.of(context);
    final accent = widget.accent;
    final item = widget.item;
    final highlighted = _hovered || _focused;

    return Semantics(
      button: true,
      label: context.l10n.desktopTilePinnedSemantics(widget.label),
      child: Focus(
        onFocusChange: (focused) => setState(() => _focused = focused),
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.enter ||
                  event.logicalKey == LogicalKeyboardKey.space)) {
            widget.onLaunch();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: MouseRegion(
          cursor: ShellMouseCursors.link,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onLaunch,
            onSecondaryTapUp: (details) =>
                widget.onShowMenu(details.globalPosition),
            child: AnimatedContainer(
              duration: Motion.tile,
              curve: Motion.standard,
              decoration: BoxDecoration(
                color: theme.panelColor(
                  highlighted ? accent.cardFillTop : accent.cardFill,
                ),
                borderRadius: BorderRadius.circular(theme.windowRadius),
              ),
              foregroundDecoration: _focused
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(theme.windowRadius),
                      border: Border.all(color: accent.color),
                    )
                  : null,
              child: ExcludeSemantics(
                child: _DesktopTileContent(
                  item: item,
                  label: widget.label,
                  accent: accent,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopTileContent extends StatelessWidget {
  const _DesktopTileContent({
    required this.item,
    required this.label,
    required this.accent,
  });

  final HomeGridItem item;
  final String label;
  final WallpaperAccent accent;

  @override
  Widget build(BuildContext context) {
    // A single cell has no room for text, which is also what Windows 10 does
    // with its small tile.
    final showLabel = item.rowSpan >= 2;
    // Wide is the only size whose cell is broader than it is tall, so it is the
    // only one that reads better with the icon beside the label than above it.
    final besideLabel = showLabel && item.colSpan > item.rowSpan;

    return LayoutBuilder(
      builder: (context, constraints) {
        final shortest = math.min(constraints.maxWidth, constraints.maxHeight);
        final padding = (shortest * 0.12).clamp(4.0, 14.0).toDouble();
        final iconExtent = (shortest * (showLabel ? 0.42 : 0.54))
            .clamp(14.0, 96.0)
            .toDouble();
        final icon = SizedBox.square(
          dimension: iconExtent,
          child: _DesktopTileIcon(item: item, accent: accent),
        );
        final text = Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: ShellText.cardTitle.copyWith(color: accent.captionColor),
        );

        return Padding(
          padding: EdgeInsets.all(padding),
          child: switch ((showLabel, besideLabel)) {
            (false, _) => Center(child: icon),
            (true, true) => Row(
              children: [
                icon,
                SizedBox(width: padding),
                Expanded(child: text),
              ],
            ),
            (true, false) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Center(child: icon)),
                SizedBox(height: padding / 2),
                text,
              ],
            ),
          },
        );
      },
    );
  }
}

/// The tile's artwork: a real application icon, or the glyph a shell-hosted
/// application declares.
class _DesktopTileIcon extends StatelessWidget {
  const _DesktopTileIcon({required this.item, required this.accent});

  final HomeGridItem item;
  final WallpaperAccent accent;

  @override
  Widget build(BuildContext context) {
    if (item.localApp case final localApp? when localApp.icon != null) {
      return LayoutBuilder(
        builder: (context, constraints) => Icon(
          localApp.icon,
          size: constraints.biggest.shortestSide,
          color: accent.color,
        ),
      );
    }
    // An application that has since been uninstalled leaves its recorded icon
    // path pointing at nothing; AppIconImage already answers that with the
    // bundled default rather than an error box.
    return DeferredAppIcon(iconPath: item.app?.iconPath);
  }
}
