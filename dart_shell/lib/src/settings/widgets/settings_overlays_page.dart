import 'package:flutter/material.dart';

import '../../localization/denial_localizations.dart';
import '../../models/shell_popup_placement.dart';
import '../shell_settings.dart';
import 'settings_controls.dart';

Key settingsEdgeDistanceSliderKey(ShellOverlaySurface surface) =>
    ValueKey<String>('settings-${surface.name}-edge-distance-slider');

class SettingsOverlaysPage extends StatelessWidget {
  const SettingsOverlaysPage({
    required this.settings,
    required this.onChanged,
    required this.useChromeOsShelf,
    required this.onReset,
    super.key,
  });

  final ShellOverlaySettings settings;
  final void Function(
    ShellOverlaySurface surface,
    ShellPopupPlacement placement,
  )
  onChanged;

  /// Retained for the host's constructor signature. The ChromeOS shelf is the
  /// only desktop bar form: the legacy launcher and dashboard surfaces no
  /// longer render, so their placement editors are permanently gone rather
  /// than conditionally hidden. Notifications and the system-level display
  /// stay valid either way (禁令 §E3).
  final bool useChromeOsShelf;

  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SettingsPageLayout(
      icon: Icons.picture_in_picture_alt_outlined,
      eyebrow: l10n.settingsOverlaysSection,
      title: l10n.settingsOverlaysTitle,
      onReset: onReset,
      children: [
        SettingsCardGroup(
          children: [
            _PlacementEditor(
              title: l10n.settingsNotificationOverlayTitle,
              surface: ShellOverlaySurface.notifications,
              placement: settings.notifications,
              onChanged: onChanged,
              minimumWidth: 280,
            ),
            _PlacementEditor(
              title: l10n.settingsHudOverlayTitle,
              surface: ShellOverlaySurface.systemHud,
              placement: settings.systemHud,
              onChanged: onChanged,
              minimumWidth: 220,
            ),
          ],
        ),
      ],
    );
  }
}

class _PlacementEditor extends StatelessWidget {
  const _PlacementEditor({
    required this.title,
    required this.surface,
    required this.placement,
    required this.onChanged,
    required this.minimumWidth,
  });

  final String title;
  final ShellOverlaySurface surface;
  final ShellPopupPlacement placement;
  final void Function(
    ShellOverlaySurface surface,
    ShellPopupPlacement placement,
  )
  onChanged;
  final double minimumWidth;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    void update(ShellPopupPlacement value) => onChanged(surface, value);
    return SettingsSection(
      title: title,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 600;
          final controls = Expanded(
            child: Column(
              children: [
                SettingsSlider(
                  label: l10n.settingsWidth,
                  value: placement.width,
                  minimum: minimumWidth,
                  maximum: 1400,
                  divisions: ((1400 - minimumWidth) / 10).round(),
                  valueLabel: l10n.settingsPixels(placement.width.round()),
                  onChanged: (value) =>
                      update(placement.copyWith(width: value)),
                ),
                const SizedBox(height: 6),
                SettingsSlider(
                  key: settingsEdgeDistanceSliderKey(surface),
                  label: l10n.settingsEdgeDistance,
                  value: placement.margin,
                  minimum: 0,
                  maximum: 96,
                  divisions: 48,
                  valueLabel: l10n.settingsPixels(placement.margin.round()),
                  enabled: placement.anchor != ShellPopupAnchor.center,
                  onChanged: (value) =>
                      update(placement.copyWith(margin: value)),
                ),
              ],
            ),
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SettingsAnchorPicker(
                  value: placement.anchor,
                  onChanged: (anchor) =>
                      update(placement.copyWith(anchor: anchor)),
                ),
                const SizedBox(height: 16),
                Row(children: [controls]),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SettingsAnchorPicker(
                value: placement.anchor,
                onChanged: (anchor) =>
                    update(placement.copyWith(anchor: anchor)),
              ),
              const SizedBox(width: 22),
              controls,
            ],
          );
        },
      ),
    );
  }
}
