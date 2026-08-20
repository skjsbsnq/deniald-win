import 'dart:convert';
import 'dart:io';

import 'package:denial_dart_shell/src/desktop/models/desktop_tile.dart';
import 'package:denial_dart_shell/src/desktop/repositories/desktop_tile_repository.dart';
import 'package:denial_dart_shell/src/launcher/models/desktop_app.dart';
import 'package:denial_dart_shell/src/launcher/models/home_grid_item.dart';
import 'package:denial_dart_shell/src/launcher/runtime_paths.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory configHome;
  late RuntimePaths paths;
  late DesktopTileRepository repository;

  setUp(() {
    configHome = Directory.systemTemp.createTempSync('denial-desktop-tiles');
    addTearDown(() => configHome.deleteSync(recursive: true));
    paths = RuntimePaths(
      environment: <String, String>{
        'HOME': '/home/example',
        'XDG_CONFIG_HOME': configHome.path,
      },
    );
    repository = DesktopTileRepository(paths: paths);
  });

  File tilesFile() => File('${configHome.path}/denia-home/desktop-tiles.json');

  void writeRaw(String contents) {
    final file = tilesFile();
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(contents);
  }

  test(
    'the board lives beside layout.json, not in the state directory',
    () async {
      final file = await paths.desktopTilesFile();

      expect(file.path, '${configHome.path}/denia-home/desktop-tiles.json');
      // The board is user configuration, so it must not land under stateHome the
      // way the wallpaper and notification files do.
      expect(file.path, isNot(contains('.local/state')));
    },
  );

  test('writing then reading a board returns every group and span', () async {
    await repository.saveLayout(<DesktopTileGroup>[
      DesktopTileGroup(
        name: 'Create',
        slots: <HomeGridItem?>[
          HomeGridItem.pinnedApp(_app('Alacritty'), colSpan: 4, rowSpan: 2),
          null,
          HomeGridItem.pinnedApp(_app('Chromium')),
        ],
      ),
      const DesktopTileGroup(name: 'Empty', slots: <HomeGridItem?>[]),
    ]);

    final groups = await repository.readSavedLayout();

    expect(groups, hasLength(2));
    expect(groups![0].name, 'Create');
    expect(groups[0].slots.map((slot) => slot?.id), <String?>[
      'app:alacritty.desktop',
      null,
      'app:chromium.desktop',
    ]);
    expect(groups[0].slots[0]!.colSpan, 4);
    expect(groups[0].slots[0]!.rowSpan, 2);
    expect(groups[1].name, 'Empty');
    expect(groups[1].slots, isEmpty);
  });

  test(
    'a saved slot carries enough to render and launch without a scan',
    () async {
      await repository.saveLayout(<DesktopTileGroup>[
        DesktopTileGroup(
          name: '',
          slots: <HomeGridItem?>[HomeGridItem.pinnedApp(_app('Alacritty'))],
        ),
      ]);

      final slot = (await repository.readSavedLayout())!.single.slots.single!;

      // Nothing here came from the installed-application list: the board has to
      // be able to show and start a tile before any scan has run.
      expect(slot.app!.name, 'Alacritty');
      expect(slot.app!.exec, '/usr/bin/alacritty');
      expect(slot.app!.iconPath, '/icons/alacritty.png');
      expect(slot.app!.startupWmClass, 'Alacritty');
    },
  );

  test('all three slot forms decode, including a bare string', () async {
    writeRaw(
      jsonEncode({
        'version': 1,
        'groups': [
          {
            'name': 'Mixed',
            'slots': [
              null,
              'app:bssh.desktop',
              {'id': 'app:firefox.desktop', 'colSpan': 2, 'rowSpan': 2},
            ],
          },
        ],
      }),
    );

    final slots = (await repository.readSavedLayout())!.single.slots;

    expect(slots[0], isNull);
    // A hand-written bare string names no application, so the id supplies a
    // display name rather than leaving the tile blank.
    expect(slots[1]!.app!.name, 'bssh');
    expect(slots[1]!.colSpan, isNull);
    expect(slots[2]!.app!.name, 'firefox');
    expect(slots[2]!.colSpan, 2);
  });

  test('a missing file is not an error, just an empty board', () async {
    expect(await repository.readSavedLayout(), isNull);
  });

  test('malformed JSON returns an empty board without throwing', () async {
    writeRaw('{"version": 1, "groups": [');

    expect(await repository.readSavedLayout(), isNull);
  });

  test(
    'a board written by a schema this shell does not know is discarded',
    () async {
      writeRaw(
        jsonEncode({
          'version': 99,
          'groups': [
            {
              'name': 'Future',
              'slots': ['app:alacritty.desktop'],
            },
          ],
        }),
      );

      // The mobile repository writes `version` and never reads it, so a schema
      // change there would be decoded as if it were the current one. Here an
      // unrecognised version means the shape is unknown and guessing is worse
      // than starting empty.
      expect(await repository.readSavedLayout(), isNull);
    },
  );

  test('a document with no version at all is discarded', () async {
    writeRaw(jsonEncode({'groups': <Object?>[]}));

    expect(await repository.readSavedLayout(), isNull);
  });

  test('groups that are not objects are skipped, the rest survive', () async {
    writeRaw(
      jsonEncode({
        'version': 1,
        'groups': [
          'not a group',
          {'name': 'Real', 'slots': <Object?>[]},
          {'name': 'No slots key'},
        ],
      }),
    );

    final groups = await repository.readSavedLayout();

    expect(groups!.map((group) => group.name), <String>['Real']);
  });

  test('a shell-hosted application is stored by id alone', () async {
    writeRaw(
      jsonEncode({
        'version': 1,
        'groups': [
          {
            'name': '',
            'slots': [
              {'id': 'local:dev.denial.settings', 'colSpan': 2, 'rowSpan': 2},
            ],
          },
        ],
      }),
    );

    final slot = (await repository.readSavedLayout())!.single.slots.single!;

    // Its icon and title are compiled into the bundle, so persisting a copy
    // would only let the two drift apart.
    expect(slot.app, isNull);
    expect(slot.id, 'local:dev.denial.settings');
  });

  test('illegal span values are safely clamped on decode', () async {
    writeRaw(
      jsonEncode({
        'version': 1,
        'groups': [
          {
            'name': 'Clamped',
            'slots': [
              {'id': 'app:alacritty.desktop', 'colSpan': 99, 'rowSpan': -5},
            ],
          },
        ],
      }),
    );

    final slot = (await repository.readSavedLayout())!.single.slots.single!;
    expect(slot.colSpan, 4);
    expect(slot.rowSpan, 1);
  });

  test(
    'Chinese group names and titles are preserved across save and read',
    () async {
      await repository.saveLayout(<DesktopTileGroup>[
        DesktopTileGroup(
          name: '生产力工具',
          slots: <HomeGridItem?>[
            HomeGridItem.pinnedApp(_app('终端'), colSpan: 4, rowSpan: 2),
          ],
        ),
        const DesktopTileGroup(name: '游戏娱乐', slots: <HomeGridItem?>[]),
      ]);

      final groups = await repository.readSavedLayout();
      expect(groups, hasLength(2));
      expect(groups![0].name, '生产力工具');
      expect(groups[0].slots.single!.app!.name, '终端');
      expect(groups[1].name, '游戏娱乐');
    },
  );

  test('truncated garbage bytes in tiles file safely returns null', () async {
    writeRaw('{"version": 1, "groups": \x00\x01\x02\xFF\xFE');
    expect(await repository.readSavedLayout(), isNull);
  });
}

DesktopApp _app(String name) {
  final id = '${name.toLowerCase()}.desktop';
  return DesktopApp(
    id: id,
    name: name,
    exec: '/usr/bin/${name.toLowerCase()}',
    desktopPath: '/usr/share/applications/$id',
    categories: const <String>[],
    iconPath: '/icons/${name.toLowerCase()}.png',
    startupWmClass: name,
  );
}
