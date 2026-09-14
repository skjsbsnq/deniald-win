import 'dart:math' as math;

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../../../../../l10n/generated/app_localizations.dart';
import '../../../../localization/denial_localizations.dart';
import '../../../../models/battery_status.dart';
import '../../../../services/system_hardware_service.dart';
import '../../../../theme/shell_color_scheme.dart';
import '../../../../theme/shell_theme.dart';
import '../../../../theme/tokens.dart';

/// clavis `SystemStorageCard`: a full-width split hero — the tertiary left
/// ~53% carries the title, a large capacity percentage, and a usage bar;
/// the tertiaryContainer right panel lists used/total and free figures.
///
/// Unlike clavis there is no per-disk I/O history upstream, so the left
/// panel shows the capacity readout instead of a throughput sparkline —
/// no history is synthesized.
class StorageCard extends StatelessWidget {
  const StorageCard({
    super.key,
    required this.storage,
    this.surfaceColor,
    this.contentColor,
    this.mutedContentColor,
    this.panelColor,
    this.panelContentColor,
    this.accentColor,
  });

  /// Latest `df -B1 /` reading; null renders the unavailable state.
  final StorageUsage? storage;

  /// Left panel surface; clavis `surfaceColor` (tertiary).
  final Color? surfaceColor;

  /// Title and value text on the left panel (clavis `leftForeground`).
  final Color? contentColor;

  /// Secondary left-panel text.
  final Color? mutedContentColor;

  /// Right panel surface; clavis `panelColor` (tertiaryContainer).
  final Color? panelColor;

  /// Value text on the right panel (clavis `rightForeground`).
  final Color? panelContentColor;

  /// Usage-bar fill; defaults to the left foreground.
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = context.shellColors;
    final l10n = context.l10n;
    final usage = storage?.fraction ?? 0.0;
    final leftColor = surfaceColor ?? theme.panelColor(colors.surfaceContainer);
    final leftForeground = contentColor ?? colors.textPrimary;
    final leftMuted =
        mutedContentColor ?? leftForeground.withValues(alpha: 0.74);
    final rightColor =
        panelColor ?? theme.panelColor(colors.surfaceContainerHigh);
    final rightForeground = panelContentColor ?? leftForeground;
    final barFill = accentColor ?? leftForeground;
    final radius = theme.borderRadius(ShellShapeScale.extraLarge);

    return LayoutBuilder(
      builder: (context, constraints) {
        // clavis: rightPanelX = round(width * 0.53).
        final rightWidth =
            constraints.maxWidth -
            (constraints.maxWidth * 0.53).roundToDouble();
        final leftWidth = constraints.maxWidth - rightWidth;
        return Container(
          decoration: BoxDecoration(
            color: leftColor,
            borderRadius: radius,
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: colors.shadow.withValues(alpha: 0.4),
                offset: const Offset(0, 4),
                blurRadius: 18,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: Stack(
              children: [
                Positioned(
                  left: 16,
                  top: 14,
                  width: leftWidth - 16,
                  child: Text(
                    l10n.systemStorage,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: leftForeground,
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
                Positioned(
                  left: 16,
                  right: rightWidth + 16,
                  bottom: 14,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        storage == null
                            ? l10n.systemDataUnavailable
                            : '${(usage * 100).round()}%',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: leftForeground,
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          fontFeatures: const <FontFeature>[
                            FontFeature.tabularFigures(),
                          ],
                          decoration: TextDecoration.none,
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (storage != null)
                        ClipRRect(
                          borderRadius: theme.borderRadius(
                            ShellShapeScale.small,
                          ),
                          child: SizedBox(
                            height: 8,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                ColoredBox(
                                  color: barFill.withValues(alpha: 0.2),
                                ),
                                FractionallySizedBox(
                                  alignment: Alignment.centerLeft,
                                  widthFactor: usage.clamp(0.0, 1.0),
                                  child: ColoredBox(color: barFill),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        Text(
                          '—',
                          style: TextStyle(
                            color: leftMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.none,
                          ),
                        ),
                    ],
                  ),
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: rightWidth,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: rightColor,
                      borderRadius: radius,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      child: Column(
                        children: [
                          Expanded(
                            child: _StorageFigure(
                              icon: Icons.storage_rounded,
                              value: storage == null
                                  ? l10n.systemDataUnavailable
                                  : '${formatGigabytes(storage!.used)} / '
                                        '${formatGigabytes(storage!.total)} GB',
                              iconColor: leftColor,
                              textColor: rightForeground,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Expanded(
                            child: _StorageFigure(
                              icon: Icons.sd_card_rounded,
                              value: storage == null
                                  ? '—'
                                  : l10n.systemStorageFree(
                                      formatGigabytes(
                                        storage!.total - storage!.used,
                                      ),
                                    ),
                              iconColor: leftColor,
                              textColor: rightForeground,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// One right-panel figure row: symbol plus a heavy value, clavis
/// `NetworkRate`/`StorageRate` style.
class _StorageFigure extends StatelessWidget {
  const _StorageFigure({
    required this.icon,
    required this.value,
    required this.iconColor,
    required this.textColor,
  });

  final IconData icon;
  final String value;
  final Color iconColor;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 24, color: iconColor),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: textColor,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ],
    );
  }
}

/// clavis `SystemBatteryTank` as the mini 1x1 variant: a rounded vertical
/// battery silhouette — top nub plus a body whose fill rises from the
/// bottom — carrying the percentage and supply status inside the tank.
/// Content is painted twice (once on the tank color, once inside the fill
/// clip with the on-fill foreground) exactly like the clavis levelClip +
/// OpacityMask layering, so text stays readable at every charge level.
class BatteryTankCard extends StatelessWidget {
  const BatteryTankCard({
    super.key,
    required this.battery,
    this.surfaceColor,
    this.contentColor,
    this.mutedContentColor,
    this.fillColor,
    this.onFillColor,
  });

  final BatteryStatus battery;

  /// Tank body surface; clavis `containerColor` (secondaryContainer).
  final Color? surfaceColor;

  /// Foreground on the tank surface (clavis `colOnSecondaryContainer`).
  final Color? contentColor;

  /// Status-line text; defaults to [contentColor] at reduced emphasis.
  final Color? mutedContentColor;

  /// Rising fill level color; clavis `levelColor` (secondary).
  final Color? fillColor;

  /// Foreground for content the fill covers (clavis `colOnSecondary`).
  final Color? onFillColor;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = context.shellColors;
    final l10n = context.l10n;
    final capacity = battery.capacity;
    final level = (capacity ?? 0) / 100.0;
    final bodyColor = surfaceColor ?? theme.panelColor(colors.surfaceContainer);
    final onBody = contentColor ?? colors.textPrimary;
    final muted = mutedContentColor ?? onBody.withValues(alpha: 0.74);
    final fill = fillColor ?? theme.accentPalette.primary;
    final onFill = onFillColor ?? theme.accentPalette.onPrimary;
    final status = _batteryStatus(battery, l10n, muted, colors);

    return LayoutBuilder(
      builder: (context, constraints) {
        // clavis batteryBody: 3 px side margins, 8 px top (under the nub),
        // 2 px bottom; radius = min(rounding.extraLarge, width * 0.16).
        const sideInset = 3.0;
        const topInset = 8.0;
        const bottomInset = 2.0;
        final bodyWidth = math.max(0.0, constraints.maxWidth - sideInset * 2);
        final bodyHeight = math.max(
          0.0,
          constraints.maxHeight - topInset - bottomInset,
        );
        final bodyRadius = theme.borderRadius(
          math.min(ShellShapeScale.extraLarge, bodyWidth * 0.16),
        );
        final nubWidth = (constraints.maxWidth * 0.3).clamp(34.0, 54.0);
        // The status icon sits ~25 px below the body top; once the fill
        // covers it the foreground flips to the on-fill role like clavis.
        final iconCovered = level >= 1 - 25 / math.max(1, bodyHeight);
        final iconColor = iconCovered ? onFill : status.color;

        return Stack(
          children: [
            // Battery nub: centered cap, fill-colored only at 100%.
            Positioned(
              top: 0,
              left: (constraints.maxWidth - nubWidth) / 2,
              width: nubWidth,
              height: 12,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: level >= 1 ? fill : bodyColor,
                  borderRadius: theme.borderRadius(
                    ShellShapeScale.small * 0.75,
                  ),
                ),
              ),
            ),
            Positioned(
              left: sideInset,
              right: sideInset,
              top: topInset,
              bottom: bottomInset,
              child: Container(
                decoration: BoxDecoration(
                  color: bodyColor,
                  borderRadius: bodyRadius,
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: colors.shadow.withValues(alpha: 0.4),
                      offset: const Offset(0, 4),
                      blurRadius: 18,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: bodyRadius,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _TankContents(
                        label: l10n.systemBattery,
                        capacity: capacity,
                        statusLabel: status.label,
                        foreground: onBody,
                        muted: muted,
                        unavailableText: l10n.systemBatteryUnavailable,
                      ),
                      if (capacity != null && level > 0)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          height: bodyHeight * level,
                          child: ClipRect(
                            child: OverflowBox(
                              alignment: Alignment.bottomCenter,
                              minHeight: bodyHeight,
                              maxHeight: bodyHeight,
                              child: SizedBox(
                                height: bodyHeight,
                                child: ColoredBox(
                                  color: fill,
                                  child: _TankContents(
                                    label: l10n.systemBattery,
                                    capacity: capacity,
                                    statusLabel: status.label,
                                    foreground: onFill,
                                    muted: onFill.withValues(alpha: 0.74),
                                    unavailableText:
                                        l10n.systemBatteryUnavailable,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            // Status symbol over the tank's upper-right corner.
            Positioned(
              top: topInset + 10,
              right: sideInset + 12,
              child: Icon(status.icon, size: 26, color: iconColor),
            ),
          ],
        );
      },
    );
  }
}

/// Text inside the battery tank — painted twice (tank surface and inside
/// the fill clip) with different foregrounds, mirroring clavis
/// `BatteryContents`.
class _TankContents extends StatelessWidget {
  const _TankContents({
    required this.label,
    required this.capacity,
    required this.statusLabel,
    required this.foreground,
    required this.muted,
    required this.unavailableText,
  });

  final String label;
  final int? capacity;
  final String statusLabel;
  final Color foreground;
  final Color muted;
  final String unavailableText;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: foreground,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.none,
            ),
          ),
          const Spacer(),
          if (capacity == null)
            Center(
              child: Text(
                unavailableText,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.none,
                ),
              ),
            )
          else ...[
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                statusLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                '$capacity%',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: foreground,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The status triple from the old `_BatteryStatusLine`: icon, localized
/// label, and status color (charging/full keep `performanceGood`).
({IconData icon, String label, Color color}) _batteryStatus(
  BatteryStatus battery,
  AppLocalizations l10n,
  Color muted,
  ShellColorScheme colors,
) {
  return switch ((
    battery.capacity,
    battery.charging,
    battery.full,
    battery.acOnline,
  )) {
    (null, _, _, _) => (
      icon: Icons.battery_0_bar_rounded,
      label: l10n.systemStatusUnavailable,
      color: muted,
    ),
    (_, _, true, _) => (
      icon: Icons.check_rounded,
      label: l10n.batteryFull,
      color: colors.performanceGood,
    ),
    (_, true, _, _) => (
      icon: Icons.bolt_rounded,
      label: l10n.batteryCharging,
      color: colors.performanceGood,
    ),
    (_, _, _, true) => (
      icon: Icons.power_rounded,
      label: l10n.batteryOnAcPower,
      color: muted,
    ),
    _ => (
      icon: Icons.battery_full_rounded,
      label: l10n.batteryOnBattery,
      color: muted,
    ),
  };
}

/// Bytes to a one-decimal GB figure for compact card lines.
String formatGigabytes(int bytes) {
  final gigabytes = bytes / (1024 * 1024 * 1024);
  if (gigabytes >= 100) {
    return gigabytes.round().toString();
  }
  return gigabytes.toStringAsFixed(1);
}
