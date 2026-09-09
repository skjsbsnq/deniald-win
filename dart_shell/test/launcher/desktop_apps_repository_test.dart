import 'dart:io';

import 'package:denial_dart_shell/src/launcher/repositories/desktop_apps_repository.dart';
import 'package:denial_dart_shell/src/launcher/runtime_paths.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temporaryDirectory;
  late Directory dataDirectory;
  late DesktopAppsRepository repository;

  setUp(() {
    temporaryDirectory = Directory.systemTemp.createTempSync(
      'denial-app-icons-',
    );
    dataDirectory = Directory(p.join(temporaryDirectory.path, 'share'))
      ..createSync(recursive: true);
    repository = DesktopAppsRepository(
      paths: RuntimePaths(
        environment: <String, String>{
          'HOME': p.join(temporaryDirectory.path, 'home'),
          'XDG_DATA_HOME': dataDirectory.path,
          'XDG_DATA_DIRS': '',
        },
      ),
    );
  });

  tearDown(() {
    temporaryDirectory.deleteSync(recursive: true);
  });

  test('parses well-formed desktop entries into application models', () async {
    _writeDesktopEntry(
      dataDirectory,
      'org.example.Chat.desktop',
      '[Desktop Entry]\n'
          'Type=Application\n'
          'Name=Example Chat\n'
          'Exec=/usr/bin/example-chat %U\n'
          'Icon=org.example.Chat\n'
          'Categories=Network;Chat;\n'
          'StartupWMClass=ExampleChat\n',
    );
    _writeFile(
      dataDirectory,
      'icons/hicolor/128x128/apps/org.example.Chat.svg',
      '<svg/>',
    );

    final apps = await repository.loadApplications();
    final chat = apps.firstWhere(
      (app) => app.id == 'org.example.Chat.desktop',
    );
    expect(chat.name, 'Example Chat');
    expect(chat.exec, '/usr/bin/example-chat %U');
    expect(chat.icon, 'org.example.Chat');
    expect(
      chat.iconPath,
      p.join(
        dataDirectory.path,
        'icons',
        'hicolor',
        '128x128',
        'apps',
        'org.example.Chat.svg',
      ),
    );
    expect(chat.categories, <String>['Network', 'Chat']);
    expect(chat.startupWmClass, 'ExampleChat');
    expect(
      chat.desktopPath,
      p.join(dataDirectory.path, 'applications', 'org.example.Chat.desktop'),
    );
  });

  test('prefers the localized desktop entry name for the session locale', () async {
    _writeDesktopEntry(
      dataDirectory,
      'org.example.Chat.desktop',
      '[Desktop Entry]\n'
          'Type=Application\n'
          'Name=Example Chat\n'
          'Name[zh_CN]=示例聊天\n'
          'Exec=/usr/bin/example-chat\n',
    );
    final localized = DesktopAppsRepository(
      paths: RuntimePaths(
        environment: <String, String>{
          'HOME': p.join(temporaryDirectory.path, 'home'),
          'XDG_DATA_HOME': dataDirectory.path,
          'XDG_DATA_DIRS': '',
          'LANG': 'zh_CN.UTF-8',
        },
      ),
    );

    final apps = await localized.loadApplications();
    expect(
      apps.firstWhere((app) => app.id == 'org.example.Chat.desktop').name,
      '示例聊天',
    );
  });

  test('skips entries that are hidden, terminal-only, mistyped, or incomplete', () async {
    _writeDesktopEntry(
      dataDirectory,
      'org.example.Link.desktop',
      '[Desktop Entry]\nType=Link\nName=Link\nExec=x\n',
    );
    _writeDesktopEntry(
      dataDirectory,
      'org.example.Hidden.desktop',
      '[Desktop Entry]\nType=Application\nName=Hidden\nHidden=true\nExec=x\n',
    );
    _writeDesktopEntry(
      dataDirectory,
      'org.example.NoDisplay.desktop',
      '[Desktop Entry]\n'
          'Type=Application\n'
          'Name=NoDisplay\n'
          'NoDisplay=true\n'
          'Exec=x\n',
    );
    _writeDesktopEntry(
      dataDirectory,
      'org.example.Terminal.desktop',
      '[Desktop Entry]\n'
          'Type=Application\n'
          'Name=Terminal\n'
          'Terminal=true\n'
          'Exec=x\n',
    );
    _writeDesktopEntry(
      dataDirectory,
      'org.example.NoName.desktop',
      '[Desktop Entry]\nType=Application\nExec=x\n',
    );
    _writeDesktopEntry(
      dataDirectory,
      'org.example.NoExec.desktop',
      '[Desktop Entry]\nType=Application\nName=NoExec\n',
    );
    _writeDesktopEntry(
      dataDirectory,
      'org.example.Garbage.desktop',
      'not a desktop file at all\n',
    );

    final apps = await repository.loadApplications();
    expect(
      apps.where((app) => app.id.startsWith('org.example.')),
      isEmpty,
    );
  });

  test('honors OnlyShowIn, NotShowIn, and TryExec availability', () async {
    _writeDesktopEntry(
      dataDirectory,
      'org.example.Shown.desktop',
      '[Desktop Entry]\n'
          'Type=Application\n'
          'Name=Shown\n'
          'Exec=/usr/bin/example-chat\n'
          'OnlyShowIn=Denial;\n',
    );
    _writeDesktopEntry(
      dataDirectory,
      'org.example.OtherDesktop.desktop',
      '[Desktop Entry]\n'
          'Type=Application\n'
          'Name=Other Desktop\n'
          'Exec=/usr/bin/example-chat\n'
          'OnlyShowIn=GNOME;\n',
    );
    _writeDesktopEntry(
      dataDirectory,
      'org.example.Excluded.desktop',
      '[Desktop Entry]\n'
          'Type=Application\n'
          'Name=Excluded\n'
          'Exec=/usr/bin/example-chat\n'
          'NotShowIn=Denial;\n',
    );
    _writeDesktopEntry(
      dataDirectory,
      'org.example.MissingBinary.desktop',
      '[Desktop Entry]\n'
          'Type=Application\n'
          'Name=Missing Binary\n'
          'Exec=/usr/bin/example-chat\n'
          'TryExec=/nonexistent/example-chat\n',
    );

    final apps = await repository.loadApplications();
    final ids = apps
        .map((app) => app.id)
        .where((id) => id.startsWith('org.example.'))
        .toList();
    expect(ids, <String>['org.example.Shown.desktop']);
  });

  test('sorts applications by name and then id', () async {
    _writeDesktopEntry(
      dataDirectory,
      'b.desktop',
      '[Desktop Entry]\nType=Application\nName=Gamma\nExec=x\n',
    );
    _writeDesktopEntry(
      dataDirectory,
      'a.desktop',
      '[Desktop Entry]\nType=Application\nName=beta\nExec=x\n',
    );
    _writeDesktopEntry(
      dataDirectory,
      'c.desktop',
      '[Desktop Entry]\nType=Application\nName=Alpha\nExec=x\n',
    );

    final apps = await repository.loadApplications();
    final orderedIds = apps
        .map((app) => app.id)
        .where((id) => const ['a.desktop', 'b.desktop', 'c.desktop'].contains(
              id,
            ))
        .toList();
    expect(orderedIds, <String>['c.desktop', 'a.desktop', 'b.desktop']);
  });

  test('prefers XDG_DATA_HOME entries over data-dir collisions', () async {
    final systemData = Directory(
      p.join(temporaryDirectory.path, 'system-share'),
    )..createSync(recursive: true);
    _writeDesktopEntry(
      dataDirectory,
      'org.example.Dupe.desktop',
      '[Desktop Entry]\n'
          'Type=Application\n'
          'Name=Dupe\n'
          'Exec=/usr/bin/from-data-home\n',
    );
    _writeFile(
      systemData,
      'applications/org.example.Dupe.desktop',
      '[Desktop Entry]\n'
          'Type=Application\n'
          'Name=Dupe\n'
          'Exec=/usr/bin/from-system\n',
    );
    final layered = DesktopAppsRepository(
      paths: RuntimePaths(
        environment: <String, String>{
          'HOME': p.join(temporaryDirectory.path, 'home'),
          'XDG_DATA_HOME': dataDirectory.path,
          'XDG_DATA_DIRS': systemData.path,
        },
      ),
    );

    final apps = await layered.loadApplications();
    expect(
      apps.firstWhere((app) => app.id == 'org.example.Dupe.desktop').exec,
      '/usr/bin/from-data-home',
    );
  });

  test('resolves absolute icon paths after safety checks', () {
    final directIcon = _writeFile(
      temporaryDirectory,
      'direct/icon.svg',
      '<svg/>',
    );
    expect(repository.resolveIconPath(directIcon.path), directIcon.path);
    expect(
      repository.resolveIconPath(
        p.join(temporaryDirectory.path, 'missing.svg'),
      ),
      isNull,
    );
    final textIcon = _writeFile(temporaryDirectory, 'direct/icon.txt', 'x');
    expect(repository.resolveIconPath(textIcon.path), isNull);
  });

  test('resolves symbolic icon names through scanned theme directories', () {
    final batteryIcon = _writeFile(
      dataDirectory,
      'icons/Fixture/symbolic/apps/battery-caution-symbolic.svg',
      '<svg/>',
    );
    expect(
      repository.resolveIconPath('battery-caution-symbolic'),
      batteryIcon.path,
    );
    expect(
      repository.resolveIconPath('battery-caution-symbolic.svg'),
      batteryIcon.path,
    );
    expect(
      repository.resolveIconPath('org.example.nonexistent-icon'),
      isNull,
    );
  });

  test('prefers the configured icon theme over hicolor', () {
    final hicolorIcon = _writeFile(
      dataDirectory,
      'icons/hicolor/scalable/apps/org.example.Themed.svg',
      '<svg/>',
    );
    final themedIcon = _writeFile(
      dataDirectory,
      'icons/Custom/scalable/apps/org.example.Themed.svg',
      '<svg/>',
    );
    final themed = DesktopAppsRepository(
      paths: RuntimePaths(
        environment: <String, String>{
          'HOME': p.join(temporaryDirectory.path, 'home'),
          'XDG_DATA_HOME': dataDirectory.path,
          'XDG_DATA_DIRS': '',
        },
      ),
      iconThemeName: 'Custom',
    );

    expect(themed.resolveIconPath('org.example.Themed'), themedIcon.path);
    expect(repository.resolveIconPath('org.example.Themed'), hicolorIcon.path);
  });

  test('falls back to the pixmaps directory for named icons', () {
    final pixmapIcon = _writeFile(
      dataDirectory,
      'pixmaps/org.example.Pixmap.png',
      'png',
    );
    expect(
      repository.resolveIconPath('org.example.Pixmap'),
      pixmapIcon.path,
    );
  });

  test('uses the desktop entry icon when the app icon is omitted', () {
    final appIcon = _writeFile(
      dataDirectory,
      'icons/hicolor/128x128/apps/org.example.Chat.svg',
      '<svg/>',
    );
    _writeDesktopEntry(
      dataDirectory,
      'org.example.Chat.desktop',
      '[Desktop Entry]\n'
          'Type=Application\n'
          'Name=Example Chat\n'
          'Icon=org.example.Chat\n',
    );

    expect(
      repository.resolveNotificationIcon(
        appIcon: '',
        desktopEntry: 'org.example.Chat',
      ),
      appIcon.path,
    );
    expect(
      repository.resolveNotificationIcon(
        appIcon: '',
        desktopEntry: 'org.example.Chat.desktop',
      ),
      appIcon.path,
    );
  });

  test('rejects desktop entry lookups that escape the application directories', () {
    _writeDesktopEntry(
      dataDirectory,
      'org.example.Chat.desktop',
      '[Desktop Entry]\n'
          'Type=Application\n'
          'Name=Example Chat\n'
          'Icon=org.example.Chat\n',
    );

    expect(
      repository.resolveNotificationIcon(
        appIcon: '',
        desktopEntry: '../applications/org.example.Chat',
      ),
      isNull,
    );
    expect(
      repository.resolveNotificationIcon(
        appIcon: '',
        desktopEntry: 'sub/dir/org.example.Chat',
      ),
      isNull,
    );
    expect(
      repository.resolveNotificationIcon(appIcon: '', desktopEntry: '.'),
      isNull,
    );
    expect(
      repository.resolveNotificationIcon(appIcon: '', desktopEntry: ''),
      isNull,
    );
  });

  test('prefers a resolvable app icon over the desktop entry hint', () {
    final directIcon = _writeFile(
      temporaryDirectory,
      'direct/direct-icon.svg',
      '<svg/>',
    );
    _writeFile(
      dataDirectory,
      'icons/hicolor/128x128/apps/org.example.Chat.svg',
      '<svg/>',
    );
    _writeDesktopEntry(
      dataDirectory,
      'org.example.Chat.desktop',
      '[Desktop Entry]\n'
          'Type=Application\n'
          'Name=Example Chat\n'
          'Icon=org.example.Chat\n',
    );

    expect(
      repository.resolveNotificationIcon(
        appIcon: directIcon.path,
        desktopEntry: 'org.example.Chat',
      ),
      directIcon.path,
    );
  });
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
) => _writeFile(
  dataRoot,
  p.join('applications', relativePath),
  contents,
);
