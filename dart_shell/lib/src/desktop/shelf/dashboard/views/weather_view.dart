import 'dart:async';

import 'package:flutter/material.dart' show Icons, Scrollbar;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../localization/denial_localizations.dart';
import '../../../../services/weather_service.dart';
import '../../../../settings/settings_application.dart';
import '../../../../settings/settings_controller.dart';
import '../../../../settings/widgets/settings_navigation.dart';
import '../../../../state/weather_state.dart';
import '../../../../theme/shell_color_scheme.dart';
import '../../../../theme/shell_theme.dart';
import '../../../../theme/tokens.dart';
import '../../../../widgets/shell_hover_pill.dart';
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
  final ScrollController _scrollController = ScrollController();

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
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(weatherProvider);
    final snapshot = state.snapshot;

    if (snapshot == null) {
      if (state.status == WeatherStatus.failed) {
        return _WeatherErrorPane(
          locationFailed: state.error is WeatherLocationFailure,
          onRetry: () =>
              unawaited(ref.read(weatherProvider.notifier).forceRefresh()),
          onChooseCity: () =>
              launchSettingsPage(ref, context, SettingsPageId.weather),
        );
      }
      return _WeatherLoadingPane(status: state.status);
    }

    final theme = context.shellTheme;
    final colors = context.shellColors;
    final l10n = context.l10n;
    final temperatureUnit = ref.watch(
      shellSettingsProvider.select(
        (settings) => settings.weather.temperatureUnit,
      ),
    );

    // The scrollbar shares an explicit controller with the scroll view
    // because the shell provides no PrimaryScrollController to adopt.
    return Scrollbar(
      controller: _scrollController,
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (state.status == WeatherStatus.failed) ...[
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
                      l10n.weatherCachedDataNotice,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.text.labelSmall.copyWith(
                        color: colors.textTertiary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            WeatherHeroSection(
              snapshot: snapshot,
              // Day/night must be resolved on the city's wall clock; the
              // device clock would flip the glyph across time zones.
              isDay: isDaylight(
                cityNow(snapshot.utcOffsetSeconds),
                snapshot.days.firstOrNull,
              ),
              temperatureUnit: temperatureUnit,
              onRefresh: () =>
                  unawaited(ref.read(weatherProvider.notifier).forceRefresh()),
            ),
            // Sections whose data is absent collapse together with their
            // heading instead of leaving an orphaned caption behind.
            if (snapshot.hours.isNotEmpty) ...[
              const SizedBox(height: 18),
              _SectionCaption(colors: colors, label: l10n.weatherSectionHourly),
              const SizedBox(height: 8),
              WeatherHourlyStrip(
                hours: snapshot.hours,
                days: snapshot.days,
                temperatureUnit: temperatureUnit,
                utcOffsetSeconds: snapshot.utcOffsetSeconds,
              ),
            ],
            if (snapshot.days.isNotEmpty) ...[
              const SizedBox(height: 18),
              _SectionCaption(colors: colors, label: l10n.weatherSectionDaily),
              const SizedBox(height: 8),
              WeatherDailyForecast(
                days: snapshot.days,
                temperatureUnit: temperatureUnit,
              ),
            ],
            const SizedBox(height: 18),
            WeatherMetricsGrid(snapshot: snapshot),
          ],
        ),
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
      style: context.shellTheme.text.labelSmall.copyWith(
        color: colors.textTertiary,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

/// Skeleton loading pane: static tonal placeholder blocks echoing the hero
/// card, the hourly strip, and the daily list so a cold open paints the
/// page's shape instead of a bare spinner. The status caption below keeps
/// the locating/loading wording visible for context.
class _WeatherLoadingPane extends StatelessWidget {
  const _WeatherLoadingPane({required this.status});

  final WeatherStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = context.shellColors;
    final l10n = context.l10n;
    final locating = status == WeatherStatus.locating;

    return Column(
      key: const Key('weather-loading-skeleton'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _SkeletonBlock(height: 200, radius: ShellShapeScale.extraLarge),
        const SizedBox(height: 18),
        const _SkeletonBlock(height: 12, width: 96),
        const SizedBox(height: 8),
        const _SkeletonBlock(height: 110, radius: ShellShapeScale.large),
        const SizedBox(height: 18),
        const _SkeletonBlock(height: 12, width: 72),
        const SizedBox(height: 8),
        const _SkeletonBlock(height: 170, radius: ShellShapeScale.large),
        const SizedBox(height: 18),
        Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                locating
                    ? Icons.location_on_rounded
                    : Icons.cloud_queue_rounded,
                size: 16,
                color: colors.textTertiary,
              ),
              const SizedBox(width: 8),
              Text(
                locating
                    ? l10n.weatherLoadingLocating
                    : l10n.weatherLoadingData,
                style: theme.text.bodyMedium.copyWith(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One tonal placeholder slab of the loading skeleton.
class _SkeletonBlock extends StatelessWidget {
  const _SkeletonBlock({
    required this.height,
    this.width,
    this.radius = ShellShapeScale.small,
  });

  final double height;
  final double? width;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = context.shellColors;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        height: height,
        width: width,
        decoration: BoxDecoration(
          color: theme.panelColor(colors.surfaceContainer),
          borderRadius: theme.borderRadius(radius),
        ),
      ),
    );
  }
}

class _WeatherErrorPane extends StatelessWidget {
  const _WeatherErrorPane({
    required this.onRetry,
    required this.onChooseCity,
    this.locationFailed = false,
  });

  final VoidCallback onRetry;
  final VoidCallback onChooseCity;

  /// Location discovery failing is actionable (switch to a manual city),
  /// unlike a network failure where only retrying helps.
  final bool locationFailed;

  @override
  Widget build(BuildContext context) {
    final colors = context.shellColors;
    final l10n = context.l10n;

    return SizedBox(
      height: 280,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              locationFailed
                  ? Icons.location_off_rounded
                  : Icons.error_outline_rounded,
              size: 38,
              color: colors.textTertiary,
            ),
            const SizedBox(height: 10),
            Text(
              locationFailed
                  ? l10n.weatherErrorLocationUnavailable
                  : l10n.weatherErrorLoadFailed,
              style: context.shellTheme.text.bodyMedium.copyWith(
                color: colors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _WeatherErrorAction(
                  icon: Icons.refresh_rounded,
                  label: l10n.weatherRetry,
                  onPressed: onRetry,
                ),
                if (locationFailed) ...[
                  const SizedBox(width: 8),
                  _WeatherErrorAction(
                    icon: Icons.location_city_rounded,
                    label: l10n.weatherChooseCity,
                    onPressed: onChooseCity,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WeatherErrorAction extends StatelessWidget {
  const _WeatherErrorAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;

    return ShellHoverPill(
      onTap: onPressed,
      semanticLabel: label,
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      color: theme.accentPalette.container,
      radius: ShellShapeScale.full,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: theme.accentPalette.onContainer),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.text.labelMediumEmphasized.copyWith(
              color: theme.accentPalette.onContainer,
            ),
          ),
        ],
      ),
    );
  }
}
