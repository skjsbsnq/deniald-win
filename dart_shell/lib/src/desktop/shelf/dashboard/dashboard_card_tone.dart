import 'package:flutter/widgets.dart';

import '../../../theme/shell_color_scheme.dart';
import '../../../theme/shell_theme.dart';

/// Tonal color family for a dashboard metric card (02-VISUAL-SPEC §3.3):
/// the mixed-emphasis grid pairs quiet surface cards with secondary- and
/// tertiary-family fills so sibling cards read as different widget kinds.
enum DashboardCardTone { surface, primary, secondary, tertiary }

/// Resolved foreground/background roles for a [DashboardCardTone].
///
/// `container` is the raw tonal fill — card surfaces still pass it through
/// `ShellThemeData.panelColor`/`cardColor` so the user's panel and card
/// opacity settings keep applying. `foregroundSecondary` is derived from the
/// on-container role instead of a hand-picked mid-tone so light and dark
/// brightness stay symmetric.
({
  Color container,
  Color foreground,
  Color foregroundSecondary,
  Color accent,
  Color onAccent,
})
dashboardCardToneColors(
  ShellThemeData theme,
  ShellColorScheme colors,
  DashboardCardTone tone,
) {
  final palette = theme.accentPalette;
  return switch (tone) {
    DashboardCardTone.surface => (
      container: colors.surfaceContainer,
      foreground: colors.textPrimary,
      foregroundSecondary: colors.textSecondary,
      accent: palette.primary,
      onAccent: palette.onPrimary,
    ),
    DashboardCardTone.primary => (
      container: palette.container,
      foreground: palette.onContainer,
      foregroundSecondary: palette.onContainerSecondary,
      accent: palette.primary,
      onAccent: palette.onPrimary,
    ),
    DashboardCardTone.secondary => (
      container: palette.secondaryContainer,
      foreground: palette.onSecondaryContainer,
      foregroundSecondary: palette.onSecondaryContainer.withValues(alpha: 0.72),
      accent: palette.secondary,
      onAccent: palette.onSecondary,
    ),
    DashboardCardTone.tertiary => (
      container: palette.tertiaryContainer,
      foreground: palette.onTertiaryContainer,
      foregroundSecondary: palette.onTertiaryContainer.withValues(alpha: 0.72),
      accent: palette.tertiary,
      onAccent: palette.onTertiary,
    ),
  };
}
