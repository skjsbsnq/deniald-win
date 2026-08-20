import 'dart:io';

import 'package:denial_dart_shell/src/launcher/runtime_paths.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses the configured home directory', () {
    final paths = RuntimePaths(
      environment: const <String, String>{'HOME': '/home/example'},
    );

    expect(paths.homeDir, '/home/example');
    expect(paths.configHome, '/home/example/.config');
  });

  test('uses a sentinel path when home is unavailable', () {
    expect(
      RuntimePaths(environment: const <String, String>{}).homeDir,
      '/nonexistent',
    );
    expect(
      RuntimePaths(environment: const <String, String>{'HOME': ''}).homeDir,
      '/nonexistent',
    );
  });

  group('xdgUserDirectory', () {
    late Directory configHome;

    setUp(() {
      configHome = Directory.systemTemp.createTempSync('denial-user-dirs');
      addTearDown(() => configHome.deleteSync(recursive: true));
    });

    RuntimePaths pathsWith(String? userDirs) {
      if (userDirs != null) {
        File('${configHome.path}/user-dirs.dirs').writeAsStringSync(userDirs);
      }
      return RuntimePaths(
        environment: <String, String>{
          'HOME': '/home/example',
          'XDG_CONFIG_HOME': configHome.path,
        },
      );
    }

    test('expands \$HOME against a localised directory name', () async {
      // The real file on this machine, comments and all.
      final paths = pathsWith('''
# This file is written by xdg-user-dirs-update
XDG_DESKTOP_DIR="\$HOME/桌面"
XDG_DOCUMENTS_DIR="\$HOME/文档"
XDG_PICTURES_DIR="\$HOME/图片"
''');

      expect(
        await paths.xdgUserDirectory('DOCUMENTS', fallback: 'Documents'),
        '/home/example/文档',
      );
      expect(
        await paths.xdgUserDirectory('PICTURES', fallback: 'Pictures'),
        '/home/example/图片',
      );
    });

    test('accepts an absolute path and a bare \$HOME', () async {
      final paths = pathsWith('''
XDG_DOCUMENTS_DIR="/srv/shared/docs"
XDG_PICTURES_DIR="\$HOME"
''');

      expect(
        await paths.xdgUserDirectory('DOCUMENTS', fallback: 'Documents'),
        '/srv/shared/docs',
      );
      expect(
        await paths.xdgUserDirectory('PICTURES', fallback: 'Pictures'),
        '/home/example',
      );
    });

    test('falls back when the file is missing, silent, or empty', () async {
      expect(
        await pathsWith(
          null,
        ).xdgUserDirectory('DOCUMENTS', fallback: 'Documents'),
        '/home/example/Documents',
      );
      expect(
        await pathsWith(
          'XDG_DESKTOP_DIR="\$HOME/桌面"\n',
        ).xdgUserDirectory('DOCUMENTS', fallback: 'Documents'),
        '/home/example/Documents',
      );
      expect(
        await pathsWith(
          'XDG_DOCUMENTS_DIR=""\n',
        ).xdgUserDirectory('DOCUMENTS', fallback: 'Documents'),
        '/home/example/Documents',
      );
    });

    test('an explicit environment variable wins over the file', () async {
      File(
        '${configHome.path}/user-dirs.dirs',
      ).writeAsStringSync('XDG_DOCUMENTS_DIR="\$HOME/文档"\n');
      final paths = RuntimePaths(
        environment: <String, String>{
          'HOME': '/home/example',
          'XDG_CONFIG_HOME': configHome.path,
          'XDG_DOCUMENTS_DIR': '/tmp/override',
        },
      );

      expect(
        await paths.xdgUserDirectory('DOCUMENTS', fallback: 'Documents'),
        '/tmp/override',
      );
    });
  });
}
