import 'dart:math' as math;

import 'package:androidx_graphics_shapes/material_shapes.dart';
import 'package:androidx_graphics_shapes/shapes.dart' show RoundedPolygon;
import 'package:flutter/widgets.dart';

import '../../../../theme/shell_theme.dart';
import '../../../../theme/tokens.dart';

/// One-column metric card whose fill level renders as a liquid wave. Shared
/// by the System memory card and the Weather humidity card.
class LiquidMetricCard extends StatelessWidget {
  const LiquidMetricCard({
    super.key,
    required this.label,
    required this.fraction,
    this.valueLabel,
    this.surfaceColor,
    this.contentColor,
    this.mutedContentColor,
    this.fillColor,
    this.shape,
  });

  final String label;

  /// 0-1 fill level.
  final double fraction;

  /// Optional bottom line with the raw figures, e.g. `7.8 / 15.4 GB`.
  final String? valueLabel;

  /// clavis card-surface override; defaults to the panel surface.
  final Color? surfaceColor;

  /// Strong text inside the card (the percentage readout).
  final Color? contentColor;

  /// Label and caption text; defaults to the secondary/tertiary text roles.
  final Color? mutedContentColor;

  /// Liquid fill wave color; defaults to the accent primary.
  final Color? fillColor;

  /// clavis expressive surface: when set the card surface is clipped to this
  /// normalized polygon (`MaterialShapes.*`) stretched to the tile bounds
  /// and the rectangular border drops out, like the reference shell's
  /// `MaterialShape` cards.
  final RoundedPolygon? shape;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = context.shellColors;
    final level = fraction.clamp(0.0, 1.0).toDouble();
    final surface = surfaceColor ?? theme.panelColor(colors.surfaceContainer);
    final strong = contentColor ?? colors.textPrimary;
    final muted = mutedContentColor ?? colors.textSecondary;
    final polygon = shape;

    final card = DecoratedBox(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: polygon == null
            ? theme.borderRadius(ShellShapeScale.large)
            : null,
        border: polygon == null
            ? Border.all(color: colors.hairlineSoft, width: 1.0)
            : null,
      ),
      child: Padding(
        // A polygon surface loses usable corner area, so shaped cards pad a
        // little deeper than the rectangular ones.
        padding: polygon == null
            ? const EdgeInsets.fromLTRB(14, 12, 14, 12)
            : const EdgeInsets.fromLTRB(20, 16, 20, 16),
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
                    style: TextStyle(
                      color: muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,

                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
                Text(
                  '${(level * 100).round()}%',
                  style: TextStyle(
                    color: strong,
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
              child: LiquidFill(
                fraction: level,
                color: fillColor,
                trackColor: fillColor?.withValues(alpha: 0.18),
              ),
            ),
            // The bottom line reserves its height even when absent so every
            // card in the two-column grid stays equally tall.
            if (valueLabel != null) ...[
              const SizedBox(height: 8),
              Text(
                valueLabel!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: mutedContentColor ?? colors.textTertiary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.none,
                ),
              ),
            ] else
              const SizedBox(height: 21),
          ],
        ),
      ),
    );
    if (polygon == null) {
      return card;
    }
    return ClipPath(clipper: _PolygonClipper(polygon), child: card);
  }
}

/// Clips a normalized [RoundedPolygon] (the `MaterialShapes` catalog works
/// in a 0-1 square) into the card's tile bounds.
class _PolygonClipper extends CustomClipper<Path> {
  const _PolygonClipper(this.polygon);

  final RoundedPolygon polygon;

  @override
  Path getClip(Size size) {
    final path = polygon.toPath();
    final bounds = path.getBounds();
    if (bounds.width <= 0 || bounds.height <= 0) {
      return path;
    }
    return path.transform(
      (Matrix4.diagonal3Values(
                size.width / bounds.width,
                size.height / bounds.height,
                1,
              ) *
              Matrix4.translationValues(-bounds.left, -bounds.top, 0))
          .storage,
    );
  }

  @override
  bool shouldReclip(_PolygonClipper oldClipper) =>
      !identical(oldClipper.polygon, polygon);
}

/// Bare liquid fill for a container of any size: two overlapping static sine
/// crests suggest water without an idle ticker animating them.
class LiquidFill extends StatelessWidget {
  const LiquidFill({
    super.key,
    required this.fraction,
    this.color,
    this.trackColor,
  });

  /// 0-1 fill level.
  final double fraction;

  /// Wave color; defaults to the accent primary.
  final Color? color;

  /// Empty-track color; defaults to the highest surface role.
  final Color? trackColor;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = context.shellColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: trackColor ?? colors.surfaceContainerHighest,
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
