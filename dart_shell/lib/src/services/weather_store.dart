import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../launcher/launcher_providers.dart';
import '../launcher/runtime_paths.dart';
import 'weather_service.dart';

final weatherStoreProvider = Provider<WeatherStore>((ref) {
  return WeatherFileStore(paths: ref.watch(runtimePathsProvider));
}, isAutoDispose: true);

abstract interface class WeatherStore {
  Future<WeatherSnapshot?> read();

  Future<void> write(WeatherSnapshot snapshot);
}

/// Persists the last weather snapshot to XDG state so reopening the panel
/// shows cached data instantly and IP geolocation never runs twice. Mirrors
/// the atomic write-then-rename pattern of the todo repository.
class WeatherFileStore implements WeatherStore {
  WeatherFileStore({required this.paths});

  final RuntimePaths paths;

  // Writes serialize through a chain: a stale write from a previous
  // controller must not interleave with a fresh one around the shared
  // ".tmp" path (write-then-rename would race otherwise).
  Future<void>? _pendingWrite;

  @override
  Future<WeatherSnapshot?> read() async {
    try {
      final file = await _file();
      if (!await file.exists()) {
        return null;
      }
      return weatherSnapshotFromJson(jsonDecode(await file.readAsString()));
    } on Object {
      return null;
    }
  }

  @override
  Future<void> write(WeatherSnapshot snapshot) {
    final pending = _pendingWrite;
    final next = pending == null
        ? _writeUnchecked(snapshot)
        : pending.then((_) => _writeUnchecked(snapshot));
    return _pendingWrite = next;
  }

  Future<void> _writeUnchecked(WeatherSnapshot snapshot) async {
    try {
      final file = await _file();
      final temporary = File('${file.path}.tmp');
      final payload = jsonEncode(snapshot.toJson());
      await temporary.writeAsString('$payload\n', flush: true);
      await temporary.rename(file.path);
    } on Object {
      // Best-effort persistence: the in-memory snapshot stays authoritative
      // for this session even when the disk write fails.
    }
  }

  Future<File> _file() async {
    final dir = Directory(p.join(paths.stateHome, 'denial'));
    await dir.create(recursive: true);
    return File(p.join(dir.path, 'weather.json'));
  }
}

extension WeatherSnapshotJson on WeatherSnapshot {
  Map<String, Object> toJson() {
    return <String, Object>{
      // Version 2 stores the location's wall clock in UTC-flagged
      // DateTimes plus its UTC offset; version 1 timestamps were parsed
      // through the device zone and are not convertible in place.
      'version': 2,
      'location': location.toJson(),
      'current': current.toJson(),
      'hours': [for (final hour in hours) hour.toJson()],
      'days': [for (final day in days) day.toJson()],
      'utcOffsetSeconds': utcOffsetSeconds,
      if (airQuality case final quality?) 'airQuality': quality.toJson(),
      'fetchedAt': fetchedAt.millisecondsSinceEpoch,
    };
  }
}

WeatherSnapshot? weatherSnapshotFromJson(Object? raw) {
  if (raw is! Map) {
    return null;
  }
  final json = raw.cast<Object?, Object?>();
  if (json['version'] != 2) {
    return null;
  }
  final location = GeoLocation.fromJson(json['location']);
  final current = WeatherCurrent.fromJson(json['current']);
  final fetchedAtMs = json['fetchedAt'];
  if (location == null ||
      current == null ||
      fetchedAtMs is! int ||
      fetchedAtMs < 0) {
    return null;
  }
  final hoursRaw = json['hours'];
  final hours = hoursRaw is List
      ? hoursRaw
            .map(WeatherHour.fromJson)
            .whereType<WeatherHour>()
            .toList(growable: false)
      : const <WeatherHour>[];
  final daysRaw = json['days'];
  final days = daysRaw is List
      ? daysRaw
            .map(WeatherDay.fromJson)
            .whereType<WeatherDay>()
            .toList(growable: false)
      : const <WeatherDay>[];
  if (days.isEmpty) {
    return null;
  }
  return WeatherSnapshot(
    location: location,
    current: current,
    hours: hours,
    days: days,
    airQuality: AirQuality.fromJson(json['airQuality']),
    fetchedAt: DateTime.fromMillisecondsSinceEpoch(fetchedAtMs),
    utcOffsetSeconds: json['utcOffsetSeconds'] is int
        ? json['utcOffsetSeconds'] as int
        : 0,
  );
}
