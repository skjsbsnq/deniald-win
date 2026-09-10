import 'package:flutter/material.dart';

import '../../localization/denial_localizations.dart';
import '../../models/display_layout.dart';
import '../../theme/shell_theme.dart';
import '../../theme/tokens.dart';
import '../shell_settings.dart';
import 'settings_controls.dart';
import 'system_bar_placement_card.dart';

/// Identifies the system bar / shelf thickness slider (§5.1), so tests can
/// assert the effective range while its label switches between the two modes.
const settingsBarThicknessSliderKey = ValueKey<String>(
  'settings-bar-thickness-slider',
);

/// Floor of the classic system bar thickness slider (§5.1).
const double settingsBarMinimumHeight = 24;

/// Floor of the shelf height slider when ChromeOS shelf is active (§5.1).
const double settingsShelfMinimumHeight = 48;

/// Ceiling shared by the classic bar thickness and the shelf height (§5.1).
const double settingsBarMaximumHeight = 112;

class SettingsLayoutPage extends StatelessWidget {
  const SettingsLayoutPage({
    required this.settings,
    required this.displayLayout,
    required this.onWindowLayoutChanged,
    required this.onWorkspacesEnabledChanged,
    required this.onWorkspaceCountChanged,
    required this.onSystemBarChanged,
    required this.onSystemBarThicknessChanged,
    required this.onMaximizePaddingChanged,
    required this.onMinimizedWindowPlacementChanged,
    required this.onClipboardTrayEdgeChanged,
    required this.onClipboardTrayExtentChanged,
    this.onUseChromeOsShelfChanged,
    required this.onReset,
    super.key,
  });

  final ShellLayoutSettings settings;
  final DisplayLayout? displayLayout;
  final ValueChanged<DesktopWindowLayout> onWindowLayoutChanged;
  final ValueChanged<bool> onWorkspacesEnabledChanged;
  final ValueChanged<double> onWorkspaceCountChanged;
  final SystemBarPlacementChanged onSystemBarChanged;
  final ValueChanged<double> onSystemBarThicknessChanged;
  final ValueChanged<double> onMaximizePaddingChanged;
  final ValueChanged<MinimizedWindowPlacement>
  onMinimizedWindowPlacementChanged;
  final ValueChanged<ClipboardTrayEdge> onClipboardTrayEdgeChanged;
  final ValueChanged<double> onClipboardTrayExtentChanged;
  final ValueChanged<bool>? onUseChromeOsShelfChanged;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Single validity source for the ChromeOS shelf (§E4): the layout settings
    // are already selected once by the page host, and the card never reads a
    // provider of its own.
    final shelfActive = settings.useChromeOsShelf;
    final thicknessMinimum = shelfActive
        ? settingsShelfMinimumHeight
        : settingsBarMinimumHeight;
    final thickness = shelfActive
        ? settings.effectiveSystemBarThickness
              .clamp(settingsShelfMinimumHeight, settingsBarMaximumHeight)
              .toDouble()
        : settings.systemBarThickness;
    return SettingsPageLayout(
      icon: Icons.space_dashboard_outlined,
      eyebrow: l10n.settingsLayoutSection,
      title: l10n.settingsLayoutTitle,
      onReset: onReset,
      children: [
        SettingsCardGroup(
          children: [
            SettingsSection(
              title: l10n.settingsWindowLayoutTitle,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SettingsSegmentedControl<DesktopWindowLayout>(
                    value: settings.windowLayout,
                    choices: [
                      SettingsChoice(
                        DesktopWindowLayout.stacking,
                        l10n.settingsWindowLayoutStacking,
                      ),
                      SettingsChoice(
                        DesktopWindowLayout.dwindle,
                        l10n.settingsWindowLayoutDwindle,
                      ),
                    ],
                    onChanged: onWindowLayoutChanged,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.settingsWindowLayoutDescription,
                    style: ShellText.settingsRowSupport.copyWith(
                      color: context.shellColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        SettingsCardGroup(
          children: [
            SettingsSection(
              title: l10n.settingsWorkspacesTitle,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SettingsToggle(
                    key: const ValueKey<String>(
                      'settings-workspaces-enabled-toggle',
                    ),
                    label: l10n.settingsWorkspacesEnable,
                    description: l10n.settingsWorkspacesDescription,
                    value: settings.workspacesEnabled,
                    onChanged: onWorkspacesEnabledChanged,
                  ),
                  const SizedBox(height: 18),
                  SettingsSlider(
                    label: l10n.settingsWorkspaceCount,
                    value: settings.workspaceCount.toDouble(),
                    minimum: minimumWorkspaceCount.toDouble(),
                    maximum: maximumWorkspaceCount.toDouble(),
                    divisions: maximumWorkspaceCount - minimumWorkspaceCount,
                    valueLabel: settings.workspaceCount.toString(),
                    onChanged: onWorkspaceCountChanged,
                    enabled: settings.workspacesEnabled,
                  ),
                ],
              ),
            ),
          ],
        ),
        SettingsCardGroup(
          children: [
            SettingsSection(
              title: l10n.settingsChromeOsShelfTitle,
              child: SettingsToggle(
                key: const ValueKey<String>(
                  'settings-use-chromeos-shelf-toggle',
                ),
                label: l10n.settingsUseChromeOsShelf,
                description: l10n.settingsUseChromeOsShelfDescription,
                value: settings.useChromeOsShelf,
                onChanged: onUseChromeOsShelfChanged ?? (_) {},
                enabled: onUseChromeOsShelfChanged != null,
              ),
            ),
            SystemBarPlacementCard(
              layout: displayLayout,
              onChanged: onSystemBarChanged,
              showEdgeSelector: !shelfActive,
            ),
            SettingsSection(
              title: l10n.settingsBarGeometryTitle,
              child: SettingsSlider(
                key: settingsBarThicknessSliderKey,
                label: shelfActive
                    ? l10n.settingsShelfHeight
                    : l10n.settingsBarThickness,
                value: thickness,
                minimum: thicknessMinimum,
                maximum: settingsBarMaximumHeight,
                // One division per logical pixel across the active range.
                divisions: (settingsBarMaximumHeight - thicknessMinimum)
                    .round(),
                valueLabel: l10n.settingsPixels(thickness.round()),
                onChanged: onSystemBarThicknessChanged,
              ),
            ),
          ],
        ),
        SettingsCardGroup(
          children: [
            SettingsSection(
              title: l10n.settingsWindowMinimizationTitle,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SettingsSegmentedControl<MinimizedWindowPlacement>(
                    value: settings.minimizedWindowPlacement,
                    choices: [
                      SettingsChoice(
                        MinimizedWindowPlacement.desktop,
                        l10n.settingsWindowMinimizationDesktop,
                      ),
                      SettingsChoice(
                        MinimizedWindowPlacement.offscreen,
                        l10n.settingsWindowMinimizationOffscreen,
                      ),
                    ],
                    onChanged: onMinimizedWindowPlacementChanged,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.settingsWindowMinimizationDescription,
                    style: ShellText.settingsRowSupport.copyWith(
                      color: context.shellColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            SettingsSection(
              title: l10n.settingsMaximizedSpacingTitle,
              child: SettingsSlider(
                label: l10n.settingsOuterPadding,
                value: settings.maximizePadding,
                minimum: 0,
                maximum: 64,
                divisions: 64,
                valueLabel: l10n.settingsPixels(
                  settings.maximizePadding.round(),
                ),
                onChanged: onMaximizePaddingChanged,
              ),
            ),
            SettingsSection(
              title: l10n.settingsClipboardTrayTitle,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SettingsSegmentedControl<ClipboardTrayEdge>(
                    value: settings.clipboardTrayEdge,
                    choices: [
                      SettingsChoice(
                        ClipboardTrayEdge.left,
                        l10n.settingsClipboardTrayEdgeLeft,
                      ),
                      SettingsChoice(
                        ClipboardTrayEdge.right,
                        l10n.settingsClipboardTrayEdgeRight,
                      ),
                      SettingsChoice(
                        ClipboardTrayEdge.top,
                        l10n.settingsClipboardTrayEdgeTop,
                      ),
                      SettingsChoice(
                        ClipboardTrayEdge.bottom,
                        l10n.settingsClipboardTrayEdgeBottom,
                      ),
                    ],
                    onChanged: onClipboardTrayEdgeChanged,
                  ),
                  const SizedBox(height: 18),
                  SettingsSlider(
                    label: l10n.settingsClipboardTraySize,
                    value: settings.clipboardTrayExtent,
                    minimum: clipboardTrayMinimumExtent,
                    maximum: clipboardTrayMaximumExtent,
                    divisions: 20,
                    valueLabel: l10n.settingsPixels(
                      settings.clipboardTrayExtent.round(),
                    ),
                    onChanged: onClipboardTrayExtentChanged,
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
