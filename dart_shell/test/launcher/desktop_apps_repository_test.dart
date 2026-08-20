import 'dart:io';

import 'package:denial_dart_shell/src/launcher/repositories/desktop_apps_repository.dart';
import 'package:denial_dart_shell/src/launcher/runtime_paths.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temporary;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('denial-desktop-apps-');
  });

  tearDown(() async {
    await temporary.delete(recursive: true);
  });

  test('loads desktop entries linked into an XDG data directory', () async {
    final applications = Directory(
      p.join(temporary.path, 'profile', 'share', 'applications'),
    );
    await applications.create(recursive: true);
    final source = File(p.join(temporary.path, 'nix-store-app.desktop'));
    await source.writeAsString('''
[Desktop Entry]
Type=Application
Name=Store Application
Exec=/bin/true
''');
    await Link(
      p.join(applications.path, 'store-application.desktop'),
    ).create(source.path);

    final repository = DesktopAppsRepository(
      paths: RuntimePaths(
        environment: <String, String>{
          'HOME': temporary.path,
          'XDG_DATA_DIRS': p.join(temporary.path, 'profile', 'share'),
          'XDG_CURRENT_DESKTOP': 'Denial',
        },
      ),
    );

    final applicationsFound = await repository.loadApplications();

    expect(applicationsFound, hasLength(1));
    expect(applicationsFound.single.id, 'store-application.desktop');
    expect(applicationsFound.single.name, 'Store Application');
    expect(
      applicationsFound.single.desktopPath,
      p.join(applications.path, 'store-application.desktop'),
    );
  });

  test('ignores broken desktop-entry links', () async {
    final applications = Directory(
      p.join(temporary.path, 'profile', 'share', 'applications'),
    );
    await applications.create(recursive: true);
    await Link(
      p.join(applications.path, 'broken.desktop'),
    ).create(p.join(temporary.path, 'missing.desktop'));

    final repository = DesktopAppsRepository(
      paths: RuntimePaths(
        environment: <String, String>{
          'HOME': temporary.path,
          'XDG_DATA_DIRS': p.join(temporary.path, 'profile', 'share'),
        },
      ),
    );

    expect(await repository.loadApplications(), isEmpty);
  });

  test('resolves themed application icon from Papirus', () async {
    final profile = Directory(p.join(temporary.path, 'profile'));
    final applications = Directory(p.join(profile.path, 'applications'));
    final icons = Directory(
      p.join(profile.path, 'icons', 'Papirus', '48x48', 'apps'),
    );
    await applications.create(recursive: true);
    await icons.create(recursive: true);
    await File(
      p.join(profile.path, 'icons', 'Papirus', 'index.theme'),
    ).writeAsString('''
[Icon Theme]
Name=Papirus
Directories=48x48/apps

[48x48/apps]
Size=48
Type=Fixed
Context=Applications
''');
    final icon = File(p.join(icons.path, 'test-app.svg'));
    await icon.writeAsString('<svg xmlns="http://www.w3.org/2000/svg"/>');
    await File(p.join(applications.path, 'test-app.desktop')).writeAsString('''
[Desktop Entry]
Type=Application
Name=Theme Application
Exec=/bin/true
Icon=test-app
''');

    final repository = DesktopAppsRepository(
      paths: RuntimePaths(
        environment: <String, String>{
          'HOME': temporary.path,
          'XDG_DATA_HOME': profile.path,
          'XDG_DATA_DIRS': '',
          'XDG_CURRENT_DESKTOP': 'Denial',
        },
      ),
    );

    final applicationsFound = await repository.loadApplications();

    expect(applicationsFound.single.iconPath, icon.path);
  });

  test(
    'resolves the largest icon a theme offers, not a panel-sized one',
    () async {
      final profile = Directory(p.join(temporary.path, 'profile'));
      final applications = Directory(p.join(profile.path, 'applications'));
      await applications.create(recursive: true);
      final themeRoot = Directory(p.join(profile.path, 'icons', 'Papirus'));
      await themeRoot.create(recursive: true);
      await File(p.join(themeRoot.path, 'index.theme')).writeAsString('''
[Icon Theme]
Name=Papirus
Directories=16x16/apps,24x24/apps,256x256/apps

[16x16/apps]
Size=16
Type=Threshold
Context=Applications

[24x24/apps]
Size=24
Type=Threshold
Context=Applications

[256x256/apps]
Size=256
Type=Threshold
Context=Applications
''');
      for (final size in <String>['16x16', '24x24', '256x256']) {
        final directory = Directory(p.join(themeRoot.path, size, 'apps'));
        await directory.create(recursive: true);
        await File(
          p.join(directory.path, 'test-app.png'),
        ).writeAsBytes(<int>[0x89, 0x50, 0x4e, 0x47]);
      }
      await File(p.join(applications.path, 'test-app.desktop')).writeAsString(
        '''
[Desktop Entry]
Type=Application
Name=Sized Application
Exec=/bin/true
Icon=test-app
''',
      );

      final repository = DesktopAppsRepository(
        paths: RuntimePaths(
          environment: <String, String>{
            'HOME': temporary.path,
            'XDG_DATA_HOME': profile.path,
            'XDG_DATA_DIRS': '',
            'XDG_CURRENT_DESKTOP': 'Denial',
          },
        ),
      );

      final applicationsFound = await repository.loadApplications();

      expect(
        applicationsFound.single.iconPath,
        p.join(themeRoot.path, '256x256', 'apps', 'test-app.png'),
      );
    },
  );

  test('resolves icons from a theme that declares no directories', () async {
    final profile = Directory(p.join(temporary.path, 'profile'));
    final applications = Directory(p.join(profile.path, 'applications'));
    await applications.create(recursive: true);
    // Installers ship a per-user hicolor index carrying only Name and
    // Inherits. Every icon they drop there is reachable only by reading the
    // directory layout off disk.
    final themeRoot = Directory(p.join(profile.path, 'icons', 'hicolor'));
    await themeRoot.create(recursive: true);
    await File(p.join(themeRoot.path, 'index.theme')).writeAsString('''
[Icon Theme]
Name=Hicolor
Comment=Fallback icon theme
Inherits=hicolor
''');
    final icons = Directory(p.join(themeRoot.path, '256x256', 'apps'));
    await icons.create(recursive: true);
    final icon = File(p.join(icons.path, 'vendor-app.0.png'));
    await icon.writeAsBytes(<int>[0x89, 0x50, 0x4e, 0x47]);
    await File(p.join(applications.path, 'vendor-app.desktop')).writeAsString(
      '''
[Desktop Entry]
Type=Application
Name=Vendor Application
Exec=/bin/true
Icon=vendor-app.0
''',
    );

    final repository = DesktopAppsRepository(
      paths: RuntimePaths(
        environment: <String, String>{
          'HOME': temporary.path,
          'XDG_DATA_HOME': profile.path,
          'XDG_DATA_DIRS': '',
          'XDG_CURRENT_DESKTOP': 'Denial',
        },
      ),
    );

    final applicationsFound = await repository.loadApplications();

    expect(applicationsFound.single.iconPath, icon.path);
  });
}
