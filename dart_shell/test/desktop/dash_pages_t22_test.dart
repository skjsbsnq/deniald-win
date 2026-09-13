import 'package:denial_dart_shell/l10n/generated/app_localizations.dart';
import 'package:denial_dart_shell/src/desktop/shelf/dashboard/dashboard_card_tone.dart';
import 'package:denial_dart_shell/src/desktop/shelf/dashboard/dashboard_tab_bar.dart';
import 'package:denial_dart_shell/src/desktop/shelf/dashboard/views/weather_view.dart';
import 'package:denial_dart_shell/src/desktop/shelf/dashboard/weather/weather_hero_section.dart';
import 'package:denial_dart_shell/src/services/weather_service.dart';
import 'package:denial_dart_shell/src/state/weather_state.dart';
import 'package:denial_dart_shell/src/theme/shell_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('dash tab pill stretches wider than its cell mid-flight', (
    tester,
  ) async {
    _TabBarHost.selected = DashboardTab.info;
    addTearDown(() => _TabBarHost.selected = DashboardTab.info);
    await tester.pumpWidget(
      _wrap(const SizedBox(height: 52, width: 420, child: _TabBarHost())),
    );
    await tester.pump();

    const cellWidth = (420 - 12) / 3; // bar padding is 6 on each side.
    Size pillSize() =>
        tester.getSize(find.byKey(const Key('dashboard-tab-pill')));
    expect(pillSize().width, cellWidth);

    await tester.tap(find.text('Weather'));
    await tester.pump();
    // Mid-flight the spring carries velocity, so the indicator deforms wider
    // than a single cell before settling back to the exact cell width.
    await tester.pump(const Duration(milliseconds: 16));
    expect(pillSize().width, greaterThan(cellWidth));

    await tester.pumpAndSettle();
    expect(pillSize().width, cellWidth);
    expect(_TabBarHost.selected, DashboardTab.weather);
  });

  test('dash weather hero maps conditions onto tonal families', () {
    // Clear-ish daylight reads as primaryContainer; night, overcast, and
    // precipitation rotate to the tertiary family.
    expect(weatherHeroTone(0, true), DashboardCardTone.primary);
    expect(weatherHeroTone(2, true), DashboardCardTone.primary);
    expect(weatherHeroTone(0, false), DashboardCardTone.tertiary);
    expect(weatherHeroTone(3, true), DashboardCardTone.tertiary);
    expect(weatherHeroTone(61, true), DashboardCardTone.tertiary);
    expect(weatherHeroTone(95, false), DashboardCardTone.tertiary);
  });

  testWidgets('dash weather loading paints the tonal skeleton', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          weatherProvider.overrideWith(
            () => _FixedWeatherController(
              const WeatherState(status: WeatherStatus.locating),
            ),
          ),
        ],
        child: _wrap(
          const SizedBox(width: 420, height: 640, child: WeatherView()),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('weather-loading-skeleton')), findsOneWidget);
    // The locating caption stays visible so the pane still says what it is
    // doing instead of being a shapeless spinner.
    expect(find.text('Locating…'), findsOneWidget);
  });

  testWidgets('dash weather hero segmented bar swaps its pane', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          weatherProvider.overrideWith(
            () => _FixedWeatherController(
              WeatherState(
                status: WeatherStatus.ready,
                snapshot: _snapshot(),
                lastFetchedAt: DateTime(2026, 9, 7, 14, 30),
              ),
            ),
          ),
        ],
        child: _wrap(
          const SizedBox(width: 420, height: 900, child: WeatherView()),
        ),
      ),
    );
    await tester.pump();

    // Conditions pane is the default: condition, feels-like, high/low.
    expect(find.byKey(const Key('weather-hero-card')), findsOneWidget);
    expect(find.text('Partly cloudy'), findsOneWidget);
    expect(find.textContaining('Feels like 28°'), findsOneWidget);
    expect(find.textContaining('H 28°'), findsOneWidget);

    // Scope taps to the hero card: the metric grid below carries labels
    // with the same wording.
    final hero = find.byKey(const Key('weather-hero-card'));
    await tester.tap(
      find.descendant(of: hero, matching: find.text('Air quality')),
    );
    await tester.pumpAndSettle();
    expect(find.text('AQI 42'), findsOneWidget);
    // The hero pane and the metrics grid both carry the PM pair.
    expect(find.text('PM2.5 10 · PM10 20'), findsNWidgets(2));

    await tester.tap(find.descendant(of: hero, matching: find.text('Wind')));
    await tester.pumpAndSettle();
    expect(find.text('NE'), findsWidgets);
    expect(find.text('3 · 4.5 m/s'), findsWidgets);
  });
}

class _TabBarHost extends StatefulWidget {
  const _TabBarHost();

  static DashboardTab selected = DashboardTab.info;

  @override
  State<_TabBarHost> createState() => _TabBarHostState();
}

class _TabBarHostState extends State<_TabBarHost> {
  @override
  Widget build(BuildContext context) {
    return DashboardTabBar(
      selected: _TabBarHost.selected,
      onSelected: (tab) => setState(() => _TabBarHost.selected = tab),
    );
  }
}

class _FixedWeatherController extends WeatherController {
  _FixedWeatherController(this.initial);

  final WeatherState initial;

  @override
  WeatherState build() => initial;

  @override
  Future<void> refresh() async {}

  @override
  Future<void> forceRefresh() async {}
}

WeatherSnapshot _snapshot() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return WeatherSnapshot(
    location: const GeoLocation(
      latitude: 39.9,
      longitude: 116.4,
      city: 'Beijing',
    ),
    current: WeatherCurrent(
      temperatureC: 26.4,
      apparentTemperatureC: 28.1,
      weatherCode: 2,
      humidityPercent: 62,
      windSpeedMs: 4.5,
      windDirectionDeg: 45,
      uvIndex: 3.2,
      pressureHpa: 1013,
      visibilityM: 24000,
    ),
    hours: <WeatherHour>[
      for (var i = 1; i <= 26; i++)
        WeatherHour(
          time: now.add(Duration(hours: i)),
          temperatureC: 21.0 + (i % 3),
          weatherCode: i % 2,
          precipitationProbability: (i * 7) % 100,
        ),
    ],
    days: <WeatherDay>[
      WeatherDay(
        date: today,
        weatherCode: 2,
        maxTemperatureC: 28,
        minTemperatureC: 18,
        sunrise: now.subtract(const Duration(hours: 6)),
        sunset: now.add(const Duration(hours: 6)),
      ),
    ],
    airQuality: const AirQuality(pm10: 20, pm2_5: 10),
    fetchedAt: DateTime(now.year, now.month, now.day, 14, 30),
  );
}

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: Scaffold(
      backgroundColor: const Color(0xff121212),
      body: ShellTheme(data: const ShellThemeData(), child: child),
    ),
  );
}
