import 'dart:math' as math;

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
      child: ClipRRect(
        borderRadius: theme.borderRadius(ShellShapeScale.large),
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
                            color: colors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,

                            decoration: TextDecoration.none,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          usage == null ? '--' : '${(usage! * 100).round()}%',
                          style: TextStyle(
                            color: colors.textPrimary,
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
                        lineColor: theme.accentPalette.primary,
                        fillColor: theme.accentPalette.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (showExpressivePolygon)
              Positioned(
                right: -18,
                bottom: -18,
                child: SizedBox.square(
                  dimension: 96,
                  child: CustomPaint(
                    painter: _ExpressivePolygonPainter(
                      // The decoration blooms from a four-point bud at idle to
                      // an eight-point star under full load.
                      complexity: usage ?? 0,
                      color: theme.accentPalette.primary,
                    ),
                  ),
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

/// Decorative expressive star whose vertex count grows with the metric, per
/// the M3E "shape as state" idea. Purely static: no idle ticker runs for it.
class _ExpressivePolygonPainter extends CustomPainter {
  const _ExpressivePolygonPainter({
    required this.complexity,
    required this.color,
  });

  /// 0-1 load fraction driving 4 -> 8 points.
  final double complexity;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2;
    final points = 4 + (complexity.clamp(0.0, 1.0) * 4).round();
    final inner = radius * 0.44;

    final path = Path();
    for (var i = 0; i < points * 2; i++) {
      final angle = -math.pi / 2 + i * math.pi / points;
      final r = i.isEven ? radius : inner;
      final point = Offset(
        center.dx + math.cos(angle) * r,
        center.dy + math.sin(angle) * r,
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();

    canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.10));
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: 0.28)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_ExpressivePolygonPainter oldDelegate) =>
      oldDelegate.complexity != complexity || oldDelegate.color != color;
}
