import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final systemHardwareServiceProvider = Provider<SystemHardwareService>((ref) {
  return SystemHardwareService();
}, isAutoDispose: true);

/// Memory snapshot in bytes from `/proc/meminfo`.
@immutable
class MemoryUsage {
  const MemoryUsage({required this.used, required this.total});

  /// `MemTotal - MemAvailable` keeps the kernel reclaimable heuristic.
  final int used;
  final int total;

  double get fraction =>
      total <= 0 ? 0.0 : (used / total).clamp(0.0, 1.0).toDouble();
}

/// One counter snapshot of an interface pair from `/proc/net/dev`.
@immutable
class NetworkCounters {
  const NetworkCounters({required this.rxBytes, required this.txBytes});

  final int rxBytes;
  final int txBytes;
}

/// Root filesystem occupancy parsed from `df -B1 /` output.
@immutable
class StorageUsage {
  const StorageUsage({required this.used, required this.total});

  final int used;
  final int total;

  double get fraction =>
      total <= 0 ? 0.0 : (used / total).clamp(0.0, 1.0).toDouble();
}

/// Reads dashboard hardware counters (memory, network, storage) directly from
/// `/proc` and one `df` subprocess, following the shell's best-effort pattern:
/// dart:io has no statvfs, so root filesystem capacity goes through `df`.
/// Interfaces that report no traffic are excluded to avoid counting
/// tunnel/loopback noise into the aggregate rates.
class SystemHardwareService {
  SystemHardwareService({
    this._meminfoPath = '/proc/meminfo',
    this._netDevPath = '/proc/net/dev',
    this._dfExecutable = 'df',
  });

  final String _meminfoPath;
  final String _netDevPath;
  final String _dfExecutable;

  Future<MemoryUsage?> readMemory() async {
    try {
      final content = await File(_meminfoPath).readAsString();
      return parseMeminfo(content);
    } on FileSystemException {
      return null;
    }
  }

  Future<NetworkCounters?> readNetworkCounters() async {
    try {
      final content = await File(_netDevPath).readAsString();
      return parseNetDev(content);
    } on FileSystemException {
      return null;
    }
  }

  Future<StorageUsage?> readRootStorage() async {
    try {
      final result = await Process.run(_dfExecutable, const <String>[
        '-B1',
        '/',
      ]);
      final storage = parseDf(
        result.stdout is String ? result.stdout as String : '',
      );
      return storage;
    } on Object {
      // A container or minimal host may lack `df`; the card renders empty.
      return null;
    }
  }
}

@visibleForTesting
MemoryUsage? parseMeminfo(String content) {
  final fields = <String, int>{};
  for (final line in content.split('\n')) {
    final split = line.indexOf(':');
    if (split <= 0) {
      continue;
    }
    final key = line.substring(0, split);
    final value = int.tryParse(
      line.substring(split + 1).trim().split(' ').first,
    );
    if (value != null) {
      fields[key] = value * 1024;
    }
  }
  final total = fields['MemTotal'];
  final available = fields['MemAvailable'];
  if (total == null || total <= 0 || available == null) {
    return null;
  }
  return MemoryUsage(used: (total - available).clamp(0, total), total: total);
}

const Set<String> _ignoredInterfaces = <String>{'lo', 'docker0', 'podman0'};

@visibleForTesting
NetworkCounters? parseNetDev(String content) {
  var sawInterface = false;
  var rx = 0;
  var tx = 0;
  for (final rawLine in content.split('\n')) {
    final separator = rawLine.indexOf(':');
    if (separator <= 0) {
      continue;
    }
    final name = rawLine.substring(0, separator).trim();
    if (name.isEmpty || _ignoredInterfaces.contains(name)) {
      continue;
    }
    final fields = rawLine
        .substring(separator + 1)
        .trim()
        .split(RegExp(r'\s+'))
        .map(int.tryParse)
        .toList(growable: false);
    if (fields.length < 16 || fields.any((field) => field == null)) {
      continue;
    }
    sawInterface = true;
    rx += fields[0]!;
    tx += fields[8]!;
  }
  return sawInterface ? NetworkCounters(rxBytes: rx, txBytes: tx) : null;
}

@visibleForTesting
StorageUsage? parseDf(String content) {
  for (final line in content.split('\n').skip(1)) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    final fields = trimmed.split(RegExp(r'\s+'));
    if (fields.length < 3 || !fields[0].startsWith('/dev/')) {
      continue;
    }
    final total = int.tryParse(fields[1]);
    final used = int.tryParse(fields[2]);
    if (total != null && used != null && total > 0) {
      return StorageUsage(used: used.clamp(0, total), total: total);
    }
  }
  return null;
}
