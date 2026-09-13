import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Shared expressive-star decoration for dashboard metric cards.
///
/// The vertex count is driven by a 0-1 "complexity" signal — a four-point bud
/// at rest that blooms into an eight-point star under full load — which is the
/// shell's M3E "shape as state" idiom. The painter is static: repaints are
/// driven only by the host metric changing, so no idle ticker runs for it.
class ExpressivePolygon extends StatelessWidget {
  const ExpressivePolygon({
    super.key,
    required this.complexity,
    required this.color,
  });

  /// 0-1 load fraction driving the 4 -> 8 vertex morph.
  final double complexity;

  /// Accent family color; the painter derives its fill/stroke alphas.
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: ExpressivePolygonPainter(complexity: complexity, color: color),
      size: Size.infinite,
    );
  }
}

/// Decorative expressive star whose vertex count grows with the metric, per
/// the M3E "shape as state" idea. Purely static: no idle ticker runs for it.
class ExpressivePolygonPainter extends CustomPainter {
  const ExpressivePolygonPainter({
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
  bool shouldRepaint(ExpressivePolygonPainter oldDelegate) =>
      oldDelegate.complexity != complexity || oldDelegate.color != color;
}
