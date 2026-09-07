import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../../../../theme/shell_color_scheme.dart';
import '../../../../theme/shell_theme.dart';
import '../../../../theme/tokens.dart';

/// Aggregate interface throughput card with one row per direction.
class NetworkMetricCard extends StatelessWidget {
  const NetworkMetricCard({
    super.key,
    required this.label,
    required this.downloadBytesPerSecond,
    required this.uploadBytesPerSecond,
  });

  final String label;

  /// Bytes per second across all interfaces, or null before two counter
  /// samples exist.
  final double? downloadBytesPerSecond;
  final double? uploadBytesPerSecond;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = context.shellColors;

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
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
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
                    iconColor: theme.accentPalette.primary,
                    colors: colors,
                  ),
                  const SizedBox(height: 8),
                  _RateRow(
                    icon: Icons.arrow_upward_rounded,
                    value: uploadBytesPerSecond,
                    iconColor: colors.textSecondary,
                    colors: colors,
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
    required this.colors,
  });

  final IconData icon;
  final double? value;
  final Color iconColor;
  final ShellColorScheme colors;

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
              color: colors.textPrimary,
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
