import 'dart:async';

import 'package:denial_dart_shell/src/desktop/shelf/dashboard/system/network_metric_card.dart';
import 'package:denial_dart_shell/src/desktop/shelf/dashboard/system/storage_battery_cards.dart';
import 'package:denial_dart_shell/src/desktop/shelf/dashboard/views/system_view.dart';
import 'package:denial_dart_shell/src/desktop/shelf/dashboard/views/weather_view.dart';
import 'package:denial_dart_shell/src/desktop/shelf/dashboard/weather/weather_hero_section.dart';
import 'package:denial_dart_shell/src/desktop/shelf/dashboard/weather/weather_metrics_grid.dart';
import 'package:denial_dart_shell/src/desktop/shelf/dashboard/weather/weather_temperature.dart';
import 'package:denial_dart_shell/l10n/generated/app_localizations.dart';
import 'package:denial_dart_shell/src/models/battery_status.dart';
import 'package:denial_dart_shell/src/services/system_hardware_service.dart';
import 'package:denial_dart_shell/src/services/weather_service.dart';
import 'package:denial_dart_shell/src/services/weather_store.dart';
import 'package:denial_dart_shell/src/settings/settings_controller.dart';
import 'package:denial_dart_shell/src/settings/shell_settings.dart';
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

  testWidgets('extended status reports storage from the first sample', (
    tester,
  ) async {
    final service = _ScriptedHardwareService();
    final container = ProviderContainer.test(
      overrides: [systemHardwareServiceProvider.overrideWithValue(service)],
    );
    final sub = container.listen(systemExtendedStatusProvider, (_, _) {});
    try {
      await tester.pump();
      await tester.pump();
      final first = container.read(systemExtendedStatusProvider);
      expect(first.memory, isNotNull);
      // Regression: the very first sample discarded its results and storage
      // was never written, leaving the card on "Unavailable" forever.
      expect(first.storage, isNotNull);
      // A rate needs a completed counter pair; the first sample has none.
      expect(first.downloadBytesPerSecond, isNull);
      expect(service.storageReads, 1);

      // Let real wall-clock time pass so the rate interval clears the 0.5 s
      // guard, then take the second sample.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 600)),
      );
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      final second = container.read(systemExtendedStatusProvider);
      expect(second.storage, isNotNull);
      expect(second.downloadBytesPerSecond, greaterThan(0));
      expect(second.uploadBytesPerSecond, greaterThan(0));
      // The `df` subprocess stays on its slow cadence between samples.
      expect(service.storageReads, 1);

      // Advance the full storage refresh period: exactly one more reading.
      for (var tick = 0; tick < 30; tick++) {
        await tester.pump(const Duration(seconds: 2));
        await tester.pump();
      }
      expect(service.storageReads, 2);
      expect(
        container.read(systemExtendedStatusProvider).storage?.fraction,
        closeTo(0.4, 0.01),
      );
    } finally {
      // Tear the sampler down inside the body: addTearDown runs after the
      // binding's pending-timer invariant, so its periodic timer must be
      // cancelled before the test completes.
      sub.close();
      container.dispose();
    }
  });

  testWidgets('weather service outlives an in-flight fetch', (tester) async {
    final events = <String>[];
    final store = _MemoryWeatherStore();
    final container = ProviderContainer.test(
      overrides: [
        weatherServiceProvider.overrideWith((ref) {
          final service = _SlowWeatherService(events);
          ref.onDispose(() {
            events.add('service-disposed');
            service.dispose();
          });
          return service;
        }),
        weatherStoreProvider.overrideWithValue(store),
        // The real settings controller talks to the platform bridge, whose
        // subscription timer never fires inside fake async.
        shellSettingsProvider.overrideWith(_DefaultWeatherSettingsController.new),
      ],
    );
    addTearDown(container.dispose);
    final sub = container.listen(weatherProvider, (_, _) {});
    addTearDown(sub.close);

    unawaited(container.read(weatherProvider.notifier).refresh());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Regression: a transiently-read autoDispose service was reclaimed while
    // the fetch was still awaiting, and its dispose force-closed the
    // HttpClient, aborting the request into a permanent failure state.
    expect(events, containsAllInOrder(<String>['fetch-start', 'fetch-end']));
    expect(events, isNot(contains('service-disposed')));

    final state = container.read(weatherProvider);
    expect(state.status, WeatherStatus.ready);
    expect(state.snapshot, isNotNull);
    expect(state.snapshot?.location.city, 'Beijing');
    // A successful fetch persists to the store for the next panel open.
    expect(store.written?.location.city, 'Beijing');
  });

  test('weather controller hydrates from disk without geolocation', () async {
    final store = _MemoryWeatherStore()
      ..written = _snapshot().copyWithFreshTimestamp();
    final service = _CountingWeatherService();
    final container = ProviderContainer.test(
      overrides: [
        weatherServiceProvider.overrideWithValue(service),
        weatherStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(container.dispose);
    final sub = container.listen(weatherProvider, (_, _) {});
    addTearDown(sub.close);

    await container.read(weatherProvider.notifier).refresh();

    // Regression: every panel open re-ran IP geolocation because the
    // autoDispose controller had no disk cache to hydrate from.
    expect(service.locationLookups, 0);
    expect(service.fetches, 0);
    final state = container.read(weatherProvider);
    expect(state.status, WeatherStatus.ready);
    expect(state.snapshot?.location.city, 'Beijing');
  });

  test('weather controller refreshes in background when cache is stale', () async {
    final stale = DateTime.now().subtract(
      weatherCacheLifetime + const Duration(minutes: 1),
    );
    final store = _MemoryWeatherStore()
      ..written = _snapshot().withFetchedAt(stale);
    final service = _CountingWeatherService();
    final container = ProviderContainer.test(
      overrides: [
        weatherServiceProvider.overrideWithValue(service),
        weatherStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(container.dispose);
    final sub = container.listen(weatherProvider, (_, _) {});
    addTearDown(sub.close);

    await container.read(weatherProvider.notifier).refresh();

    // The cached location is reused, so no new geolocation lookup happens,
    // but the stale snapshot triggers a fresh fetch that lands back on disk.
    expect(service.locationLookups, 0);
    expect(service.fetches, 1);
    final state = container.read(weatherProvider);
    expect(state.status, WeatherStatus.ready);
    expect(state.snapshot?.location.city, 'Beijing');
    expect(store.written?.location.city, 'Beijing');
  });

  test('weather controller uses the manual city without geolocation', () async {
    final store = _MemoryWeatherStore()
      ..written = _snapshot().copyWithFreshTimestamp();
    final service = _CountingWeatherService();
    final container = ProviderContainer.test(
      overrides: [
        weatherServiceProvider.overrideWithValue(service),
        weatherStoreProvider.overrideWithValue(store),
        shellSettingsProvider.overrideWith(
          () => _ManualWeatherSettingsController(),
        ),
      ],
    );
    addTearDown(container.dispose);
    final sub = container.listen(weatherProvider, (_, _) {});
    addTearDown(sub.close);

    await container.read(weatherProvider.notifier).forceRefresh();

    // Manual mode must resolve the location from settings alone.
    expect(service.locationLookups, 0);
    expect(service.fetches, 1);
    expect(service.lastFetched?.city, 'Shenzhen');
    final state = container.read(weatherProvider);
    expect(state.status, WeatherStatus.ready);
    expect(state.snapshot?.location.city, 'Shenzhen');
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

    test('formatTemperature converts units and rounds', () {
      expect(formatTemperature(26.4, ShellTemperatureUnit.celsius), '26°');
      expect(formatTemperature(-3.6, ShellTemperatureUnit.celsius), '-4°');
      // 26.4°C is 79.52°F.
      expect(formatTemperature(26.4, ShellTemperatureUnit.fahrenheit), '80°');
      expect(formatTemperature(0, ShellTemperatureUnit.fahrenheit), '32°');
      expect(formatTemperature(-40, ShellTemperatureUnit.fahrenheit), '-40°');
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
      memory: MemoryUsage(
        used: (7.8 * _gib).round(),
        total: (15.4 * _gib).round(),
      ),
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

/// Scripted hardware reader with monotonically growing network counters and
/// a fixed 40% storage occupancy.
class _ScriptedHardwareService extends SystemHardwareService {
  int storageReads = 0;
  int _rx = 1024;
  int _tx = 512;

  @override
  Future<MemoryUsage?> readMemory() async {
    return MemoryUsage(
      used: 8 * 1024 * 1024 * 1024,
      total: 16 * 1024 * 1024 * 1024,
    );
  }

  @override
  Future<NetworkCounters?> readNetworkCounters() async {
    _rx += 2621440;
    _tx += 327680;
    return NetworkCounters(rxBytes: _rx, txBytes: _tx);
  }

  @override
  Future<StorageUsage?> readRootStorage() async {
    storageReads++;
    return StorageUsage(
      used: 200 * 1024 * 1024 * 1024,
      total: 500 * 1024 * 1024 * 1024,
    );
  }
}

/// Weather service whose fetch takes a moment, so the test can observe
/// whether the provider layer reclaims it mid-flight.
class _SlowWeatherService extends WeatherService {
  _SlowWeatherService(this.events);

  final List<String> events;

  @override
  Future<GeoLocation?> resolveLocation() async {
    return const GeoLocation(latitude: 39.9, longitude: 116.4, city: 'Beijing');
  }

  @override
  Future<WeatherSnapshot> fetch(GeoLocation location) async {
    events.add('fetch-start');
    await Future<void>.delayed(const Duration(milliseconds: 120));
    events.add('fetch-end');
    return _snapshot();
  }
}

extension _SnapshotTestCopy on WeatherSnapshot {
  /// Copy with a fetched-at of now, marking the cache fresh.
  WeatherSnapshot copyWithFreshTimestamp() {
    return WeatherSnapshot(
      location: location,
      current: current,
      hours: hours,
      days: days,
      airQuality: airQuality,
      fetchedAt: DateTime.now(),
    );
  }

  WeatherSnapshot withFetchedAt(DateTime time) {
    return WeatherSnapshot(
      location: location,
      current: current,
      hours: hours,
      days: days,
      airQuality: airQuality,
      fetchedAt: time,
    );
  }
}

class _MemoryWeatherStore implements WeatherStore {
  WeatherSnapshot? written;

  @override
  Future<WeatherSnapshot?> read() async => written;

  @override
  Future<void> write(WeatherSnapshot snapshot) async {
    written = snapshot;
  }
}

/// Counts network calls so tests can assert that cached or manual locations
/// never fall back to IP geolocation. Fetches report the requested location
/// so assertions can tell which coordinates were actually used.
class _CountingWeatherService extends WeatherService {
  int locationLookups = 0;
  int fetches = 0;
  GeoLocation? lastFetched;

  @override
  Future<GeoLocation?> resolveLocation() async {
    locationLookups++;
    return const GeoLocation(latitude: 39.9, longitude: 116.4, city: 'Beijing');
  }

  @override
  Future<WeatherSnapshot> fetch(GeoLocation location) async {
    fetches++;
    lastFetched = location;
    return _snapshotAt(location);
  }
}

WeatherSnapshot _snapshotAt(GeoLocation location) {
  final snapshot = _snapshot();
  return WeatherSnapshot(
    location: location,
    current: snapshot.current,
    hours: snapshot.hours,
    days: snapshot.days,
    airQuality: snapshot.airQuality,
    fetchedAt: DateTime.now(),
  );
}

class _ManualWeatherSettingsController extends ShellSettingsController {
  @override
  ShellSettings build() {
    return const ShellSettings(
      weather: ShellWeatherSettings(
        locationMode: ShellWeatherLocationMode.manual,
        manualLocation: ShellManualLocation(
          latitude: 22.5,
          longitude: 114.06,
          city: 'Shenzhen',
        ),
      ),
    );
  }
}

/// Synchronous settings controller that avoids the platform bridge so it can
/// run inside fake-async widget tests.
class _DefaultWeatherSettingsController extends ShellSettingsController {
  @override
  ShellSettings build() => const ShellSettings();
}
