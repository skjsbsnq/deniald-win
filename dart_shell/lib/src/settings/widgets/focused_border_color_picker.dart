import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../localization/denial_localizations.dart';
import '../../theme/motion.dart';
import '../../theme/shell_theme.dart';
import '../../theme/tokens.dart';
import '../color_format.dart';
import 'hsv_color_wheel.dart';
import 'settings_buttons.dart';
import 'settings_controls.dart';

const settingsAccentColorPickerKey = ValueKey<String>(
  'settings-accent-color-picker',
);
const settingsAccentColorResetKey = ValueKey<String>(
  'settings-accent-color-reset',
);

class SettingsAccentColorPicker extends StatelessWidget {
  const SettingsAccentColorPicker({
    super.key,
    required this.color,
    required this.onChanged,
    required this.onReset,
    required this.onClose,
    this.title,
    this.routeLabel,
    this.wheelSemanticsLabel,
  });

  final Color color;
  final ValueChanged<Color> onChanged;
  final VoidCallback onReset;
  final VoidCallback onClose;
  final String? title;
  final String? routeLabel;
  final String? wheelSemanticsLabel;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Shared modal chrome: overviewScrim dim, outside-tap + Escape dismiss,
    // centred panel, focus returned to the opener on close.
    return SettingsModalScrim(
      onDismiss: onClose,
      padding: EdgeInsets.zero,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final panelWidth = math.min(360.0, constraints.maxWidth - 32.0);
          final panelHeight = math.min(410.0, constraints.maxHeight - 32.0);
          final wheelSize = math.max(
            128.0,
            math.min(220.0, panelHeight - 174.0),
          );
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: SizedBox(
              width: panelWidth,
              height: panelHeight,
              child: _ColorPickerPanel(
                color: color,
                wheelSize: wheelSize,
                onChanged: onChanged,
                onReset: onReset,
                onClose: onClose,
                title: title ?? l10n.settingsColorPickerTitle,
                routeLabel: routeLabel ?? l10n.settingsColorPickerRouteLabel,
                wheelSemanticsLabel:
                    wheelSemanticsLabel ??
                    l10n.settingsColorWheelSemanticsLabel,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ColorPickerPanel extends StatelessWidget {
  const _ColorPickerPanel({
    required this.color,
    required this.wheelSize,
    required this.onChanged,
    required this.onReset,
    required this.onClose,
    required this.title,
    required this.routeLabel,
    required this.wheelSemanticsLabel,
  });

  final Color color;
  final double wheelSize;
  final ValueChanged<Color> onChanged;
  final VoidCallback onReset;
  final VoidCallback onClose;
  final String title;
  final String routeLabel;
  final String wheelSemanticsLabel;

  @override
  Widget build(BuildContext context) {
    final hex = formatOpaqueColorHex(color);
    final l10n = context.l10n;
    final theme = ShellTheme.of(context);
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      role: .dialog,
      label: routeLabel,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.cardColor(context.shellColors.panelBackgroundBottom),
          // Shared modal radius: the 28dp `extraLarge` panel shape used by
          // the other settings overlays (§4 card/sheet family).
          borderRadius: theme.borderRadius(ShellShapeScale.extraLarge),
          border: Border.all(color: context.shellColors.hairline),
        ),
        child: FocusTraversalGroup(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
            child: Column(
              children: [
                _PickerHeader(
                  color: color,
                  hex: hex,
                  title: title,
                  onClose: onClose,
                ),
                const SizedBox(height: 12),
                SizedBox.square(
                  dimension: wheelSize,
                  child: HsvColorWheel(
                    color: color,
                    onChanged: onChanged,
                    semanticsLabel: wheelSemanticsLabel,
                  ),
                ),
                const Spacer(),
                Text(
                  l10n.settingsColorPickerInstructions,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ShellText.cardTitle.copyWith(
                    color: context.shellColors.textTertiary,
                    fontSize: 10,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    SettingsButton(
                      key: settingsAccentColorResetKey,
                      label: l10n.settingsColorPickerReset,
                      variant: SettingsButtonVariant.outlined,
                      onPressed: onReset,
                    ),
                    const Spacer(),
                    SettingsButton(
                      label: l10n.settingsColorPickerDone,
                      variant: SettingsButtonVariant.filledTonal,
                      onPressed: onClose,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PickerHeader extends StatelessWidget {
  const _PickerHeader({
    required this.color,
    required this.hex,
    required this.title,
    required this.onClose,
  });

  final Color color;
  final String hex;
  final String title;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      children: [
        AnimatedContainer(
          duration: Motion.tile,
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: context.shellColors.panelHighlight),
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: ShellText.cardTitle),
              const SizedBox(height: 2),
              Text(
                hex,
                style: ShellText.cardTitle.copyWith(
                  color: context.shellColors.textSecondary,
                  fontFamily: ShellText.systemBarFontFamily,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        SettingsIconButton(
          icon: Icons.close_rounded,
          iconSize: 18,
          semanticsLabel: l10n.settingsColorPickerCloseSemanticsLabel,
          onPressed: onClose,
        ),
      ],
    );
  }
}
