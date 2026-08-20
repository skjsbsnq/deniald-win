import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../localization/denial_localizations.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';
import '../wallpaper/state/wallpaper_accent.dart';
import '../widgets/shell_cursor.dart';

/// The start menu's left icon rail.
///
/// Expanding reveals labels beside the glyphs and covers the all-apps column
/// rather than resizing it, which is both what Windows 10 does and the only
/// option that cannot push the tile area below its minimum width.
class DesktopStartMenuRail extends StatelessWidget {
  const DesktopStartMenuRail({
    super.key,
    required this.expanded,
    required this.accent,
    required this.onToggleExpanded,
    required this.onOpenDocuments,
    required this.onOpenPictures,
    required this.onOpenSettings,
    required this.onOpenPower,
  });

  static const double collapsedWidth = 48;
  static const double expandedWidth = 200;

  final bool expanded;
  final WallpaperAccent accent;
  final VoidCallback onToggleExpanded;
  final VoidCallback onOpenDocuments;
  final VoidCallback onOpenPictures;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenPower;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AnimatedContainer(
      duration: Motion.tile,
      curve: Motion.standard,
      width: expanded ? expandedWidth : collapsedWidth,
      // Opaque only while expanded: collapsed, the rail is part of the panel
      // and must not read as a separate strip.
      color: expanded
          ? ShellColors.surfaceContainerHigh
          : const Color(0x00000000),
      child: ClipRect(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _RailButton(
              icon: Icons.menu_rounded,
              label: expanded
                  ? l10n.desktopStartMenuCollapseRail
                  : l10n.desktopStartMenuExpandRail,
              expanded: expanded,
              accent: accent,
              onTap: onToggleExpanded,
            ),
            const Spacer(),
            _RailGlyph(
              icon: Icons.person_outline_rounded,
              label: l10n.desktopStartMenuUser,
              expanded: expanded,
            ),
            _RailButton(
              icon: Icons.description_outlined,
              label: l10n.desktopStartMenuDocuments,
              expanded: expanded,
              accent: accent,
              onTap: onOpenDocuments,
            ),
            _RailButton(
              icon: Icons.image_outlined,
              label: l10n.desktopStartMenuPictures,
              expanded: expanded,
              accent: accent,
              onTap: onOpenPictures,
            ),
            _RailButton(
              icon: Icons.settings_outlined,
              label: l10n.settingsApplicationTitle,
              expanded: expanded,
              accent: accent,
              onTap: onOpenSettings,
            ),
            _RailButton(
              icon: Icons.power_settings_new_rounded,
              label: l10n.powerSessionTitle,
              expanded: expanded,
              accent: accent,
              onTap: onOpenPower,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Shared geometry for both rail cells, so glyphs never shift when labels
/// appear.
class _RailCell extends StatelessWidget {
  const _RailCell({
    required this.icon,
    required this.label,
    required this.expanded,
    required this.iconColor,
  });

  final IconData icon;
  final String label;
  final bool expanded;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          SizedBox.square(
            dimension: DesktopStartMenuRail.collapsedWidth,
            child: Icon(icon, size: 20, color: iconColor),
          ),
          if (expanded)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ShellText.cardTitle,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RailButton extends StatefulWidget {
  const _RailButton({
    required this.icon,
    required this.label,
    required this.expanded,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool expanded;
  final WallpaperAccent accent;
  final VoidCallback onTap;

  @override
  State<_RailButton> createState() => _RailButtonState();
}

class _RailButtonState extends State<_RailButton> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final highlighted = _hovered || _focused;
    return Semantics(
      button: true,
      label: widget.label,
      child: Focus(
        onFocusChange: (focused) => setState(() => _focused = focused),
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.enter ||
                  event.logicalKey == LogicalKeyboardKey.space)) {
            widget.onTap();
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
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: Motion.tile,
              curve: Motion.standard,
              color: highlighted
                  ? widget.accent.cardFillTop
                  : const Color(0x00000000),
              // A focus ring drawn in front cannot inset the cell, so the glyph
              // stays put whether or not the entry has focus.
              foregroundDecoration: _focused
                  ? BoxDecoration(
                      border: Border.all(color: widget.accent.color),
                    )
                  : null,
              child: ExcludeSemantics(
                child: _RailCell(
                  icon: widget.icon,
                  label: widget.label,
                  expanded: widget.expanded,
                  iconColor: highlighted
                      ? ShellColors.textPrimary
                      : ShellColors.textSecondary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The account cell.
///
/// Denial exposes no account identity to the shell, so this stays a label-only
/// affordance until there is something for it to open.
class _RailGlyph extends StatelessWidget {
  const _RailGlyph({
    required this.icon,
    required this.label,
    required this.expanded,
  });

  final IconData icon;
  final String label;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      child: ExcludeSemantics(
        child: _RailCell(
          icon: icon,
          label: label,
          expanded: expanded,
          iconColor: ShellColors.textTertiary,
        ),
      ),
    );
  }
}
