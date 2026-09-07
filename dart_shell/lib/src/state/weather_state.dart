import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/weather_service.dart';

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
/// the page re-shows the last snapshot instantly.
class WeatherController extends Notifier<WeatherState> {
  int _generation = 0;
  bool _disposed = false;
  bool _refreshRunning = false;

  @override
  WeatherState build() {
    _generation++;
    _disposed = false;
    _refreshRunning = false;
    ref.onDispose(() {
      _disposed = true;
      _generation++;
    });
    return const WeatherState();
  }

  /// Loads data if the cache is missing or older than [weatherCacheLifetime].
  Future<void> refresh() async {
    final snapshot = state.snapshot;
    if (snapshot != null &&
        DateTime.now().difference(snapshot.fetchedAt) < weatherCacheLifetime) {
      if (state.status != WeatherStatus.ready) {
        state = WeatherState(
          status: WeatherStatus.ready,
          snapshot: snapshot,
          lastFetchedAt: snapshot.fetchedAt,
        );
      }
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
      var location = state.snapshot?.location;
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
    } on Object catch (error) {
      if (_isStale(generation)) {
        return;
      }
      state = state.copyWith(status: WeatherStatus.failed, error: error);
    } finally {
      _refreshRunning = false;
    }
  }

  bool _isStale(int generation) => _disposed || generation != _generation;
}
