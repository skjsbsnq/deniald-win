import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../localization/denial_localizations.dart';
import '../../settings/shell_settings.dart';
import '../../theme/shell_theme.dart';
import '../../theme/tokens.dart';
import '../../wallpaper/wallpaper.dart';
import '../../wallpaper/widgets/wallpaper_image.dart';
import 'settings_buttons.dart';

const settingsWallpaperTriggerKey = ValueKey<String>(
  'settings-wallpaper-trigger',
);

/// Hero desktop preview card conforming to MD3E specification §3.1 (Decision 1-A).
///
/// Features:
/// - 16:9 widescreen silhouette and fixed ~160dp height.
/// - 20dp corner radius ([ShellShapeScale.largeIncreased]) linked with `cornerRadiusScale`.
/// - Wallpaper rendering via [wallpaperImageProvider].
/// - Miniature desktop window silhouette reflecting dark/light scheme and accent color.
/// - Integrated bottom action bar with [settingsWallpaperTriggerKey] S-size capsule button.
class SettingsHeroPreviewCard extends StatelessWidget {
  const SettingsHeroPreviewCard({
    required this.wallpaper,
    required this.onOpenWallpaperSelector,
    this.colorSchemePreference = DesktopColorSchemePreference.preferDark,
    this.isDark,
    required this.accentColor,
    this.height = 160.0,
    super.key,
  });

  final WallpaperResource wallpaper;
  final VoidCallback onOpenWallpaperSelector;
  final DesktopColorSchemePreference colorSchemePreference;
  final bool? isDark;
  final Color accentColor;
  final double height;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = ShellTheme.of(context);
    final colors = context.shellColors;
    final cardRadius = theme.borderRadius(ShellShapeScale.largeIncreased);

    final effectiveIsDark = isDark ??
        (colorSchemePreference == DesktopColorSchemePreference.preferDark ||
            (colorSchemePreference == DesktopColorSchemePreference.noPreference &&
                Theme.of(context).brightness == Brightness.dark));

    return SizedBox(
      height: height,
      child: Container(
        decoration: BoxDecoration(
          color: theme.cardColor(colors.surfaceContainerLow),
          borderRadius: cardRadius,
          border: Border.all(color: colors.hairlineSoft),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // 1. Wallpaper background
            Positioned.fill(
              child: Image(
                image: wallpaperImageProvider(
                  wallpaper,
                  targetPixelSize: Size(480, height) *
                      MediaQuery.devicePixelRatioOf(context),
                ),
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
                excludeFromSemantics: true,
                errorBuilder: (_, _, _) => ColoredBox(
                  color: colors.surfaceContainerHighest,
                  child: Icon(
                    Icons.wallpaper_rounded,
                    size: 32,
                    color: accentColor,
                  ),
                ),
              ),
            ),

            // 2. Translucent tint overlay for readability & contrast
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: effectiveIsDark
                      ? ShellMediaColors.darkness.withValues(alpha: 0.22)
                      : ShellMediaColors.contrastLight.withValues(alpha: 0.12),
                ),
              ),
            ),

            // 3. Desktop Silhouette (Miniature Window & Dock) in the upper preview area
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              bottom: 48,
              child: Center(
                child: _DesktopSilhouette(
                  isDark: effectiveIsDark,
                  accentColor: accentColor,
                ),
              ),
            ),

            // 4. Bottom Action Bar with wallpaper trigger button
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 48,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.cardColor(
                    Color.alphaBlend(
                      colors.surfaceContainerHighest.withValues(alpha: 0.7),
                      colors.surfaceContainerLow.withValues(alpha: 0.85),
                    ),
                  ),
                  border: Border(
                    top: BorderSide(color: colors.hairlineSoft),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.wallpaper_rounded,
                      size: 20,
                      color: colors.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.settingsWallpaperTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ShellText.settingsRowTitle.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    SettingsButton(
                      key: settingsWallpaperTriggerKey,
                      label: l10n.settingsWallpaperChoose,
                      variant: SettingsButtonVariant.filledTonal,
                      size: SettingsButtonSize.small,
                      onPressed: onOpenWallpaperSelector,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopSilhouette extends StatelessWidget {
  const _DesktopSilhouette({
    required this.isDark,
    required this.accentColor,
  });

  final bool isDark;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = ShellTheme.of(context);
    final colors = context.shellColors;
    final windowRadius = theme.borderRadius(ShellShapeScale.small);
    final surfaceColor = isDark
        ? colors.surfaceContainerHighest.withValues(alpha: 0.85)
        : colors.surfaceContainerLow.withValues(alpha: 0.85);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Miniature window
        Container(
          width: 130,
          height: 64,
          decoration: BoxDecoration(
            color: theme.cardColor(surfaceColor),
            borderRadius: windowRadius,
            border: Border.all(
              color: accentColor.withValues(alpha: 0.8),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: colors.shadow.withValues(alpha: 0.25),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              // Miniature titlebar
              Container(
                height: 14,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                color: colors.surfaceContainerHigh.withValues(alpha: 0.6),
                child: Row(
                  children: [
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: accentColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      width: 24,
                      height: 3,
                      decoration: BoxDecoration(
                        color: colors.textSecondary.withValues(alpha: 0.4),
                        borderRadius: theme.borderRadius(ShellShapeScale.full),
                      ),
                    ),
                    const Spacer(),
                    for (int i = 0; i < 3; i++) ...[
                      if (i > 0) const SizedBox(width: 3),
                      Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          color: colors.textSecondary.withValues(alpha: 0.35),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Miniature window body
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(5),
                  child: Row(
                    children: [
                      // Miniature sidebar
                      Container(
                        width: 20,
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerHigh.withValues(alpha: 0.4),
                          borderRadius:
                              theme.borderRadius(ShellShapeScale.extraSmall),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            Container(
                              width: 8,
                              height: 3,
                              decoration: BoxDecoration(
                                color: accentColor,
                                borderRadius:
                                    theme.borderRadius(ShellShapeScale.full),
                              ),
                            ),
                            Container(
                              width: 8,
                              height: 3,
                              decoration: BoxDecoration(
                                color: colors.textSecondary.withValues(alpha: 0.3),
                                borderRadius:
                                    theme.borderRadius(ShellShapeScale.full),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Miniature content lines
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            Container(
                              width: 42,
                              height: 4,
                              decoration: BoxDecoration(
                                color: accentColor.withValues(alpha: 0.7),
                                borderRadius:
                                    theme.borderRadius(ShellShapeScale.full),
                              ),
                            ),
                            Container(
                              width: 54,
                              height: 3,
                              decoration: BoxDecoration(
                                color: colors.textSecondary.withValues(alpha: 0.3),
                                borderRadius:
                                    theme.borderRadius(ShellShapeScale.full),
                              ),
                            ),
                            Container(
                              width: 32,
                              height: 3,
                              decoration: BoxDecoration(
                                color: colors.textSecondary.withValues(alpha: 0.2),
                                borderRadius:
                                    theme.borderRadius(ShellShapeScale.full),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 5),
        // Miniature shelf dock
        Container(
          width: 56,
          height: 6,
          decoration: BoxDecoration(
            color: theme.cardColor(
              (isDark ? colors.surfaceContainerHighest : colors.surfaceContainerHigh)
                  .withValues(alpha: 0.7),
            ),
            borderRadius: theme.borderRadius(ShellShapeScale.full),
            border: Border.all(
              color: colors.hairlineSoft,
              width: 0.5,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (int i = 0; i < 4; i++)
                Container(
                  width: 3,
                  height: 3,
                  decoration: BoxDecoration(
                    color: i == 1
                        ? accentColor
                        : colors.textSecondary.withValues(alpha: 0.6),
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
