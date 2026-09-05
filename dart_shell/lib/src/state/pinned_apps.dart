import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../launcher/launcher_providers.dart';
import '../launcher/runtime_paths.dart';

abstract interface class PinnedAppsStore {
  Future<List<String>?> readPinnedAppIds();
  Future<void> savePinnedAppIds(List<String> appIds);
}

class PinnedAppsRepository implements PinnedAppsStore {
  const PinnedAppsRepository({required this.paths});

  final RuntimePaths paths;

  Future<File> _file() async {
    final dir = Directory(p.join(paths.configHome, 'denial'));
    await dir.create(recursive: true);
    return File(p.join(dir.path, 'pinned-apps.json'));
  }

  @override
  Future<List<String>?> readPinnedAppIds() async {
    try {
      final file = await _file();
      if (!await file.exists()) {
        return null;
      }
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      final list = decoded['pinned'];
      if (list is! List) {
        return null;
      }
      return list
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList(growable: false);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> savePinnedAppIds(List<String> appIds) async {
    try {
      final file = await _file();
      final temp = File('${file.path}.tmp');
      final payload = jsonEncode(<String, Object>{
        'version': 1,
        'pinned': appIds,
      });
      await temp.writeAsString('$payload\n', flush: true);
      await temp.rename(file.path);
    } catch (_) {
      // Best-effort persistence
    }
  }
}

final pinnedAppsStoreProvider = Provider<PinnedAppsStore>((ref) {
  return PinnedAppsRepository(paths: ref.watch(runtimePathsProvider));
});

final pinnedAppsProvider = NotifierProvider<PinnedAppsController, List<String>>(
  PinnedAppsController.new,
);

class PinnedAppsController extends Notifier<List<String>> {
  bool _disposed = false;
  Future<void> _saveQueue = Future<void>.value();

  @override
  List<String> build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    final store = ref.watch(pinnedAppsStoreProvider);
    unawaited(_load(store));
    return const <String>[];
  }

  Future<void> _load(PinnedAppsStore store) async {
    final saved = await store.readPinnedAppIds();
    if (_disposed) return;
    if (saved != null) {
      state = saved;
    }
  }

  bool isPinned(String appId) {
    final normalized = _normalizeAppId(appId);
    return state.any((id) => _normalizeAppId(id) == normalized);
  }

  void pin(String appId) {
    if (appId.isEmpty || isPinned(appId)) return;
    final next = [...state, appId];
    state = next;
    _queueSave(next);
  }

  void unpin(String appId) {
    final normalized = _normalizeAppId(appId);
    final next = state
        .where((id) => _normalizeAppId(id) != normalized)
        .toList();
    if (next.length == state.length) return;
    state = next;
    _queueSave(next);
  }

  void togglePin(String appId) {
    if (isPinned(appId)) {
      unpin(appId);
    } else {
      pin(appId);
    }
  }

  void _queueSave(List<String> appIds) {
    final store = ref.read(pinnedAppsStoreProvider);
    _saveQueue = _saveQueue.then((_) => store.savePinnedAppIds(appIds));
  }

  static String _normalizeAppId(String value) => value.trim().toLowerCase();
}
