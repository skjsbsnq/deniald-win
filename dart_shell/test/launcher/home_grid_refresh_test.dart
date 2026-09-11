import 'dart:io';

import 'package:denial_dart_shell/src/launcher/controllers/home_grid_controller.dart';
import 'package:denial_dart_shell/src/launcher/repositories/desktop_apps_repository.dart';
import 'package:denial_dart_shell/src/launcher/repositories/home_layout_repository.dart';
import 'package:denial_dart_shell/src/launcher/runtime_paths.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temporaryDirectory;
  late Directory dataDirectory;
  late RuntimePaths paths;
  late DesktopAppsRepository repository;

  setUp(() {
    temporaryDirectory = Directory.systemTemp.createTempSync(
      'denial-home-grid-refresh-',
    );
    dataDirectory = Directory(p.join(temporaryDirectory.path, 'share'))
      ..createSync(recursive: true);
    paths = RuntimePaths(
      environment: <String, String>{
        'HOME': p.join(temporaryDirectory.path, 'home'),
        'XDG_DATA_HOME': dataDirectory.path,
        'XDG_DATA_DIRS': '',
        'XDG_CONFIG_HOME': p.join(temporaryDirectory.path, 'config'),
      },
    );
    repository = DesktopAppsRepository(paths: paths);
  });

  tearDown(() {
    temporaryDirectory.deleteSync(recursive: true);
  });

  test(
    'loadApplicationsIfChanged skips reparsing while the fingerprint matches',
    () async {
      _writeDesktopEntry(
        dataDirectory,
        'org.example.Chat.desktop',
        '[Desktop Entry]\n'
            'Type=Application\n'
            'Name=Example Chat\n'
            'Exec=/usr/bin/example-chat\n',
      );

      final first = await repository.loadApplicationsIfChanged(null);
      // Host flatpak exports may contribute extra apps; match by id.
      expect(
        first.apps!.map((app) => app.id),
        contains('org.example.Chat.desktop'),
      );

      final again = await repository.loadApplicationsIfChanged(
        first.fingerprint,
      );
      expect(again.fingerprint, first.fingerprint);
      expect(again.apps, isNull);
    },
  );

  test(
    'loadApplicationsIfChanged reparses on add, edit, and removal',
    () async {
      _writeDesktopEntry(
        dataDirectory,
        'org.example.Chat.desktop',
        '[Desktop Entry]\n'
            'Type=Application\n'
            'Name=Example Chat\n'
            'Exec=/usr/bin/example-chat\n',
      );
      final initial = await repository.loadApplicationsIfChanged(null);
      var fingerprint = initial.fingerprint;
      final initialCount = initial.apps!.length;

      _writeDesktopEntry(
        dataDirectory,
        'org.example.Mail.desktop',
        '[Desktop Entry]\n'
            'Type=Application\n'
            'Name=Example Mail\n'
            'Exec=/usr/bin/example-mail\n',
      );
      var result = await repository.loadApplicationsIfChanged(fingerprint);
      expect(result.apps, hasLength(initialCount + 1));
      fingerprint = result.fingerprint;

      // Rewriting an entry changes size and mtime, so it must invalidate too.
      _writeDesktopEntry(
        dataDirectory,
        'org.example.Chat.desktop',
        '[Desktop Entry]\n'
            'Type=Application\n'
            'Name=Example Chat Renamed\n'
            'Exec=/usr/bin/example-chat --new\n',
      );
      result = await repository.loadApplicationsIfChanged(fingerprint);
      expect(
        result.apps!
            .firstWhere((app) => app.id == 'org.example.Chat.desktop')
            .name,
        'Example Chat Renamed',
      );
      fingerprint = result.fingerprint;

      File(
        p.join(dataDirectory.path, 'applications', 'org.example.Mail.desktop'),
      ).deleteSync();
      result = await repository.loadApplicationsIfChanged(fingerprint);
      expect(result.apps, hasLength(initialCount));
      expect(
        result.apps!.map((app) => app.id),
        isNot(contains('org.example.Mail.desktop')),
      );
    },
  );

  test(
    'timer refresh while visible keeps the parsed state when nothing changed',
    () async {
      _writeDesktopEntry(
        dataDirectory,
        'org.example.Chat.desktop',
        '[Desktop Entry]\n'
            'Type=Application\n'
            'Name=Example Chat\n'
            'Exec=/usr/bin/example-chat\n',
      );
      final container = _container(paths, repository);
      addTearDown(container.dispose);

      final initial = await container.read(homeGridControllerProvider.future);
      expect(_appIds(initial), contains('app:org.example.Chat.desktop'));

      final before = container.read(homeGridControllerProvider);
      await container
          .read(homeGridControllerProvider.notifier)
          .refreshDesktopApps(reason: 'timer');
      // An unchanged fingerprint returns before any state write, so the grid
      // keeps the exact same slots and skips the layout recompute.
      expect(
        identical(before, container.read(homeGridControllerProvider)),
        isTrue,
      );
    },
  );

  test(
    'hidden launcher suppresses refreshes and reloads once visible again',
    () async {
      _writeDesktopEntry(
        dataDirectory,
        'org.example.Chat.desktop',
        '[Desktop Entry]\n'
            'Type=Application\n'
            'Name=Example Chat\n'
            'Exec=/usr/bin/example-chat\n',
      );
      final container = _container(paths, repository);
      addTearDown(container.dispose);

      await container.read(homeGridControllerProvider.future);
      final controller = container.read(homeGridControllerProvider.notifier);
      controller.setLauncherActive(false);

      _writeDesktopEntry(
        dataDirectory,
        'org.example.Mail.desktop',
        '[Desktop Entry]\n'
            'Type=Application\n'
            'Name=Example Mail\n'
            'Exec=/usr/bin/example-mail\n',
      );
      await controller.refreshDesktopApps(reason: 'timer');
      expect(
        _appIds(container.read(homeGridControllerProvider).requireValue),
        isNot(contains('app:org.example.Mail.desktop')),
      );

      controller.setLauncherActive(true);
      await _waitFor(
        () => _appIds(
          container.read(homeGridControllerProvider).requireValue,
        ).contains('app:org.example.Mail.desktop'),
      );
    },
  );

  test('a scan finishing while the launcher is hidden is discarded', () async {
    _writeDesktopEntry(
      dataDirectory,
      'org.example.Chat.desktop',
      '[Desktop Entry]\n'
          'Type=Application\n'
          'Name=Example Chat\n'
          'Exec=/usr/bin/example-chat\n',
    );
    final container = _container(paths, repository);
    addTearDown(container.dispose);

    await container.read(homeGridControllerProvider.future);
    final controller = container.read(homeGridControllerProvider.notifier);

    _writeDesktopEntry(
      dataDirectory,
      'org.example.Mail.desktop',
      '[Desktop Entry]\n'
          'Type=Application\n'
          'Name=Example Mail\n'
          'Exec=/usr/bin/example-mail\n',
    );
    // Hiding synchronously while the isolate scan is in flight means the
    // result lands in a hidden grid and must be dropped.
    final pending = controller.refreshDesktopApps(reason: 'timer');
    controller.setLauncherActive(false);
    await pending;
    expect(
      _appIds(container.read(homeGridControllerProvider).requireValue),
      isNot(contains('app:org.example.Mail.desktop')),
    );

    // The next activation refreshes immediately and picks the entry up.
    controller.setLauncherActive(true);
    await _waitFor(
      () => _appIds(
        container.read(homeGridControllerProvider).requireValue,
      ).contains('app:org.example.Mail.desktop'),
    );
  });

  test(
    'a provider rebuild re-arms the refresh triggers for the new generation',
    () async {
      _writeDesktopEntry(
        dataDirectory,
        'org.example.Chat.desktop',
        '[Desktop Entry]\n'
            'Type=Application\n'
            'Name=Example Chat\n'
            'Exec=/usr/bin/example-chat\n',
      );
      final container = _container(paths, repository);
      addTearDown(container.dispose);

      await container.read(homeGridControllerProvider.future);
      // Invalidation re-runs build() on the same notifier instance, the same
      // path a watched dependency change takes.
      container.invalidate(homeGridControllerProvider);
      final rebuilt = await container.read(homeGridControllerProvider.future);
      expect(_appIds(rebuilt), contains('app:org.example.Chat.desktop'));

      bool hasRebuiltApp() => _appIds(
        container.read(homeGridControllerProvider).requireValue,
      ).any((id) => id.startsWith('app:org.example.Rebuilt'));

      // Keep emitting watch events until the new generation's re-armed
      // watcher fires and the debounced refresh picks an entry up on its own.
      final deadline = DateTime.now().add(const Duration(seconds: 6));
      var attempt = 0;
      while (!hasRebuiltApp()) {
        if (DateTime.now().isAfter(deadline)) {
          fail('rebuilt generation never picked up a new desktop entry');
        }
        _writeDesktopEntry(
          dataDirectory,
          'org.example.Rebuilt${attempt++}.desktop',
          '[Desktop Entry]\n'
              'Type=Application\n'
              'Name=Rebuilt App\n'
              'Exec=/usr/bin/rebuilt\n',
        );
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    },
  );
}

ProviderContainer _container(RuntimePaths paths, DesktopAppsRepository repo) {
  return ProviderContainer(
    overrides: [
      desktopAppsRepositoryProvider.overrideWithValue(repo),
      homeLayoutRepositoryProvider.overrideWithValue(
        HomeLayoutRepository(paths: paths),
      ),
    ],
  );
}

Set<String> _appIds(HomeGridState state) {
  return {
    for (final item in state.slots)
      if (item != null && item.app != null) item.id,
  };
}

Future<void> _waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 4));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('timed out waiting for the refreshed grid');
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

File _writeFile(Directory root, String relativePath, String contents) {
  final file = File(p.join(root.path, relativePath));
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(contents);
  return file;
}

File _writeDesktopEntry(
  Directory dataRoot,
  String relativePath,
  String contents,
) => _writeFile(dataRoot, p.join('applications', relativePath), contents);
