import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../../../../theme/shell_theme.dart';
import '../../../../theme/tokens.dart';

/// Aggregate interface throughput card with one row per direction.
class NetworkMetricCard extends StatelessWidget {
  const NetworkMetricCard({
    super.key,
    required this.label,
    required this.downloadBytesPerSecond,
    required this.uploadBytesPerSecond,
    this.surfaceColor,
    this.contentColor,
    this.mutedContentColor,
    this.accentColor,
  });

  final String label;

  /// Bytes per second across all interfaces, or null before two counter
  /// samples exist.
  final double? downloadBytesPerSecond;
  final double? uploadBytesPerSecond;

  /// clavis card-surface override; defaults to the panel surface.
  final Color? surfaceColor;

  /// Rate text inside the card.
  final Color? contentColor;

  /// Label and secondary icon color; defaults to the secondary text role.
  final Color? mutedContentColor;

  /// Download-direction icon color; defaults to the accent primary.
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = context.shellColors;
    final strong = contentColor ?? colors.textPrimary;
    final muted = mutedContentColor ?? colors.textSecondary;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: surfaceColor ?? theme.panelColor(colors.surfaceContainer),
        borderRadius: theme.borderRadius(ShellShapeScale.large),
        border: Border.all(color: colors.hairlineSoft, width: 1.0),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: muted,
                fontSize: 12,
                fontWeight: FontWeight.w600,

                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(height: 10),
            // Fixed zone matching the liquid card's fill+value block keeps
            // the paired grid cards equally tall inside the scroll view.
            SizedBox(
              height: 67,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _RateRow(
                    icon: Icons.arrow_downward_rounded,
                    value: downloadBytesPerSecond,
                    iconColor: accentColor ?? theme.accentPalette.primary,
                    textColor: strong,
                  ),
                  const SizedBox(height: 8),
                  _RateRow(
                    icon: Icons.arrow_upward_rounded,
                    value: uploadBytesPerSecond,
                    iconColor: muted,
                    textColor: strong,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RateRow extends StatelessWidget {
  const _RateRow({
    required this.icon,
    required this.value,
    required this.iconColor,
    required this.textColor,
  });

  final IconData icon;
  final double? value;
  final Color iconColor;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: iconColor),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            formatDataRate(value),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: textColor,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ],
    );
  }
}

/// Human-readable byte rate; null renders as `--` before samples exist.
String formatDataRate(double? bytesPerSecond) {
  if (bytesPerSecond == null || !bytesPerSecond.isFinite) {
    return '--';
  }
  if (bytesPerSecond < 1024) {
    return '${bytesPerSecond.round()} B/s';
  }
  final kibibytes = bytesPerSecond / 1024;
  if (kibibytes < 1024) {
    return '${kibibytes.toStringAsFixed(1)} KB/s';
  }
  return '${(kibibytes / 1024).toStringAsFixed(1)} MB/s';
}
