import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final weatherServiceProvider = Provider<WeatherService>((ref) {
  final service = WeatherService();
  ref.onDispose(() => service.dispose());
  return service;
}, isAutoDispose: true);

@immutable
class GeoLocation {
  const GeoLocation({
    required this.latitude,
    required this.longitude,
    required this.city,
  });

  final double latitude;
  final double longitude;
  final String city;

  Map<String, Object> toJson() => <String, Object>{
    'latitude': latitude,
    'longitude': longitude,
    'city': city,
  };

  static GeoLocation? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final json = raw.cast<Object?, Object?>();
    final latitude = json['latitude'];
    final longitude = json['longitude'];
    final city = json['city'];
    if (latitude is! num ||
        longitude is! num ||
        city is! String ||
        !latitude.isFinite ||
        !longitude.isFinite) {
      return null;
    }
    final name = city.trim();
    if (name.isEmpty || name.length > 128 || name.contains('\u0000')) {
      return null;
    }
    return GeoLocation(
      latitude: latitude.toDouble(),
      longitude: longitude.toDouble(),
      city: name,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is GeoLocation &&
        other.latitude == latitude &&
        other.longitude == longitude &&
        other.city == city;
  }

  @override
  int get hashCode => Object.hash(latitude, longitude, city);
}

@immutable
class WeatherCurrent {
  const WeatherCurrent({
    required this.temperatureC,
    required this.apparentTemperatureC,
    required this.weatherCode,
    required this.humidityPercent,
    required this.windSpeedMs,
    required this.windDirectionDeg,
    required this.uvIndex,
    required this.pressureHpa,
    required this.visibilityM,
  });

  final double temperatureC;
  final double apparentTemperatureC;
  final int weatherCode;
  final int humidityPercent;
  final double windSpeedMs;
  final double windDirectionDeg;
  final double uvIndex;
  final double pressureHpa;
  final double visibilityM;

  Map<String, Object> toJson() => <String, Object>{
    'temperatureC': temperatureC,
    'apparentTemperatureC': apparentTemperatureC,
    'weatherCode': weatherCode,
    'humidityPercent': humidityPercent,
    'windSpeedMs': windSpeedMs,
    'windDirectionDeg': windDirectionDeg,
    'uvIndex': uvIndex,
    'pressureHpa': pressureHpa,
    'visibilityM': visibilityM,
  };

  static WeatherCurrent? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final json = raw.cast<Object?, Object?>();
    final temperature = _finiteDouble(json['temperatureC']);
    final apparent = _finiteDouble(json['apparentTemperatureC']);
    final code = _finiteDouble(json['weatherCode'])?.round();
    final humidity = _finiteDouble(json['humidityPercent'])?.round();
    final windSpeed = _finiteDouble(json['windSpeedMs']);
    final windDirection = _finiteDouble(json['windDirectionDeg']);
    if (temperature == null ||
        apparent == null ||
        code == null ||
        humidity == null ||
        windSpeed == null ||
        windDirection == null) {
      return null;
    }
    return WeatherCurrent(
      temperatureC: temperature,
      apparentTemperatureC: apparent,
      weatherCode: code,
      humidityPercent: humidity,
      windSpeedMs: windSpeed,
      windDirectionDeg: windDirection,
      uvIndex: _finiteDouble(json['uvIndex']) ?? 0,
      pressureHpa: _finiteDouble(json['pressureHpa']) ?? 0,
      visibilityM: _finiteDouble(json['visibilityM']) ?? 0,
    );
  }
}

@immutable
class WeatherHour {
  const WeatherHour({
    required this.time,
    required this.temperatureC,
    required this.weatherCode,
    required this.precipitationProbability,
  });

  final DateTime time;
  final double temperatureC;
  final int weatherCode;
  final int precipitationProbability;

  Map<String, Object> toJson() => <String, Object>{
    'time': time.millisecondsSinceEpoch,
    'temperatureC': temperatureC,
    'weatherCode': weatherCode,
    'precipitationProbability': precipitationProbability,
  };

  static WeatherHour? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final json = raw.cast<Object?, Object?>();
    final timeMs = json['time'];
    final temperature = _finiteDouble(json['temperatureC']);
    final code = _finiteDouble(json['weatherCode'])?.round();
    if (timeMs is! int || timeMs < 0 || temperature == null || code == null) {
      return null;
    }
    return WeatherHour(
      // Wall-clock fields are UTC-flagged so .hour reads the location's
      // local hour instead of the device zone's rendering of the instant.
      time: DateTime.fromMillisecondsSinceEpoch(timeMs, isUtc: true),
      temperatureC: temperature,
      weatherCode: code,
      precipitationProbability:
          _finiteDouble(json['precipitationProbability'])?.round() ?? 0,
    );
  }
}

@immutable
class WeatherDay {
  const WeatherDay({
    required this.date,
    required this.weatherCode,
    required this.maxTemperatureC,
    required this.minTemperatureC,
    required this.sunrise,
    required this.sunset,
  });

  final DateTime date;
  final int weatherCode;
  final double maxTemperatureC;
  final double minTemperatureC;
  final DateTime sunrise;
  final DateTime sunset;

  Map<String, Object> toJson() => <String, Object>{
    'date': date.millisecondsSinceEpoch,
    'weatherCode': weatherCode,
    'maxTemperatureC': maxTemperatureC,
    'minTemperatureC': minTemperatureC,
    'sunrise': sunrise.millisecondsSinceEpoch,
    'sunset': sunset.millisecondsSinceEpoch,
  };

  static WeatherDay? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final json = raw.cast<Object?, Object?>();
    final dateMs = json['date'];
    final code = _finiteDouble(json['weatherCode'])?.round();
    final max = _finiteDouble(json['maxTemperatureC']);
    final min = _finiteDouble(json['minTemperatureC']);
    if (dateMs is! int ||
        dateMs < 0 ||
        code == null ||
        max == null ||
        min == null) {
      return null;
    }
    final sunriseMs = json['sunrise'];
    final sunsetMs = json['sunset'];
    // Wall-clock fields are UTC-flagged; see WeatherHour.fromJson.
    final date = DateTime.fromMillisecondsSinceEpoch(dateMs, isUtc: true);
    return WeatherDay(
      date: date,
      weatherCode: code,
      maxTemperatureC: max,
      minTemperatureC: min,
      sunrise: sunriseMs is int && sunriseMs >= 0
          ? DateTime.fromMillisecondsSinceEpoch(sunriseMs, isUtc: true)
          : date,
      sunset: sunsetMs is int && sunsetMs >= 0
          ? DateTime.fromMillisecondsSinceEpoch(sunsetMs, isUtc: true)
          : date,
    );
  }
}

@immutable
class AirQuality {
  const AirQuality({required this.pm10, required this.pm2_5});

  final double pm10;
  final double pm2_5;

  Map<String, Object> toJson() => <String, Object>{
    'pm10': pm10,
    'pm2_5': pm2_5,
  };

  static AirQuality? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final json = raw.cast<Object?, Object?>();
    final pm10 = _finiteDouble(json['pm10']);
    final pm25 = _finiteDouble(json['pm2_5']);
    if (pm10 == null || pm25 == null) {
      return null;
    }
    return AirQuality(pm10: pm10, pm2_5: pm25);
  }
}

@immutable
class WeatherSnapshot {
  const WeatherSnapshot({
    required this.location,
    required this.current,
    required this.hours,
    required this.days,
    required this.airQuality,
    required this.fetchedAt,
    this.utcOffsetSeconds = 0,
  });

  final GeoLocation location;
  final WeatherCurrent current;
  final List<WeatherHour> hours;
  final List<WeatherDay> days;
  final AirQuality? airQuality;
  final DateTime fetchedAt;

  /// The location's UTC offset in seconds at fetch time. Open-Meteo returns
  /// naive local timestamps; parsing them as UTC keeps the location's wall
  /// clock intact while this offset lets callers reconstruct "now" there
  /// instead of comparing against the device's time zone.
  final int utcOffsetSeconds;
}

/// Location discovery produced no usable position. Carried as a distinct
/// type so the UI can steer toward the manual-city settings rather than
/// reporting a generic network failure.
class WeatherLocationFailure implements Exception {
  const WeatherLocationFailure();

  @override
  String toString() => 'WeatherLocationFailure';
}

/// Open-Meteo requires no API key, which keeps the shell free of user-held
/// secrets. Location discovery goes through ipwho.is for the same reason.
/// Failures throw so the state layer can keep the last cached snapshot.
class WeatherService {
  WeatherService({HttpClient? httpClient})
    : _httpClient = httpClient ?? HttpClient();

  static const Duration _requestTimeout = Duration(seconds: 20);
  static const int _maximumResponseBytes = 1024 * 1024;

  static final Uri _geoEndpoint = Uri.parse(
    'https://ipwho.is/?fields=success,latitude,longitude,city',
  );
  static final Uri _geocodingEndpoint = Uri.parse(
    'https://geocoding-api.open-meteo.com/v1/search',
  );
  static final Uri _forecastEndpoint = Uri.parse(
    'https://api.open-meteo.com/v1/forecast',
  );
  static final Uri _airQualityEndpoint = Uri.parse(
    'https://air-quality-api.open-meteo.com/v1/air-quality',
  );

  final HttpClient _httpClient;

  Future<GeoLocation?> resolveLocation() async {
    final decoded = await _getJson(_geoEndpoint);
    if (decoded is! Map<String, dynamic> || decoded['success'] != true) {
      return null;
    }
    final latitude = _finiteDouble(decoded['latitude']);
    final longitude = _finiteDouble(decoded['longitude']);
    final city = decoded['city'];
    if (latitude == null || longitude == null || city is! String) {
      return null;
    }
    return GeoLocation(latitude: latitude, longitude: longitude, city: city);
  }

  /// Resolves a free-text city query into up to five candidate locations via
  /// the Open-Meteo geocoding API. Errors surface as an empty list: the
  /// settings page treats a failed search as "no results", never as a crash.
  Future<List<GeoLocation>> searchCities(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty || trimmed.length > 128) {
      return const <GeoLocation>[];
    }
    final Uri uri;
    try {
      uri = _geocodingEndpoint.replace(
        queryParameters: <String, String>{'name': trimmed, 'count': '5'},
      );
    } on ArgumentError {
      return const <GeoLocation>[];
    }
    final Object? decoded;
    try {
      decoded = await _getJson(uri);
    } on Object {
      return const <GeoLocation>[];
    }
    if (decoded is! Map<String, dynamic>) {
      return const <GeoLocation>[];
    }
    final results = decoded['results'];
    if (results is! List) {
      return const <GeoLocation>[];
    }
    final cities = <GeoLocation>[];
    for (final result in results) {
      if (result is! Map<String, dynamic>) {
        continue;
      }
      final latitude = _finiteDouble(result['latitude']);
      final longitude = _finiteDouble(result['longitude']);
      final name = result['name'];
      if (latitude == null || longitude == null || name is! String) {
        continue;
      }
      final city = name.trim();
      if (city.isEmpty) {
        continue;
      }
      cities.add(
        GeoLocation(latitude: latitude, longitude: longitude, city: city),
      );
    }
    return List.unmodifiable(cities);
  }

  Future<WeatherSnapshot> fetch(GeoLocation location) async {
    final forecast = await _fetchForecast(location);
    final airQuality = await _fetchAirQuality(location).onError((_, _) => null);
    return WeatherSnapshot(
      location: location,
      current: forecast.current,
      hours: forecast.hours,
      days: forecast.days,
      airQuality: airQuality,
      fetchedAt: DateTime.now(),
      utcOffsetSeconds: forecast.utcOffsetSeconds,
    );
  }

  Future<
    ({
      WeatherCurrent current,
      List<WeatherHour> hours,
      List<WeatherDay> days,
      int utcOffsetSeconds,
    })
  >
  _fetchForecast(GeoLocation location) async {
    final uri = _forecastEndpoint.replace(
      queryParameters: <String, String>{
        'latitude': '${location.latitude}',
        'longitude': '${location.longitude}',
        'current':
            'temperature_2m,apparent_temperature,weather_code,'
            'relative_humidity_2m,wind_speed_10m,wind_direction_10m,uv_index,'
            'pressure_msl,visibility',
        'hourly': 'temperature_2m,weather_code,precipitation_probability',
        'daily':
            'weather_code,temperature_2m_max,temperature_2m_min,'
            'sunrise,sunset',
        'timezone': 'auto',
      },
    );
    final decoded = await _getJson(uri);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid Open-Meteo forecast response');
    }
    final currentRaw = decoded['current'];
    if (currentRaw is! Map<String, dynamic>) {
      throw const FormatException('Open-Meteo response lacks current data');
    }
    final current = WeatherCurrent(
      temperatureC: _requiredDouble(currentRaw['temperature_2m']),
      apparentTemperatureC: _requiredDouble(currentRaw['apparent_temperature']),
      weatherCode: _requiredInt(currentRaw['weather_code']),
      humidityPercent: _requiredInt(currentRaw['relative_humidity_2m']),
      windSpeedMs: _requiredDouble(currentRaw['wind_speed_10m']),
      windDirectionDeg: _requiredDouble(currentRaw['wind_direction_10m']),
      uvIndex: _finiteDouble(currentRaw['uv_index']) ?? 0,
      pressureHpa: _finiteDouble(currentRaw['pressure_msl']) ?? 0,
      visibilityM: _finiteDouble(currentRaw['visibility']) ?? 0,
    );

    final hours = _parseHourly(decoded['hourly']);
    final days = _parseDaily(decoded['daily']);
    if (days.isEmpty) {
      throw const FormatException('Open-Meteo response lacks daily data');
    }
    return (
      current: current,
      hours: hours,
      days: days,
      utcOffsetSeconds:
          _finiteDouble(decoded['utc_offset_seconds'])?.round() ?? 0,
    );
  }

  Future<AirQuality?> _fetchAirQuality(GeoLocation location) async {
    final uri = _airQualityEndpoint.replace(
      queryParameters: <String, String>{
        'latitude': '${location.latitude}',
        'longitude': '${location.longitude}',
        'hourly': 'pm10,pm2_5',
        'past_days': '1',
        'forecast_days': '1',
        'timezone': 'auto',
      },
    );
    final decoded = await _getJson(uri);
    if (decoded is! Map<String, dynamic>) {
      return null;
    }
    final hourly = decoded['hourly'];
    if (hourly is! Map<String, dynamic>) {
      return null;
    }
    final times = hourly['time'];
    final pm10Series = hourly['pm10'];
    final pm25Series = hourly['pm2_5'];
    if (times is! List || pm10Series is! List || pm25Series is! List) {
      return null;
    }
    // The hourly series extend across past and forecast days; take the value
    // nearest to now so the AQI card reflects current conditions. The series
    // is in the location's local time, so "now" must be reconstructed there
    // rather than read off the device clock.
    final offsetSeconds =
        _finiteDouble(decoded['utc_offset_seconds'])?.round() ?? 0;
    final now = DateTime.now().toUtc().add(Duration(seconds: offsetSeconds));
    final index = _closestTimeIndex(times, now);
    if (index == null) {
      return null;
    }
    final pm10 = _finiteDouble(pm10Series[index]);
    final pm25 = _finiteDouble(pm25Series[index]);
    if (pm10 == null || pm25 == null) {
      return null;
    }
    return AirQuality(pm10: pm10, pm2_5: pm25);
  }

  static int? _closestTimeIndex(List times, DateTime target) {
    int? best;
    Duration? bestDistance;
    for (var i = 0; i < times.length; i++) {
      final time = _parseLocalWallTime(times[i]);
      if (time == null) {
        continue;
      }
      final distance = time.difference(target).abs();
      if (bestDistance == null || distance < bestDistance) {
        best = i;
        bestDistance = distance;
      }
    }
    return best;
  }

  /// Parses an Open-Meteo naive local timestamp ("2026-09-08T14:00") into a
  /// UTC-flagged DateTime that carries the location's wall clock. Reading
  /// wall-clock fields and comparing against a city-local "now" then never
  /// passes through the device's time zone.
  static DateTime? _parseLocalWallTime(Object? raw) {
    if (raw is! String) {
      return null;
    }
    final text = raw.trim().replaceAll(RegExp(r'(Z|[+-]\d{2}:?\d{2})$'), '');
    return DateTime.tryParse('$text${text.length > 10 ? '' : 'T00:00'}Z');
  }

  static List<WeatherHour> _parseHourly(Object? raw) {
    if (raw is! Map<String, dynamic>) {
      return const <WeatherHour>[];
    }
    final times = raw['time'];
    final temperatures = raw['temperature_2m'];
    final codes = raw['weather_code'];
    final probabilities = raw['precipitation_probability'];
    if (times is! List ||
        temperatures is! List ||
        codes is! List ||
        probabilities is! List) {
      return const <WeatherHour>[];
    }
    final hours = <WeatherHour>[];
    for (var i = 0; i < times.length; i++) {
      final time = _parseLocalWallTime(times[i]);
      final temperature = _finiteDouble(temperatures[i]);
      final code = _finiteDouble(codes[i])?.round();
      final probability = _finiteDouble(probabilities[i])?.round();
      if (time == null || temperature == null || code == null) {
        continue;
      }
      hours.add(
        WeatherHour(
          time: time,
          temperatureC: temperature,
          weatherCode: code,
          precipitationProbability: probability ?? 0,
        ),
      );
    }
    return List.unmodifiable(hours);
  }

  static List<WeatherDay> _parseDaily(Object? raw) {
    if (raw is! Map<String, dynamic>) {
      return const <WeatherDay>[];
    }
    final dates = raw['time'];
    final codes = raw['weather_code'];
    final maxima = raw['temperature_2m_max'];
    final minima = raw['temperature_2m_min'];
    final sunrises = raw['sunrise'];
    final sunsets = raw['sunset'];
    if (dates is! List ||
        codes is! List ||
        maxima is! List ||
        minima is! List ||
        sunrises is! List ||
        sunsets is! List) {
      return const <WeatherDay>[];
    }
    final days = <WeatherDay>[];
    for (var i = 0; i < dates.length; i++) {
      final date = _parseLocalWallTime(dates[i]);
      final code = _finiteDouble(codes[i])?.round();
      final max = _finiteDouble(maxima[i]);
      final min = _finiteDouble(minima[i]);
      final sunrise = _parseLocalWallTime(sunrises[i]);
      final sunset = _parseLocalWallTime(sunsets[i]);
      if (date == null || code == null || max == null || min == null) {
        continue;
      }
      days.add(
        WeatherDay(
          date: date,
          weatherCode: code,
          maxTemperatureC: max,
          minTemperatureC: min,
          sunrise: sunrise ?? date,
          sunset: sunset ?? date,
        ),
      );
    }
    return List.unmodifiable(days);
  }

  Future<Object?> _getJson(Uri uri) async {
    final request = await _httpClient.getUrl(uri).timeout(_requestTimeout);
    request.headers
      ..set(HttpHeaders.userAgentHeader, 'denial-weather/1.0')
      ..set(HttpHeaders.acceptHeader, 'application/json');
    // Aborting on timeout matters: without it the connection keeps
    // transferring after the caller has moved on, and nothing but the
    // service's forced dispose would stop it.
    final response = await request.close().timeout(
      _requestTimeout,
      onTimeout: () {
        request.abort();
        throw const SocketException('Weather request timed out');
      },
    );
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>().timeout(_requestTimeout);
      throw HttpException(
        'Weather endpoint returned HTTP ${response.statusCode}',
        uri: uri,
      );
    }
    if (response.contentLength > _maximumResponseBytes) {
      await response.drain<void>().timeout(_requestTimeout);
      throw const FormatException('Weather response is too large');
    }
    return _readJsonBody(response, request).timeout(
      _requestTimeout,
      onTimeout: () {
        request.abort();
        throw const SocketException('Weather response timed out');
      },
    );
  }

  Future<Object?> _readJsonBody(
    HttpClientResponse response,
    HttpClientRequest request,
  ) async {
    // Chunked responses carry no content length, so the byte cap is
    // enforced while the body streams in rather than up front.
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response) {
      bytes.add(chunk);
      if (bytes.length > _maximumResponseBytes) {
        request.abort();
        throw const FormatException('Weather response is too large');
      }
    }
    return jsonDecode(utf8.decode(bytes.takeBytes()));
  }

  void dispose() {
    _httpClient.close(force: true);
  }
}

double? _finiteDouble(Object? raw) {
  if (raw is! num) {
    return null;
  }
  final value = raw.toDouble();
  return value.isFinite ? value : null;
}

double _requiredDouble(Object? raw) {
  final value = _finiteDouble(raw);
  if (value == null) {
    throw const FormatException('Missing numeric field in weather payload');
  }
  return value;
}

int _requiredInt(Object? raw) {
  final value = _finiteDouble(raw);
  if (value == null) {
    throw const FormatException('Missing integer field in weather payload');
  }
  return value.round();
}
