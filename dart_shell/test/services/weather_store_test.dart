import 'dart:io';

import 'package:denial_dart_shell/src/launcher/runtime_paths.dart';
import 'package:denial_dart_shell/src/services/weather_service.dart';
import 'package:denial_dart_shell/src/services/weather_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempHome;
  late WeatherFileStore store;

  setUp(() {
    tempHome = Directory.systemTemp.createTempSync('denial-weather-store-');
    store = WeatherFileStore(
      paths: RuntimePaths(environment: <String, String>{
        'HOME': tempHome.path,
      }),
    );
  });

  tearDown(() {
    tempHome.deleteSync(recursive: true);
  });

  test('a snapshot survives a disk round trip', () async {
    final snapshot = _snapshot();

    await store.write(snapshot);
    final restored = await store.read();

    expect(restored, isNotNull);
    expect(restored!.location, snapshot.location);
    expect(restored.current.temperatureC, snapshot.current.temperatureC);
    expect(restored.current.apparentTemperatureC,
        snapshot.current.apparentTemperatureC);
    expect(restored.hours.length, snapshot.hours.length);
    expect(restored.hours.first.time, snapshot.hours.first.time);
    expect(restored.days.length, snapshot.days.length);
    expect(restored.days.first.sunrise, snapshot.days.first.sunrise);
    expect(restored.airQuality?.pm2_5, snapshot.airQuality?.pm2_5);
    expect(restored.fetchedAt, snapshot.fetchedAt);
  });

  test('reading a missing or corrupt file yields null', () async {
    expect(await store.read(), isNull);

    final file = File(
      '${tempHome.path}/.local/state/denial/weather.json',
    );
    await file.parent.create(recursive: true);
    await file.writeAsString('{not json');
    expect(await store.read(), isNull);
  });

  test('writes are atomic and survive a partial temporary file', () async {
    final file = File(
      '${tempHome.path}/.local/state/denial/weather.json',
    );
    await file.parent.create(recursive: true);
    // A leftover temporary file from a crashed write must not corrupt reads.
    await File('${file.path}.tmp').writeAsString('garbage');

    await store.write(_snapshot());
    expect(await file.readAsString(), startsWith('{'));

    final restored = await store.read();
    expect(restored, isNotNull);
  });
}

WeatherSnapshot _snapshot() {
  final now = DateTime(2026, 9, 7, 14, 30);
  final today = DateTime(2026, 9, 7);
  return WeatherSnapshot(
    location: const GeoLocation(
      latitude: 39.9,
      longitude: 116.4,
      city: 'Beijing',
    ),
    current: const WeatherCurrent(
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
      WeatherHour(
        time: now.add(const Duration(hours: 1)),
        temperatureC: 21.5,
        weatherCode: 1,
        precipitationProbability: 30,
      ),
    ],
    days: <WeatherDay>[
      WeatherDay(
        date: today,
        weatherCode: 2,
        maxTemperatureC: 28,
        minTemperatureC: 18,
        sunrise: today.add(const Duration(hours: 6)),
        sunset: today.add(const Duration(hours: 18)),
      ),
    ],
    airQuality: const AirQuality(pm10: 20, pm2_5: 10),
    fetchedAt: now,
  );
}
