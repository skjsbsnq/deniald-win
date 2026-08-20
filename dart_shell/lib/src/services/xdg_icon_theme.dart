import 'dart:async';
import 'dart:io';

/// Directory metadata parsed from an XDG `index.theme` file.
class XdgThemeDirectory {
  const XdgThemeDirectory({
    required this.name,
    required this.size,
    this.scale = 1,
    this.context = '',
    this.type = 'Threshold',
    this.maxSize = 0,
    this.minSize = 0,
    this.threshold = 2,
  });

  final String name;
  final int size;
  final int scale;
  final String context;
  final String type; // 'Threshold', 'Fixed', 'Scalable'
  final int maxSize;
  final int minSize;
  final int threshold;

  /// Calculates a distance penalty (lower is better) for the target size and scale.
  int distance(int targetSize, int targetScale) {
    final effectiveTarget = targetSize * targetScale;
    final effectiveDirSize = size * scale;

    switch (type.toLowerCase()) {
      case 'fixed':
        return (effectiveDirSize - effectiveTarget).abs();
      case 'scalable':
        final effectiveMin = (minSize > 0 ? minSize : size) * scale;
        final effectiveMax = (maxSize > 0 ? maxSize : size) * scale;
        if (effectiveTarget >= effectiveMin &&
            effectiveTarget <= effectiveMax) {
          return 0;
        } else if (effectiveTarget < effectiveMin) {
          return effectiveMin - effectiveTarget;
        } else {
          return effectiveTarget - effectiveMax;
        }
      case 'threshold':
      default:
        final effectiveThreshold = threshold * scale;
        final diff = (effectiveDirSize - effectiveTarget).abs();
        if (diff <= effectiveThreshold) {
          return 0;
        }
        return diff;
    }
  }
}

/// Parsed XDG icon theme specification with directory mappings and inheritance.
class XdgThemeData {
  const XdgThemeData({
    required this.name,
    required this.rootPath,
    this.inherits = const <String>[],
    this.directories = const <XdgThemeDirectory>[],
  });

  final String name;
  final String rootPath;
  final List<String> inherits;
  final List<XdgThemeDirectory> directories;
}

/// XDG Icon Theme specification lookup engine (Level 1 + Level 2).
///
/// Complies with XDG Icon Theme specification and Ayatana `IconThemePath` extension.
/// Uses purely asynchronous non-blocking file IO to avoid any main isolate stalls.
class XdgIconTheme {
  XdgIconTheme({List<String>? baseIconDirs, this.maxCacheEntries = 256})
    : baseIconDirs = baseIconDirs ?? _resolveDefaultIconDirs();

  final List<String> baseIconDirs;
  final int maxCacheEntries;

  final Map<String, String?> _lookupCache = <String, String?>{};
  final Map<String, XdgThemeData?> _themeDataCache = <String, XdgThemeData?>{};
  final Map<String, Future<String?>> _inFlightLookups =
      <String, Future<String?>>{};

  static const List<String> _supportedExtensions = <String>[
    '.png',
    '.svg',
    '.xpm',
  ];

  static List<String> _resolveDefaultIconDirs() {
    final dirs = <String>[];

    final home = Platform.environment['HOME'] ?? '';
    final xdgDataHome =
        Platform.environment['XDG_DATA_HOME'] ??
        (home.isNotEmpty ? '$home/.local/share' : '');
    if (xdgDataHome.isNotEmpty) {
      dirs.add('$xdgDataHome/icons');
    }

    if (home.isNotEmpty) {
      dirs.add('$home/.icons');
    }

    final xdgDataDirs =
        Platform.environment['XDG_DATA_DIRS'] ?? '/usr/local/share:/usr/share';
    for (final part in xdgDataDirs.split(':')) {
      final trimmed = part.trim();
      if (trimmed.isNotEmpty) {
        dirs.add('$trimmed/icons');
      }
    }

    dirs.add('/usr/share/pixmaps');
    return dirs;
  }

  /// Looks up the absolute file path for [iconName].
  ///
  /// [iconThemePath] is the custom theme directory provided by Ayatana / SNI.
  /// [themeName] is the active desktop icon theme (e.g. `breeze`, `Adwaita`, `Papirus`).
  /// [targetSize] is the requested physical pixel dimension (e.g. 24).
  /// [scale] is the device pixel ratio scale factor (e.g. 1 or 2).
  Future<String?> lookupIcon(
    String iconName, {
    String? iconThemePath,
    String themeName = 'Papirus',
    int targetSize = 24,
    int scale = 1,
  }) async {
    final cleanName = iconName.trim();
    if (cleanName.isEmpty) return null;

    final cacheKey = '$cleanName|$iconThemePath|$themeName|$targetSize|$scale';
    if (_lookupCache.containsKey(cacheKey)) {
      return _lookupCache[cacheKey];
    }

    if (_inFlightLookups.containsKey(cacheKey)) {
      return await _inFlightLookups[cacheKey];
    }

    final future = _performLookup(
      cleanName,
      iconThemePath: iconThemePath?.trim(),
      themeName: themeName.trim().isEmpty ? 'Papirus' : themeName.trim(),
      targetSize: targetSize,
      scale: scale,
    );

    _inFlightLookups[cacheKey] = future;
    try {
      final result = await future;
      _storeCache(cacheKey, result);
      return result;
    } finally {
      _inFlightLookups.remove(cacheKey);
    }
  }

  Future<String?> _performLookup(
    String name, {
    String? iconThemePath,
    required String themeName,
    required int targetSize,
    required int scale,
  }) async {
    // 1. Direct absolute or file URI path
    if (name.startsWith('/') || name.startsWith('file://')) {
      final path = name.startsWith('file://') ? name.substring(7) : name;
      if (await File(path).exists()) {
        return path;
      }
    }

    // 2. Custom IconThemePath (Ayatana SNI extension - highest priority)
    if (iconThemePath != null && iconThemePath.isNotEmpty) {
      final customMatch = await _searchInCustomPath(
        iconThemePath,
        name,
        targetSize,
        scale,
      );
      if (customMatch != null) {
        return customMatch;
      }
    }

    // 3. Search active theme and inheritance chain
    final visitedThemes = <String>{};
    final themesToSearch = <String>[themeName];

    while (themesToSearch.isNotEmpty) {
      final currentTheme = themesToSearch.removeAt(0);
      if (visitedThemes.contains(currentTheme)) continue;
      visitedThemes.add(currentTheme);

      for (final baseDir in baseIconDirs) {
        if (baseDir.endsWith('/pixmaps')) continue;
        final themeRoot = '$baseDir/$currentTheme';
        final themeData = await _getThemeData(themeRoot, currentTheme);
        if (themeData == null) continue;

        // Queue inherited themes
        for (final inherited in themeData.inherits) {
          if (!visitedThemes.contains(inherited) &&
              !themesToSearch.contains(inherited)) {
            themesToSearch.add(inherited);
          }
        }

        // Search directories sorted by distance to target size & scale
        final matchedPath = await _searchInTheme(
          themeData,
          name,
          targetSize,
          scale,
        );
        if (matchedPath != null) {
          return matchedPath;
        }
      }
    }

    // 4. Always ensure fallback to 'hicolor' if not already visited
    if (!visitedThemes.contains('hicolor')) {
      for (final baseDir in baseIconDirs) {
        if (baseDir.endsWith('/pixmaps')) continue;
        final themeRoot = '$baseDir/hicolor';
        final themeData = await _getThemeData(themeRoot, 'hicolor');
        if (themeData != null) {
          final matchedPath = await _searchInTheme(
            themeData,
            name,
            targetSize,
            scale,
          );
          if (matchedPath != null) {
            return matchedPath;
          }
        }
      }
    }

    // 5. Check global /usr/share/pixmaps fallback
    final pixmapMatch = await _searchInDirectory('/usr/share/pixmaps', name);
    if (pixmapMatch != null) {
      return pixmapMatch;
    }

    return null;
  }

  Future<String?> _searchInCustomPath(
    String customPath,
    String name,
    int targetSize,
    int scale,
  ) async {
    final dir = Directory(customPath);
    if (!await dir.exists()) return null;

    // Check directly in root of custom path
    final direct = await _searchInDirectory(customPath, name);
    if (direct != null) return direct;

    // Check if custom path contains an index.theme
    final indexFile = File('$customPath/index.theme');
    if (await indexFile.exists()) {
      final themeData = await _parseIndexTheme(indexFile, customPath, 'custom');
      if (themeData != null) {
        final themeMatch = await _searchInTheme(
          themeData,
          name,
          targetSize,
          scale,
        );
        if (themeMatch != null) return themeMatch;
      }
    }

    // Shallow check subdirectories (e.g. 24x24, scalable, status, icons)
    try {
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is Directory) {
          final subDirect = await _searchInDirectory(entity.path, name);
          if (subDirect != null) return subDirect;
        }
      }
    } catch (_) {}

    return null;
  }

  Future<String?> _searchInTheme(
    XdgThemeData themeData,
    String name,
    int targetSize,
    int scale,
  ) async {
    final sortedDirs = List<XdgThemeDirectory>.from(themeData.directories);
    sortedDirs.sort((a, b) {
      final distA = a.distance(targetSize, scale);
      final distB = b.distance(targetSize, scale);
      if (distA != distB) return distA.compareTo(distB);

      // Prioritize Status and Panel contexts for tray icons
      final contextScoreA = _contextScore(a.context);
      final contextScoreB = _contextScore(b.context);
      return contextScoreB.compareTo(contextScoreA);
    });

    for (final dirInfo in sortedDirs) {
      final dirPath = '${themeData.rootPath}/${dirInfo.name}';
      final fileMatch = await _searchInDirectory(dirPath, name);
      if (fileMatch != null) {
        return fileMatch;
      }
    }

    return null;
  }

  int _contextScore(String context) {
    switch (context.toLowerCase()) {
      case 'status':
        return 4;
      case 'panel':
        return 3;
      case 'applications':
      case 'apps':
        return 2;
      case 'actions':
        return 1;
      default:
        return 0;
    }
  }

  Future<String?> _searchInDirectory(String dirPath, String name) async {
    // 1. If name already has an extension
    for (final ext in _supportedExtensions) {
      if (name.endsWith(ext)) {
        final f = File('$dirPath/$name');
        if (await f.exists()) return f.path;
      }
    }

    // 2. Try each extension in preference order (svg, png, xpm)
    for (final ext in _supportedExtensions) {
      final f = File('$dirPath/$name$ext');
      if (await f.exists()) return f.path;
    }

    // 3. Exact raw name
    final raw = File('$dirPath/$name');
    if (await raw.exists()) return raw.path;

    return null;
  }

  Future<XdgThemeData?> _getThemeData(
    String themeRoot,
    String themeName,
  ) async {
    if (_themeDataCache.containsKey(themeRoot)) {
      return _themeDataCache[themeRoot];
    }

    final indexFile = File('$themeRoot/index.theme');
    if (!await indexFile.exists()) {
      _themeDataCache[themeRoot] = null;
      return null;
    }

    final parsed = await _parseIndexTheme(indexFile, themeRoot, themeName);
    final resolved = parsed != null && parsed.directories.isEmpty
        ? XdgThemeData(
            name: parsed.name,
            rootPath: parsed.rootPath,
            inherits: parsed.inherits,
            directories: await _discoverDirectories(themeRoot),
          )
        : parsed;
    _themeDataCache[themeRoot] = resolved;
    return resolved;
  }

  /// Reads a theme's directory layout off disk when its `index.theme` declares
  /// no `Directories`.
  ///
  /// Such an index is malformed per the spec, yet installers ship it: the
  /// `hicolor` index under `$XDG_DATA_HOME/icons` carries only `Name` and
  /// `Inherits`. Trusting the declaration alone makes every icon installed
  /// there unreachable, so recover the layout from the directory names.
  Future<List<XdgThemeDirectory>> _discoverDirectories(String themeRoot) async {
    final root = Directory(themeRoot);
    final discovered = <XdgThemeDirectory>[];
    try {
      await for (final sizeEntry in root.list(followLinks: false)) {
        if (sizeEntry is! Directory) continue;
        final sizeName = sizeEntry.path.split('/').last;
        final size = _parseSizeDirectoryName(sizeName);
        if (size == null) continue;
        await for (final contextEntry in sizeEntry.list(followLinks: false)) {
          if (contextEntry is! Directory) continue;
          final context = contextEntry.path.split('/').last;
          discovered.add(
            XdgThemeDirectory(
              name: '$sizeName/$context',
              size: size.size,
              scale: size.scale,
              context: context,
              type: size.type,
              minSize: size.minSize,
              maxSize: size.maxSize,
            ),
          );
        }
      }
    } on FileSystemException {
      return discovered;
    }
    return discovered;
  }

  /// Reads `48x48`, `48x48@2`, `scalable` and `symbolic` directory names.
  static ({int size, int scale, String type, int minSize, int maxSize})?
  _parseSizeDirectoryName(String name) {
    if (name == 'scalable' || name == 'symbolic') {
      return (size: 128, scale: 1, type: 'Scalable', minSize: 1, maxSize: 512);
    }
    final match = RegExp(r'^(\d+)x(\d+)(?:@(\d+))?$').firstMatch(name);
    if (match == null) {
      return null;
    }
    final width = int.parse(match.group(1)!);
    if (width != int.parse(match.group(2)!)) {
      return null;
    }
    return (
      size: width,
      scale: int.tryParse(match.group(3) ?? '1') ?? 1,
      type: 'Threshold',
      minSize: width,
      maxSize: width,
    );
  }

  Future<XdgThemeData?> _parseIndexTheme(
    File indexFile,
    String rootPath,
    String defaultName,
  ) async {
    try {
      final content = await indexFile.readAsString();
      final lines = content.split('\n');

      String themeName = defaultName;
      final inherits = <String>[];
      final dirNames = <String>[];
      final sections = <String, Map<String, String>>{};

      String currentSection = '';

      for (final rawLine in lines) {
        final line = rawLine.trim();
        if (line.isEmpty || line.startsWith('#')) continue;

        if (line.startsWith('[') && line.endsWith(']')) {
          currentSection = line.substring(1, line.length - 1).trim();
          sections[currentSection] ??= <String, String>{};
          continue;
        }

        final eqIdx = line.indexOf('=');
        if (eqIdx != -1 && currentSection.isNotEmpty) {
          final key = line.substring(0, eqIdx).trim();
          final val = line.substring(eqIdx + 1).trim();
          sections[currentSection]![key] = val;
        }
      }

      final iconThemeSection = sections['Icon Theme'] ?? sections['icon theme'];
      if (iconThemeSection != null) {
        if (iconThemeSection.containsKey('Name')) {
          themeName = iconThemeSection['Name']!;
        }
        if (iconThemeSection.containsKey('Inherits')) {
          final rawInherits = iconThemeSection['Inherits']!;
          inherits.addAll(
            rawInherits
                .split(',')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty),
          );
        }
        if (iconThemeSection.containsKey('Directories')) {
          final rawDirs = iconThemeSection['Directories']!;
          dirNames.addAll(
            rawDirs.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty),
          );
        }
      }

      final directories = <XdgThemeDirectory>[];
      for (final dirName in dirNames) {
        final sec = sections[dirName];
        final size = int.tryParse(sec?['Size'] ?? '') ?? 16;
        final scale = int.tryParse(sec?['Scale'] ?? '') ?? 1;
        final context = sec?['Context'] ?? '';
        final type = sec?['Type'] ?? 'Threshold';
        final maxSize = int.tryParse(sec?['MaxSize'] ?? '') ?? size;
        final minSize = int.tryParse(sec?['MinSize'] ?? '') ?? size;
        final threshold = int.tryParse(sec?['Threshold'] ?? '') ?? 2;

        directories.add(
          XdgThemeDirectory(
            name: dirName,
            size: size,
            scale: scale,
            context: context,
            type: type,
            maxSize: maxSize,
            minSize: minSize,
            threshold: threshold,
          ),
        );
      }

      return XdgThemeData(
        name: themeName,
        rootPath: rootPath,
        inherits: inherits,
        directories: directories,
      );
    } catch (_) {
      return null;
    }
  }

  void _storeCache(String key, String? value) {
    if (_lookupCache.length >= maxCacheEntries) {
      _lookupCache.remove(_lookupCache.keys.first);
    }
    _lookupCache[key] = value;
  }

  /// Clears in-memory icon lookup caches.
  void clear() {
    _lookupCache.clear();
    _themeDataCache.clear();
    _inFlightLookups.clear();
  }
}

/// Global shared instance for XDG icon resolution.
final XdgIconTheme defaultXdgIconTheme = XdgIconTheme();
