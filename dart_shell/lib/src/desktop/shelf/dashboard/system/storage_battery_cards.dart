import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../../../../../l10n/generated/app_localizations.dart';
import '../../../../localization/denial_localizations.dart';
import '../../../../models/battery_status.dart';
import '../../../../services/system_hardware_service.dart';
import '../../../../theme/shell_theme.dart';
import '../../../../theme/tokens.dart';
import '../dashboard_card_tone.dart';
import 'expressive_polygon.dart';
import 'liquid_metric_card.dart';

/// Root filesystem occupancy card in the tertiary family: a labeled tonal
/// indicator bar replaces the bare progress strip, and the shared expressive
/// polygon blooms in the corner as the disk fills.
class StorageCard extends StatelessWidget {
  const StorageCard({
    super.key,
    required this.storage,
    this.tone = DashboardCardTone.tertiary,
  });

  /// Latest `df -B1 /` reading; null renders the unavailable state.
  final StorageUsage? storage;

  /// Tonal family of the card fill; storage defaults to the tertiary family
  /// per the mixed-emphasis grid.
  final DashboardCardTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final toneColors = dashboardCardToneColors(
      theme,
      context.shellColors,
      tone,
    );
    final l10n = context.l10n;
    final usage = storage?.fraction ?? 0.0;
    final radius = theme.borderRadius(ShellShapeScale.large);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.panelColor(toneColors.container),
        borderRadius: radius,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.systemStorage,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.text.labelMediumEmphasized.copyWith(
                            color: toneColors.foregroundSecondary,
                          ),
                        ),
                      ),
                      Text(
                        storage == null ? '--' : '${(usage * 100).round()}%',
                        style: theme.text.titleSmallEmphasized.copyWith(
                          color: toneColors.foreground,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 46,
                    child: Center(
                      child: _TonalIndicatorBar(
                        fraction: usage,
                        accent: toneColors.accent,
                        trackColor: toneColors.foregroundSecondary.withValues(
                          alpha: 0.22,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    storage == null
                        ? l10n.systemDataUnavailable
                        : l10n.systemStorageFree(
                            formatGigabytes(storage!.total - storage!.used),
                          ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.text.labelSmall.copyWith(
                      color: toneColors.foregroundSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              right: -16,
              bottom: -16,
              child: SizedBox.square(
                dimension: 88,
                child: ExpressivePolygon(
                  complexity: usage,
                  color: toneColors.accent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Rounded tonal indicator bar: a full-radius track in the card's quiet
/// foreground tone with the family accent sweeping the used fraction.
class _TonalIndicatorBar extends StatelessWidget {
  const _TonalIndicatorBar({
    required this.fraction,
    required this.accent,
    required this.trackColor,
  });

  final double fraction;
  final Color accent;
  final Color trackColor;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return ClipRRect(
      borderRadius: theme.borderRadius(ShellShapeScale.full),
      child: SizedBox(
        height: ShellSpacing.md,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: trackColor),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: fraction.clamp(0.0, 1.0).toDouble(),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: theme.borderRadius(ShellShapeScale.full),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Battery tank card: liquid level, percentage, and supply status.
class BatteryTankCard extends StatelessWidget {
  const BatteryTankCard({
    super.key,
    required this.battery,
    this.tone = DashboardCardTone.surface,
  });

  final BatteryStatus battery;

  /// Tonal family of the card fill and its foreground roles.
  final DashboardCardTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final toneColors = dashboardCardToneColors(
      theme,
      context.shellColors,
      tone,
    );
    final l10n = context.l10n;
    final capacity = battery.capacity;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.panelColor(toneColors.container),
        borderRadius: theme.borderRadius(ShellShapeScale.large),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.systemBattery,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.text.labelMediumEmphasized.copyWith(
                      color: toneColors.foregroundSecondary,
                    ),
                  ),
                ),
                Text(
                  capacity == null ? '--' : '$capacity%',
                  style: theme.text.titleSmallEmphasized.copyWith(
                    color: toneColors.foreground,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 46,
              child: capacity == null
                  ? Center(
                      child: Text(
                        l10n.systemBatteryUnavailable,
                        style: theme.text.labelSmall.copyWith(
                          color: toneColors.foregroundSecondary,
                        ),
                      ),
                    )
                  : LiquidFill(
                      fraction: capacity / 100,
                      color: toneColors.accent,
                    ),
            ),
            const SizedBox(height: 8),
            _BatteryStatusLine(
              battery: battery,
              l10n: l10n,
              idleColor: toneColors.foregroundSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _BatteryStatusLine extends StatelessWidget {
  const _BatteryStatusLine({
    required this.battery,
    required this.l10n,
    required this.idleColor,
  });

  final BatteryStatus battery;
  final AppLocalizations l10n;
  final Color idleColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.shellColors;

    final (icon, label, color) = switch ((
      battery.capacity,
      battery.charging,
      battery.full,
      battery.acOnline,
    )) {
      (null, _, _, _) => (
        Icons.battery_0_bar_rounded,
        l10n.systemStatusUnavailable,
        idleColor,
      ),
      (_, _, true, _) => (
        Icons.check_rounded,
        l10n.batteryFull,
        colors.performanceGood,
      ),
      (_, true, _, _) => (
        Icons.bolt_rounded,
        l10n.batteryCharging,
        colors.performanceGood,
      ),
      (_, _, _, true) => (
        Icons.power_rounded,
        l10n.batteryOnAcPower,
        idleColor,
      ),
      _ => (Icons.battery_full_rounded, l10n.batteryOnBattery, idleColor),
    };

    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.shellTheme.text.labelSmall.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

/// Bytes to a one-decimal GB figure for compact card lines.
String formatGigabytes(int bytes) {
  final gigabytes = bytes / (1024 * 1024 * 1024);
  if (gigabytes >= 100) {
    return gigabytes.round().toString();
  }
  return gigabytes.toStringAsFixed(1);
}
