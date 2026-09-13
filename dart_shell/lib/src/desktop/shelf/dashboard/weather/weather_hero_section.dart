import 'dart:math' as math;

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../../../../../l10n/generated/app_localizations.dart';
import '../../../../localization/denial_localizations.dart';
import '../../../../services/weather_service.dart';
import '../../../../settings/shell_settings.dart';
import '../../../../theme/motion.dart';
import '../../../../theme/shell_theme.dart';
import '../../../../theme/tokens.dart';
import '../../../../widgets/shell_hover_pill.dart';
import '../dashboard_card_tone.dart';
import 'weather_metrics_grid.dart';
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

/// Tonal family for the weather hero card (02-VISUAL-SPEC §4): clear-ish
/// daylight conditions read as `primaryContainer`; night, overcast, and
/// precipitation fall back to the rotated-hue `tertiaryContainer`.
DashboardCardTone weatherHeroTone(int weatherCode, bool isDay) {
  final mild = weatherCode <= 2;
  return mild && isDay ? DashboardCardTone.primary : DashboardCardTone.tertiary;
}

enum _HeroSegment { conditions, airQuality, wind }

/// Hero card of the Weather view: city and update time, the emphasized
/// Display temperature with the 72 px condition glyph, and an in-card
/// segmented selector that swaps the lower content pane between current
/// conditions, air quality, and wind.
class WeatherHeroSection extends StatefulWidget {
  const WeatherHeroSection({
    super.key,
    required this.snapshot,
    required this.isDay,
    this.temperatureUnit = ShellTemperatureUnit.celsius,
    this.onRefresh,
  });

  final WeatherSnapshot snapshot;
  final bool isDay;
  final ShellTemperatureUnit temperatureUnit;

  /// Optional manual-refresh affordance rendered in the card header.
  final VoidCallback? onRefresh;

  @override
  State<WeatherHeroSection> createState() => _WeatherHeroSectionState();
}

class _WeatherHeroSectionState extends State<WeatherHeroSection>
    with SingleTickerProviderStateMixin {
  _HeroSegment _segment = _HeroSegment.conditions;
  late final AnimationController _segmentPill = AnimationController.unbounded(
    vsync: this,
  );

  @override
  void dispose() {
    _segmentPill.dispose();
    super.dispose();
  }

  void _selectSegment(_HeroSegment segment) {
    if (_segment == segment) {
      return;
    }
    setState(() => _segment = segment);
    if (MediaQuery.disableAnimationsOf(context)) {
      _segmentPill.value = segment.index.toDouble();
    } else {
      springTo(
        _segmentPill,
        segment.index.toDouble(),
        spring: Motion.expressiveSpatialFast,
        telemetryLabel: 'weather_hero_segment',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = context.shellColors;
    final l10n = context.l10n;
    final current = widget.snapshot.current;
    final toneColors = dashboardCardToneColors(
      theme,
      colors,
      weatherHeroTone(current.weatherCode, widget.isDay),
    );
    final condition = weatherConditionFor(current.weatherCode);

    return DecoratedBox(
      key: const Key('weather-hero-card'),
      decoration: BoxDecoration(
        color: theme.panelColor(toneColors.container),
        borderRadius: theme.borderRadius(ShellShapeScale.extraLarge),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          ShellSpacing.lg,
          ShellSpacing.lg,
          ShellSpacing.lg,
          ShellSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  Icons.location_on_rounded,
                  size: 14,
                  color: toneColors.foregroundSecondary,
                ),
                const SizedBox(width: ShellSpacing.xs),
                Expanded(
                  child: Text(
                    widget.snapshot.location.city,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.text.titleSmallEmphasized.copyWith(
                      color: toneColors.foreground,
                    ),
                  ),
                ),
                Text(
                  l10n.weatherUpdated(_formatClock(widget.snapshot.fetchedAt)),
                  style: theme.text.labelSmall.copyWith(
                    color: toneColors.foregroundSecondary,
                  ),
                ),
                if (widget.onRefresh != null) ...[
                  const SizedBox(width: ShellSpacing.sm),
                  ShellHoverPill(
                    onTap: widget.onRefresh,
                    semanticLabel: l10n.weatherRetry,
                    width: 30,
                    height: 30,
                    color: colors.surfaceContainerHighest,
                    hoverColor: colors.panelHighlight,
                    child: Icon(
                      Icons.refresh_rounded,
                      size: 16,
                      color: toneColors.foregroundSecondary,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: ShellSpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    formatTemperature(
                      current.temperatureC,
                      widget.temperatureUnit,
                    ),
                    // "64pt Display-L emphasized" per the spec table resolves
                    // to the DisplayLarge emphasized role, whose line box is
                    // exactly 64dp.
                    style: theme.text.displayLargeEmphasized.copyWith(
                      color: toneColors.foreground,
                      height: 1.0,
                    ),
                  ),
                ),
                const SizedBox(width: ShellSpacing.md),
                Icon(
                  condition.icon(day: widget.isDay),
                  size: 72,
                  color: toneColors.accent,
                ),
              ],
            ),
            const SizedBox(height: ShellSpacing.sm),
            _HeroSegmentedBar(
              selected: _segment,
              pill: _segmentPill,
              toneColors: toneColors,
              onSelected: _selectSegment,
            ),
            const SizedBox(height: ShellSpacing.sm),
            AnimatedSwitcher(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : Motion.cardSettle,
              switchInCurve: Motion.standard,
              switchOutCurve: Motion.standard,
              child: KeyedSubtree(
                key: ValueKey(_segment),
                child: SizedBox(
                  height: 64,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _segmentPane(toneColors),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _segmentPane(
    ({
      Color accent,
      Color container,
      Color foreground,
      Color foregroundSecondary,
      Color onAccent,
    })
    toneColors,
  ) {
    final l10n = context.l10n;
    final theme = context.shellTheme;
    final current = widget.snapshot.current;
    final today = widget.snapshot.days.firstOrNull;
    return switch (_segment) {
      _HeroSegment.conditions => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            weatherConditionLabel(l10n, current.weatherCode),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.text.titleMediumEmphasized.copyWith(
              color: toneColors.foreground,
            ),
          ),
          const SizedBox(height: ShellSpacing.xs),
          Text(
            '${l10n.weatherFeelsLike(formatTemperature(current.apparentTemperatureC, widget.temperatureUnit))}'
            '${today == null ? '' : ' · ${l10n.weatherHeroHighLow(formatTemperature(today.maxTemperatureC, widget.temperatureUnit), formatTemperature(today.minTemperatureC, widget.temperatureUnit))}'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.text.labelMedium.copyWith(
              color: toneColors.foregroundSecondary,
            ),
          ),
        ],
      ),
      _HeroSegment.airQuality => _AirQualityPane(
        airQuality: widget.snapshot.airQuality,
        toneColors: toneColors,
      ),
      _HeroSegment.wind => _WindPane(
        windSpeedMs: current.windSpeedMs,
        windDirectionDeg: current.windDirectionDeg,
        toneColors: toneColors,
      ),
    };
  }
}

class _HeroSegmentedBar extends StatelessWidget {
  const _HeroSegmentedBar({
    required this.selected,
    required this.pill,
    required this.toneColors,
    required this.onSelected,
  });

  final _HeroSegment selected;
  final AnimationController pill;
  final ({
    Color accent,
    Color container,
    Color foreground,
    Color foregroundSecondary,
    Color onAccent,
  })
  toneColors;
  final ValueChanged<_HeroSegment> onSelected;

  static const int _segmentCount = 3;

  String _label(AppLocalizations l10n, _HeroSegment segment) {
    return switch (segment) {
      _HeroSegment.conditions => l10n.weatherSegmentConditions,
      _HeroSegment.airQuality => l10n.weatherMetricAirQuality,
      _HeroSegment.wind => l10n.weatherMetricWind,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = context.shellColors;
    final l10n = context.l10n;

    return Container(
      height: 36,
      padding: const EdgeInsets.all(ShellSpacing.xs - 1),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: theme.borderRadius(ShellShapeScale.full),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cellWidth = constraints.maxWidth / _segmentCount;
          return Stack(
            children: [
              AnimatedBuilder(
                animation: pill,
                builder: (context, child) => Positioned(
                  left: pill.value * cellWidth,
                  top: 0,
                  bottom: 0,
                  width: cellWidth,
                  child: child!,
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: toneColors.accent,
                    borderRadius: theme.borderRadius(ShellShapeScale.full),
                  ),
                ),
              ),
              Row(
                children: [
                  for (final segment in _HeroSegment.values)
                    Expanded(
                      child: ShellHoverPill.builder(
                        onTap: () => onSelected(segment),
                        height: double.infinity,
                        childBuilder: (context, hovered, focused) {
                          final isSelected = segment == selected;
                          final fg = isSelected
                              ? toneColors.onAccent
                              : (hovered
                                    ? toneColors.foreground
                                    : toneColors.foregroundSecondary);
                          return Center(
                            child: Text(
                              _label(l10n, segment),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.text.labelSmall.copyWith(
                                color: fg,
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w600,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Air-quality pane of the hero card: the EPA index, its rating, and the
/// PM pair on one line — a condensed restack of the metric-grid data.
class _AirQualityPane extends StatelessWidget {
  const _AirQualityPane({required this.airQuality, required this.toneColors});

  final AirQuality? airQuality;
  final ({
    Color accent,
    Color container,
    Color foreground,
    Color foregroundSecondary,
    Color onAccent,
  })
  toneColors;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = context.shellColors;
    final l10n = context.l10n;

    if (airQuality == null) {
      return Text(
        l10n.weatherMetricUnavailable,
        style: theme.text.labelMedium.copyWith(
          color: toneColors.foregroundSecondary,
        ),
      );
    }
    final index = airQualityIndex(airQuality!);
    final (label, ratingColor) = airQualityRating(index, l10n, colors);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              'AQI $index',
              style: theme.text.headlineSmallEmphasized.copyWith(
                color: toneColors.foreground,
              ),
            ),
            const SizedBox(width: ShellSpacing.sm),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.text.labelMediumEmphasized.copyWith(
                  color: ratingColor,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: ShellSpacing.xs),
        Text(
          'PM2.5 ${airQuality!.pm2_5.toStringAsFixed(0)} · '
          'PM10 ${airQuality!.pm10.toStringAsFixed(0)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.text.labelMedium.copyWith(
            color: toneColors.foregroundSecondary,
          ),
        ),
      ],
    );
  }
}

/// Wind pane of the hero card: a tonal compass disc plus the Beaufort force
/// and speed line, restacking the metric-grid wind data.
class _WindPane extends StatelessWidget {
  const _WindPane({
    required this.windSpeedMs,
    required this.windDirectionDeg,
    required this.toneColors,
  });

  final double windSpeedMs;
  final double windDirectionDeg;
  final ({
    Color accent,
    Color container,
    Color foreground,
    Color foregroundSecondary,
    Color onAccent,
  })
  toneColors;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = context.shellColors;
    final l10n = context.l10n;

    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
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
                size: 22,
                color: toneColors.accent,
              ),
            ),
          ),
        ),
        const SizedBox(width: ShellSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                windDirectionName(windDirectionDeg, l10n),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.text.titleSmallEmphasized.copyWith(
                  color: toneColors.foreground,
                ),
              ),
              const SizedBox(height: ShellSpacing.xs),
              Text(
                l10n.weatherWindDetails(
                  beaufortLevel(windSpeedMs),
                  windSpeedMs.toStringAsFixed(1),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.text.labelMedium.copyWith(
                  color: toneColors.foregroundSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

String _formatClock(DateTime time) {
  return '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';
}
