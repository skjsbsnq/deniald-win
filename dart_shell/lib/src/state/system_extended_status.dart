import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/system_hardware_service.dart';
import 'notifier_lifecycle.dart';

@immutable
class SystemExtendedStatus {
  const SystemExtendedStatus({
    this.memory,
    this.downloadBytesPerSecond,
    this.uploadBytesPerSecond,
    this.storage,
  });

  final MemoryUsage? memory;

  /// Aggregate interface rates, or null before two counter samples exist.
  final double? downloadBytesPerSecond;
  final double? uploadBytesPerSecond;

  final StorageUsage? storage;
}

/// Samples memory, network rates, and root storage on the same 2 s cadence
/// the CPU/GPU telemetry uses, so the System dashboard lands in one scheduler
/// burst instead of three. Storage moves slowly and its `df` subprocess is
/// comparatively expensive, so it re-runs on a slower cadence than the rest.
final systemExtendedStatusProvider =
    NotifierProvider<SystemExtendedStatusController, SystemExtendedStatus>(
      SystemExtendedStatusController.new,
      isAutoDispose: true,
    );

class SystemExtendedStatusController extends Notifier<SystemExtendedStatus>
    with NotifierLifecycle<SystemExtendedStatus> {
  static const Duration _interval = Duration(seconds: 2);
  static const int _storageRefreshPeriod = 30;

  Timer? _timer;
  int _samplingGeneration = 0;
  int _sampleCount = 0;
  int _nextStorageSample = 0;
  DateTime? _lastCounterTime;
  NetworkCounters? _lastCounters;

  @override
  SystemExtendedStatus build() {
    // Bump the lifecycle generation first: currentBuildGeneration below (and
    // every isBuildGenerationActive check in _refresh) is meaningless without
    // it — the accessor reads the same field this call increments.
    beginBuildGeneration();
    _samplingGeneration++;
    _sampleCount = 0;
    _nextStorageSample = 0;
    _lastCounterTime = null;
    _lastCounters = null;
    final service = ref.watch(systemHardwareServiceProvider);
    final generation = currentBuildGeneration;
    scheduleMicrotask(() => unawaited(_refresh(service, generation)));
    _timer = Timer.periodic(_interval, (_) {
      unawaited(_refresh(service, generation));
    });
    ref.onDispose(() {
      _timer?.cancel();
      _timer = null;
      _samplingGeneration++;
    });
    return const SystemExtendedStatus();
  }

  Future<void> _refresh(SystemHardwareService service, int generation) async {
    // Serialise refreshes: rate math depends on strictly ordered counter
    // pairs, so overlapping samples would corrupt the deltas.
    final sample = ++_samplingGeneration;
    final storageDue = _sampleCount >= _nextStorageSample;
    final results = await Future.wait<Object?>(<Future<Object?>>[
      service.readMemory(),
      service.readNetworkCounters(),
      if (storageDue) service.readRootStorage(),
    ]);
    if (!isBuildGenerationActive(generation) || sample != _samplingGeneration) {
      return;
    }
    _sampleCount++;
    if (storageDue) {
      // Advance the schedule even when the reading fails: a host without
      // `df` would otherwise spawn the subprocess again on every tick.
      _nextStorageSample = _sampleCount + _storageRefreshPeriod;
    }
    final memory = results[0] as MemoryUsage?;
    final counters = results[1] as NetworkCounters?;
    final storage = storageDue ? results[2] as StorageUsage? : null;

    double? download;
    double? upload;
    final previous = _lastCounters;
    final previousTime = _lastCounterTime;
    final now = DateTime.now();
    if (previous != null &&
        previousTime != null &&
        counters != null &&
        _sampleCount > 1) {
      final elapsed = now.difference(previousTime).inMilliseconds / 1000.0;
      if (elapsed > 0.5) {
        download = ((counters.rxBytes - previous.rxBytes) / elapsed)
            .clamp(0.0, double.infinity)
            .toDouble();
        upload = ((counters.txBytes - previous.txBytes) / elapsed)
            .clamp(0.0, double.infinity)
            .toDouble();
      }
    }
    if (counters != null) {
      _lastCounters = counters;
      _lastCounterTime = now;
    }

    // Keep the last good storage reading on ticks that skipped or failed it.
    final effectiveStorage = storage ?? state.storage;
    if (memory == null && counters == null && effectiveStorage == null) {
      return;
    }
    state = SystemExtendedStatus(
      memory: memory ?? state.memory,
      downloadBytesPerSecond: download,
      uploadBytesPerSecond: upload,
      storage: effectiveStorage,
    );
  }
}

/// Rolling network rate history for the dashboard sparkline, oldest first.
@immutable
class NetworkRateSeries {
  const NetworkRateSeries({
    this.down = const <double>[],
    this.up = const <double>[],
  });

  static const int capacity = 45;

  final List<double> down;
  final List<double> up;

  NetworkRateSeries append(double down, double up) {
    final nextDown = <double>[...this.down, down];
    final nextUp = <double>[...this.up, up];
    if (nextDown.length > capacity) {
      nextDown.removeRange(0, nextDown.length - capacity);
      nextUp.removeRange(0, nextUp.length - capacity);
    }
    return NetworkRateSeries(
      down: List.unmodifiable(nextDown),
      up: List.unmodifiable(nextUp),
    );
  }
}
