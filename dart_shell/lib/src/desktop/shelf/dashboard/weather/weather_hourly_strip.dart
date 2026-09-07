import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../../services/weather_service.dart';
import '../../../../theme/shell_theme.dart';
import 'weather_hero_section.dart';

/// Horizontal scrolling forecast band: one column per upcoming hour with the
/// time, condition icon, a temperature chip whose vertical position traces a
/// smoothed polyline across the strip, and the precipitation probability.
class WeatherHourlyStrip extends StatelessWidget {
  const WeatherHourlyStrip({
    super.key,
    required this.hours,
    required this.days,
  });

  /// Full hourly series; entries at or before [now] are skipped.
  final List<WeatherHour> hours;

  /// Daily entries used to resolve day/night per hour.
  final List<WeatherDay> days;

  static const double _itemWidth = 58;
  static const double _timeLabelHeight = 14;
  static const double _iconZoneHeight = 24;
  static const double _curveZoneHeight = 48;
  static const double _precipLabelHeight = 14;
  static const double _chipHeight = 12;
  static const double _gap = 6;

  static const double _stripHeight =
      _timeLabelHeight +
      _gap +
      _iconZoneHeight +
      _gap +
      _curveZoneHeight +
      _gap +
      _precipLabelHeight;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = context.shellColors;
    final isZh = Localizations.localeOf(context).languageCode == 'zh';

    final now = DateTime.now();
    final upcoming = hours
        .where((hour) => hour.time.isAfter(now))
        .take(24)
        .toList(growable: false);
    if (upcoming.isEmpty) {
      return const SizedBox.shrink();
    }

    final dayByDate = <DateTime, WeatherDay>{
      for (final day in days)
        DateTime(day.date.year, day.date.month, day.date.day): day,
    };

    var minimum = upcoming.first.temperatureC;
    var maximum = upcoming.first.temperatureC;
    for (final hour in upcoming) {
      minimum = math.min(minimum, hour.temperatureC);
      maximum = math.max(maximum, hour.temperatureC);
    }
    final span = maximum - minimum;

    return SizedBox(
      height: _stripHeight,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: upcoming.length * _itemWidth,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _HourlyCurvePainter(
                    temperatures: <double>[
                      for (final hour in upcoming) hour.temperatureC,
                    ],
                    minimum: minimum,
                    span: span,
                    lineColor: theme.accentPalette.primary,
                  ),
                ),
              ),
              Row(
                children: <Widget>[
                  for (final hour in upcoming)
                    SizedBox(
                      width: _itemWidth,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            height: _timeLabelHeight,
                            child: Center(
                              child: Text(
                                isZh
                                    ? '${hour.time.hour}时'
                                    : '${hour.time.hour.toString().padLeft(2, '0')}:00',
                                style: TextStyle(
                                  color: colors.textTertiary,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: _gap),
                          SizedBox(
                            height: _iconZoneHeight,
                            child: Center(
                              child: Icon(
                                weatherConditionFor(hour.weatherCode).icon(
                                  day: isDaylight(
                                    hour.time,
                                    _dayFor(hour, dayByDate),
                                  ),
                                ),
                                size: 20,
                                color: colors.textSecondary,
                              ),
                            ),
                          ),
                          const SizedBox(height: _gap),
                          SizedBox(
                            height: _curveZoneHeight,
                            child: Align(
                              alignment: Alignment(
                                0,
                                _chipAlignment(
                                  hour.temperatureC,
                                  minimum,
                                  span,
                                ),
                              ),
                              child: Text(
                                '${hour.temperatureC.round()}°',
                                style: TextStyle(
                                  color: colors.textPrimary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  height: _chipHeight / 11,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: _gap),
                          SizedBox(
                            height: _precipLabelHeight,
                            child: Center(
                              child: Text(
                                '${hour.precipitationProbability}%',
                                style: TextStyle(
                                  color: hour.precipitationProbability >= 40
                                      ? theme.accentPalette.primary
                                      : colors.textTertiary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static WeatherDay? _dayFor(
    WeatherHour hour,
    Map<DateTime, WeatherDay> dayByDate,
  ) {
    return dayByDate[DateTime(hour.time.year, hour.time.month, hour.time.day)];
  }

  /// Vertical alignment for a temperature chip inside the curve zone; 1 is
  /// the window minimum, -1 the maximum.
  static double _chipAlignment(
    double temperature,
    double minimum,
    double span,
  ) {
    if (span <= 0) {
      return 0;
    }
    final t = ((temperature - minimum) / span).clamp(0.0, 1.0).toDouble();
    return 1 - 2 * t;
  }
}

/// Draws the smoothed temperature curve through the chip centers of the
/// strip. The geometry mirrors the column layout so the line passes exactly
/// behind each chip.
class _HourlyCurvePainter extends CustomPainter {
  const _HourlyCurvePainter({
    required this.temperatures,
    required this.minimum,
    required this.span,
    required this.lineColor,
  });

  final List<double> temperatures;
  final double minimum;
  final double span;
  final Color lineColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (temperatures.length < 2 || size.width <= 0) {
      return;
    }
    final curveTop =
        WeatherHourlyStrip._timeLabelHeight +
        WeatherHourlyStrip._gap +
        WeatherHourlyStrip._iconZoneHeight +
        WeatherHourlyStrip._gap;
    final curveHeight = WeatherHourlyStrip._curveZoneHeight;
    final chipHeight = WeatherHourlyStrip._chipHeight;
    final itemWidth = WeatherHourlyStrip._itemWidth;

    Offset centerOf(int index, double temperature) {
      final t = span <= 0
          ? 0.5
          : ((temperature - minimum) / span).clamp(0.0, 1.0).toDouble();
      // Alignment(0, 1 - 2t) centers the chip at this offset inside the zone.
      final y =
          curveTop +
          curveHeight / 2 +
          (1 - 2 * t) * (curveHeight - chipHeight) / 2;
      return Offset(index * itemWidth + itemWidth / 2, y);
    }

    final points = <Offset>[
      for (var i = 0; i < temperatures.length; i++)
        centerOf(i, temperatures[i]),
    ];

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final previous = points[i - 1];
      final current = points[i];
      final mid = Offset(
        (previous.dx + current.dx) / 2,
        (previous.dy + current.dy) / 2,
      );
      path.quadraticBezierTo(previous.dx, previous.dy, mid.dx, mid.dy);
    }
    path.lineTo(points.last.dx, points.last.dy);

    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_HourlyCurvePainter oldDelegate) =>
      oldDelegate.temperatures != temperatures ||
      oldDelegate.minimum != minimum ||
      oldDelegate.span != span ||
      oldDelegate.lineColor != lineColor;
}
