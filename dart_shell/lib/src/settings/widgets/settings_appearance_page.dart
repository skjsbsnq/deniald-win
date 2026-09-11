import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;

import '../../../l10n/generated/app_localizations.dart';
import '../../localization/denial_localizations.dart';
import '../../settings/shell_settings.dart';
import '../../theme/backdrop_blur_level.dart';
import '../../theme/cursor_theme_repository.dart';
import '../../theme/cursor_themes.dart';
import '../../theme/motion.dart';
import '../../theme/shell_theme.dart';
import '../../theme/tokens.dart';
import '../../wallpaper/wallpaper.dart';
import '../../widgets/shell_cursor.dart';
import 'settings_controls.dart';
import 'settings_hero_preview_card.dart';
import 'settings_loading_indicator.dart';

export 'settings_hero_preview_card.dart'
    show settingsWallpaperTriggerKey, SettingsHeroPreviewCard;

const settingsAccentColorTriggerKey = ValueKey<String>(
  'settings-accent-color-trigger',
);
const settingsColorSchemeControlKey = ValueKey<String>(
  'settings-color-scheme-control',
);
const settingsBackdropBlurToggleKey = ValueKey<String>(
  'settings-backdrop-blur-toggle',
);
const settingsBackdropBlurSliderKey = ValueKey<String>(
  'settings-backdrop-blur-slider',
);
const settingsBackdropBlurOpacityThresholdKey = ValueKey<String>(
  'settings-backdrop-blur-opacity-threshold',
);
const settingsCursorSizeSliderKey = ValueKey<String>(
  'settings-cursor-size-slider',
);
const settingsCornerRoundnessSliderKey = ValueKey<String>(
  'settings-corner-roundness-slider',
);
const settingsCardOpacitySliderKey = ValueKey<String>(
  'settings-card-opacity-slider',
);

/// Appearance page refactored into 7 modular card groups conforming to MD3E
/// specification (Decisions 1-A, 2-A, 3-A).
class SettingsAppearancePage extends StatelessWidget {
  const SettingsAppearancePage({
    required this.settings,
    required this.extractedAccent,
    required this.wallpaper,
    required this.onOpenWallpaperSelector,
    required this.onColorSchemePreferenceChanged,
    required this.onAccentSourceChanged,
    required this.onOpenAccentPicker,
    required this.onCornerRadiusScaleChanged,
    required this.onPanelOpacityChanged,
    required this.onCardOpacityChanged,
    required this.onBackdropBlurEnabledChanged,
    required this.onBackdropBlurLevelChanged,
    required this.onBackdropBlurOpacityThresholdChanged,
    required this.onFocusedWindowBorderEnabledChanged,
    required this.onFocusedOpacityChanged,
    required this.onUnfocusedOpacityChanged,
    required this.onCursorSizeChanged,
    required this.cursorThemes,
    required this.cursorCatalogLoading,
    required this.onCursorThemeChanged,
    required this.onAllowClientCursorSurfacesChanged,
    required this.onImportCursorZip,
    required this.onRemoveCursorTheme,
    required this.onUiFontFamilyChanged,
    required this.onIconThemeNameChanged,
    required this.onReset,
    super.key,
  });

  final ShellAppearanceSettings settings;
  final Color extractedAccent;
  final WallpaperResource wallpaper;
  final VoidCallback onOpenWallpaperSelector;
  final ValueChanged<DesktopColorSchemePreference>
  onColorSchemePreferenceChanged;
  final ValueChanged<ShellAccentSource> onAccentSourceChanged;
  final VoidCallback onOpenAccentPicker;
  final ValueChanged<double> onCornerRadiusScaleChanged;
  final ValueChanged<double> onPanelOpacityChanged;
  final ValueChanged<double> onCardOpacityChanged;
  final ValueChanged<bool> onBackdropBlurEnabledChanged;
  final ValueChanged<ShellBackdropBlurLevel> onBackdropBlurLevelChanged;
  final ValueChanged<double> onBackdropBlurOpacityThresholdChanged;
  final ValueChanged<bool> onFocusedWindowBorderEnabledChanged;
  final ValueChanged<double> onFocusedOpacityChanged;
  final ValueChanged<double> onUnfocusedOpacityChanged;
  final ValueChanged<double> onCursorSizeChanged;
  final List<ShellCursorThemeData> cursorThemes;
  final bool cursorCatalogLoading;
  final ValueChanged<String> onCursorThemeChanged;
  final ValueChanged<bool> onAllowClientCursorSurfacesChanged;
  final Future<ShellCursorThemeData?> Function()? onImportCursorZip;
  final Future<void> Function(ShellCursorThemeData) onRemoveCursorTheme;
  final ValueChanged<String> onUiFontFamilyChanged;
  final ValueChanged<String> onIconThemeNameChanged;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final effectiveAccent = settings.accentSource == ShellAccentSource.wallpaper
        ? extractedAccent
        : settings.customAccentColor;

    return SettingsPageLayout(
      icon: Icons.palette_outlined,
      eyebrow: l10n.settingsAppearanceSection,
      title: l10n.settingsNavigationAppearance,
      subtitle: l10n.settingsAppearanceTitle,
      onReset: onReset,
      children: [
        // 1. Card 1: Desktop & Wallpaper Hero Preview (Decision 1-A)
        SettingsCardGroup(
          children: [
            SettingsHeroPreviewCard(
              wallpaper: wallpaper,
              onOpenWallpaperSelector: onOpenWallpaperSelector,
              colorSchemePreference: settings.colorSchemePreference,
              accentColor: effectiveAccent,
            ),
          ],
        ),

        // 2. Card 2: Colour Scheme & Shell Accent (Decision 2-A & 3-A)
        SettingsSectionContainer(
          title: l10n.settingsColorSchemeTitle,
          child: SettingsCardGroup(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SettingsSegmentedControl<DesktopColorSchemePreference>(
                      key: settingsColorSchemeControlKey,
                      value: settings.colorSchemePreference,
                      choices: [
                        SettingsChoice(
                          DesktopColorSchemePreference.preferDark,
                          l10n.settingsColorSchemeDark,
                        ),
                        SettingsChoice(
                          DesktopColorSchemePreference.preferLight,
                          l10n.settingsColorSchemeLight,
                        ),
                        SettingsChoice(
                          DesktopColorSchemePreference.noPreference,
                          l10n.settingsColorSchemeNoPreference,
                        ),
                      ],
                      onChanged: onColorSchemePreferenceChanged,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      settings.colorSchemePreference ==
                              DesktopColorSchemePreference.noPreference
                          ? l10n.settingsColorSchemeNoPreferenceDescription
                          : l10n.settingsColorSchemeDescription,
                      style: ShellText.settingsRowSupport.copyWith(
                        color: context.shellColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _ColorOrb(color: effectiveAccent),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.settingsShellAccentTitle,
                                style: ShellText.settingsRowTitle,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                settings.accentSource ==
                                        ShellAccentSource.wallpaper
                                    ? l10n.settingsShellAccentWallpaper
                                    : l10n.settingsShellAccentCustom,
                                style: ShellText.settingsRowSupport.copyWith(
                                  color: context.shellColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (settings.accentSource == ShellAccentSource.custom)
                          SettingsColorButton(
                            key: settingsAccentColorTriggerKey,
                            color: settings.customAccentColor,
                            label: l10n.settingsShellAccentChoose,
                            onPressed: onOpenAccentPicker,
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SettingsSegmentedControl<ShellAccentSource>(
                      value: settings.accentSource,
                      choices: [
                        SettingsChoice(
                          ShellAccentSource.wallpaper,
                          l10n.settingsShellAccentWallpaper,
                        ),
                        SettingsChoice(
                          ShellAccentSource.custom,
                          l10n.settingsShellAccentCustom,
                        ),
                      ],
                      onChanged: onAccentSourceChanged,
                    ),
                    if (settings.accentSource ==
                        ShellAccentSource.wallpaper) ...[
                      const SizedBox(height: 12),
                      _DynamicTonalSwatches(
                        seedColor: extractedAccent,
                        selectedColor: effectiveAccent,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),

        // 3. Card 3: Material & Backdrop Blur
        SettingsSectionContainer(
          title: l10n.settingsBackdropBlur,
          child: SettingsCardGroup(
            indentDividers: true,
            children: [
              SettingsRow.toggle(
                toggleKey: settingsBackdropBlurToggleKey,
                leading: const Icon(Icons.blur_on_rounded, size: 24),
                title: l10n.settingsBackdropBlurEnabled,
                subtitle: l10n.settingsBackdropBlurEnabledDescription,
                value: settings.backdropBlurEnabled,
                onChanged: onBackdropBlurEnabledChanged,
              ),
              SettingsRow.slider(
                sliderKey: settingsBackdropBlurSliderKey,
                leading: const Icon(Icons.tune_rounded, size: 24),
                title: l10n.settingsBackdropBlurIntensity,
                value: settings.backdropBlurLevel.index.toDouble(),
                minimum: 0,
                maximum: ShellBackdropBlurLevel.values.length - 1,
                divisions: ShellBackdropBlurLevel.values.length - 1,
                enabled: settings.backdropBlurEnabled,
                valueLabel: _backdropBlurLevelLabel(
                  l10n,
                  settings.backdropBlurLevel,
                ),
                onChanged: (value) => onBackdropBlurLevelChanged(
                  ShellBackdropBlurLevel.values[value.round()],
                ),
              ),
              SettingsRow.slider(
                sliderKey: settingsBackdropBlurOpacityThresholdKey,
                leading: const Icon(Icons.opacity_rounded, size: 24),
                title: l10n.settingsBackdropBlurOpacityThreshold,
                value: settings.backdropBlurOpacityThreshold,
                minimum: 0,
                maximum: 1,
                divisions: 100,
                enabled: settings.backdropBlurEnabled,
                valueLabel: l10n.settingsPercent(
                  (settings.backdropBlurOpacityThreshold * 100).round(),
                ),
                onChanged: onBackdropBlurOpacityThresholdChanged,
              ),
            ],
          ),
        ),

        // 4. Card 4: Shape & Opacity
        SettingsSectionContainer(
          title: l10n.settingsShapeTitle,
          child: SettingsCardGroup(
            indentDividers: true,
            children: [
              SettingsRow.slider(
                sliderKey: settingsCornerRoundnessSliderKey,
                leading: const Icon(Icons.rounded_corner_rounded, size: 24),
                title: l10n.settingsCornerRoundness,
                value: settings.cornerRadiusScale,
                minimum: ShellRoundness.minimum,
                maximum: ShellRoundness.maximum,
                divisions: 40,
                valueLabel: l10n.settingsPercent(
                  (settings.cornerRadiusScale * 100).round(),
                ),
                onChanged: onCornerRadiusScaleChanged,
              ),
              SettingsRow.slider(
                leading: const Icon(Icons.layers_outlined, size: 24),
                title: l10n.settingsPanelOpacity,
                value: settings.panelOpacity,
                minimum: ShellOpacity.minimumPanel,
                maximum: 1,
                divisions: 95,
                valueLabel: l10n.settingsPercent(
                  (settings.panelOpacity * 100).round(),
                ),
                onChanged: onPanelOpacityChanged,
              ),
              SettingsRow.slider(
                sliderKey: settingsCardOpacitySliderKey,
                leading: const Icon(Icons.crop_portrait_rounded, size: 24),
                title: l10n.settingsCardOpacity,
                value: settings.cardOpacity,
                minimum: ShellOpacity.minimumCard,
                maximum: 1,
                divisions: 95,
                valueLabel: l10n.settingsPercent(
                  (settings.cardOpacity * 100).round(),
                ),
                onChanged: onCardOpacityChanged,
              ),
            ],
          ),
        ),

        // 5. Card 5: Mouse Cursor
        SettingsSectionContainer(
          title: l10n.settingsCursorTitle,
          child: SettingsCardGroup(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: _CursorSettings(
                  settings: settings,
                  themes: cursorThemes,
                  catalogLoading: cursorCatalogLoading,
                  onThemeChanged: onCursorThemeChanged,
                  onSizeChanged: onCursorSizeChanged,
                  onAllowClientCursorSurfacesChanged:
                      onAllowClientCursorSurfacesChanged,
                  onImport: onImportCursorZip,
                  onRemove: onRemoveCursorTheme,
                ),
              ),
            ],
          ),
        ),

        // 6. Card 6: Typography & Icons
        SettingsSectionContainer(
          title: l10n.settingsFontsAndIconsTitle,
          child: SettingsCardGroup(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: _FontsAndIconsSettings(
                  settings: settings,
                  onUiFontFamilyChanged: onUiFontFamilyChanged,
                  onIconThemeNameChanged: onIconThemeNameChanged,
                ),
              ),
            ],
          ),
        ),

        // 7. Card 7: Window Focus & Opacity
        SettingsSectionContainer(
          title: l10n.settingsWindowOpacityTitle,
          child: SettingsCardGroup(
            indentDividers: true,
            children: [
              SettingsRow.toggle(
                leading: const Icon(Icons.filter_frames_outlined, size: 24),
                title: l10n.settingsFocusedWindowBorder,
                subtitle: l10n.settingsFocusedWindowBorderDescription,
                value: settings.focusedWindowBorderEnabled,
                onChanged: onFocusedWindowBorderEnabledChanged,
              ),
              SettingsRow.slider(
                leading: const Icon(Icons.window_rounded, size: 24),
                title: l10n.settingsFocusedWindows,
                value: settings.focusedWindowOpacity,
                minimum: 0.35,
                maximum: 1,
                divisions: 65,
                valueLabel: l10n.settingsPercent(
                  (settings.focusedWindowOpacity * 100).round(),
                ),
                onChanged: onFocusedOpacityChanged,
              ),
              SettingsRow.slider(
                leading: const Icon(Icons.wb_twilight_rounded, size: 24),
                title: l10n.settingsUnfocusedWindows,
                value: settings.unfocusedWindowOpacity,
                minimum: 0.2,
                maximum: 1,
                divisions: 80,
                valueLabel: l10n.settingsPercent(
                  (settings.unfocusedWindowOpacity * 100).round(),
                ),
                onChanged: onUnfocusedOpacityChanged,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

final class _DynamicAccentKey {
  const _DynamicAccentKey(this.colorValue, this.brightness);

  final int colorValue;
  final Brightness brightness;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _DynamicAccentKey &&
          other.colorValue == colorValue &&
          other.brightness == brightness;

  @override
  int get hashCode => Object.hash(colorValue, brightness);
}

final _dynamicSwatchesCache = <_DynamicAccentKey, List<Color>>{};

List<Color> _dynamicAccentSwatches(Color seed, Brightness brightness) {
  final key = _DynamicAccentKey(seed.toARGB32(), brightness);
  return _dynamicSwatchesCache.putIfAbsent(key, () {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed.withValues(alpha: 1),
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.expressive,
    );
    return [
      seed.withValues(alpha: 1),
      scheme.primary,
      scheme.secondary,
      scheme.tertiary,
      scheme.primaryContainer,
    ];
  });
}

class _DynamicTonalSwatches extends StatefulWidget {
  const _DynamicTonalSwatches({
    required this.seedColor,
    required this.selectedColor,
  });

  final Color seedColor;
  final Color selectedColor;

  @override
  State<_DynamicTonalSwatches> createState() => _DynamicTonalSwatchesState();
}

class _DynamicTonalSwatchesState extends State<_DynamicTonalSwatches> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final colors = context.shellColors;
    final theme = ShellTheme.of(context);
    final swatches = _dynamicAccentSwatches(
      widget.seedColor,
      colors.brightness,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.settingsShellAccentWallpaper,
          style: ShellText.settingsRowSupport.copyWith(
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            for (var i = 0; i < swatches.length; i++)
              Semantics(
                button: true,
                selected: _selectedIndex == i,
                label: 'Accent tone ${i + 1}',
                child: GestureDetector(
                  onTap: () => setState(() => _selectedIndex = i),
                  child: AnimatedContainer(
                    duration: Motion.tile,
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: swatches[i],
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _selectedIndex == i
                            ? theme.accentPalette.primary
                            : colors.panelHighlight.withValues(alpha: 0.6),
                        width: _selectedIndex == i ? 2.5 : 1.0,
                      ),
                      boxShadow: _selectedIndex == i
                          ? [
                              BoxShadow(
                                color: swatches[i].withValues(alpha: 0.4),
                                blurRadius: 6,
                              ),
                            ]
                          : null,
                    ),
                    child: _selectedIndex == i
                        ? Center(
                            child: Icon(
                              Icons.check_rounded,
                              size: 16,
                              color: swatches[i].computeLuminance() > 0.5
                                  ? ShellMediaColors.darkness
                                  : ShellMediaColors.contrastLight,
                            ),
                          )
                        : null,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _FontsAndIconsSettings extends StatelessWidget {
  const _FontsAndIconsSettings({
    required this.settings,
    required this.onUiFontFamilyChanged,
    required this.onIconThemeNameChanged,
  });

  final ShellAppearanceSettings settings;
  final ValueChanged<String> onUiFontFamilyChanged;
  final ValueChanged<String> onIconThemeNameChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final fontChoices = <SettingsChoice<String>>[
      SettingsChoice<String>('', l10n.settingsUiFontFamilyDefault),
      const SettingsChoice<String>('Maple Mono NF CN', 'Maple Mono NF CN'),
    ];
    final iconChoices = <SettingsChoice<String>>[
      SettingsChoice<String>('', l10n.settingsIconThemeDefault),
      const SettingsChoice<String>('Papirus', 'Papirus'),
      const SettingsChoice<String>('Papirus-Dark', 'Papirus-Dark'),
      const SettingsChoice<String>('Papirus-Light', 'Papirus-Light'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.settingsUiFontFamily,
          style: ShellText.cardTitle.copyWith(
            color: context.shellColors.textSecondary,
          ),
        ),
        const SizedBox(height: 9),
        SettingsSegmentedControl<String>(
          value: _containsChoice(fontChoices, settings.uiFontFamily)
              ? settings.uiFontFamily
              : '',
          choices: fontChoices,
          onChanged: onUiFontFamilyChanged,
        ),
        const SizedBox(height: 12),
        Text(
          l10n.settingsIconTheme,
          style: ShellText.cardTitle.copyWith(
            color: context.shellColors.textSecondary,
          ),
        ),
        const SizedBox(height: 9),
        SettingsSegmentedControl<String>(
          value: _containsChoice(iconChoices, settings.iconThemeName)
              ? settings.iconThemeName
              : '',
          choices: iconChoices,
          onChanged: onIconThemeNameChanged,
        ),
        const SizedBox(height: 12),
        Text(
          l10n.settingsFontsAndIconsRestartNotice,
          style: ShellText.settingsRowSupport.copyWith(
            color: context.shellColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

bool _containsChoice(List<SettingsChoice<String>> choices, String value) {
  return choices.any((choice) => choice.value == value);
}

class _CursorSettings extends StatefulWidget {
  const _CursorSettings({
    required this.settings,
    required this.themes,
    required this.catalogLoading,
    required this.onThemeChanged,
    required this.onSizeChanged,
    required this.onAllowClientCursorSurfacesChanged,
    required this.onImport,
    required this.onRemove,
  });

  final ShellAppearanceSettings settings;
  final List<ShellCursorThemeData> themes;
  final bool catalogLoading;
  final ValueChanged<String> onThemeChanged;
  final ValueChanged<double> onSizeChanged;
  final ValueChanged<bool> onAllowClientCursorSurfacesChanged;
  final Future<ShellCursorThemeData?> Function()? onImport;
  final Future<void> Function(ShellCursorThemeData) onRemove;

  @override
  State<_CursorSettings> createState() => _CursorSettingsState();
}

class _CursorSettingsState extends State<_CursorSettings> {
  bool _busy = false;
  String? _error;

  Future<void> _import() async {
    final importer = widget.onImport;
    if (importer == null || _busy) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await importer();
    } on CursorThemeException catch (error) {
      if (mounted) {
        setState(() => _error = error.message);
      }
    } on Object {
      if (mounted) {
        setState(() => _error = context.l10n.settingsCursorImportFailed);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _remove(ShellCursorThemeData theme) async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onRemove(theme);
    } on CursorThemeException catch (error) {
      if (mounted) {
        setState(() => _error = error.message);
      }
    } on Object {
      if (mounted) {
        setState(() => _error = context.l10n.settingsCursorRemoveFailed);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return FocusTraversalGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.settingsCursorTheme,
            style: ShellText.cardTitle.copyWith(
              color: context.shellColors.textSecondary,
            ),
          ),
          const SizedBox(height: 9),
          if (widget.catalogLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: SettingsLoadingIndicator(),
              ),
            )
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final theme in widget.themes)
                  _CursorThemeCard(
                    theme: theme,
                    selected: theme.id == widget.settings.cursorThemeId,
                    enabled: !_busy,
                    onSelected: () => widget.onThemeChanged(theme.id),
                    onRemove: theme.isImported ? () => _remove(theme) : null,
                  ),
              ],
            ),
          const SizedBox(height: 12),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: SettingsTextButton(
              label: _busy
                  ? l10n.settingsCursorImporting
                  : l10n.settingsCursorImport,
              onPressed: widget.onImport == null || _busy ? null : _import,
            ),
          ),
          if (_error case final error?) ...[
            const SizedBox(height: 8),
            Semantics(
              liveRegion: true,
              child: Text(
                error,
                style: ShellText.settingsRowSupport.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          SettingsSlider(
            key: settingsCursorSizeSliderKey,
            label: l10n.settingsCursorSize,
            value: widget.settings.cursorSize,
            minimum: shellCursorMinimumSize,
            maximum: shellCursorMaximumSize,
            divisions: ((shellCursorMaximumSize - shellCursorMinimumSize) / 4)
                .round(),
            valueLabel: l10n.settingsPixels(widget.settings.cursorSize.round()),
            onChanged: widget.onSizeChanged,
          ),
          const SizedBox(height: 12),
          SettingsToggle(
            label: l10n.settingsCursorAllowApplications,
            description: l10n.settingsCursorAllowApplicationsDescription,
            value: widget.settings.allowClientCursorSurfaces,
            onChanged: widget.onAllowClientCursorSurfacesChanged,
          ),
        ],
      ),
    );
  }
}

class _CursorThemeCard extends StatefulWidget {
  const _CursorThemeCard({
    required this.theme,
    required this.selected,
    required this.enabled,
    required this.onSelected,
    required this.onRemove,
  });

  final ShellCursorThemeData theme;
  final bool selected;
  final bool enabled;
  final VoidCallback onSelected;
  final VoidCallback? onRemove;

  @override
  State<_CursorThemeCard> createState() => _CursorThemeCardState();
}

class _CursorThemeCardState extends State<_CursorThemeCard> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = ShellTheme.of(context);
    final accent = theme.accent;
    final colors = context.shellColors;
    final enabled = widget.enabled;
    return Semantics(
      button: true,
      selected: widget.selected,
      enabled: enabled,
      label: widget.theme.label,
      child: FocusableActionDetector(
        enabled: enabled,
        mouseCursor: enabled
            ? ShellMouseCursors.link
            : SystemMouseCursors.basic,
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        onShowHoverHighlight: (value) => setState(() => _hovered = value),
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              if (enabled) {
                widget.onSelected();
              }
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? widget.onSelected : null,
          child: AnimatedOpacity(
            duration: Motion.tile,
            opacity: enabled ? 1 : 0.52,
            child: AnimatedContainer(
              duration: Motion.tile,
              width: 250,
              constraints: const BoxConstraints(minHeight: 124),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: widget.selected
                    ? theme.cardColor(
                        Color.alphaBlend(
                          accent.withAlpha(34),
                          colors.surfaceContainerHigh.withValues(alpha: 1),
                        ),
                      )
                    : theme.cardColor(colors.surfaceContainerHigh),
                borderRadius: context.shellTheme.borderRadius(
                  ShellShapeScale.medium,
                ),
                border: Border.all(
                  color: widget.selected
                      ? accent
                      : _hovered || _focused
                      ? colors.panelHighlight
                      : colors.hairline,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.theme.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: ShellText.cardTitle,
                            ),
                            if (!widget.theme.isImported &&
                                widget.theme.author.trim().isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                widget.theme.author,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: ShellText.settingsRowSupport.copyWith(
                                  color: colors.textSecondary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (widget.onRemove case final remove?)
                        Tooltip(
                          message: context.l10n.settingsCursorRemove,
                          child: IconButton(
                            onPressed: enabled ? remove : null,
                            icon: const Icon(Icons.delete_outline_rounded),
                            iconSize: 18,
                            visualDensity: VisualDensity.compact,
                          ),
                        )
                      else if (widget.selected)
                        Icon(
                          Icons.check_circle_rounded,
                          size: 18,
                          color: accent,
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  RepaintBoundary(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        for (final kind in const <ShellCursorKind>[
                          ShellCursorKind.normal,
                          ShellCursorKind.link,
                          ShellCursorKind.text,
                          ShellCursorKind.working,
                          ShellCursorKind.busy,
                        ])
                          SizedBox.square(
                            dimension: 34,
                            child: Center(
                              child: ShellCursorArtwork(
                                theme: widget.theme,
                                kind: kind,
                                longestEdge: 28,
                                running: enabled,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _backdropBlurLevelLabel(
  AppLocalizations l10n,
  ShellBackdropBlurLevel level,
) {
  return switch (level) {
    ShellBackdropBlurLevel.shitty => l10n.settingsBackdropBlurLevelShitty,
    ShellBackdropBlurLevel.fast => l10n.settingsBackdropBlurLevelFast,
    ShellBackdropBlurLevel.good => l10n.settingsBackdropBlurLevelGood,
    ShellBackdropBlurLevel.best => l10n.settingsBackdropBlurLevelBest,
  };
}

class _ColorOrb extends StatelessWidget {
  const _ColorOrb({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: context.shellColors.panelHighlight),
        boxShadow: [BoxShadow(color: color.withAlpha(48), blurRadius: 18)],
      ),
    );
  }
}
