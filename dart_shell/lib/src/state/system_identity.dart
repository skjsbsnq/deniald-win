import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/system_identity_service.dart';

@immutable
class SystemIdentityState {
  const SystemIdentityState({this.uptimeSeconds, this.distro, this.avatarPath});

  /// Seconds since boot, or null before the first read succeeds.
  final double? uptimeSeconds;

  final DistroInfo? distro;

  final String? avatarPath;
}

/// Resolves the dashboard profile identity once per mount: environment facts
/// (user, hostname) are free, uptime re-reads every minute so the card ticks
/// over while the panel is open, and a build restart clears any stale facts.
final systemIdentityProvider =
    NotifierProvider<SystemIdentityController, SystemIdentityState>(
      SystemIdentityController.new,
      isAutoDispose: true,
    );

class SystemIdentityController extends Notifier<SystemIdentityState> {
  static const Duration _uptimeInterval = Duration(minutes: 1);

  Timer? _uptimeTimer;
  int _generation = 0;
  bool _disposed = false;

  @override
  SystemIdentityState build() {
    _generation++;
    _disposed = false;
    final service = ref.watch(systemIdentityServiceProvider);
    final generation = _generation;
    unawaited(_load(service, generation));
    _uptimeTimer = Timer.periodic(_uptimeInterval, (_) {
      unawaited(_refreshUptime(service, generation));
    });
    ref.onDispose(() {
      _disposed = true;
      _uptimeTimer?.cancel();
      _uptimeTimer = null;
    });
    return const SystemIdentityState();
  }

  Future<void> _load(SystemIdentityService service, int generation) async {
    final results = await Future.wait(<Future<Object?>>[
      service.readUptimeSeconds(),
      service.readDistro(),
      service.resolveAvatarPath(),
    ]);
    if (_isStale(generation)) {
      return;
    }
    state = SystemIdentityState(
      uptimeSeconds: results[0] as double?,
      distro: results[1] as DistroInfo?,
      avatarPath: results[2] as String?,
    );
  }

  Future<void> _refreshUptime(
    SystemIdentityService service,
    int generation,
  ) async {
    final seconds = await service.readUptimeSeconds();
    if (_isStale(generation) ||
        seconds == null ||
        seconds == state.uptimeSeconds) {
      return;
    }
    state = SystemIdentityState(
      uptimeSeconds: seconds,
      distro: state.distro,
      avatarPath: state.avatarPath,
    );
  }

  bool _isStale(int generation) => _disposed || generation != _generation;
}
