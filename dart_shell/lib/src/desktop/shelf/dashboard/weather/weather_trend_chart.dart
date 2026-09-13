import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../../../l10n/generated/app_localizations.dart';
import '../../../../localization/denial_localizations.dart';
import '../../../../services/weather_service.dart';
import '../../../../settings/shell_settings.dart';
import '../../../../theme/shell_theme.dart';
import '../../../../theme/tokens.dart';
import 'weather_hero_section.dart';
import 'weather_meteo_icon.dart';
import 'weather_temperature.dart';

/// Pure-canvas forecast chart of the clavis trend cards
/// (`DailyForecastTrendCard`/`HourlyForecastTrendCard` onPaint blocks):
/// an area gradient under the temperature line, a 3 px hourly stroke (4 px
/// for both daily lines), double-circle data points, on-point temperature
/// labels and rounded precipitation bars.
class WeatherTrendChart extends StatelessWidget {
  const WeatherTrendChart({
    super.key,
    required this.values,
    this.lowValues,
    this.precipitationProbabilities,
    this.valueLabels,
    this.fadeFirstBar = false,
  });

  /// Primary series (hourly temperatures or daily highs), one entry per slot.
  final List<double> values;

  /// Optional second series (daily lows); enables the dual-line mode.
  final List<double>? lowValues;

  /// Precipitation probability 0-100 per slot; drawn as rounded bars.
  final List<int>? precipitationProbabilities;

  /// Label drawn above each primary point; falls back to the raw value.
  final List<String>? valueLabels;

  /// Daily cards fade today's probability bar (the day is already spent).
  final bool fadeFirstBar;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = context.shellColors;
    return CustomPaint(
      painter: _TrendChartPainter(
        values: values,
        lowValues: lowValues,
        precipitationProbabilities: precipitationProbabilities,
        valueLabels: valueLabels,
        fadeFirstBar: fadeFirstBar,
        primaryColor: theme.accentPalette.primary,
        secondaryColor: theme.accentPalette.secondary,
        pointInnerColor: colors.surfaceContainer,
        textColor: colors.textPrimary,
        faintTextColor: colors.textTertiary,
        textDirection: Directionality.of(context),
      ),
    );
  }
}

class _TrendChartPainter extends CustomPainter {
  const _TrendChartPainter({
    required this.values,
    required this.lowValues,
    required this.precipitationProbabilities,
    required this.valueLabels,
    required this.fadeFirstBar,
    required this.primaryColor,
    required this.secondaryColor,
    required this.pointInnerColor,
    required this.textColor,
    required this.faintTextColor,
    required this.textDirection,
  });

  final List<double> values;
  final List<double>? lowValues;
  final List<int>? precipitationProbabilities;
  final List<String>? valueLabels;
  final bool fadeFirstBar;
  final Color primaryColor;
  final Color secondaryColor;
  final Color pointInnerColor;
  final Color textColor;
  final Color faintTextColor;
  final TextDirection textDirection;

  // clavis insets: labels sit above the topmost point, the precipitation
  // strip parks at the bottom edge.
  static const double _labelBand = 16;
  static const double _chartTop = _labelBand + 4;
  static const double _popLabelBand = 14;
  static const double _bottomPad = 6;
  static const double _barWidth = 10;
  static const double _hourlyBarBand = 18;

  bool get _dual => lowValues != null && lowValues!.length >= 2;

  @override
  void paint(Canvas canvas, Size size) {
    final count = math.min(values.length, lowValues?.length ?? values.length);
    if (count < 2 || size.width <= 0 || size.height <= _chartTop) {
      return;
    }
    final pops = precipitationProbabilities;
    final hasPops = pops != null && pops.isNotEmpty;

    var min = values.first;
    var max = values.first;
    for (var i = 0; i < count; i++) {
      min = math.min(min, values[i]);
      max = math.max(max, values[i]);
      if (_dual) {
        min = math.min(min, lowValues![i]);
        max = math.max(max, lowValues![i]);
      }
    }
    if ((max - min).abs() < 0.1) {
      max += 1;
      min -= 1;
    }

    final bottomInset =
        _bottomPad + (hasPops ? (_dual ? _popLabelBand : _hourlyBarBand) : 0);
    final chartTop = _chartTop;
    final chartBottom = math.max(chartTop + 24, size.height - bottomInset);
    final itemWidth = size.width / count;

    double pointX(int index) => itemWidth * index + itemWidth / 2;

    double yAt(double value) =>
        chartBottom - (value - min) / (max - min) * (chartBottom - chartTop);

    // Precipitation bars first so the temperature strokes draw over them.
    if (hasPops) {
      _drawPrecipitationBars(
        canvas,
        size,
        count,
        pops,
        pointX,
        chartTop,
        chartBottom,
      );
    }

    // Area fill: between the two lines for the daily card, from the line to
    // the chart floor for the hourly one.
    final fillPath = Path();
    fillPath.moveTo(pointX(0), yAt(values[0]));
    for (var i = 1; i < count; i++) {
      fillPath.lineTo(pointX(i), yAt(values[i]));
    }
    if (_dual) {
      for (var i = count - 1; i >= 0; i--) {
        fillPath.lineTo(pointX(i), yAt(lowValues![i]));
      }
    } else {
      fillPath.lineTo(pointX(count - 1), chartBottom);
      fillPath.lineTo(pointX(0), chartBottom);
    }
    fillPath.close();
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            primaryColor.withValues(alpha: _dual ? 0.12 : 0.20),
            primaryColor.withValues(alpha: 0.02),
          ],
        ).createShader(Rect.fromLTRB(0, chartTop, 0, chartBottom)),
    );

    // clavis lineWidth: 3 on the hourly card, 4 on both daily series.
    final strokeWidth = _dual ? 4.0 : 3.0;
    void stroke(List<double> series, Color color) {
      final path = Path()..moveTo(pointX(0), yAt(series[0]));
      for (var i = 1; i < count; i++) {
        path.lineTo(pointX(i), yAt(series[i]));
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
    }

    stroke(values, primaryColor);
    if (_dual) {
      stroke(lowValues!, secondaryColor);
    }

    // Double-circle points: primary ring (r4.5) + inner dot (r2.4).
    final outerPaint = Paint()..color = primaryColor;
    final innerPaint = Paint()..color = pointInnerColor;
    for (var i = 0; i < count; i++) {
      final center = Offset(pointX(i), yAt(values[i]));
      canvas
        ..drawCircle(center, 4.5, outerPaint)
        ..drawCircle(center, 2.4, innerPaint);
    }

    // On-point temperature labels (clavis draws them bold above the point).
    for (var i = 0; i < count; i++) {
      final label = i < (valueLabels?.length ?? 0)
          ? valueLabels![i]
          : '${values[i].round()}°';
      _paintLabel(
        canvas,
        label,
        // clavis draws the bold 13 px label baseline 10 px above the point.
        Offset(pointX(i), math.max(0.0, yAt(values[i]) - 10)),
        TextStyle(
          color: textColor,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          fontFamily: 'GoogleSansFlex',
          decoration: TextDecoration.none,
        ),
      );
    }
  }

  void _drawPrecipitationBars(
    Canvas canvas,
    Size size,
    int count,
    List<int> pops,
    double Function(int) pointX,
    double chartTop,
    double chartBottom,
  ) {
    for (var i = 0; i < count && i < pops.length; i++) {
      final pop = pops[i].clamp(0, 100).toDouble();
      if (pop <= 0) {
        continue;
      }
      final x = pointX(i);
      final faded = fadeFirstBar && i == 0;
      final barColor = secondaryColor.withValues(alpha: faded ? 0.10 : 0.18);
      if (_dual) {
        // Daily: the bar rises from the chart floor by the probability
        // percentage of the whole span.
        final barTop = chartBottom - (chartBottom - chartTop) * pop / 100;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(
              x - _barWidth / 2,
              barTop,
              x + _barWidth / 2,
              chartBottom,
            ),
            const Radius.circular(5),
          ),
          Paint()..color = barColor,
        );
        _paintLabel(
          canvas,
          '${pop.round()}%',
          Offset(x, chartBottom + 3),
          TextStyle(
            color: faded ? primaryColor.withValues(alpha: 0.42) : primaryColor,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            fontFamily: 'GoogleSansFlex',
            decoration: TextDecoration.none,
          ),
        );
      } else {
        // Hourly: a short band below the chart, height ∝ probability.
        final bandBottom = size.height - _bottomPad;
        final bandHeight = _hourlyBarBand;
        final barHeight = (bandHeight * pop / 100)
            .clamp(0.0, bandHeight)
            .toDouble();
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(
              x - _barWidth / 2,
              bandBottom - barHeight,
              x + _barWidth / 2,
              bandBottom,
            ),
            const Radius.circular(5),
          ),
          Paint()..color = barColor,
        );
      }
    }
  }

  void _paintLabel(
    Canvas canvas,
    String text,
    Offset topCenter,
    TextStyle style,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textAlign: TextAlign.center,
      textDirection: textDirection,
      maxLines: 1,
    )..layout();
    painter.paint(
      canvas,
      Offset(topCenter.dx - painter.width / 2, topCenter.dy),
    );
  }

  @override
  bool shouldRepaint(_TrendChartPainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.lowValues != lowValues ||
        oldDelegate.precipitationProbabilities != precipitationProbabilities ||
        oldDelegate.valueLabels != valueLabels ||
        oldDelegate.fadeFirstBar != fadeFirstBar ||
        oldDelegate.primaryColor != primaryColor ||
        oldDelegate.secondaryColor != secondaryColor ||
        oldDelegate.pointInnerColor != pointInnerColor ||
        oldDelegate.textColor != textColor ||
        oldDelegate.faintTextColor != faintTextColor;
  }
}

/// Card surface shared by the forecast trend cards: the standard weather
/// metric-card chrome (panel-tinted surface, large rounding, hairline).
class WeatherTrendCard extends StatelessWidget {
  const WeatherTrendCard({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

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
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
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
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(height: 6),
            child,
          ],
        ),
      ),
    );
  }
}

/// The clavis `HourlyForecastTrendCard` equivalent: the next eight hours as
/// label + meteocons columns over a single-line temperature chart with a
/// precipitation-probability bar strip underneath.
class WeatherHourlyTrendCard extends StatelessWidget {
  const WeatherHourlyTrendCard({
    super.key,
    required this.hours,
    required this.days,
    this.temperatureUnit = ShellTemperatureUnit.celsius,
    this.utcOffsetSeconds = 0,
  });

  final List<WeatherHour> hours;
  final List<WeatherDay> days;
  final ShellTemperatureUnit temperatureUnit;
  final int utcOffsetSeconds;

  static const int _slotCount = 8;

  @override
  Widget build(BuildContext context) {
    final colors = context.shellColors;
    final l10n = context.l10n;

    final now = cityNow(utcOffsetSeconds);
    final upcoming = hours
        .where((hour) => hour.time.isAfter(now))
        .take(_slotCount)
        .toList(growable: false);
    if (upcoming.length < 2) {
      return const SizedBox.shrink();
    }
    final dayByDate = <DateTime, WeatherDay>{
      for (final day in days)
        DateTime(day.date.year, day.date.month, day.date.day): day,
    };

    return WeatherTrendCard(
      label: l10n.weatherTrendHourly,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: <Widget>[
              for (final hour in upcoming)
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l10n.weatherHourLabel(
                          hour.time.hour.toString().padLeft(2, '0'),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.textTertiary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.none,
                        ),
                      ),
                      const SizedBox(height: 4),
                      WeatherMeteoIcon(
                        weatherCode: hour.weatherCode,
                        night: !isDaylight(
                          hour.time,
                          dayByDate[DateTime(
                            hour.time.year,
                            hour.time.month,
                            hour.time.day,
                          )],
                        ),
                        size: 24,
                        // One static glyph per column like the reference card
                        // (`animated: false`) — 8 lottie players per card is
                        // not worth the ticker pressure.
                        animated: false,
                        fallbackIcon: weatherConditionFor(hour.weatherCode)
                            .icon(
                              day: isDaylight(
                                hour.time,
                                dayByDate[DateTime(
                                  hour.time.year,
                                  hour.time.month,
                                  hour.time.day,
                                )],
                              ),
                            ),
                        fallbackIconColor: colors.textSecondary,
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 96,
            child: WeatherTrendChart(
              values: <double>[for (final hour in upcoming) hour.temperatureC],
              precipitationProbabilities: <int>[
                for (final hour in upcoming) hour.precipitationProbability,
              ],
              valueLabels: <String>[
                for (final hour in upcoming)
                  formatTemperature(hour.temperatureC, temperatureUnit),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The clavis `DailyForecastTrendCard` equivalent: dual day/night
/// temperature lines over the week, rounded precipitation bars and a weekday
/// label row. The daily probability is the day's hourly maximum (the data
/// layer stores probability only per hour).
class WeatherDailyTrendCard extends StatelessWidget {
  const WeatherDailyTrendCard({
    super.key,
    required this.days,
    required this.hours,
    this.temperatureUnit = ShellTemperatureUnit.celsius,
    this.utcOffsetSeconds = 0,
  });

  final List<WeatherDay> days;
  final List<WeatherHour> hours;
  final ShellTemperatureUnit temperatureUnit;
  final int utcOffsetSeconds;

  @override
  Widget build(BuildContext context) {
    final colors = context.shellColors;
    final l10n = context.l10n;

    if (days.length < 2) {
      return const SizedBox.shrink();
    }
    final shown = days.take(7).toList(growable: false);
    final pops = _dailyPrecipitationProbabilities(shown);

    return WeatherTrendCard(
      label: l10n.weatherTrendDaily,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 118,
            child: WeatherTrendChart(
              values: <double>[for (final day in shown) day.maxTemperatureC],
              lowValues: <double>[for (final day in shown) day.minTemperatureC],
              precipitationProbabilities: pops,
              valueLabels: <String>[
                for (final day in shown)
                  formatTemperature(day.maxTemperatureC, temperatureUnit),
              ],
              fadeFirstBar: true,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            children: <Widget>[
              for (var i = 0; i < shown.length; i++)
                Expanded(
                  child: Text(
                    _weekdayLabel(l10n, shown[i].date, i),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: i == 0 ? colors.textPrimary : colors.textTertiary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  List<int> _dailyPrecipitationProbabilities(List<WeatherDay> shown) {
    final pops = <int>[for (var i = 0; i < shown.length; i++) 0];
    final indexByDate = <DateTime, int>{
      for (var i = 0; i < shown.length; i++)
        DateTime(shown[i].date.year, shown[i].date.month, shown[i].date.day): i,
    };
    for (final hour in hours) {
      final index =
          indexByDate[DateTime(hour.time.year, hour.time.month, hour.time.day)];
      if (index != null && hour.precipitationProbability > pops[index]) {
        pops[index] = hour.precipitationProbability;
      }
    }
    return pops;
  }

  /// Chart axis labels stay pure weekday symbols — the forecast list below
  /// already carries the Today/Tomorrow wording, and duplicating it here
  /// would render the same strings twice on the page.
  static String _weekdayLabel(AppLocalizations l10n, DateTime date, int index) {
    return localizedWeekdaySymbol(l10n, date.weekday);
  }
}
