import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../launcher/launcher_providers.dart';
import '../launcher/runtime_paths.dart';

final systemCardStoreProvider = Provider<SystemCardStore>((ref) {
  final store = SystemCardFileStore(paths: ref.watch(runtimePathsProvider));
  ref.onDispose(store.dispose);
  return store;
}, isAutoDispose: true);

/// The committed tile anchors `{id: (x, y)}` plus hydration state.
///
/// Kept deliberately geometry-free: pixel validity is checked at resolve
/// time against the canvas actually measured, so a panel width change simply
/// falls back to default anchors instead of corrupting the file.
class SystemCardLayoutState {
  const SystemCardLayoutState({
    this.anchors = const <String, ({double x, double y})>{},
    this.hydrated = false,
  });

  /// Saved tile positions; empty until a commit or when hydration found no
  /// usable file. May contain unknown ids — the layout layer rejects them.
  final Map<String, ({double x, double y})> anchors;

  /// False until the first read completes; the canvas suppresses position
  /// animations until then so hydration lands without a visible shuffle.
  final bool hydrated;
}

final systemCardLayoutProvider =
    NotifierProvider<SystemCardLayoutController, SystemCardLayoutState>(
      SystemCardLayoutController.new,
      isAutoDispose: true,
    );

/// Owns the committed system card layout and pushes every change through
/// the debounced [SystemCardStore].
class SystemCardLayoutController extends Notifier<SystemCardLayoutState> {
  late SystemCardStore _store;

  @override
  SystemCardLayoutState build() {
    _store = ref.watch(systemCardStoreProvider);
    unawaited(_hydrate());
    return const SystemCardLayoutState();
  }

  Future<void> _hydrate() async {
    final saved = await _store.read();
    // A commit that landed while the read was in flight (slow disk plus a
    // fast keyboard nudge) is newer than anything on disk; overwriting it
    // would snap the cards back to the stale saved anchors.
    if (!ref.mounted || state.hydrated) {
      return;
    }
    state = SystemCardLayoutState(
      hydrated: true,
      anchors: saved == null
          ? const <String, ({double x, double y})>{}
          : <String, ({double x, double y})>{
              for (final tile in saved.tiles) tile.id: (x: tile.x, y: tile.y),
            },
    );
  }

  /// Commits a resolved layout. [anchors] maps tile id → canvas pixels; the
  /// `container` schema field stays `'panel'` until desktop drops exist.
  void commit(
    Map<String, ({double x, double y})> anchors, {
    required double canvasWidth,
  }) {
    state = SystemCardLayoutState(
      anchors: Map<String, ({double x, double y})>.unmodifiable(anchors),
      hydrated: true,
    );
    unawaited(
      _store.write(
        SavedSystemCardLayout(
          canvasWidth: canvasWidth,
          tiles: <SavedCardTile>[
            for (final entry in anchors.entries)
              SavedCardTile(id: entry.key, x: entry.value.x, y: entry.value.y),
          ],
        ),
      ),
    );
  }
}

/// One persisted tile position.
class SavedCardTile {
  const SavedCardTile({
    required this.id,
    required this.x,
    required this.y,
    this.container = 'panel',
  });

  final String id;
  final double x;
  final double y;

  /// Reserved for the "cards on the desktop" container clavis supports;
  /// denial only writes `'panel'` for now (task scope: no desktop drops).
  final String container;
}

/// Persisted layout document: `{version: 1, canvasWidth: W, tiles: [...]}`.
class SavedSystemCardLayout {
  const SavedSystemCardLayout({required this.canvasWidth, required this.tiles});

  final double canvasWidth;
  final List<SavedCardTile> tiles;

  Map<String, Object> toJson() => <String, Object>{
    'version': 1,
    'canvasWidth': canvasWidth,
    'tiles': <Map<String, Object>>[
      for (final tile in tiles)
        <String, Object>{
          'id': tile.id,
          'x': tile.x,
          'y': tile.y,
          'container': tile.container,
        },
    ],
  };
}

/// Parses a saved document. Structural checks only — id legality, snap
/// alignment, and overlap need catalog + measured geometry and happen in
/// `resolveCardLayout`.
SavedSystemCardLayout? savedSystemCardLayoutFromJson(Object? raw) {
  if (raw is! Map) {
    return null;
  }
  final json = raw.cast<Object?, Object?>();
  if (json['version'] != 1) {
    return null;
  }
  final canvasWidth = json['canvasWidth'];
  final tilesRaw = json['tiles'];
  if (canvasWidth is! num || canvasWidth <= 0 || tilesRaw is! List) {
    return null;
  }
  final tiles = <SavedCardTile>[];
  final seen = <String>{};
  for (final entry in tilesRaw) {
    if (entry is! Map) {
      return null;
    }
    final tile = entry.cast<Object?, Object?>();
    final id = tile['id'];
    final x = tile['x'];
    final y = tile['y'];
    final container = tile['container'] ?? 'panel';
    if (id is! String ||
        id.isEmpty ||
        !seen.add(id) ||
        x is! num ||
        !x.isFinite ||
        y is! num ||
        !y.isFinite ||
        container is! String) {
      return null;
    }
    tiles.add(
      SavedCardTile(
        id: id,
        x: x.toDouble(),
        y: y.toDouble(),
        container: container,
      ),
    );
  }
  return SavedSystemCardLayout(
    canvasWidth: canvasWidth.toDouble(),
    tiles: tiles,
  );
}

abstract interface class SystemCardStore {
  Future<SavedSystemCardLayout?> read();

  Future<void> write(SavedSystemCardLayout layout);

  void dispose();
}

/// Persists the card layout to `$XDG_STATE_HOME/denial/system-cards.json`
/// with the same atomic write-then-rename pattern as `weather_store.dart`
/// (constraint G5: independent JSON state file, never the settings schema).
class SystemCardFileStore implements SystemCardStore {
  SystemCardFileStore({
    required this.paths,
    this.debounce = const Duration(milliseconds: 250),
  });

  final RuntimePaths paths;

  /// Write coalescing window: rapid commits (keyboard nudges, repeated
  /// drops) collapse into one disk write.
  final Duration debounce;

  // Writes serialize through a chain so a stale write from a previous
  // commit cannot interleave with a fresh one around the shared ".tmp"
  // path (write-then-rename would race otherwise).
  Future<void>? _inflight;
  Timer? _debounce;
  SavedSystemCardLayout? _queued;
  Completer<void>? _flushCompleter;

  @override
  Future<SavedSystemCardLayout?> read() async {
    try {
      final file = await _file();
      if (!await file.exists()) {
        return null;
      }
      return savedSystemCardLayoutFromJson(
        jsonDecode(await file.readAsString()),
      );
    } on Object {
      return null;
    }
  }

  @override
  Future<void> write(SavedSystemCardLayout layout) {
    _queued = layout;
    _flushCompleter ??= Completer<void>();
    final future = _flushCompleter!.future;
    if (debounce <= Duration.zero) {
      _flush();
    } else {
      _debounce?.cancel();
      _debounce = Timer(debounce, _flush);
    }
    return future;
  }

  void _flush() {
    _debounce?.cancel();
    _debounce = null;
    final queued = _queued;
    _queued = null;
    final completer = _flushCompleter;
    _flushCompleter = null;
    if (queued == null) {
      completer?.complete();
      return;
    }
    final previous = _inflight;
    final next = (previous ?? Future<void>.value()).then(
      (_) => _writeUnchecked(queued),
    );
    _inflight = next;
    unawaited(
      next.whenComplete(() {
        completer?.complete();
        if (identical(_inflight, next)) {
          _inflight = null;
        }
      }),
    );
  }

  Future<void> _writeUnchecked(SavedSystemCardLayout layout) async {
    try {
      final file = await _file();
      final temporary = File('${file.path}.tmp');
      final payload = jsonEncode(layout.toJson());
      await temporary.writeAsString('$payload\n', flush: true);
      await temporary.rename(file.path);
    } on Object {
      // Best-effort persistence: the in-memory anchors stay authoritative
      // for this session even when the disk write fails.
    }
  }

  /// Releases the debounce timer; a queued payload is flushed immediately so
  /// provider disposal never silently drops a committed layout.
  @override
  void dispose() {
    _debounce?.cancel();
    _debounce = null;
    _flush();
  }

  Future<File> _file() async {
    final dir = Directory(p.join(paths.stateHome, 'denial'));
    await dir.create(recursive: true);
    return File(p.join(dir.path, 'system-cards.json'));
  }
}
