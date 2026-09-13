import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../../../../../l10n/generated/app_localizations.dart';
import '../../../../localization/denial_localizations.dart';
import '../../../../services/weather_service.dart';
import '../../../../settings/shell_settings.dart';
import '../../../../theme/shell_theme.dart';
import 'weather_temperature.dart';

/// One WMO 4677 weather-code family with the icons the dashboard renders
/// for it; the label comes from the generated localizations.
class WeatherCondition {
  const WeatherCondition({required this.dayIcon, required this.nightIcon});

  final IconData dayIcon;
  final IconData nightIcon;

  IconData icon({required bool day}) => day ? dayIcon : nightIcon;
}

const WeatherCondition _clear = WeatherCondition(
  dayIcon: Icons.wb_sunny_rounded,
  nightIcon: Icons.dark_mode_rounded,
);

const WeatherCondition _mostlyClear = WeatherCondition(
  dayIcon: Icons.light_mode_rounded,
  nightIcon: Icons.dark_mode_rounded,
);

const WeatherCondition _partlyCloudy = WeatherCondition(
  dayIcon: Icons.wb_cloudy_rounded,
  nightIcon: Icons.cloud_rounded,
);

const WeatherCondition _overcast = WeatherCondition(
  dayIcon: Icons.cloud_rounded,
  nightIcon: Icons.cloud_rounded,
);

const WeatherCondition _drizzle = WeatherCondition(
  dayIcon: Icons.grain_rounded,
  nightIcon: Icons.grain_rounded,
);

const WeatherCondition _snow = WeatherCondition(
  dayIcon: Icons.ac_unit_rounded,
  nightIcon: Icons.ac_unit_rounded,
);

const WeatherCondition _thunderstorm = WeatherCondition(
  dayIcon: Icons.thunderstorm_rounded,
  nightIcon: Icons.thunderstorm_rounded,
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
    ),
    51 || 53 || 55 || 56 || 57 => _drizzle,
    61 => WeatherCondition(
      dayIcon: Icons.water_drop_rounded,
      nightIcon: Icons.water_drop_rounded,
    ),
    63 => WeatherCondition(
      dayIcon: Icons.water_drop_rounded,
      nightIcon: Icons.water_drop_rounded,
    ),
    65 => WeatherCondition(
      dayIcon: Icons.water_drop_rounded,
      nightIcon: Icons.water_drop_rounded,
    ),
    66 || 67 => WeatherCondition(
      dayIcon: Icons.water_drop_rounded,
      nightIcon: Icons.water_drop_rounded,
    ),
    71 => WeatherCondition(
      dayIcon: Icons.ac_unit_rounded,
      nightIcon: Icons.ac_unit_rounded,
    ),
    73 => _snow,
    75 => WeatherCondition(
      dayIcon: Icons.ac_unit_rounded,
      nightIcon: Icons.ac_unit_rounded,
    ),
    77 => WeatherCondition(
      dayIcon: Icons.ac_unit_rounded,
      nightIcon: Icons.ac_unit_rounded,
    ),
    80 || 81 || 82 => WeatherCondition(
      dayIcon: Icons.water_drop_rounded,
      nightIcon: Icons.water_drop_rounded,
    ),
    85 || 86 => WeatherCondition(
      dayIcon: Icons.ac_unit_rounded,
      nightIcon: Icons.ac_unit_rounded,
    ),
    95 || 96 || 99 => _thunderstorm,
    _ => _overcast,
  };
}

/// Localized prose for a WMO weather code; unmapped codes degrade to
/// overcast, mirroring [weatherConditionFor].
String weatherConditionLabel(AppLocalizations l10n, int code) {
  return switch (code) {
    0 => l10n.weatherConditionClear,
    1 => l10n.weatherConditionMostlyClear,
    2 => l10n.weatherConditionPartlyCloudy,
    3 => l10n.weatherConditionOvercast,
    45 || 48 => l10n.weatherConditionFog,
    51 || 53 || 55 || 56 || 57 => l10n.weatherConditionDrizzle,
    61 => l10n.weatherConditionLightRain,
    63 => l10n.weatherConditionRain,
    65 => l10n.weatherConditionHeavyRain,
    66 || 67 => l10n.weatherConditionFreezingRain,
    71 => l10n.weatherConditionLightSnow,
    73 => l10n.weatherConditionSnow,
    75 => l10n.weatherConditionHeavySnow,
    77 => l10n.weatherConditionSnowGrains,
    80 || 81 || 82 => l10n.weatherConditionShowers,
    85 || 86 => l10n.weatherConditionSnowShowers,
    95 || 96 || 99 => l10n.weatherConditionThunderstorm,
    _ => l10n.weatherConditionOvercast,
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

/// The location's current wall clock. Snapshot timestamps are UTC-flagged
/// carriers of the location's wall clock, so "now" must be reconstructed in
/// that same frame rather than read from the device's DateTime.now().
DateTime cityNow(int utcOffsetSeconds) {
  return DateTime.now().toUtc().add(Duration(seconds: utcOffsetSeconds));
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
    final l10n = context.l10n;
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

                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                weatherConditionLabel(l10n, current.weatherCode),
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                l10n.weatherFeelsLike(
                  formatTemperature(
                    current.apparentTemperatureC,
                    temperatureUnit,
                  ),
                ),
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
