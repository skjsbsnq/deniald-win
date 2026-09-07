import 'dart:math' as math;

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../../../../services/weather_service.dart';
import '../../../../theme/shell_color_scheme.dart';
import '../../../../theme/shell_theme.dart';
import '../../../../theme/tokens.dart';
import '../system/liquid_metric_card.dart';

/// Six metric cards of the Weather view arranged in a two-column grid:
/// humidity, wind, UV, air quality, pressure and visibility, sunrise and
/// sunset.
class WeatherMetricsGrid extends StatelessWidget {
  const WeatherMetricsGrid({super.key, required this.snapshot});

  final WeatherSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    final current = snapshot.current;
    final today = snapshot.days.firstOrNull;

    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: LiquidMetricCard(
                label: isZh ? '湿度' : 'Humidity',
                fraction: current.humidityPercent / 100,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _WeatherMetricCard(
                label: isZh ? '风速风向' : 'Wind',
                child: _WindPane(
                  windSpeedMs: current.windSpeedMs,
                  windDirectionDeg: current.windDirectionDeg,
                  isZh: isZh,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _WeatherMetricCard(
                label: 'UV',
                child: _UvPane(uvIndex: current.uvIndex, isZh: isZh),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _WeatherMetricCard(
                label: isZh ? '空气质量' : 'Air quality',
                child: _AirQualityPane(
                  airQuality: snapshot.airQuality,
                  isZh: isZh,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _WeatherMetricCard(
                label: isZh ? '气压与能见度' : 'Pressure & visibility',
                child: _PressureVisibilityPane(
                  pressureHpa: current.pressureHpa,
                  visibilityM: current.visibilityM,
                  isZh: isZh,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _WeatherMetricCard(
                label: isZh ? '日出与日落' : 'Sunrise & sunset',
                child: _SunCyclePane(day: today, isZh: isZh),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _WeatherMetricCard extends StatelessWidget {
  const _WeatherMetricCard({required this.label, required this.child});

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
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
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
                letterSpacing: 0.2,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(height: 10),
            // A fixed zone (not Expanded) keeps the grid cards equally tall
            // inside the unbounded-height scroll view.
            SizedBox(height: 67, child: Center(child: child)),
          ],
        ),
      ),
    );
  }
}

class _WindPane extends StatelessWidget {
  const _WindPane({
    required this.windSpeedMs,
    required this.windDirectionDeg,
    required this.isZh,
  });

  final double windSpeedMs;
  final double windDirectionDeg;
  final bool isZh;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = context.shellColors;

    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.surfaceContainerHighest,
          ),
          child: Center(
            child: Transform.rotate(
              // Meteorological degrees say where the wind comes from; the
              // arrow points where it is blowing to.
              angle: (windDirectionDeg + 180) * math.pi / 180,
              child: Icon(
                Icons.navigation_rounded,
                size: 18,
                color: theme.accentPalette.primary,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                windDirectionName(windDirectionDeg, isZh),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${beaufortLevel(windSpeedMs)}${isZh ? ' 级' : ''} · '
                '${windSpeedMs.toStringAsFixed(1)} m/s',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.textTertiary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _UvPane extends StatelessWidget {
  const _UvPane({required this.uvIndex, required this.isZh});

  final double uvIndex;
  final bool isZh;

  @override
  Widget build(BuildContext context) {
    final colors = context.shellColors;
    final (label, color) = uvRating(uvIndex, isZh, colors);

    // Stacked so the widest rating chip can never overflow the half-width
    // card.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          uvIndex.toStringAsFixed(1),
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w700,
            height: 1.05,
            decoration: TextDecoration.none,
          ),
        ),
        const SizedBox(height: 4),
        _RatingChip(label: label, color: color),
      ],
    );
  }
}

class _AirQualityPane extends StatelessWidget {
  const _AirQualityPane({required this.airQuality, required this.isZh});

  final AirQuality? airQuality;
  final bool isZh;

  @override
  Widget build(BuildContext context) {
    final colors = context.shellColors;

    if (airQuality == null) {
      return Text(
        isZh ? '暂无数据' : 'Unavailable',
        style: TextStyle(
          color: colors.textTertiary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          decoration: TextDecoration.none,
        ),
      );
    }
    final index = airQualityIndex(airQuality!);
    final (label, color) = airQualityRating(index, isZh, colors);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$index',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w700,
            height: 1.05,
            decoration: TextDecoration.none,
          ),
        ),
        const SizedBox(height: 4),
        _RatingChip(label: label, color: color),
        const SizedBox(height: 4),
        Text(
          'PM2.5 ${airQuality!.pm2_5.toStringAsFixed(0)} · '
          'PM10 ${airQuality!.pm10.toStringAsFixed(0)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: colors.textTertiary,
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.none,
          ),
        ),
      ],
    );
  }
}

class _PressureVisibilityPane extends StatelessWidget {
  const _PressureVisibilityPane({
    required this.pressureHpa,
    required this.visibilityM,
    required this.isZh,
  });

  final double pressureHpa;
  final double visibilityM;
  final bool isZh;

  @override
  Widget build(BuildContext context) {
    final colors = context.shellColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _MetricLine(
          icon: Icons.compress_rounded,
          label: isZh ? '气压' : 'Pressure',
          value: '${pressureHpa.round()} hPa',
          colors: colors,
        ),
        const SizedBox(height: 6),
        _MetricLine(
          icon: Icons.visibility_rounded,
          label: isZh ? '能见度' : 'Visibility',
          value: formatVisibility(visibilityM),
          colors: colors,
        ),
      ],
    );
  }
}

class _SunCyclePane extends StatelessWidget {
  const _SunCyclePane({required this.day, required this.isZh});

  final WeatherDay? day;
  final bool isZh;

  @override
  Widget build(BuildContext context) {
    final colors = context.shellColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _MetricLine(
          icon: Icons.wb_twilight_rounded,
          label: isZh ? '日出' : 'Sunrise',
          value: _formatTime(day?.sunrise),
          colors: colors,
        ),
        const SizedBox(height: 6),
        _MetricLine(
          icon: Icons.dark_mode_rounded,
          label: isZh ? '日落' : 'Sunset',
          value: _formatTime(day?.sunset),
          colors: colors,
        ),
      ],
    );
  }

  static String _formatTime(DateTime? time) {
    if (time == null) {
      return '--';
    }
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
  }
}

class _MetricLine extends StatelessWidget {
  const _MetricLine({
    required this.icon,
    required this.label,
    required this.value,
    required this.colors,
  });

  final IconData icon;
  final String label;
  final String value;
  final ShellColorScheme colors;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: colors.textSecondary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.none,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            decoration: TextDecoration.none,
          ),
        ),
      ],
    );
  }
}

class _RatingChip extends StatelessWidget {
  const _RatingChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: theme.borderRadius(ShellShapeScale.full),
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }
}

/// Eight-sector compass name for a meteorological heading.
String windDirectionName(double degrees, bool isZh) {
  const zhSectors = <String>['北', '东北', '东', '东南', '南', '西南', '西', '西北'];
  const enSectors = <String>['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
  final normalized = (degrees % 360 + 360) % 360;
  final index = ((normalized + 22.5) / 45).floor() % 8;
  return isZh ? '${zhSectors[index]}风' : enSectors[index];
}

/// Beaufort force for a wind speed in m/s.
int beaufortLevel(double metersPerSecond) {
  const thresholds = <double>[
    0.3,
    1.6,
    3.4,
    5.5,
    8.0,
    10.8,
    13.9,
    17.2,
    20.8,
    24.5,
    28.5,
    32.7,
  ];
  var level = 0;
  for (final threshold in thresholds) {
    if (metersPerSecond >= threshold) {
      level++;
    }
  }
  return level;
}

/// UV severity band and its semantic color.
(String, Color) uvRating(double uvIndex, bool isZh, ShellColorScheme colors) {
  if (uvIndex < 3) {
    return (isZh ? '低' : 'Low', colors.performanceGood);
  }
  if (uvIndex < 6) {
    return (isZh ? '中' : 'Moderate', colors.performanceWarning);
  }
  if (uvIndex < 8) {
    return (isZh ? '高' : 'High', colors.performanceWarning);
  }
  return (isZh ? '极高' : 'Extreme', colors.performanceBad);
}

/// Rating band and semantic color for a computed AQI value.
(String, Color) airQualityRating(
  int index,
  bool isZh,
  ShellColorScheme colors,
) {
  if (index <= 50) {
    return (isZh ? '优' : 'Good', colors.performanceGood);
  }
  if (index <= 100) {
    return (isZh ? '良' : 'Moderate', colors.textSecondary);
  }
  if (index <= 150) {
    return (isZh ? '轻度污染' : 'Light pollution', colors.performanceWarning);
  }
  if (index <= 200) {
    return (isZh ? '中度污染' : 'Unhealthy', colors.performanceWarning);
  }
  if (index <= 300) {
    return (isZh ? '重度污染' : 'Very unhealthy', colors.performanceBad);
  }
  return (isZh ? '严重污染' : 'Hazardous', colors.performanceBad);
}

/// Combined AQI: the maximum of the US EPA PM2.5 and PM10 sub-indices.
int airQualityIndex(AirQuality airQuality) {
  final pm25 = _subIndex(airQuality.pm2_5, const <List<double>>[
    [0, 12.0, 0, 50],
    [12.1, 35.4, 51, 100],
    [35.5, 55.4, 101, 150],
    [55.5, 150.4, 151, 200],
    [150.5, 250.4, 201, 300],
    [250.5, 500.4, 301, 500],
  ]);
  final pm10 = _subIndex(airQuality.pm10, const <List<double>>[
    [0, 54, 0, 50],
    [55, 154, 51, 100],
    [155, 254, 101, 150],
    [255, 354, 151, 200],
    [355, 424, 201, 300],
    [425, 604, 301, 500],
  ]);
  return math.max(pm25, pm10).round();
}

double _subIndex(double concentration, List<List<double>> breakpoints) {
  for (final band in breakpoints) {
    final low = band[0];
    final high = band[1];
    if (concentration <= high) {
      if (concentration < low) {
        // A reading can sit in the gap between EPA bands; clamp to the band
        // floor so the sub-index stays monotonic.
        return band[2];
      }
      final t = (concentration - low) / (high - low);
      return band[2] + t * (band[3] - band[2]);
    }
  }
  return 500;
}

/// Visibility in km above 1 km, otherwise metres.
String formatVisibility(double visibilityM) {
  if (visibilityM < 0) {
    return '--';
  }
  if (visibilityM < 1000) {
    return '${visibilityM.round()} m';
  }
  final kilometers = visibilityM / 1000;
  if (kilometers >= 10) {
    return '${kilometers.round()} km';
  }
  return '${kilometers.toStringAsFixed(1)} km';
}
