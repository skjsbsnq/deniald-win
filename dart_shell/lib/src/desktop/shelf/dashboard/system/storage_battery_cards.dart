import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../../../../../l10n/generated/app_localizations.dart';
import '../../../../localization/denial_localizations.dart';
import '../../../../models/battery_status.dart';
import '../../../../services/system_hardware_service.dart';
import '../../../../theme/shell_theme.dart';
import '../../../../theme/tokens.dart';
import 'liquid_metric_card.dart';

/// Root filesystem occupancy card with a linear usage bar.
class StorageCard extends StatelessWidget {
  const StorageCard({super.key, required this.storage});

  /// Latest `df -B1 /` reading; null renders the unavailable state.
  final StorageUsage? storage;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = context.shellColors;
    final l10n = context.l10n;
    final usage = storage?.fraction ?? 0.0;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.panelColor(colors.surfaceContainer),
        borderRadius: theme.borderRadius(ShellShapeScale.large),
        border: Border.all(color: colors.hairlineSoft, width: 1.0),
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
                    l10n.systemStorage,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,

                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
                Text(
                  storage == null ? '--' : '${(usage * 100).round()}%',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 46,
              child: Center(
                child: ClipRRect(
                  borderRadius: theme.borderRadius(ShellShapeScale.small),
                  child: SizedBox(
                    height: 8,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ColoredBox(color: colors.surfaceContainerHighest),
                        FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: usage,
                          child: ColoredBox(color: theme.accentPalette.primary),
                        ),
                      ],
                    ),
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
              style: TextStyle(
                color: colors.textTertiary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.none,
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
  const BatteryTankCard({super.key, required this.battery});

  final BatteryStatus battery;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = context.shellColors;
    final l10n = context.l10n;
    final capacity = battery.capacity;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.panelColor(colors.surfaceContainer),
        borderRadius: theme.borderRadius(ShellShapeScale.large),
        border: Border.all(color: colors.hairlineSoft, width: 1.0),
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
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,

                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
                Text(
                  capacity == null ? '--' : '$capacity%',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.none,
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
                        style: TextStyle(
                          color: colors.textTertiary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    )
                  : LiquidFill(fraction: capacity / 100),
            ),
            const SizedBox(height: 8),
            _BatteryStatusLine(battery: battery, l10n: l10n),
          ],
        ),
      ),
    );
  }
}

class _BatteryStatusLine extends StatelessWidget {
  const _BatteryStatusLine({required this.battery, required this.l10n});

  final BatteryStatus battery;
  final AppLocalizations l10n;

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
        colors.textTertiary,
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
        colors.textSecondary,
      ),
      _ => (
        Icons.battery_full_rounded,
        l10n.batteryOnBattery,
        colors.textSecondary,
      ),
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
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.none,
            ),
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
