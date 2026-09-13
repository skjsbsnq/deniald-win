import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../../theme/shell_theme.dart';
import '../../../../theme/tokens.dart';
import '../dashboard_card_tone.dart';

/// One-column metric card whose fill level renders as a liquid wave. Shared
/// by the System memory card and the Weather humidity card.
class LiquidMetricCard extends StatelessWidget {
  const LiquidMetricCard({
    super.key,
    required this.label,
    required this.fraction,
    this.valueLabel,
    this.tone = DashboardCardTone.surface,
  });

  final String label;

  /// 0-1 fill level.
  final double fraction;

  /// Optional bottom line with the raw figures, e.g. `7.8 / 15.4 GB`.
  final String? valueLabel;

  /// Tonal family of the card fill and its foreground roles.
  final DashboardCardTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = context.shellColors;
    final toneColors = dashboardCardToneColors(theme, colors, tone);
    final level = fraction.clamp(0.0, 1.0).toDouble();

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
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.text.labelMediumEmphasized.copyWith(
                      color: toneColors.foregroundSecondary,
                    ),
                  ),
                ),
                Text(
                  '${(level * 100).round()}%',
                  style: theme.text.titleSmallEmphasized.copyWith(
                    color: toneColors.foreground,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 46,
              child: LiquidFill(fraction: level, color: toneColors.accent),
            ),
            // The bottom line reserves its height even when absent so every
            // card in the two-column grid stays equally tall.
            if (valueLabel != null) ...[
              const SizedBox(height: 8),
              Text(
                valueLabel!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.text.labelSmall.copyWith(
                  color: toneColors.foregroundSecondary,
                ),
              ),
            ] else
              const SizedBox(height: 21),
          ],
        ),
      ),
    );
  }
}

/// Bare liquid fill for a container of any size: two overlapping static sine
/// crests suggest water without an idle ticker animating them.
class LiquidFill extends StatelessWidget {
  const LiquidFill({super.key, required this.fraction, this.color});

  /// 0-1 fill level.
  final double fraction;

  /// Wave color; defaults to the accent primary when omitted.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = context.shellColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: theme.borderRadius(ShellShapeScale.small),
      ),
      child: ClipRRect(
        borderRadius: theme.borderRadius(ShellShapeScale.small),
        child: CustomPaint(
          painter: _LiquidWavePainter(
            fraction: fraction.clamp(0.0, 1.0).toDouble(),
            color: color ?? theme.accentPalette.primary,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _LiquidWavePainter extends CustomPainter {
  const _LiquidWavePainter({required this.fraction, required this.color});

  final double fraction;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) {
      return;
    }
    final level = size.height * (1 - fraction.clamp(0.0, 1.0));
    if (fraction <= 0) {
      return;
    }

    for (final (phase, alpha) in <(double, double)>[
      (0.6, 0.38),
      (math.pi, 0.72),
    ]) {
      final path = Path()..moveTo(0, size.height);
      final waveLength = math.max(24.0, size.width / 1.6);
      final amplitude = 2.4;
      for (var x = 0.0; x <= size.width; x += 2) {
        final y =
            level +
            math.sin((x / waveLength) * 2 * math.pi + phase) * amplitude +
            amplitude;
        path.lineTo(x, y.clamp(0, size.height));
      }
      path
        ..lineTo(size.width, size.height)
        ..close();
      canvas.drawPath(path, Paint()..color = color.withValues(alpha: alpha));
    }
  }

  @override
  bool shouldRepaint(_LiquidWavePainter oldDelegate) =>
      oldDelegate.fraction != fraction || oldDelegate.color != color;
}
