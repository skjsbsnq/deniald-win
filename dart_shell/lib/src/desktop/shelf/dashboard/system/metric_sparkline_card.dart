import 'dart:math' as math;

import 'package:androidx_graphics_shapes/material_shapes.dart';
import 'package:androidx_graphics_shapes/shapes.dart' show RoundedPolygon;
import 'package:flutter/widgets.dart';

import '../../../../theme/shell_theme.dart';
import '../../../../theme/tokens.dart';

/// Usage card with a large live percentage and a smoothed history sparkline
/// under a gradient fill, shared by the CPU card and every GPU card.
class MetricSparklineCard extends StatelessWidget {
  const MetricSparklineCard({
    super.key,
    required this.label,
    required this.usage,
    required this.history,
    this.detail,
    this.showExpressivePolygon = false,
    this.decorationShape,
    this.decorationIcon,
    this.decorationForeground,
    this.surfaceColor,
    this.contentColor,
    this.mutedContentColor,
    this.accentColor,
  });

  final String label;

  /// Current usage as a 0-1 fraction, or null before telemetry exists.
  final double? usage;

  /// Rolling samples, oldest first; the newest equals [usage].
  final List<double> history;

  /// Extra identity chips (core count, temperature) rendered under the label.
  final Widget? detail;

  /// Whether to draw the expressive corner polygon that blooms with load.
  final bool showExpressivePolygon;

  /// clavis `shapeOverride`: pins the corner decoration to one
  /// `MaterialShapes` polygon (gpu uses Gem) instead of picking by load.
  final RoundedPolygon? decorationShape;

  /// Icon centered inside the corner decoration (clavis `MaterialSymbol`).
  final IconData? decorationIcon;

  /// Color of [decorationIcon]; defaults to the accent's "on" role.
  final Color? decorationForeground;

  /// clavis card-surface override; defaults to the panel surface.
  final Color? surfaceColor;

  /// Strong text inside the card (the percentage readout).
  final Color? contentColor;

  /// Label text; defaults to the secondary text role.
  final Color? mutedContentColor;

  /// Sparkline stroke/fill and polygon decoration; defaults to accent
  /// primary.
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = context.shellColors;
    final accent = accentColor ?? theme.accentPalette.primary;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: surfaceColor ?? theme.panelColor(colors.surfaceContainer),
        borderRadius: theme.borderRadius(ShellShapeScale.extraLarge),
        boxShadow: <BoxShadow>[
          // clavis MultiEffect card shadow: +4 y, low alpha, heavy blur.
          BoxShadow(
            color: colors.shadow.withValues(alpha: 0.4),
            offset: const Offset(0, 4),
            blurRadius: 18,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: theme.borderRadius(ShellShapeScale.extraLarge),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: mutedContentColor ?? colors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,

                            decoration: TextDecoration.none,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          usage == null ? '--' : '${(usage! * 100).round()}%',
                          style: TextStyle(
                            color: contentColor ?? colors.textPrimary,
                            fontSize: 30,
                            fontWeight: FontWeight.w700,
                            height: 1.05,
                            fontFeatures: const <FontFeature>[
                              FontFeature.tabularFigures(),
                            ],
                            decoration: TextDecoration.none,
                          ),
                        ),
                        if (detail != null) ...[
                          const SizedBox(height: 6),
                          detail!,
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 132,
                    height: 76,
                    // The series repaints on every telemetry tick, so the
                    // boundary keeps that damage confined to its own layer.
                    child: RepaintBoundary(
                      child: MetricSparkline(
                        history: history,
                        lineColor: accent,
                        fillColor: accent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (showExpressivePolygon)
              Positioned.fill(
                child: _ExpressiveDecoration(
                  usage: usage,
                  accentColor: accent,
                  shapeOverride: decorationShape,
                  icon: decorationIcon,
                  iconColor:
                      decorationForeground ?? theme.accentPalette.onPrimary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Smoothed sparkline with a gradient fill under the curve.
class MetricSparkline extends StatelessWidget {
  const MetricSparkline({
    super.key,
    required this.history,
    required this.lineColor,
    required this.fillColor,
    this.strokeWidth = 2.0,
  });

  final List<double> history;
  final Color lineColor;
  final Color fillColor;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _MetricSparklinePainter(
        history: history,
        lineColor: lineColor,
        fillColor: fillColor,
        strokeWidth: strokeWidth,
      ),
      size: Size.infinite,
    );
  }
}

class _MetricSparklinePainter extends CustomPainter {
  const _MetricSparklinePainter({
    required this.history,
    required this.lineColor,
    required this.fillColor,
    required this.strokeWidth,
  });

  final List<double> history;
  final Color lineColor;
  final Color fillColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (history.length < 2 || size.width <= 0 || size.height <= 0) {
      if (history.length == 1 && size.width > 0) {
        // A single sample still shows a dot so the card does not look dead.
        final paint = Paint()
          ..color = lineColor
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round;
        canvas.drawCircle(
          Offset(size.width / 2, _y(history[0], size)),
          strokeWidth / 2,
          paint,
        );
      }
      return;
    }

    final points = <Offset>[
      for (var i = 0; i < history.length; i++)
        Offset(i * size.width / (history.length - 1), _y(history[i], size)),
    ];

    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final previous = points[i - 1];
      final current = points[i];
      // Quadratic segments through segment midpoints keep the curve smooth
      // without overshooting between samples.
      final mid = Offset(
        (previous.dx + current.dx) / 2,
        (previous.dy + current.dy) / 2,
      );
      line.quadraticBezierTo(previous.dx, previous.dy, mid.dx, mid.dy);
    }
    line.lineTo(points.last.dx, points.last.dy);

    final fill = Path.from(line)
      ..lineTo(points.last.dx, size.height)
      ..lineTo(points.first.dx, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            fillColor.withValues(alpha: 0.34),
            fillColor.withValues(alpha: 0.0),
          ],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  static double _y(double sample, Size size) {
    final t = sample.clamp(0.0, 1.0).toDouble();
    return size.height - size.height * t;
  }

  @override
  bool shouldRepaint(_MetricSparklinePainter oldDelegate) =>
      oldDelegate.history != history ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.fillColor != fillColor ||
      oldDelegate.strokeWidth != strokeWidth;
}

/// clavis `ExpressiveMetricTile` corner decoration: a filled `MaterialShapes`
/// polygon anchored to the card's lower-right corner with negative margins,
/// rotated +18°, carrying a counter-rotated icon. Which polygon shows is
/// picked from the load level — idle or unreadable renders Cookie4Sided,
/// medium Sunny, high SoftBurst — unless [shapeOverride] pins one.
class _ExpressiveDecoration extends StatelessWidget {
  const _ExpressiveDecoration({
    required this.usage,
    required this.accentColor,
    required this.iconColor,
    this.shapeOverride,
    this.icon,
  });

  final double? usage;
  final Color accentColor;
  final Color iconColor;
  final RoundedPolygon? shapeOverride;
  final IconData? icon;

  static RoundedPolygon _shapeFor(double? usage) {
    final level = usage ?? -1.0;
    if (level < 0) {
      return MaterialShapes.cookie4Sided;
    }
    if (level >= 0.82) {
      return MaterialShapes.softBurst;
    }
    if (level >= 0.48) {
      return MaterialShapes.sunny;
    }
    return MaterialShapes.cookie4Sided;
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final level = (usage ?? -1.0).clamp(0.0, 1.0);
          final dense =
              constraints.maxWidth < 210 || constraints.maxHeight < 190;
          // clavis: implicitSize = min(w * 0.38, h * 0.42, base 50 grown
          // slightly with load); the shape overflows the card corner by
          // 18%/20% of its size.
          final side = math.min(
            constraints.maxWidth * 0.38,
            math.min(constraints.maxHeight * 0.42, 50 * (1.08 + level * 0.14)),
          );
          return Align(
            alignment: Alignment.bottomRight,
            child: Transform.translate(
              offset: Offset(side * 0.18, side * 0.2),
              child: Transform.rotate(
                angle: 18 * math.pi / 180,
                child: SizedBox.square(
                  dimension: side,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CustomPaint(
                        painter: _FilledPolygonPainter(
                          polygon: shapeOverride ?? _shapeFor(usage),
                          color: accentColor,
                        ),
                      ),
                      if (icon != null)
                        Center(
                          child: Transform.rotate(
                            angle: -12 * math.pi / 180,
                            child: Icon(
                              icon,
                              size: dense ? 21 : 25,
                              color: iconColor,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Paints a normalized `MaterialShapes` [RoundedPolygon] scaled into the box
/// it is given, preserving aspect ratio and centering.
class _FilledPolygonPainter extends CustomPainter {
  const _FilledPolygonPainter({required this.polygon, required this.color});

  final RoundedPolygon polygon;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) {
      return;
    }
    final path = polygon.toPath();
    final bounds = path.getBounds();
    if (bounds.width <= 0 || bounds.height <= 0) {
      return;
    }
    final scale = math.min(
      size.width / bounds.width,
      size.height / bounds.height,
    );
    final matrix = Matrix4.translationValues(size.width / 2, size.height / 2, 0)
      ..multiply(Matrix4.diagonal3Values(scale, scale, 1))
      ..multiply(
        Matrix4.translationValues(-bounds.center.dx, -bounds.center.dy, 0),
      );
    canvas.drawPath(path.transform(matrix.storage), Paint()..color = color);
  }

  @override
  bool shouldRepaint(_FilledPolygonPainter oldDelegate) =>
      !identical(oldDelegate.polygon, polygon) || oldDelegate.color != color;
}
