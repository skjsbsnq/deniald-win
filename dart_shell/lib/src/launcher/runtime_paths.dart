import 'dart:io';

import 'package:path/path.dart' as p;

class RuntimePaths {
  RuntimePaths({required Map<String, String> environment})
    : environment = Map.unmodifiable(environment);

  final Map<String, String> environment;

  String get homeDir {
    final home = environment['HOME'];
    if (home == null || home.isEmpty) {
      // Fail closed instead of reading or writing another user's home.
      return '/nonexistent';
    }
    return home;
  }

  String get configHome =>
      environment['XDG_CONFIG_HOME'] ?? p.join(homeDir, '.config');

  String get dataHome =>
      environment['XDG_DATA_HOME'] ?? p.join(homeDir, '.local', 'share');

  String get stateHome =>
      environment['XDG_STATE_HOME'] ?? p.join(homeDir, '.local', 'state');

  String get cacheHome =>
      environment['XDG_CACHE_HOME'] ?? p.join(homeDir, '.cache');

  String get wallpaperDirectory =>
      environment['DENIA_WALLPAPER_DIR'] ??
      p.join(homeDir, 'Pictures', 'Wallpapers');

  List<String> get dataDirs {
    return (environment['XDG_DATA_DIRS'] ?? '/usr/local/share:/usr/share')
        .split(':')
        .where((dir) => dir.isNotEmpty)
        .toList(growable: false);
  }

  String get powerdControlSocketPath =>
      environment['DENIA_POWERD_CONTROL_SOCKET'] ??
      '/run/denia-powerd/control.sock';

  Future<File> layoutFile() async {
    final dir = Directory(p.join(configHome, 'denia-home'));
    await dir.create(recursive: true);
    return File(p.join(dir.path, 'layout.json'));
  }

  /// The desktop start menu's pin board.
  ///
  /// It sits beside [layoutFile] because both are user configuration rather
  /// than runtime state, but it is a separate file: the mobile home screen
  /// holds every installed application, while the pin board holds only what
  /// the user pinned, and one file cannot mean both.
  Future<File> desktopTilesFile() async {
    final dir = Directory(p.join(configHome, 'denia-home'));
    await dir.create(recursive: true);
    return File(p.join(dir.path, 'desktop-tiles.json'));
  }

  Future<File> wallpaperStateFile() async {
    final dir = Directory(p.join(stateHome, 'denial'));
    await dir.create(recursive: true);
    return File(p.join(dir.path, 'wallpaper'));
  }

  Future<File> notificationPolicyFile() async {
    final dir = Directory(p.join(stateHome, 'denial'));
    await dir.create(recursive: true);
    return File(p.join(dir.path, 'notifications.json'));
  }

  List<Directory> desktopApplicationDirs() {
    final paths = <String>[
      p.join(dataHome, 'applications'),
      for (final dir in dataDirs) p.join(dir, 'applications'),
      p.join(
        homeDir,
        '.local',
        'share',
        'flatpak',
        'exports',
        'share',
        'applications',
      ),
      '/var/lib/flatpak/exports/share/applications',
    ];

    return uniquePaths(paths).map(Directory.new).toList(growable: false);
  }

  /// Resolves one `xdg-user-dirs` entry, for example `DOCUMENTS`.
  ///
  /// The directory names are localised — this session's Documents is `文档` —
  /// so the English [fallback] is only correct when `user-dirs.dirs` is absent
  /// or does not name the entry. Values are shell-quoted with `$HOME` left
  /// unexpanded, which is the only substitution the format allows.
  Future<String> xdgUserDirectory(
    String name, {
    required String fallback,
  }) async {
    final fromEnvironment = environment['XDG_${name}_DIR'];
    if (fromEnvironment != null && fromEnvironment.isNotEmpty) {
      return fromEnvironment;
    }
    final file = File(p.join(configHome, 'user-dirs.dirs'));
    try {
      final pattern = RegExp('^\\s*XDG_${name}_DIR\\s*=\\s*"(.*)"\\s*\$');
      for (final line in await file.readAsLines()) {
        final match = pattern.firstMatch(line);
        if (match == null) {
          continue;
        }
        final value = match.group(1)!;
        if (value.isEmpty) {
          break;
        }
        if (value == r'$HOME') {
          return homeDir;
        }
        if (value.startsWith(r'$HOME/')) {
          return p.join(homeDir, value.substring(r'$HOME/'.length));
        }
        return value;
      }
    } on FileSystemException {
      // No user-dirs.dirs, or it is unreadable; the English default is the
      // documented fallback for exactly this case.
    }
    return p.join(homeDir, fallback);
  }

  List<String> iconRoots() {
    return uniquePaths([
      dataHome,
      ...dataDirs,
      p.join(homeDir, '.local', 'share', 'flatpak', 'exports', 'share'),
      '/var/lib/flatpak/exports/share',
    ]);
  }

  /// Base directories containing XDG icon themes (`index.theme`).
  List<String> iconThemeDirs() {
    return uniquePaths([
      p.join(dataHome, 'icons'),
      p.join(homeDir, '.icons'),
      for (final dir in dataDirs) p.join(dir, 'icons'),
      p.join(
        homeDir,
        '.local',
        'share',
        'flatpak',
        'exports',
        'share',
        'icons',
      ),
      '/var/lib/flatpak/exports/share/icons',
    ]);
  }

  static List<String> uniquePaths(Iterable<String> paths) {
    final seen = <String>{};
    final unique = <String>[];
    for (final path in paths) {
      if (path.isEmpty || !seen.add(path)) {
        continue;
      }
      unique.add(path);
    }
    return unique;
  }
}
