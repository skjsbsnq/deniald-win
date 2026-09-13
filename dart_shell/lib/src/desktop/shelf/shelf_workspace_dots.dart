import 'package:flutter/widgets.dart';

import '../../localization/denial_localizations.dart';
import '../../theme/shell_color_scheme.dart';
import '../../theme/shell_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/shell_expressive_surface.dart';
import '../desktop_workspace.dart';

/// Number of visible windows assigned to each workspace on one monitor.
///
/// Pure derivation from [DesktopWorkspaceState.placements]: a window counts
/// toward workspace `n` when it sits on [monitorId], carries
/// `workspaceId == n`, and is not minimized (minimized windows are
/// workspace-less in the compositor's model). Returns a list of
/// [workspaceCount] entries indexed by `workspaceId - 1`.
List<int> workspaceWindowCounts(
  Iterable<DesktopWindowPlacement> placements,
  int monitorId,
  int workspaceCount,
) {
  final counts = List<int>.filled(workspaceCount, 0);
  for (final placement in placements) {
    if (placement.monitorId != monitorId || placement.minimized) {
      continue;
    }
    final index = placement.workspaceId - 1;
    if (index >= 0 && index < workspaceCount) {
      counts[index] += 1;
    }
  }
  return counts;
}

/// Clavis-style workspace indicator: one dot per workspace, the active dot
/// stretched along the shelf axis into a capsule.
///
/// Visual parameters follow `CLAVIS/Modules/Bar/Workspaces/Workspaces.qml`:
/// a 12px resting dot elongating to a 32px pill for the active/hovered entry
/// (300ms OutCubic geometry, 200ms color), 8px spacing, accent fill for the
/// active workspace, on-surface fill for occupied ones, and a raised surface
/// fill for empty ones. Every dot is an individual tap target that jumps
/// straight to its workspace.
class ShelfWorkspaceDots extends StatelessWidget {
  const ShelfWorkspaceDots({
    required this.workspaceCount,
    required this.activeWorkspace,
    required this.windowCounts,
    required this.onSelect,
    super.key,
  });

  /// Resting dot diameter; clavis' 12px indicator on the [ShellSpacing.md]
  /// token.
  static const double dotSize = ShellSpacing.md;

  /// Width of the active/hovered dot; clavis' 32px pill on the
  /// [ShellSpacing.xxl] token (≈2.7× the resting dot).
  static const double activeDotWidth = ShellSpacing.xxl;

  /// Geometry animation shared by every dot (clavis 300ms OutCubic).
  static const Duration expandDuration = Duration(milliseconds: 300);

  /// Color animation shared by every dot (clavis 200ms).
  static const Duration colorDuration = Duration(milliseconds: 200);

  /// Number of workspaces shown; comes from
  /// [DesktopWorkspaceState.workspaceCount].
  final int workspaceCount;

  /// Currently active workspace id (1-based) for this monitor.
  final int activeWorkspace;

  /// Per-workspace visible window counts, indexed by `workspaceId - 1`,
  /// as produced by [workspaceWindowCounts].
  final List<int> windowCounts;

  /// Called with the tapped workspace id (1-based).
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final count = workspaceCount < 1 ? 1 : workspaceCount;
    final active = activeWorkspace.clamp(1, count);
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: ShellSpacing.sm,
      children: [
        for (var workspaceId = 1; workspaceId <= count; workspaceId++)
          _WorkspaceDot(
            key: ValueKey<String>('shelf-workspace-dot-$workspaceId'),
            isActive: workspaceId == active,
            windowCount: workspaceId - 1 < windowCounts.length
                ? windowCounts[workspaceId - 1]
                : 0,
            tooltip:
                '${l10n.wsWorkspaceLabel(workspaceId)} · '
                '${l10n.wsWorkspaceWindows(workspaceId - 1 < windowCounts.length ? windowCounts[workspaceId - 1] : 0)}',
            semanticLabel: l10n.wsWorkspaceLabel(workspaceId),
            onPressed: () => onSelect(workspaceId),
          ),
      ],
    );
  }
}

/// One interactive workspace dot: a [ShellExpressiveSurface] hit target whose
/// visible pill animates its width and fill from interaction state.
class _WorkspaceDot extends StatelessWidget {
  const _WorkspaceDot({
    required this.isActive,
    required this.windowCount,
    required this.tooltip,
    required this.semanticLabel,
    required this.onPressed,
    super.key,
  });

  final bool isActive;
  final int windowCount;
  final String tooltip;
  final String semanticLabel;
  final VoidCallback onPressed;

  Color _dotColor(
    ShellThemeData theme,
    ShellColorScheme colors, {
    required bool hovered,
  }) {
    if (isActive) {
      return theme.accentPalette.primary;
    }
    // clavis paints `hasWindows ? onSurface : (hovered ? hover : empty)`:
    // an occupied dot keeps its on-surface fill while hovered; only an
    // empty dot swaps to the hover variant.
    if (windowCount > 0) {
      return colors.textPrimary;
    }
    final base = colors.surfaceContainerHighest;
    return hovered ? Color.alphaBlend(colors.panelHighlight, base) : base;
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = context.shellColors;
    final animationsDisabled = MediaQuery.disableAnimationsOf(context);
    // MergeSemantics folds the `selected` flag, the surface's own button
    // semantics, and its label into one node so assistive tech announces a
    // single "selected Workspace N" control.
    return MergeSemantics(
      child: Semantics(
        selected: isActive,
        child: ShellExpressiveSurface.builder(
          onPressed: onPressed,
          shape: ShellShapeScale.full,
          padding: const EdgeInsets.symmetric(
            horizontal: ShellSpacing.xs,
            vertical: ShellSpacing.sm,
          ),
          tooltip: tooltip,
          semanticLabel: semanticLabel,
          childBuilder: (context, interaction) {
            final expanded = isActive || interaction.hovered;
            return AnimatedContainer(
              duration: animationsDisabled
                  ? Duration.zero
                  : ShelfWorkspaceDots.expandDuration,
              curve: Curves.easeOutCubic,
              width: expanded
                  ? ShelfWorkspaceDots.activeDotWidth
                  : ShelfWorkspaceDots.dotSize,
              height: ShelfWorkspaceDots.dotSize,
              child: AnimatedContainer(
                duration: animationsDisabled
                    ? Duration.zero
                    : ShelfWorkspaceDots.colorDuration,
                decoration: BoxDecoration(
                  color: _dotColor(theme, colors, hovered: interaction.hovered),
                  borderRadius: theme.borderRadius(ShellShapeScale.full),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
