import 'dart:math' as math;

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../../../../../l10n/generated/app_localizations.dart';
import '../../../../localization/denial_localizations.dart';
import '../../../../services/weather_service.dart';
import '../../../../theme/shell_color_scheme.dart';
import '../../../../theme/shell_theme.dart';
import '../../../../theme/tokens.dart';
import 'weather_animated_value.dart';
import 'weather_arc_gauge.dart';

// Wind severity accents, the `windAccent` six-band table of
// `Modules/Sidebars/Dashboard/WeatherView.qml` (invalid → muted teal).
const Color _windAccentInvalid = Color(0xFF4D8D7B);
const List<Color> _windAccentBands = <Color>[
  Color(0xFF72D572),
  Color(0xFFFFCA28),
  Color(0xFFFFA726),
  Color(0xFFE52F35),
  Color(0xFF99004C),
  Color(0xFF7E0023),
];

// AQI banding, the `aqiThresholds`/`aqiPalette` tables of
// `Modules/Sidebars/Dashboard/WeatherView.qml`.
const List<double> _aqiThresholds = <double>[0, 20, 50, 100, 150, 250];
const List<Color> _aqiPalette = <Color>[
  Color(0xFF00E59B),
  Color(0xFFFFC302),
  Color(0xFFFF712B),
  Color(0xFFF62A55),
  Color(0xFFC72EAA),
  Color(0xFF9930FF),
];

// Concentration breakpoints of the clavis `aqiSummary` pollutant table for
// the pollutants the provider reports (ozone/NO2 have no data source here).
const List<double> _pm25Breakpoints = <double>[0, 5, 15, 30, 60, 150];
const List<double> _pm10Breakpoints = <double>[0, 15, 45, 80, 160, 400];

// UV severity dots of `Modules/Sidebars/Dashboard/WeatherBlob.qml` — five
// buckets (`uvIndexBucket`: <3, <6, <8, <11, else).
const List<Color> _uvPalette = <Color>[
  Color(0xFF6DD58C),
  Color(0xFFFCC934),
  Color(0xFFFA903E),
  Color(0xFFEE675C),
  Color(0xFFAF5CF7),
];

/// Accent color for a wind speed in m/s — six bands like the reference.
Color weatherWindAccent(double metersPerSecond) {
  if (!metersPerSecond.isFinite) {
    return _windAccentInvalid;
  }
  if (metersPerSecond < 4) {
    return _windAccentBands[0];
  }
  if (metersPerSecond < 6) {
    return _windAccentBands[1];
  }
  if (metersPerSecond < 8) {
    return _windAccentBands[2];
  }
  if (metersPerSecond < 10) {
    return _windAccentBands[3];
  }
  if (metersPerSecond < 12) {
    return _windAccentBands[4];
  }
  return _windAccentBands[5];
}

/// Six metric cards of the Weather view arranged in a two-column grid:
/// humidity, wind, UV, air quality, pressure and visibility, sunrise and
/// sunset.
class WeatherMetricsGrid extends StatelessWidget {
  const WeatherMetricsGrid({super.key, required this.snapshot});

  final WeatherSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final current = snapshot.current;
    final today = snapshot.days.firstOrNull;

    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _WeatherMetricCard(
                label: l10n.weatherMetricHumidity,
                child: _HumidityPane(humidityPercent: current.humidityPercent),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _WeatherMetricCard(
                label: l10n.weatherMetricWind,
                child: _WindPane(
                  windSpeedMs: current.windSpeedMs,
                  windDirectionDeg: current.windDirectionDeg,
                  l10n: l10n,
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
                label: l10n.weatherMetricUv,
                child: _UvPane(uvIndex: current.uvIndex, l10n: l10n),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _WeatherMetricCard(
                label: l10n.weatherMetricAirQuality,
                child: _AirQualityPane(
                  airQuality: snapshot.airQuality,
                  l10n: l10n,
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
                label: l10n.weatherMetricPressureVisibility,
                child: _PressureVisibilityPane(
                  pressureHpa: current.pressureHpa,
                  visibilityM: current.visibilityM,
                  l10n: l10n,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _WeatherMetricCard(
                label: l10n.weatherMetricSunCycle,
                child: _SunCyclePane(day: today, l10n: l10n),
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
                letterSpacing: 0,
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

/// Ring gauge + centered rolling readout — the clavis `Weather*Card`
/// composition (`WeatherArcGauge` + `WeatherAnimatedValue`) shrunk into the
/// fixed 67 dp card zone. [detail] docks extra content (rating chip, units)
/// on the right; without it the gauge centers itself.
class _GaugePane extends StatelessWidget {
  const _GaugePane({
    required this.value,
    required this.maximum,
    required this.color,
    required this.center,
    this.detail,
  });

  final double value;
  final double maximum;
  final Color color;

  /// Center content of the ring — the rolling value readout.
  final Widget center;
  final Widget? detail;

  @override
  Widget build(BuildContext context) {
    final gauge = SizedBox(
      width: 62,
      height: 62,
      child: WeatherArcGauge(
        value: value,
        maximum: maximum,
        progressColor: color,
        child: Padding(padding: const EdgeInsets.all(6), child: center),
      ),
    );
    final detail = this.detail;
    if (detail == null) {
      return Center(child: gauge);
    }
    return Row(
      children: [
        gauge,
        const SizedBox(width: 10),
        Expanded(child: detail),
      ],
    );
  }
}

class _HumidityPane extends StatelessWidget {
  const _HumidityPane({required this.humidityPercent});

  final int humidityPercent;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = context.shellColors;
    return WeatherAnimatedValue(
      value: humidityPercent.toDouble(),
      builder: (context, value) => _GaugePane(
        value: value ?? 0,
        maximum: 100,
        color: theme.accentPalette.primary,
        center: Text(
          value == null ? '--' : '${value.round()}%',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }
}

class _WindPane extends StatelessWidget {
  const _WindPane({
    required this.windSpeedMs,
    required this.windDirectionDeg,
    required this.l10n,
  });

  final double windSpeedMs;
  final double windDirectionDeg;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final colors = context.shellColors;
    final accent = weatherWindAccent(windSpeedMs);

    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: accent.withValues(alpha: 0.18),
          ),
          child: Center(
            child: Transform.rotate(
              // Meteorological degrees say where the wind comes from; the
              // arrow points where it is blowing to.
              angle: (windDirectionDeg + 180) * math.pi / 180,
              child: Icon(Icons.navigation_rounded, size: 18, color: accent),
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
                windDirectionName(windDirectionDeg, l10n),
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
                l10n.weatherWindDetails(
                  beaufortLevel(windSpeedMs),
                  windSpeedMs.toStringAsFixed(1),
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
            ],
          ),
        ),
      ],
    );
  }
}

class _UvPane extends StatelessWidget {
  const _UvPane({required this.uvIndex, required this.l10n});

  final double uvIndex;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final colors = context.shellColors;
    final (label, color) = uvRating(uvIndex, l10n, colors);

    return WeatherAnimatedValue(
      value: uvIndex,
      builder: (context, value) => _GaugePane(
        value: value ?? 0,
        maximum: 11,
        color: color,
        center: Text(
          value == null ? '--' : value.toStringAsFixed(1),
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            decoration: TextDecoration.none,
          ),
        ),
        detail: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [_RatingChip(label: label, color: color)],
        ),
      ),
    );
  }
}

class _AirQualityPane extends StatelessWidget {
  const _AirQualityPane({required this.airQuality, required this.l10n});

  final AirQuality? airQuality;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final colors = context.shellColors;

    if (airQuality == null) {
      return Text(
        l10n.weatherMetricUnavailable,
        style: TextStyle(
          color: colors.textTertiary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          decoration: TextDecoration.none,
        ),
      );
    }
    final index = airQualityIndex(airQuality!);
    final (label, color) = airQualityRating(index, l10n, colors);

    return WeatherAnimatedValue(
      value: index.toDouble(),
      builder: (context, value) => _GaugePane(
        value: value ?? 0,
        // The clavis AQI gauge saturates at the top of its 0–250 scale.
        maximum: 250,
        color: color,
        center: Text(
          value == null ? '--' : '${value.round()}',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            decoration: TextDecoration.none,
          ),
        ),
        detail: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _RatingChip(label: label, color: color),
            const SizedBox(height: 4),
            Text(
              'PM2.5 ${airQuality!.pm2_5.toStringAsFixed(0)} · '
              'PM10 ${airQuality!.pm10.toStringAsFixed(0)}',
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
    );
  }
}

class _PressureVisibilityPane extends StatelessWidget {
  const _PressureVisibilityPane({
    required this.pressureHpa,
    required this.visibilityM,
    required this.l10n,
  });

  final double pressureHpa;
  final double visibilityM;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final colors = context.shellColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _MetricLine(
          icon: Icons.compress_rounded,
          label: l10n.weatherMetricPressure,
          value: '${pressureHpa.round()} hPa',
          colors: colors,
        ),
        const SizedBox(height: 6),
        _MetricLine(
          icon: Icons.visibility_rounded,
          label: l10n.weatherMetricVisibility,
          value: formatVisibility(visibilityM),
          colors: colors,
        ),
        const SizedBox(height: 4),
        // Six-band wording of the clavis WeatherVisibilityCard; monochrome —
        // the reference assigns no severity color to visibility.
        Text(
          visibilityRating(visibilityM, l10n),
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
    );
  }
}

class _SunCyclePane extends StatelessWidget {
  const _SunCyclePane({required this.day, required this.l10n});

  final WeatherDay? day;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final colors = context.shellColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _MetricLine(
          icon: Icons.wb_twilight_rounded,
          label: l10n.weatherMetricSunrise,
          value: _formatTime(day?.sunrise),
          colors: colors,
        ),
        const SizedBox(height: 6),
        _MetricLine(
          icon: Icons.dark_mode_rounded,
          label: l10n.weatherMetricSunset,
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
            fontSize: 12,
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
            fontSize: 11,
            fontWeight: FontWeight.w700,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }
}

/// Eight-sector compass name for a meteorological heading.
String windDirectionName(double degrees, AppLocalizations l10n) {
  final sectors = <String>[
    l10n.windDirectionNorth,
    l10n.windDirectionNorthEast,
    l10n.windDirectionEast,
    l10n.windDirectionSouthEast,
    l10n.windDirectionSouth,
    l10n.windDirectionSouthWest,
    l10n.windDirectionWest,
    l10n.windDirectionNorthWest,
  ];
  final normalized = (degrees % 360 + 360) % 360;
  final index = ((normalized + 22.5) / 45).floor() % 8;
  return sectors[index];
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

/// `uvIndexBucket`: <3 → 0, <6 → 1, <8 → 2, <11 → 3, else 4; -1 for
/// unusable readings, like the reference.
int uvIndexBucket(double uvIndex) {
  if (!uvIndex.isFinite) {
    return -1;
  }
  if (uvIndex < 3) {
    return 0;
  }
  if (uvIndex < 6) {
    return 1;
  }
  if (uvIndex < 8) {
    return 2;
  }
  if (uvIndex < 11) {
    return 3;
  }
  return 4;
}

/// UV severity band and its clavis dot color — five buckets over the
/// `uvLevel` wording table. [colors] stays in the signature for callers
/// that already resolve the scheme; the palette itself is the ported
/// `WeatherBlob` table.
(String, Color) uvRating(
  double uvIndex,
  AppLocalizations l10n,
  ShellColorScheme colors,
) {
  final bucket = uvIndexBucket(uvIndex) < 0 ? 0 : uvIndexBucket(uvIndex);
  final label = switch (bucket) {
    0 => l10n.weatherUvLow,
    1 => l10n.weatherUvModerate,
    2 => l10n.weatherUvHigh,
    3 => l10n.weatherUvVeryHigh,
    _ => l10n.weatherUvExtreme,
  };
  return (label, _uvPalette[bucket]);
}

/// Six-band visibility wording of the clavis `WeatherVisibilityCard`
/// `descriptionText` (metre thresholds).
String visibilityRating(double visibilityM, AppLocalizations l10n) {
  if (visibilityM < 1000) {
    return l10n.weatherVisibilityVeryPoor;
  }
  if (visibilityM < 4000) {
    return l10n.weatherVisibilityPoor;
  }
  if (visibilityM < 10000) {
    return l10n.weatherVisibilityModerate;
  }
  if (visibilityM < 20000) {
    return l10n.weatherVisibilityGood;
  }
  if (visibilityM < 40000) {
    return l10n.weatherVisibilityClear;
  }
  return l10n.weatherVisibilityExcellent;
}

/// `aqiLevelIndex`: the highest band of [_aqiThresholds] the value reaches,
/// clamped to the six palette entries; -1 for unusable readings.
int aqiLevelIndex(double value) {
  if (!value.isFinite) {
    return -1;
  }
  var level = 0;
  for (var i = 0; i < _aqiThresholds.length; i++) {
    if (value >= _aqiThresholds[i]) {
      level = i;
    }
  }
  return math.min(level, _aqiPalette.length - 1);
}

/// Rating band and clavis palette color for a computed AQI value; [colors]
/// stays in the signature for callers that already resolve the scheme.
(String, Color) airQualityRating(
  int index,
  AppLocalizations l10n,
  ShellColorScheme colors,
) {
  final level = aqiLevelIndex(index.toDouble());
  final band = level < 0 ? 0 : level;
  final label = switch (band) {
    0 => l10n.weatherAqiGood,
    1 => l10n.weatherAqiModerate,
    2 => l10n.weatherAqiLightPollution,
    3 => l10n.weatherAqiUnhealthy,
    4 => l10n.weatherAqiVeryUnhealthy,
    _ => l10n.weatherAqiHazardous,
  };
  return (label, _aqiPalette[band]);
}

/// `pollutantIndex`: piecewise-linear map of a concentration onto the
/// clavis AQI scale ([_aqiThresholds]); NaN for unusable readings.
double _pollutantIndex(double concentration, List<double> breakpoints) {
  if (!concentration.isFinite) {
    return double.nan;
  }
  var level = -1;
  for (var i = 0; i < breakpoints.length; i++) {
    if (concentration >= breakpoints[i]) {
      level = i;
    }
  }
  if (level < 0) {
    return double.nan;
  }
  if (level < breakpoints.length - 1) {
    final bpLo = breakpoints[level];
    final bpHi = breakpoints[level + 1];
    final inLo = _aqiThresholds[level];
    final inHi = _aqiThresholds[level + 1];
    return ((inHi - inLo) / (bpHi - bpLo)) * (concentration - bpLo) + inLo;
  }
  return concentration * _aqiThresholds.last / breakpoints.last;
}

/// `aqiSummary`: the worst clavis AQI over the reported pollutants — the
/// 0–250 scale of the reference, not the US EPA sub-indices.
int airQualityIndex(AirQuality airQuality) {
  final pm25 = _pollutantIndex(airQuality.pm2_5, _pm25Breakpoints);
  final pm10 = _pollutantIndex(airQuality.pm10, _pm10Breakpoints);
  final worst = math.max(pm25.isFinite ? pm25 : 0, pm10.isFinite ? pm10 : 0);
  return worst.round();
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
