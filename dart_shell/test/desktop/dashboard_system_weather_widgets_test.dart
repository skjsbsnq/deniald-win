import 'package:denial_dart_shell/src/desktop/shelf/dashboard/system/network_metric_card.dart';
import 'package:denial_dart_shell/src/desktop/shelf/dashboard/system/storage_battery_cards.dart';
import 'package:denial_dart_shell/src/desktop/shelf/dashboard/views/system_view.dart';
import 'package:denial_dart_shell/src/desktop/shelf/dashboard/views/weather_view.dart';
import 'package:denial_dart_shell/src/desktop/shelf/dashboard/weather/weather_hero_section.dart';
import 'package:denial_dart_shell/src/desktop/shelf/dashboard/weather/weather_metrics_grid.dart';
import 'package:denial_dart_shell/l10n/generated/app_localizations.dart';
import 'package:denial_dart_shell/src/models/battery_status.dart';
import 'package:denial_dart_shell/src/services/system_hardware_service.dart';
import 'package:denial_dart_shell/src/services/weather_service.dart';
import 'package:denial_dart_shell/src/state/system_extended_status.dart';
import 'package:denial_dart_shell/src/state/system_status.dart';
import 'package:denial_dart_shell/src/state/weather_state.dart';
import 'package:denial_dart_shell/src/theme/shell_color_scheme.dart';
import 'package:denial_dart_shell/src/theme/shell_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('system view renders the full metric grid', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cpuUsageProvider.overrideWith(
            (ref) => const LoadSeries(
              current: 0.42,
              history: <double>[0.2, 0.3, 0.35, 0.42],
              temperatureC: 47,
            ),
          ),
          gpuUsageProvider.overrideWith(
            (ref) => const <GpuLoad>[
              GpuLoad(
                id: 'card0',
                label: 'AMD',
                series: LoadSeries(
                  current: 0.10,
                  history: <double>[0.08, 0.10],
                  temperatureC: 52,
                ),
              ),
            ],
          ),
          systemExtendedStatusProvider.overrideWith(
            _FixedExtendedStatusController.new,
          ),
          batteryProvider.overrideWith(_FixedBatteryController.new),
        ],
        child: _wrap(
          const SizedBox(width: 420, height: 640, child: SystemView()),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('CPU'), findsOneWidget);
    expect(find.text('42%'), findsOneWidget);
    expect(find.text('47°C'), findsOneWidget);
    expect(find.text('AMD'), findsOneWidget);
    expect(find.text('10%'), findsOneWidget);
    expect(find.text('52°C'), findsOneWidget);
    expect(find.text('7.8 / 15.4 GB'), findsOneWidget);
    expect(find.text('51%'), findsOneWidget);
    expect(find.text('2.5 MB/s'), findsOneWidget);
    expect(find.text('320.0 KB/s'), findsOneWidget);
    expect(find.text('39%'), findsOneWidget);
    expect(find.text('305 free'), findsOneWidget);
    expect(find.text('80%'), findsOneWidget);
    expect(find.text('Charging'), findsOneWidget);
    expect(find.textContaining('cores'), findsOneWidget);
  });

  testWidgets('system view degrades to empty states without data', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cpuUsageProvider.overrideWith((ref) => LoadSeries.empty),
          gpuUsageProvider.overrideWith((ref) => const <GpuLoad>[]),
          systemExtendedStatusProvider.overrideWith(
            _EmptyExtendedStatusController.new,
          ),
          batteryProvider.overrideWith(_NoBatteryController.new),
        ],
        child: _wrap(
          const SizedBox(width: 420, height: 640, child: SystemView()),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('0%'), findsOneWidget);
    expect(find.text('No battery'), findsOneWidget);
    // Storage and the battery status line both render the unavailable label.
    expect(find.text('Unavailable'), findsNWidgets(2));
    // CPU big number, both network rates, storage and battery percentages.
    expect(find.text('--'), findsNWidgets(5));
  });

  testWidgets('weather view shows the locating pane first', (tester) async {
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

    expect(find.text('Locating…'), findsOneWidget);
  });

  testWidgets('weather view failed without data offers retry', (tester) async {
    final controller = _FixedWeatherController(
      const WeatherState(status: WeatherStatus.failed),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [weatherProvider.overrideWith(() => controller)],
        child: _wrap(
          const SizedBox(width: 420, height: 640, child: WeatherView()),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Failed to load weather'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(controller._forceRefreshCalls, 1);
  });

  testWidgets('weather view ready renders hero, strip, forecast, metrics', (
    tester,
  ) async {
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

    expect(find.text('Beijing'), findsOneWidget);
    expect(find.text('26°'), findsOneWidget);
    expect(find.text('Partly cloudy'), findsOneWidget);
    expect(find.text('Feels like 28°'), findsOneWidget);
    expect(find.text('Hourly'), findsOneWidget);
    // All 24 upcoming hour columns render inside the horizontal strip.
    expect(find.textContaining(':00'), findsAtLeastNWidgets(24));
    expect(find.text('Next 7 days'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Tomorrow'), findsOneWidget);
    expect(find.text('18°'), findsOneWidget);
    expect(find.text('28°'), findsOneWidget);
    expect(find.text('62%'), findsOneWidget);
    expect(find.text('NE'), findsOneWidget);
    expect(find.text('3 · 4.5 m/s'), findsOneWidget);
    expect(find.text('3.2'), findsOneWidget);
    expect(find.text('Moderate'), findsOneWidget);
    expect(find.text('42'), findsOneWidget);
    expect(find.text('Good'), findsOneWidget);
    expect(find.text('PM2.5 10 · PM10 20'), findsOneWidget);
    expect(find.text('1013 hPa'), findsOneWidget);
    expect(find.text('24 km'), findsOneWidget);
    expect(find.text('Sunrise'), findsOneWidget);
    expect(find.text('Sunset'), findsOneWidget);
  });

  group('dashboard formatting helpers', () {
    test('formatDataRate adapts units', () {
      expect(formatDataRate(null), '--');
      expect(formatDataRate(512), '512 B/s');
      expect(formatDataRate(2048), '2.0 KB/s');
      expect(formatDataRate(327680), '320.0 KB/s');
      expect(formatDataRate(2621440), '2.5 MB/s');
    });

    test('formatGigabytes trims large values', () {
      expect(formatGigabytes(8 * 1024 * 1024 * 1024), '8.0');
      expect(formatGigabytes(305 * 1024 * 1024 * 1024), '305');
    });

    test('windDirectionName maps eight sectors', () {
      expect(windDirectionName(45, false), 'NE');
      expect(windDirectionName(45, true), '东北风');
      expect(windDirectionName(350, false), 'N');
      expect(windDirectionName(180, false), 'S');
    });

    test('beaufortLevel follows the scale thresholds', () {
      expect(beaufortLevel(0), 0);
      expect(beaufortLevel(4.5), 3);
      expect(beaufortLevel(32.8), 12);
    });

    test('airQualityIndex takes the worst sub-index', () {
      expect(airQualityIndex(const AirQuality(pm10: 20, pm2_5: 10)), 42);
      expect(airQualityIndex(const AirQuality(pm10: 160, pm2_5: 5)), 103);
    });

    test('rating labels localize', () {
      const colors = ShellColorScheme.dark;
      expect(uvRating(2.9, false, colors).$1, 'Low');
      expect(uvRating(3.2, false, colors).$1, 'Moderate');
      expect(uvRating(6.5, false, colors).$1, 'High');
      expect(uvRating(11, true, colors).$1, '极高');
      expect(airQualityRating(42, false, colors).$1, 'Good');
      expect(airQualityRating(120, true, colors).$1, '轻度污染');
    });

    test('formatVisibility switches to kilometres above 1 km', () {
      expect(formatVisibility(500), '500 m');
      expect(formatVisibility(9400), '9.4 km');
      expect(formatVisibility(24000), '24 km');
    });

    test('weatherConditionFor maps WMO codes with fallback', () {
      expect(weatherConditionFor(0).label(isZh: false), 'Clear');
      expect(weatherConditionFor(95).label(isZh: false), 'Thunderstorm');
      expect(weatherConditionFor(999).label(isZh: false), 'Overcast');
    });

    test('isDaylight honours sunrise and sunset', () {
      final date = DateTime(2026, 9, 7);
      final day = WeatherDay(
        date: date,
        weatherCode: 0,
        maxTemperatureC: 28,
        minTemperatureC: 18,
        sunrise: DateTime(2026, 9, 7, 6),
        sunset: DateTime(2026, 9, 7, 18),
      );
      expect(isDaylight(DateTime(2026, 9, 7, 12), day), isTrue);
      expect(isDaylight(DateTime(2026, 9, 7, 20), day), isFalse);
      expect(isDaylight(DateTime(2026, 9, 7, 12), null), isTrue);
      expect(isDaylight(DateTime(2026, 9, 7, 3), null), isFalse);
    });
  });
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

const int _gib = 1024 * 1024 * 1024;

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
      for (var i = 1; i <= 6; i++)
        WeatherDay(
          date: today.add(Duration(days: i)),
          weatherCode: <int>[1, 3, 61, 80, 95, 0][i - 1],
          maxTemperatureC: 30.0 + i,
          minTemperatureC: 11.0 + i,
          sunrise: today.add(Duration(days: i, hours: 6)),
          sunset: today.add(Duration(days: i, hours: 18)),
        ),
    ],
    airQuality: const AirQuality(pm10: 20, pm2_5: 10),
    fetchedAt: DateTime(now.year, now.month, now.day, 14, 30),
  );
}

class _FixedExtendedStatusController extends SystemExtendedStatusController {
  @override
  SystemExtendedStatus build() {
    return SystemExtendedStatus(
      memory: MemoryUsage(used: (7.8 * _gib).round(), total: (15.4 * _gib).round()),
      downloadBytesPerSecond: 2621440,
      uploadBytesPerSecond: 327680,
      storage: StorageUsage(used: 195 * _gib, total: 500 * _gib),
    );
  }
}

class _EmptyExtendedStatusController extends SystemExtendedStatusController {
  @override
  SystemExtendedStatus build() => const SystemExtendedStatus();
}

class _FixedBatteryController extends BatteryController {
  @override
  BatteryStatus build() {
    return const BatteryStatus(capacity: 80, charging: true, acOnline: true);
  }
}

class _NoBatteryController extends BatteryController {
  @override
  BatteryStatus build() => BatteryStatus.unknown;
}

class _FixedWeatherController extends WeatherController {
  _FixedWeatherController(this.initial);

  final WeatherState initial;
  int _forceRefreshCalls = 0;

  @override
  WeatherState build() => initial;

  @override
  Future<void> refresh() async {}

  @override
  Future<void> forceRefresh() async {
    _forceRefreshCalls++;
  }
}
