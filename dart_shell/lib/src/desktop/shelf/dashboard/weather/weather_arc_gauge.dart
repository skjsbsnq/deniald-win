import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Ring gauge of the clavis weather cards (`WeatherArcGauge.qml`): a 10 px
/// round-cap arc that starts at 135° and sweeps 270°, leaving the gap at the
/// bottom, over a track ring tinted at 12 % of the progress color.
class WeatherArcGauge extends StatelessWidget {
  const WeatherArcGauge({
    super.key,
    required this.value,
    required this.maximum,
    required this.progressColor,
    this.thickness = 10,
    this.child,
  });

  final double value;
  final double maximum;
  final Color progressColor;
  final double thickness;

  /// Optional content centered inside the ring (value text, caption).
  final Widget? child;

  /// Reference geometry (`WeatherArcGauge.qml`): the arc opens at the lower
  /// left, sweeps clockwise and leaves a 90° gap at the bottom.
  static const double startAngleDegrees = 135;
  static const double sweepAngleDegrees = 270;

  @override
  Widget build(BuildContext context) {
    final ratio = maximum > 0
        ? (value / maximum).clamp(0.0, 1.0).toDouble()
        : 0.0;
    return CustomPaint(
      painter: _ArcGaugePainter(
        ratio: ratio,
        progressColor: progressColor,
        trackColor: progressColor.withValues(alpha: 0.12),
        thickness: thickness,
        startAngle: startAngleDegrees * math.pi / 180,
        sweepAngle: sweepAngleDegrees * math.pi / 180,
      ),
      child: child == null ? null : Center(child: child),
    );
  }
}

class _ArcGaugePainter extends CustomPainter {
  const _ArcGaugePainter({
    required this.ratio,
    required this.progressColor,
    required this.trackColor,
    required this.thickness,
    required this.startAngle,
    required this.sweepAngle,
  });

  final double ratio;
  final Color progressColor;
  final Color trackColor;
  final double thickness;
  final double startAngle;
  final double sweepAngle;

  @override
  void paint(Canvas canvas, Size size) {
    final gaugeRadius = math.max(
      0.0,
      math.min(size.width, size.height) / 2 - thickness / 2 - 3,
    );
    if (gaugeRadius <= 0) {
      return;
    }
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: gaugeRadius.toDouble(),
    );
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, startAngle, sweepAngle, false, trackPaint);

    if (ratio > 0) {
      final progressPaint = Paint()
        ..color = progressColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = thickness
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        rect,
        startAngle,
        sweepAngle * ratio,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_ArcGaugePainter oldDelegate) {
    return oldDelegate.ratio != ratio ||
        oldDelegate.progressColor != progressColor ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.thickness != thickness;
  }
}
