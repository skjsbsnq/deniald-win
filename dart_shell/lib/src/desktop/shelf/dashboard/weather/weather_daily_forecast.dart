import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../../services/weather_service.dart';
import '../../../../settings/shell_settings.dart';
import '../../../../theme/shell_theme.dart';
import '../../../../theme/tokens.dart';
import 'weather_hero_section.dart';
import 'weather_temperature.dart';

/// Seven-day forecast list: weekday, condition icon, and a temperature range
/// bar normalized against the week's own extremes.
class WeatherDailyForecast extends StatelessWidget {
  const WeatherDailyForecast({
    super.key,
    required this.days,
    this.temperatureUnit = ShellTemperatureUnit.celsius,
  });

  final List<WeatherDay> days;

  final ShellTemperatureUnit temperatureUnit;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = context.shellColors;
    final isZh = Localizations.localeOf(context).languageCode == 'zh';

    if (days.isEmpty) {
      return const SizedBox.shrink();
    }

    var minimum = days.first.minTemperatureC;
    var maximum = days.first.maxTemperatureC;
    for (final day in days) {
      if (day.minTemperatureC < minimum) {
        minimum = day.minTemperatureC;
      }
      if (day.maxTemperatureC > maximum) {
        maximum = day.maxTemperatureC;
      }
    }
    final span = maximum - minimum;

    return Column(
      children: <Widget>[
        for (var i = 0; i < days.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i == days.length - 1 ? 0 : 10),
            child: Row(
              children: [
                SizedBox(
                  width: 52,
                  child: Text(
                    _weekdayLabel(days[i].date, i, isZh),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: i == 0 ? colors.textPrimary : colors.textSecondary,
                      fontSize: 12,
                      fontWeight: i == 0 ? FontWeight.w700 : FontWeight.w600,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  weatherConditionFor(days[i].weatherCode).icon(day: true),
                  size: 19,
                  color: colors.textSecondary,
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 30,
                  child: Text(
                    formatTemperature(days[i].minTemperatureC, temperatureUnit),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: colors.textTertiary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final trackWidth = constraints.maxWidth;
                      var left = 0.0;
                      var width = trackWidth;
                      if (span > 0 && trackWidth > 0) {
                        left =
                            (days[i].minTemperatureC - minimum) /
                            span *
                            trackWidth;
                        width =
                            (days[i].maxTemperatureC -
                                days[i].minTemperatureC) /
                            span *
                            trackWidth;
                      }
                      return SizedBox(
                        height: 6,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: colors.surfaceContainerHighest,
                                  borderRadius: theme.borderRadius(
                                    ShellShapeScale.full,
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              left: left,
                              width: width.clamp(
                                4.0,
                                math.max(4.0, trackWidth - left),
                              ),
                              top: 0,
                              bottom: 0,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: <Color>[
                                      theme.accentPalette.primary.withValues(
                                        alpha: 0.40,
                                      ),
                                      theme.accentPalette.primary,
                                    ],
                                  ),
                                  borderRadius: theme.borderRadius(
                                    ShellShapeScale.full,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 30,
                  child: Text(
                    formatTemperature(days[i].maxTemperatureC, temperatureUnit),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  static String _weekdayLabel(DateTime date, int index, bool isZh) {
    if (index == 0) {
      return isZh ? '今天' : 'Today';
    }
    if (index == 1) {
      return isZh ? '明天' : 'Tomorrow';
    }
    const zhWeekdays = <String>['一', '二', '三', '四', '五', '六', '日'];
    const enWeekdays = <String>[
      'Mon',
      'Tue',
      'Wed',
      'Thu',
      'Fri',
      'Sat',
      'Sun',
    ];
    // DateTime.weekday is 1-based with Monday first.
    final weekday = date.weekday - 1;
    return isZh ? '周${zhWeekdays[weekday]}' : enWeekdays[weekday];
  }
}
