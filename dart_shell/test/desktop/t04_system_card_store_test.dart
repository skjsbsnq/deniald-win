import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:denial_dart_shell/src/launcher/runtime_paths.dart';
import 'package:denial_dart_shell/src/services/system_card_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;
  late RuntimePaths paths;

  File layoutFile() =>
      File(p.join(tempDir.path, 'state', 'denial', 'system-cards.json'));

  SavedSystemCardLayout sample() => const SavedSystemCardLayout(
    canvasWidth: 412,
    tiles: <SavedCardTile>[
      SavedCardTile(id: 'cpu', x: 0, y: 0),
      SavedCardTile(id: 'memory', x: 144, y: 0),
      SavedCardTile(id: 'gpu:card0', x: 0, y: 168),
    ],
  );

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('t04-store-');
    paths = RuntimePaths(
      environment: <String, String>{
        'HOME': tempDir.path,
        'XDG_STATE_HOME': p.join(tempDir.path, 'state'),
      },
    );
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('write-then-read round-trips the layout document', () async {
    final store = SystemCardFileStore(paths: paths, debounce: Duration.zero);
    await store.write(sample());

    final decoded = jsonDecode(await layoutFile().readAsString());
    expect(decoded['version'], 1);
    expect(decoded['canvasWidth'], 412);
    expect(decoded['tiles'], hasLength(3));
    expect(decoded['tiles'][0]['container'], 'panel');
    // The atomic rename leaves no ".tmp" behind.
    expect(File('${layoutFile().path}.tmp').existsSync(), isFalse);

    final read = await store.read();
    expect(read, isNotNull);
    expect(read!.canvasWidth, 412);
    expect(read.tiles.map((t) => t.id), ['cpu', 'memory', 'gpu:card0']);
    expect(read.tiles[1].x, 144);
    store.dispose();
  });

  test('read returns null when no file exists', () async {
    final store = SystemCardFileStore(paths: paths, debounce: Duration.zero);
    expect(await store.read(), isNull);
    store.dispose();
  });

  test('corrupt or wrong-version files fall back to null', () async {
    final store = SystemCardFileStore(paths: paths, debounce: Duration.zero);
    await layoutFile().parent.create(recursive: true);

    await layoutFile().writeAsString('not json at all');
    expect(await store.read(), isNull);

    await layoutFile().writeAsString('{"version": 2, "tiles": []}');
    expect(await store.read(), isNull);

    // Missing canvasWidth.
    await layoutFile().writeAsString('{"version": 1, "tiles": []}');
    expect(await store.read(), isNull);

    // Malformed tile entry.
    await layoutFile().writeAsString(
      '{"version": 1, "canvasWidth": 412, "tiles": [{"id": 3, "x": 0, "y": 0}]}',
    );
    expect(await store.read(), isNull);

    // Duplicate ids are rejected.
    await layoutFile().writeAsString(
      '{"version": 1, "canvasWidth": 412, "tiles": ['
      '{"id": "cpu", "x": 0, "y": 0},'
      '{"id": "cpu", "x": 8, "y": 0}]}',
    );
    expect(await store.read(), isNull);
    store.dispose();
  });

  test('debounced writes collapse to the newest payload', () async {
    final store = SystemCardFileStore(
      paths: paths,
      debounce: const Duration(milliseconds: 30),
    );
    unawaitedWrites(store);
    await Future<void>.delayed(const Duration(milliseconds: 80));

    final read = await store.read();
    expect(read, isNotNull);
    expect(read!.tiles.single.id, 'memory');
    store.dispose();
  });

  test('hydration does not overwrite a commit that landed mid-read', () async {
    final gate = Completer<SavedSystemCardLayout?>();
    final container = ProviderContainer.test(
      overrides: [
        systemCardStoreProvider.overrideWithValue(_GatedCardStore(gate)),
      ],
    );
    addTearDown(container.dispose);
    final sub = container.listen(systemCardLayoutProvider, (_, _) {});
    addTearDown(sub.close);

    // The disk read is still parked when a keyboard nudge commits a fresh
    // layout — the in-memory anchors are now newer than the file.
    container
        .read(systemCardLayoutProvider.notifier)
        .commit(
          const <String, ({double x, double y})>{
            'cpu': (x: 8.0, y: 0.0),
          },
          canvasWidth: 412,
        );

    // The stale read resolves afterwards and must not roll the layout
    // back to the saved anchors.
    gate.complete(
      const SavedSystemCardLayout(
        canvasWidth: 412,
        tiles: <SavedCardTile>[SavedCardTile(id: 'cpu', x: 0, y: 0)],
      ),
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final state = container.read(systemCardLayoutProvider);
    expect(state.hydrated, isTrue);
    expect(state.anchors['cpu'], (x: 8.0, y: 0.0));
  });

  test('dispose flushes a queued payload instead of dropping it', () async {
    final store = SystemCardFileStore(
      paths: paths,
      debounce: const Duration(milliseconds: 500),
    );
    unawaited(store.write(sample()));
    store.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final read = await SystemCardFileStore(
      paths: paths,
      debounce: Duration.zero,
    ).read();
    expect(read, isNotNull);
    expect(read!.tiles, hasLength(3));
  });
}

/// Store whose read parks on a gate so tests can interleave a commit
/// between the read start and its completion.
class _GatedCardStore implements SystemCardStore {
  _GatedCardStore(this.readGate);

  final Completer<SavedSystemCardLayout?> readGate;
  SavedSystemCardLayout? written;

  @override
  Future<SavedSystemCardLayout?> read() => readGate.future;

  @override
  Future<void> write(SavedSystemCardLayout layout) async {
    written = layout;
  }

  @override
  void dispose() {}
}

void unawaitedWrites(SystemCardFileStore store) {
  unawaited(
    store.write(
      const SavedSystemCardLayout(
        canvasWidth: 412,
        tiles: <SavedCardTile>[SavedCardTile(id: 'cpu', x: 0, y: 0)],
      ),
    ),
  );
  unawaited(
    store.write(
      const SavedSystemCardLayout(
        canvasWidth: 412,
        tiles: <SavedCardTile>[SavedCardTile(id: 'memory', x: 144, y: 0)],
      ),
    ),
  );
}
