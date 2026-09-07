import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
}

@immutable
class AirQuality {
  const AirQuality({required this.pm10, required this.pm2_5});

  final double pm10;
  final double pm2_5;
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
  });

  final GeoLocation location;
  final WeatherCurrent current;
  final List<WeatherHour> hours;
  final List<WeatherDay> days;
  final AirQuality? airQuality;
  final DateTime fetchedAt;
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
    );
  }

  Future<
    ({WeatherCurrent current, List<WeatherHour> hours, List<WeatherDay> days})
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
    return (current: current, hours: hours, days: days);
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
    // nearest to now so the AQI card reflects current conditions.
    final now = DateTime.now();
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
      final time = DateTime.tryParse('${times[i]}');
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
      final time = DateTime.tryParse('${times[i]}');
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
      final date = DateTime.tryParse('${dates[i]}');
      final code = _finiteDouble(codes[i])?.round();
      final max = _finiteDouble(maxima[i]);
      final min = _finiteDouble(minima[i]);
      final sunrise = DateTime.tryParse('${sunrises[i]}');
      final sunset = DateTime.tryParse('${sunsets[i]}');
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
    final response = await request.close().timeout(_requestTimeout);
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw HttpException(
        'Weather endpoint returned HTTP ${response.statusCode}',
        uri: uri,
      );
    }
    if (response.contentLength > _maximumResponseBytes) {
      await response.drain<void>();
      throw const FormatException('Weather response is too large');
    }
    final body = await response
        .transform(utf8.decoder)
        .join()
        .timeout(_requestTimeout);
    return jsonDecode(body);
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
