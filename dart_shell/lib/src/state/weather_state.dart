import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/weather_service.dart';
import '../services/weather_store.dart';
import '../settings/settings_controller.dart';
import '../settings/shell_settings.dart';

enum WeatherStatus { idle, locating, loading, ready, failed }

@immutable
class WeatherState {
  const WeatherState({
    this.status = WeatherStatus.idle,
    this.snapshot,
    this.lastFetchedAt,
    this.error,
  });

  /// Pure navigation state for the page: idle before first open, failed
  /// keeps [snapshot] so the UI can degrade to the cached view.
  final WeatherStatus status;
  final WeatherSnapshot? snapshot;
  final DateTime? lastFetchedAt;
  final Object? error;

  WeatherState copyWith({WeatherStatus? status, Object? error}) {
    return WeatherState(
      status: status ?? this.status,
      snapshot: snapshot,
      lastFetchedAt: lastFetchedAt,
      error: error ?? this.error,
    );
  }
}

const Duration weatherCacheLifetime = Duration(minutes: 30);

final weatherProvider = NotifierProvider<WeatherController, WeatherState>(
  WeatherController.new,
  isAutoDispose: true,
);

/// Drives the Weather page's data channel. Location discovery and network
/// fetches happen only when [refresh] is called (the page triggers it on
/// first build), never on provider construction, and only when the cache is
/// stale — so nothing polls while the dashboard is closed (D8) and opening
/// the page re-shows the last snapshot instantly. Snapshots survive panel
/// closure via the XDG state file, so IP geolocation runs at most once per
/// location change, not once per open.
class WeatherController extends Notifier<WeatherState> {
  int _generation = 0;
  bool _disposed = false;
  bool _refreshRunning = false;
  Future<WeatherSnapshot?>? _hydration;
  Object? _lastLocationKey;
  WeatherSnapshot? _retainedSnapshot;
  Object? _retainedError;

  @override
  WeatherState build() {
    _generation++;
    _disposed = false;
    _refreshRunning = false;
    // Watching (not just reading in refresh) pins the autoDispose service to
    // this controller's lifetime: a transiently-read service is reclaimed
    // while a fetch is still in flight, and its dispose closes the HttpClient
    // with force, aborting the request mid-transfer. The store is pinned for
    // the same reason — the post-fetch cache write must not race disposal.
    ref.watch(weatherServiceProvider);
    ref.watch(weatherStoreProvider);
    ref.onDispose(() {
      _disposed = true;
      _generation++;
    });
    // Rebuild on weather setting changes: switching to a manual city must
    // re-resolve location even when a fresh snapshot is cached. The previous
    // state (including its snapshot) is retained via fields, since reading
    // `state` inside build() is not allowed on the initial element creation.
    final weatherSettings = ref.watch(
      shellSettingsProvider.select((settings) => settings.weather),
    );
    final locationKey = _locationKey(weatherSettings);
    final previousKey = _lastLocationKey;
    _lastLocationKey = locationKey;
    if (previousKey != null && previousKey != locationKey) {
      scheduleMicrotask(() {
        if (!ref.mounted || _disposed) {
          return;
        }
        forceRefresh();
      });
    }
    final retained = _retainedSnapshot;
    if (retained == null) {
      return WeatherState(error: _retainedError);
    }
    return WeatherState(
      status: WeatherStatus.ready,
      snapshot: retained,
      lastFetchedAt: retained.fetchedAt,
      error: _retainedError,
    );
  }

  @override
  set state(WeatherState next) {
    _retainedSnapshot = next.snapshot;
    _retainedError = next.error;
    super.state = next;
  }

  /// Loads data if the cache is missing or older than [weatherCacheLifetime].
  /// The disk snapshot is hydrated first so the page renders instantly.
  Future<void> refresh() async {
    final hydrated = await _hydrate();
    if (_disposed) {
      return;
    }
    final existing = state.snapshot ?? hydrated;
    if (existing != null) {
      if (state.status != WeatherStatus.ready || state.snapshot == null) {
        state = WeatherState(
          status: WeatherStatus.ready,
          snapshot: existing,
          lastFetchedAt: existing.fetchedAt,
        );
      }
    }
    final snapshot = state.snapshot;
    if (snapshot != null &&
        DateTime.now().difference(snapshot.fetchedAt) < weatherCacheLifetime) {
      return;
    }
    await forceRefresh();
  }

  Future<void> forceRefresh() async {
    if (_refreshRunning) {
      return;
    }
    _refreshRunning = true;
    final generation = _generation;
    try {
      state = WeatherState(
        status: state.snapshot == null
            ? WeatherStatus.loading
            : WeatherStatus.ready,
        snapshot: state.snapshot,
        lastFetchedAt: state.lastFetchedAt,
        error: state.error,
      );
      final service = ref.read(weatherServiceProvider);
      final weatherSettings = ref.read(shellSettingsProvider).weather;
      var location = _resolveCachedLocation(weatherSettings);
      if (location == null) {
        state = state.copyWith(status: WeatherStatus.locating);
        location = await service.resolveLocation();
      }
      if (_isStale(generation)) {
        return;
      }
      if (location == null) {
        state = state.copyWith(
          status: WeatherStatus.failed,
          error: const SocketException('Location discovery failed'),
        );
        return;
      }
      final snapshot = await service.fetch(location);
      if (_isStale(generation)) {
        return;
      }
      state = WeatherState(
        status: WeatherStatus.ready,
        snapshot: snapshot,
        lastFetchedAt: snapshot.fetchedAt,
      );
      // Persist for the next session/panel open; write failures are
      // non-fatal — the in-memory snapshot already drives the UI.
      unawaited(
        ref.read(weatherStoreProvider).write(snapshot).catchError((_) {}),
      );
    } on Object catch (error) {
      if (_isStale(generation)) {
        return;
      }
      state = state.copyWith(status: WeatherStatus.failed, error: error);
    } finally {
      _refreshRunning = false;
    }
  }

  /// Reads the disk snapshot once per controller lifetime; a failed read
  /// yields null and never retries within the same panel session.
  Future<WeatherSnapshot?> _hydrate() {
    return _hydration ??= ref.read(weatherStoreProvider).read();
  }

  /// Returns the location the next fetch should use without any network
  /// lookup: the pinned manual city, or the location already carried by the
  /// cached snapshot (IP geolocation result from a previous fetch).
  GeoLocation? _resolveCachedLocation(ShellWeatherSettings weatherSettings) {
    final manual = weatherSettings.resolvedLocation;
    if (manual != null) {
      return GeoLocation(
        latitude: manual.latitude,
        longitude: manual.longitude,
        city: manual.city,
      );
    }
    return state.snapshot?.location;
  }

  static Object? _locationKey(ShellWeatherSettings settings) {
    final manual = settings.resolvedLocation;
    if (manual != null) {
      return Object.hash(manual.latitude, manual.longitude, manual.city);
    }
    // Auto mode keeps whatever location the current snapshot carries; the
    // key only changes when IP geolocation resolves somewhere new.
    return null;
  }

  bool _isStale(int generation) => _disposed || generation != _generation;
}
