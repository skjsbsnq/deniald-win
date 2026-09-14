import 'dart:math' as math;

import 'package:androidx_graphics_shapes/material_shapes.dart';
import 'package:androidx_graphics_shapes/shapes.dart' show RoundedPolygon;
import 'package:flutter/widgets.dart';

import '../../../../theme/shell_theme.dart';

/// clavis `SystemLiquidMetricCard`: the memory card's fill level renders as
/// a liquid wave inside a centered, aspect-preserved [RoundedPolygon]
/// vessel (`MaterialShapes.*`) — the shape itself is the container and the
/// tile keeps no rectangular surface.
class LiquidMetricCard extends StatelessWidget {
  const LiquidMetricCard({
    super.key,
    required this.label,
    required this.fraction,
    required this.shape,
    this.valueLabel,
    this.icon,
    this.surfaceColor,
    this.contentColor,
    this.fillColor,
  });

  /// Accessible name of the metric; the vessel's content is icon + value.
  final String label;

  /// 0-1 fill level.
  final double fraction;

  /// Optional bottom line with the raw figures, e.g. `7.8 / 15.4 GB`.
  final String? valueLabel;

  /// Glyph centered inside the vessel (clavis `MaterialSymbol`).
  final IconData? icon;

  /// clavis card-surface override; defaults to the panel surface.
  final Color? surfaceColor;

  /// Strong text inside the vessel (the percentage readout).
  final Color? contentColor;

  /// Liquid fill wave color; defaults to the accent primary.
  final Color? fillColor;

  /// The vessel silhouette (`MaterialShapes.*`).
  final RoundedPolygon shape;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = context.shellColors;
    final level = fraction.clamp(0.0, 1.0).toDouble();
    final surface = surfaceColor ?? theme.panelColor(colors.surfaceContainer);
    final strong = contentColor ?? colors.textPrimary;
    return Semantics(
      label: label,
      child: _ShapedVesselCard(
        polygon: shape,
        level: level,
        icon: icon,
        valueText: '${(level * 100).round()}%',
        supportingText: valueLabel,
        surface: surface,
        contentColor: strong,
        fillColor: fillColor ?? theme.accentPalette.primary,
        shadowColor: colors.shadow.withValues(alpha: 0.4),
      ),
    );
  }
}

/// clavis `SystemLiquidMetricCard`: the polygon itself is the card surface —
/// a `min(w, h) - 8` square centered in the tile, liquid clipped to the
/// silhouette, icon + value + caption stacked inside. The shape is painted
/// by [PhysicalShape] so the drop shadow follows the silhouette like the
/// reference shell's `MaterialShape` shadow layer.
class _ShapedVesselCard extends StatelessWidget {
  const _ShapedVesselCard({
    required this.polygon,
    required this.level,
    required this.valueText,
    required this.surface,
    required this.contentColor,
    required this.fillColor,
    required this.shadowColor,
    this.icon,
    this.supportingText,
  });

  final RoundedPolygon polygon;
  final double level;
  final IconData? icon;
  final String valueText;
  final String? supportingText;
  final Color surface;
  final Color contentColor;
  final Color fillColor;
  final Color shadowColor;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // clavis shapeFrame: max(72, min(w, h) - spacing.small).
        final side = math
            .max(
              72.0,
              math.min(constraints.maxWidth, constraints.maxHeight) - 8,
            )
            .toDouble();
        return Center(
          child: SizedBox.square(
            dimension: side,
            child: PhysicalShape(
              clipper: ShapeBorderClipper(
                shape: RoundedPolygonBorder(polygon: polygon),
              ),
              clipBehavior: Clip.antiAlias,
              color: surface,
              shadowColor: shadowColor,
              elevation: 4,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CustomPaint(
                    painter: _VesselWavePainter(
                      fraction: level,
                      color: fillColor,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      children: [
                        const Spacer(),
                        if (icon != null)
                          Icon(icon, size: 28, color: contentColor),
                        Text(
                          valueText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: contentColor,
                            fontSize: 28,
                            fontWeight: FontWeight.w600,
                            fontFeatures: const <FontFeature>[
                              FontFeature.tabularFigures(),
                            ],
                            decoration: TextDecoration.none,
                          ),
                        ),
                        if (supportingText != null)
                          Text(
                            supportingText!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: contentColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        const Spacer(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Bottom-up liquid fill with the clavis scalloped crest: the surface wave
/// runs four quadratic bump pairs across the width with an amplitude of
/// `min(3.5, h * 0.035)` and a quarter-width wavelength. Static painter — no
/// idle ticker, the level only moves on telemetry ticks.
class _VesselWavePainter extends CustomPainter {
  const _VesselWavePainter({required this.fraction, required this.color});

  final double fraction;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) {
      return;
    }
    final level = fraction.clamp(0.0, 1.0).toDouble();
    if (level <= 0) {
      return;
    }
    // The crest hovers on the level line: `top` is the wave's upper edge,
    // and the scallops oscillate between it and `top + 2 * amplitude`.
    final top = size.height * (1 - level) - 4;
    final amplitude = math.min(3.5, size.height * 0.035);
    final waveLength = size.width / 4;
    final path = Path()..moveTo(0, top + amplitude);
    for (var x = 0.0; x < size.width; x += waveLength) {
      final half = waveLength / 2;
      path
        ..quadraticBezierTo(x + half / 2, top, x + half, top + amplitude)
        ..quadraticBezierTo(
          x + half + half / 2,
          top + amplitude * 2,
          x + waveLength,
          top + amplitude,
        );
    }
    path
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_VesselWavePainter oldDelegate) =>
      oldDelegate.fraction != fraction || oldDelegate.color != color;
}
