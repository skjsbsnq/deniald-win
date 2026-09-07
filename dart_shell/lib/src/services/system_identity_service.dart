import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../launcher/launcher_providers.dart';
import '../launcher/runtime_paths.dart';
import 'system_io.dart';

final systemIdentityServiceProvider = Provider<SystemIdentityService>((ref) {
  return SystemIdentityService(paths: ref.watch(runtimePathsProvider));
}, isAutoDispose: true);

/// One distro reading from `/etc/os-release`, best effort.
@immutable
class DistroInfo {
  const DistroInfo({this.id, this.prettyName});

  /// Lower-case distribution id (`arch`, `fedora`), used for logo mapping.
  final String? id;

  /// Human-readable name (`Arch Linux`), shown as the subtitle.
  final String? prettyName;
}

/// Reads dashboard identity facts (distro, uptime, avatar) from the
/// filesystem. Username and hostname come from the runtime environment and
/// are composed in the state layer; everything here is best effort and null
/// on a machine where the source is unreadable.
class SystemIdentityService {
  SystemIdentityService({
    required this.paths,
    this._uptimePath = '/proc/uptime',
    this._osReleasePath = '/etc/os-release',
  });

  final RuntimePaths paths;
  final String _uptimePath;
  final String _osReleasePath;

  /// Seconds since boot, from the first field of `/proc/uptime`.
  Future<double?> readUptimeSeconds() async {
    final content = await readSysString(_uptimePath);
    if (content == null) {
      return null;
    }
    final seconds = double.tryParse(content.split(' ').first);
    return seconds != null && seconds >= 0 ? seconds : null;
  }

  Future<DistroInfo?> readDistro() async {
    final fields = await readKeyValueFile(_osReleasePath);
    final id = _unquote(fields['ID']);
    final prettyName =
        _unquote(fields['PRETTY_NAME']) ?? _unquote(fields['NAME']);
    if (id == null && prettyName == null) {
      return null;
    }
    return DistroInfo(id: id, prettyName: prettyName);
  }

  /// First existing face icon in the order desktop environments scan them.
  Future<String?> resolveAvatarPath() async {
    for (final name in const <String>['.face', '.face.icon']) {
      final candidate = File(p.join(paths.homeDir, name));
      if (await candidate.exists()) {
        return candidate.path;
      }
    }
    return null;
  }
}

/// `/etc/os-release` values are conventionally double-quoted.
String? _unquote(String? value) {
  if (value == null || value.isEmpty) {
    return null;
  }
  final trimmed = value.trim();
  if (trimmed.length >= 2 && trimmed.startsWith('"') && trimmed.endsWith('"')) {
    final inner = trimmed.substring(1, trimmed.length - 1);
    return inner.isEmpty ? null : inner;
  }
  return trimmed;
}
