import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../../../../services/weather_service.dart';
import '../../../../settings/shell_settings.dart';
import '../../../../theme/shell_theme.dart';
import 'weather_temperature.dart';

/// One WMO 4677 weather-code family with the icons and labels the dashboard
/// renders for it.
class WeatherCondition {
  const WeatherCondition({
    required this.dayIcon,
    required this.nightIcon,
    required this.zhLabel,
    required this.enLabel,
  });

  final IconData dayIcon;
  final IconData nightIcon;
  final String zhLabel;
  final String enLabel;

  IconData icon({required bool day}) => day ? dayIcon : nightIcon;

  String label({required bool isZh}) => isZh ? zhLabel : enLabel;
}

const WeatherCondition _clear = WeatherCondition(
  dayIcon: Icons.wb_sunny_rounded,
  nightIcon: Icons.dark_mode_rounded,
  zhLabel: '晴',
  enLabel: 'Clear',
);

const WeatherCondition _mostlyClear = WeatherCondition(
  dayIcon: Icons.light_mode_rounded,
  nightIcon: Icons.dark_mode_rounded,
  zhLabel: '晴间多云',
  enLabel: 'Mostly clear',
);

const WeatherCondition _partlyCloudy = WeatherCondition(
  dayIcon: Icons.wb_cloudy_rounded,
  nightIcon: Icons.cloud_rounded,
  zhLabel: '多云',
  enLabel: 'Partly cloudy',
);

const WeatherCondition _overcast = WeatherCondition(
  dayIcon: Icons.cloud_rounded,
  nightIcon: Icons.cloud_rounded,
  zhLabel: '阴',
  enLabel: 'Overcast',
);

const WeatherCondition _drizzle = WeatherCondition(
  dayIcon: Icons.grain_rounded,
  nightIcon: Icons.grain_rounded,
  zhLabel: '毛毛雨',
  enLabel: 'Drizzle',
);

const WeatherCondition _snow = WeatherCondition(
  dayIcon: Icons.ac_unit_rounded,
  nightIcon: Icons.ac_unit_rounded,
  zhLabel: '雪',
  enLabel: 'Snow',
);

const WeatherCondition _thunderstorm = WeatherCondition(
  dayIcon: Icons.thunderstorm_rounded,
  nightIcon: Icons.thunderstorm_rounded,
  zhLabel: '雷雨',
  enLabel: 'Thunderstorm',
);

/// Presentation for a WMO weather code; unmapped codes degrade to overcast.
WeatherCondition weatherConditionFor(int code) {
  return switch (code) {
    0 => _clear,
    1 => _mostlyClear,
    2 => _partlyCloudy,
    3 => _overcast,
    45 || 48 => WeatherCondition(
      dayIcon: Icons.cloud_rounded,
      nightIcon: Icons.cloud_rounded,
      zhLabel: '雾',
      enLabel: 'Fog',
    ),
    51 || 53 || 55 || 56 || 57 => _drizzle,
    61 => WeatherCondition(
      dayIcon: Icons.water_drop_rounded,
      nightIcon: Icons.water_drop_rounded,
      zhLabel: '小雨',
      enLabel: 'Light rain',
    ),
    63 => WeatherCondition(
      dayIcon: Icons.water_drop_rounded,
      nightIcon: Icons.water_drop_rounded,
      zhLabel: '中雨',
      enLabel: 'Rain',
    ),
    65 => WeatherCondition(
      dayIcon: Icons.water_drop_rounded,
      nightIcon: Icons.water_drop_rounded,
      zhLabel: '大雨',
      enLabel: 'Heavy rain',
    ),
    66 || 67 => WeatherCondition(
      dayIcon: Icons.water_drop_rounded,
      nightIcon: Icons.water_drop_rounded,
      zhLabel: '冻雨',
      enLabel: 'Freezing rain',
    ),
    71 => WeatherCondition(
      dayIcon: Icons.ac_unit_rounded,
      nightIcon: Icons.ac_unit_rounded,
      zhLabel: '小雪',
      enLabel: 'Light snow',
    ),
    73 => _snow,
    75 => WeatherCondition(
      dayIcon: Icons.ac_unit_rounded,
      nightIcon: Icons.ac_unit_rounded,
      zhLabel: '大雪',
      enLabel: 'Heavy snow',
    ),
    77 => WeatherCondition(
      dayIcon: Icons.ac_unit_rounded,
      nightIcon: Icons.ac_unit_rounded,
      zhLabel: '雪粒',
      enLabel: 'Snow grains',
    ),
    80 || 81 || 82 => WeatherCondition(
      dayIcon: Icons.water_drop_rounded,
      nightIcon: Icons.water_drop_rounded,
      zhLabel: '阵雨',
      enLabel: 'Showers',
    ),
    85 || 86 => WeatherCondition(
      dayIcon: Icons.ac_unit_rounded,
      nightIcon: Icons.ac_unit_rounded,
      zhLabel: '阵雪',
      enLabel: 'Snow showers',
    ),
    95 || 96 || 99 => _thunderstorm,
    _ => _overcast,
  };
}

/// Whether [time] falls between the day's sunrise and sunset; falls back to a
/// 06:00-18:00 heuristic when the daily forecast entry is missing.
bool isDaylight(DateTime time, WeatherDay? day) {
  if (day == null) {
    final hour = time.hour;
    return hour >= 6 && hour < 18;
  }
  return !time.isBefore(day.sunrise) && time.isBefore(day.sunset);
}

/// Hero block of the Weather view: the live temperature, condition glyph,
/// condition label, and apparent temperature.
class WeatherHeroSection extends StatelessWidget {
  const WeatherHeroSection({
    super.key,
    required this.current,
    required this.isDay,
    this.temperatureUnit = ShellTemperatureUnit.celsius,
  });

  final WeatherCurrent current;
  final bool isDay;
  final ShellTemperatureUnit temperatureUnit;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = context.shellColors;
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    final condition = weatherConditionFor(current.weatherCode);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                formatTemperature(current.temperatureC, temperatureUnit),
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 64,
                  fontWeight: FontWeight.w600,
                  height: 1.0,
                  letterSpacing: -1,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                condition.label(isZh: isZh),
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                isZh
                    ? '体感 ${formatTemperature(current.apparentTemperatureC, temperatureUnit)}'
                    : 'Feels like ${formatTemperature(current.apparentTemperatureC, temperatureUnit)}',
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Icon(
          condition.icon(day: isDay),
          size: 72,
          color: theme.accentPalette.primary,
        ),
      ],
    );
  }
}
