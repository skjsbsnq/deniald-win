import 'dart:async';

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../state/weather_state.dart';
import '../../../../settings/settings_controller.dart';
import '../../../../theme/motion.dart';
import '../../../../theme/shell_color_scheme.dart';
import '../../../../theme/shell_theme.dart';
import '../../../../theme/tokens.dart';
import '../weather/weather_daily_forecast.dart';
import '../weather/weather_hero_section.dart';
import '../weather/weather_hourly_strip.dart';
import '../weather/weather_metrics_grid.dart';

/// Weather page of the dashboard: live conditions hero, 24-hour trend strip,
/// seven-day forecast, and the metric grid. Data loading starts only when
/// this page is first mounted, so a closed panel performs no network work.
class WeatherView extends ConsumerStatefulWidget {
  const WeatherView({super.key});

  @override
  ConsumerState<WeatherView> createState() => _WeatherViewState();
}

class _WeatherViewState extends ConsumerState<WeatherView> {
  @override
  void initState() {
    super.initState();
    // Deferred past the first build so the controller never mutates provider
    // state synchronously while the widget tree is assembling.
    scheduleMicrotask(() {
      if (mounted) {
        unawaited(ref.read(weatherProvider.notifier).refresh());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(weatherProvider);
    final snapshot = state.snapshot;

    if (snapshot == null) {
      if (state.status == WeatherStatus.failed) {
        return _WeatherErrorPane(
          onRetry: () =>
              unawaited(ref.read(weatherProvider.notifier).forceRefresh()),
        );
      }
      return _WeatherLoadingPane(status: state.status);
    }

    final colors = context.shellColors;
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    final temperatureUnit = ref.watch(
      shellSettingsProvider.select(
        (settings) => settings.weather.temperatureUnit,
      ),
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  snapshot.location.city,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                isZh
                    ? '${_formatClock(snapshot.fetchedAt)} 更新'
                    : 'Updated ${_formatClock(snapshot.fetchedAt)}',
                style: TextStyle(
                  color: colors.textTertiary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(width: 8),
              _RefreshButton(
                onPressed: () => unawaited(
                  ref.read(weatherProvider.notifier).forceRefresh(),
                ),
              ),
            ],
          ),
          if (state.status == WeatherStatus.failed) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  size: 14,
                  color: colors.performanceWarning,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    isZh ? '刷新失败,显示缓存数据' : 'Refresh failed · cached data',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textTertiary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          WeatherHeroSection(
            current: snapshot.current,
            isDay: isDaylight(DateTime.now(), snapshot.days.firstOrNull),
            temperatureUnit: temperatureUnit,
          ),
          const SizedBox(height: 18),
          _SectionCaption(colors: colors, label: isZh ? '逐小时' : 'Hourly'),
          const SizedBox(height: 8),
          WeatherHourlyStrip(
            hours: snapshot.hours,
            days: snapshot.days,
            temperatureUnit: temperatureUnit,
          ),
          const SizedBox(height: 18),
          _SectionCaption(
            colors: colors,
            label: isZh ? '未来 7 天' : 'Next 7 days',
          ),
          const SizedBox(height: 8),
          WeatherDailyForecast(
            days: snapshot.days,
            temperatureUnit: temperatureUnit,
          ),
          const SizedBox(height: 18),
          WeatherMetricsGrid(snapshot: snapshot),
        ],
      ),
    );
  }
}

class _SectionCaption extends StatelessWidget {
  const _SectionCaption({required this.colors, required this.label});

  final ShellColorScheme colors;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        color: colors.textTertiary,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
        decoration: TextDecoration.none,
      ),
    );
  }
}

class _RefreshButton extends StatefulWidget {
  const _RefreshButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_RefreshButton> createState() => _RefreshButtonState();
}

class _RefreshButtonState extends State<_RefreshButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.shellColors;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: Motion.pill,
          curve: Curves.easeOut,
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: _hovered
                ? colors.panelHighlight
                : colors.surfaceContainerHighest,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Icon(
              Icons.refresh_rounded,
              size: 16,
              color: colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _WeatherLoadingPane extends StatelessWidget {
  const _WeatherLoadingPane({required this.status});

  final WeatherStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = context.shellColors;
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    final locating = status == WeatherStatus.locating;

    return SizedBox(
      height: 280,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              locating ? Icons.location_on_rounded : Icons.cloud_queue_rounded,
              size: 38,
              color: colors.textTertiary,
            ),
            const SizedBox(height: 10),
            Text(
              locating
                  ? (isZh ? '正在定位…' : 'Locating…')
                  : (isZh ? '正在加载天气…' : 'Loading weather…'),
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 12.5,
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

class _WeatherErrorPane extends StatelessWidget {
  const _WeatherErrorPane({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = context.shellColors;
    final isZh = Localizations.localeOf(context).languageCode == 'zh';

    return SizedBox(
      height: 280,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 38,
              color: colors.textTertiary,
            ),
            const SizedBox(height: 10),
            Text(
              isZh ? '天气数据加载失败' : 'Failed to load weather',
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(height: 14),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onRetry,
                child: Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: theme.accentPalette.container,
                    borderRadius: theme.borderRadius(ShellShapeScale.full),
                  ),
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.refresh_rounded,
                          size: 15,
                          color: theme.accentPalette.onContainer,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isZh ? '重试' : 'Retry',
                          style: TextStyle(
                            color: theme.accentPalette.onContainer,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatClock(DateTime time) {
  return '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';
}
