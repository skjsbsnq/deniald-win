import 'dart:io';

import 'package:denial_dart_shell/src/services/xdg_icon_theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('XdgThemeDirectory distance calculation', () {
    test('Fixed type matches exact size and scale', () {
      const dir = XdgThemeDirectory(
        name: '24x24/status',
        size: 24,
        scale: 1,
        type: 'Fixed',
      );
      expect(dir.distance(24, 1), 0);
      expect(dir.distance(22, 1), 2);
      expect(dir.distance(48, 1), 24);
    });

    test('Threshold type allows threshold deviation', () {
      const dir = XdgThemeDirectory(
        name: '24x24/apps',
        size: 24,
        scale: 1,
        threshold: 2,
        type: 'Threshold',
      );
      expect(dir.distance(24, 1), 0);
      expect(dir.distance(22, 1), 0); // 24 - 22 = 2 <= threshold(2) -> 0
      expect(dir.distance(26, 1), 0); // 26 - 24 = 2 <= threshold(2) -> 0
      expect(dir.distance(20, 1), 4); // 24 - 20 = 4 > threshold(2) -> 4
    });

    test('Scalable type matches within min/max bounds', () {
      const dir = XdgThemeDirectory(
        name: 'scalable/status',
        size: 16,
        minSize: 8,
        maxSize: 512,
        type: 'Scalable',
      );
      expect(dir.distance(16, 1), 0);
      expect(dir.distance(24, 1), 0);
      expect(dir.distance(48, 1), 0);
      expect(dir.distance(512, 1), 0);
      expect(dir.distance(4, 1), 4); // 8 - 4 = 4
    });
  });

  group('XdgIconTheme lookup integration', () {
    late Directory tempDir;
    late XdgIconTheme themeEngine;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('xdg_icon_test_');

      // Setup mock theme hierarchy:
      // tempDir/
      //   icons/
      //     mock-theme/
      //       index.theme
      //       24x24/status/
      //         tray-online.svg
      //       48x48/apps/
      //         discord.png
      //     hicolor/
      //       index.theme
      //       24x24/status/
      //         fallback-icon.png
      //   custom_app/
      //     app-custom.png

      final themeDir = Directory(
        '${tempDir.path}/icons/mock-theme/24x24/status',
      );
      await themeDir.create(recursive: true);
      await File(
        '${themeDir.path}/tray-online.svg',
      ).writeAsString('<svg></svg>');

      final appsDir = Directory('${tempDir.path}/icons/mock-theme/48x48/apps');
      await appsDir.create(recursive: true);
      await File(
        '${appsDir.path}/discord.png',
      ).writeAsBytes([0x89, 0x50, 0x4E, 0x47]);

      final indexThemeFile = File(
        '${tempDir.path}/icons/mock-theme/index.theme',
      );
      await indexThemeFile.writeAsString('''
[Icon Theme]
Name=MockTheme
Inherits=hicolor
Directories=24x24/status,48x48/apps

[24x24/status]
Size=24
Context=Status
Type=Threshold

[48x48/apps]
Size=48
Context=Applications
Type=Threshold
''');

      final hicolorDir = Directory(
        '${tempDir.path}/icons/hicolor/24x24/status',
      );
      await hicolorDir.create(recursive: true);
      await File(
        '${hicolorDir.path}/fallback-icon.png',
      ).writeAsBytes([0x89, 0x50, 0x4E, 0x47]);

      final hicolorIndex = File('${tempDir.path}/icons/hicolor/index.theme');
      await hicolorIndex.writeAsString('''
[Icon Theme]
Name=Hicolor
Directories=24x24/status

[24x24/status]
Size=24
Context=Status
Type=Threshold
''');

      final customDir = Directory('${tempDir.path}/custom_app');
      await customDir.create(recursive: true);
      await File(
        '${customDir.path}/app-custom.png',
      ).writeAsBytes([0x89, 0x50, 0x4E, 0x47]);

      themeEngine = XdgIconTheme(baseIconDirs: ['${tempDir.path}/icons']);
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('resolves direct absolute path', () async {
      final customPath = '${tempDir.path}/custom_app/app-custom.png';
      final resolved = await themeEngine.lookupIcon(customPath);
      expect(resolved, customPath);
    });

    test('resolves custom IconThemePath with highest priority', () async {
      final resolved = await themeEngine.lookupIcon(
        'app-custom',
        iconThemePath: '${tempDir.path}/custom_app',
      );
      expect(resolved, '${tempDir.path}/custom_app/app-custom.png');
    });

    test('resolves icon from active theme matching size', () async {
      final resolved = await themeEngine.lookupIcon(
        'tray-online',
        themeName: 'mock-theme',
        targetSize: 24,
      );
      expect(resolved, contains('/mock-theme/24x24/status/tray-online.svg'));
    });

    test('falls back to hicolor when not in active theme', () async {
      final resolved = await themeEngine.lookupIcon(
        'fallback-icon',
        themeName: 'mock-theme',
        targetSize: 24,
      );
      expect(resolved, contains('/hicolor/24x24/status/fallback-icon.png'));
    });

    test('returns null for unknown icon', () async {
      final resolved = await themeEngine.lookupIcon(
        'non-existent-icon-12345',
        themeName: 'mock-theme',
      );
      expect(resolved, isNull);
    });
  });

  group('XdgIconTheme directory discovery', () {
    late Directory tempDir;
    late XdgIconTheme themeEngine;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('xdg_icon_bare_');

      // A theme whose index.theme omits Directories entirely, as shipped by
      // installers that write only Name and Inherits.
      final root = '${tempDir.path}/icons/bare-theme';
      for (final size in <String>['16x16', '128x128', 'scalable']) {
        await Directory('$root/$size/apps').create(recursive: true);
      }
      await File('$root/16x16/apps/vendor-app.png').writeAsBytes([0x89, 0x50]);
      await File(
        '$root/128x128/apps/vendor-app.png',
      ).writeAsBytes([0x89, 0x50]);
      await File('$root/scalable/apps/vector-app.svg').writeAsString('<svg/>');
      // A cursor theme's layout carries no size directories at all.
      await Directory('$root/cursors').create(recursive: true);
      await File('$root/index.theme').writeAsString('''
[Icon Theme]
Name=BareTheme
Comment=Fallback icon theme
Inherits=hicolor
''');

      themeEngine = XdgIconTheme(baseIconDirs: ['${tempDir.path}/icons']);
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('finds icons a theme never declared', () async {
      final resolved = await themeEngine.lookupIcon(
        'vendor-app',
        themeName: 'bare-theme',
        targetSize: 128,
      );
      expect(resolved, contains('/bare-theme/128x128/apps/vendor-app.png'));
    });

    test('honours target size across discovered directories', () async {
      final resolved = await themeEngine.lookupIcon(
        'vendor-app',
        themeName: 'bare-theme',
        targetSize: 16,
      );
      expect(resolved, contains('/bare-theme/16x16/apps/vendor-app.png'));
    });

    test('treats a discovered scalable directory as scalable', () async {
      final resolved = await themeEngine.lookupIcon(
        'vector-app',
        themeName: 'bare-theme',
        targetSize: 512,
      );
      expect(resolved, contains('/bare-theme/scalable/apps/vector-app.svg'));
    });
  });
}
