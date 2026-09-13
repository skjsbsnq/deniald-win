import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../../../../theme/shell_theme.dart';
import '../../../../theme/tokens.dart';
import '../dashboard_card_tone.dart';

/// Aggregate interface throughput card: a secondary-family tonal card with a
/// direction glyph chip and one emphasized rate line per direction.
class NetworkMetricCard extends StatelessWidget {
  const NetworkMetricCard({
    super.key,
    required this.label,
    required this.downloadBytesPerSecond,
    required this.uploadBytesPerSecond,
    this.tone = DashboardCardTone.secondary,
  });

  final String label;

  /// Bytes per second across all interfaces, or null before two counter
  /// samples exist.
  final double? downloadBytesPerSecond;
  final double? uploadBytesPerSecond;

  /// Tonal family of the card fill and its foreground roles; the network
  /// card defaults to the secondary family per the mixed-emphasis grid.
  final DashboardCardTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final toneColors = dashboardCardToneColors(
      theme,
      context.shellColors,
      tone,
    );

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
                Icon(
                  Icons.swap_vert_rounded,
                  size: 16,
                  color: toneColors.accent,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.text.labelMediumEmphasized.copyWith(
                      color: toneColors.foregroundSecondary,
                    ),
                  ),
                ),
              ],
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
                    emphasized: true,
                    accent: toneColors.accent,
                    foreground: toneColors.foreground,
                  ),
                  const SizedBox(height: 8),
                  _RateRow(
                    icon: Icons.arrow_upward_rounded,
                    value: uploadBytesPerSecond,
                    emphasized: false,
                    accent: toneColors.foregroundSecondary,
                    foreground: toneColors.foregroundSecondary,
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
    required this.emphasized,
    required this.accent,
    required this.foreground,
  });

  final IconData icon;
  final double? value;
  final bool emphasized;
  final Color accent;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: accent.withValues(alpha: emphasized ? 0.20 : 0.12),
          ),
          child: Center(child: Icon(icon, size: 14, color: accent)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            formatDataRate(value),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style:
                (emphasized
                        ? theme.text.titleSmallEmphasized
                        : theme.text.titleSmall)
                    .copyWith(color: foreground),
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
