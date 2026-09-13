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
import '../weather/weather_background.dart';
import '../weather/weather_daily_forecast.dart';
import '../weather/weather_hero_section.dart';
import '../weather/weather_hourly_strip.dart';
import '../weather/weather_metrics_grid.dart';
import '../weather/weather_reveal.dart';
import '../weather/weather_trend_chart.dart';
import '../weather/weather_visibility.dart';

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

  /// Ambient-driver plumbing of the clavis port: scroll fade for the
  /// particle background, the first-card top edge that rain splashes against
  /// (`rainBounceY`), and the page-activity flag the background publishes so
  /// reveals, rolling values and Lottie icons idle while another dashboard
  /// tab covers this still-mounted page.
  final ValueNotifier<double> _scrollProgress = ValueNotifier<double>(0);
  final ValueNotifier<double> _rainBounceY = ValueNotifier<double>(0);
  final ValueNotifier<bool> _pageActive = ValueNotifier<bool>(false);
  final GlobalKey _firstCardKey = GlobalKey();
  bool _bounceMeasurePending = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
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
    _scrollProgress.dispose();
    _rainBounceY.dispose();
    _pageActive.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    final extent = position.maxScrollExtent;
    final progress = extent > 0
        ? (position.pixels / extent).clamp(0.0, 1.0).toDouble()
        : 0.0;
    if ((progress - _scrollProgress.value).abs() > 0.001) {
      _scrollProgress.value = progress;
    }
    _measureBounce();
  }

  void _scheduleBounceMeasure() {
    if (_bounceMeasurePending) {
      return;
    }
    _bounceMeasurePending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bounceMeasurePending = false;
      if (mounted) {
        _measureBounce();
      }
    });
  }

  /// `rainBounceY` in background coordinates: the first forecast card's top
  /// edge, the line rain splashes and snow settles against in the reference
  /// (`flick.y + dailyForecastCard.y - flick.contentY`).
  void _measureBounce() {
    final card = _firstCardKey.currentContext?.findRenderObject();
    final page = context.findRenderObject();
    if (card is! RenderBox || page is! RenderBox) {
      // No measurable card (layout pass pending or none keyed this build):
      // drop any stale edge so the background uses its default instead of a
      // coordinate that no longer exists.
      if (_rainBounceY.value != 0) {
        _rainBounceY.value = 0;
      }
      return;
    }
    final y = card.localToGlobal(Offset.zero, ancestor: page).dy;
    if ((y - _rainBounceY.value).abs() > 0.5) {
      _rainBounceY.value = y;
    }
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

    final colors = context.shellColors;
    final l10n = context.l10n;
    final temperatureUnit = ref.watch(
      shellSettingsProvider.select(
        (settings) => settings.weather.temperatureUnit,
      ),
    );
    final durationScale = ref.watch(
      shellSettingsProvider.select(
        (settings) => settings.animations.durationScale,
      ),
    );
    final animationsEnabled = !MediaQuery.disableAnimationsOf(context);
    // Day/night must be resolved on the city's wall clock; the device clock
    // would flip the glyph across time zones.
    final isDay = isDaylight(
      cityNow(snapshot.utcOffsetSeconds),
      snapshot.days.firstOrNull,
    );

    _scheduleBounceMeasure();

    // The scrollbar shares an explicit controller with the scroll view
    // because the shell provides no PrimaryScrollController to adopt.
    return WeatherPageActivity(
      active: _pageActive,
      durationScale: durationScale,
      animationsEnabled: animationsEnabled,
      child: Stack(
        children: [
          Positioned.fill(
            child: WeatherBackground(
              weatherCode: snapshot.current.weatherCode,
              night: !isDay,
              windSpeedMs: snapshot.current.windSpeedMs,
              scrollProgress: _scrollProgress,
              rainBounceY: _rainBounceY,
              animationsEnabled: animationsEnabled,
              motionScale: durationScale > 0 ? 1 / durationScale : 1.0,
              activitySink: _pageActive,
            ),
          ),
          Positioned.fill(
            child: Scrollbar(
              controller: _scrollController,
              child: SingleChildScrollView(
                controller: _scrollController,
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
                          l10n.weatherUpdated(_formatClock(snapshot.fetchedAt)),
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
                              l10n.weatherCachedDataNotice,
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
                    WeatherReveal(
                      staggerIndex: 0,
                      child: WeatherHeroSection(
                        current: snapshot.current,
                        isDay: isDay,
                        temperatureUnit: temperatureUnit,
                      ),
                    ),
                    // Sections whose data is absent collapse together with
                    // their heading instead of leaving an orphaned caption
                    // behind.
                    // `rainBounceY` binds the first trend/forecast card under
                    // the hero — the slot clavis gives `dailyForecastCard`.
                    // When a section is absent the key moves down to the next
                    // existing card so the measured edge never falls back to
                    // a missing-key default.
                    if (snapshot.hours.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      WeatherReveal(
                        staggerIndex: 1,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _SectionCaption(
                              colors: colors,
                              label: l10n.weatherSectionHourly,
                            ),
                            const SizedBox(height: 8),
                            WeatherHourlyTrendCard(
                              key: _firstCardKey,
                              hours: snapshot.hours,
                              days: snapshot.days,
                              temperatureUnit: temperatureUnit,
                              utcOffsetSeconds: snapshot.utcOffsetSeconds,
                            ),
                            const SizedBox(height: 8),
                            WeatherHourlyStrip(
                              hours: snapshot.hours,
                              days: snapshot.days,
                              temperatureUnit: temperatureUnit,
                              utcOffsetSeconds: snapshot.utcOffsetSeconds,
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (snapshot.days.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      WeatherReveal(
                        staggerIndex: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _SectionCaption(
                              colors: colors,
                              label: l10n.weatherSectionDaily,
                            ),
                            const SizedBox(height: 8),
                            WeatherDailyTrendCard(
                              key: snapshot.hours.isEmpty
                                  ? _firstCardKey
                                  : null,
                              days: snapshot.days,
                              hours: snapshot.hours,
                              temperatureUnit: temperatureUnit,
                              utcOffsetSeconds: snapshot.utcOffsetSeconds,
                            ),
                            const SizedBox(height: 8),
                            WeatherDailyForecast(
                              days: snapshot.days,
                              temperatureUnit: temperatureUnit,
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    WeatherReveal(
                      staggerIndex: 3,
                      child: WeatherMetricsGrid(
                        // Last resort target: with neither trend card present
                        // this is still the first card under the hero, the
                        // edge the reference measures.
                        key: snapshot.hours.isEmpty && snapshot.days.isEmpty
                            ? _firstCardKey
                            : null,
                        snapshot: snapshot,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
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
        decoration: TextDecoration.none,
      ),
    );
  }
}

class _RefreshButton extends StatelessWidget {
  const _RefreshButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.shellColors;

    // A square pill at full scale renders the same circle the bespoke
    // BoxShape.circle decoration did.
    return ShellHoverPill(
      onTap: onPressed,
      width: 30,
      height: 30,
      color: colors.surfaceContainerHighest,
      hoverColor: colors.panelHighlight,
      child: Icon(Icons.refresh_rounded, size: 16, color: colors.textSecondary),
    );
  }
}

class _WeatherLoadingPane extends StatelessWidget {
  const _WeatherLoadingPane({required this.status});

  final WeatherStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = context.shellColors;
    final l10n = context.l10n;
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
              locating ? l10n.weatherLoadingLocating : l10n.weatherLoadingData,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 13,
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
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.none,
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

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
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
                Icon(icon, size: 15, color: theme.accentPalette.onContainer),
                const SizedBox(width: 6),
                Text(
                  label,
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
    );
  }
}

String _formatClock(DateTime time) {
  return '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';
}
