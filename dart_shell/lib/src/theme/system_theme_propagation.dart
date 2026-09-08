import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../settings/shell_settings.dart';

/// Mirrors the shell's font and icon theme choices into system-level
/// configuration so GTK, Qt, and fontconfig clients follow along.
///
/// The shell owns only fragments and keys, never the user's whole files:
/// fontconfig gets a dedicated drop-in under `conf.d`, and GTK's
/// `settings.ini` is edited key-by-key under a managed-marker comment
/// (per-user `settings.ini.d` drop-ins are not supported by GTK, unlike
/// the system-level directories). A legacy whole-file layout written by
/// older shell builds is migrated when its contents are provably
/// shell-authored; anything else in those files is preserved byte for byte.
///
/// Writes are idempotent and best effort: a failure to reach gsettings or to
/// write a config file leaves the shell itself unaffected. Empty selections
/// remove the corresponding system overrides so the pre-selection defaults
/// come back.
class SystemThemePropagation {
  SystemThemePropagation({String? homeDirectory})
    : _configHome = p.join(
        homeDirectory ?? Platform.environment['HOME'] ?? '.',
        '.config',
      );

  final String _configHome;

  /// Per-user fontconfig drop-in. Modern fontconfig (2.13+) reads this
  /// directory through XDG_CONFIG_HOME without requiring a user-level
  /// fonts.conf master file.
  static const String _fontConfigFragment = '60-denial.conf';

  /// Comment line marking the keys this shell owns inside GTK settings.ini.
  static const String _gtkManagedMarker = '# Managed by the Denial shell.';

  /// dconf can hang on a wedged session bus; the propagation must not park
  /// forever on it (the call itself stays unawaited by callers).
  static const Duration _gsettingsTimeout = Duration(seconds: 5);

  /// Keys inside the GTK `[Settings]` group that this shell maintains.
  static const List<String> _gtkManagedKeys = <String>[
    'gtk-font-name',
    'gtk-icon-theme-name',
  ];

  /// Whole-file outputs of the pre-fragment shell layout, used to recognize
  /// files this shell authored and can therefore migrate or replace.
  static final RegExp _legacyFontConfigPattern = RegExp(
    '^<\\?xml version="1\\.0"\\?>\\n'
    '<!DOCTYPE fontconfig SYSTEM "fonts\\.dtd">\\n'
    '<fontconfig>\\n'
    '  <alias><family>sans-serif</family><prefer>\\n'
    '    <family>([^<>\\n]+)</family>\\n'
    '    <family>Source Han Sans CN</family>\\n'
    '  </prefer></alias>\\n'
    '  <alias><family>monospace</family><prefer>\\n'
    '    <family>\\1</family>\\n'
    '    <family>Source Han Sans CN</family>\\n'
    '  </prefer></alias>\\n'
    '</fontconfig>\\n\$',
  );

  static final RegExp _legacyGtkIniPattern = RegExp(
    '^\\[Settings\\]\\n'
    'gtk-font-name = [^\\n]*\\n'
    'gtk-icon-theme-name = [^\\n]*\\n?\$',
  );

  Future<void> apply(ShellAppearanceSettings appearance) async {
    await Future.wait<void>([
      _applyFontConfig(appearance.uiFontFamily),
      _applyGsettings(appearance),
      _applyGtkSettingsIni(appearance),
    ]);
  }

  Future<void> _applyFontConfig(String uiFontFamily) async {
    final directory = Directory(p.join(_configHome, 'fontconfig'));
    final legacyFile = File(p.join(directory.path, 'fonts.conf'));
    final fragment = File(
      p.join(directory.path, 'conf.d', _fontConfigFragment),
    );

    // Migration (H3): a master fonts.conf that is provably the shell's own
    // legacy whole-file layout is removed in favor of the drop-in fragment,
    // byte-equivalent in effect. A file with any user content stays in place
    // untouched.
    var legacy = false;
    try {
      final contents = await legacyFile.exists()
          ? await legacyFile.readAsString()
          : null;
      legacy = contents != null && _legacyFontConfigPattern.hasMatch(contents);
      if (legacy) {
        await legacyFile.delete();
        debugPrint(
          'system_theme_propagation: migrated shell-owned fonts.conf to '
          'conf.d/$_fontConfigFragment',
        );
      } else if (contents != null && contents.trim().isNotEmpty) {
        debugPrint(
          'system_theme_propagation: user fonts.conf preserved; the shell '
          'writes its fragment to conf.d/$_fontConfigFragment only',
        );
      }
    } on Object {
      // Best effort migration; a locked-down home falls through to the
      // fragment write below.
    }

    if (uiFontFamily.isEmpty) {
      await _deleteIfExists(fragment);
      return;
    }

    final family = _escapeXml(uiFontFamily);
    final cjk = 'Source Han Sans CN';
    // Prepending the selected family to both generic aliases makes it the
    // effective default for every fontconfig client, not just monospace.
    await _writeIfChanged(
      fragment,
      '<?xml version="1.0"?>\n'
      '<!DOCTYPE fontconfig SYSTEM "fonts.dtd">\n'
      '<fontconfig>\n'
      '  <alias><family>sans-serif</family><prefer>\n'
      '    <family>$family</family>\n'
      '    <family>$cjk</family>\n'
      '  </prefer></alias>\n'
      '  <alias><family>monospace</family><prefer>\n'
      '    <family>$family</family>\n'
      '    <family>$cjk</family>\n'
      '  </prefer></alias>\n'
      '</fontconfig>\n',
    );
  }

  Future<void> _applyGsettings(ShellAppearanceSettings appearance) async {
    final fontName = appearance.uiFontFamily.isEmpty
        ? null
        : '${appearance.uiFontFamily} 11';
    final iconName = appearance.iconThemeName.isEmpty
        ? null
        : appearance.iconThemeName;
    await Future.wait<void>([
      _gsettings('font-name', fontName),
      _gsettings('icon-theme', iconName),
    ]);
  }

  Future<void> _applyGtkSettingsIni(ShellAppearanceSettings appearance) async {
    final clearing =
        appearance.uiFontFamily.isEmpty && appearance.iconThemeName.isEmpty;
    final fontValue = _escapeIniValue(
      appearance.uiFontFamily.isEmpty
          ? 'Sans 11'
          : '${appearance.uiFontFamily} 11',
    );
    final iconValue = _escapeIniValue(
      appearance.iconThemeName.isEmpty ? 'Adwaita' : appearance.iconThemeName,
    );
    for (final gtkVersion in const ['gtk-3.0', 'gtk-4.0']) {
      final directory = Directory(p.join(_configHome, gtkVersion));
      final file = File(p.join(directory.path, 'settings.ini'));
      try {
        final existing = await file.exists() ? await file.readAsString() : null;
        final next = _transformGtkSettingsIni(
          existing,
          clearing: clearing,
          fontValue: fontValue,
          iconValue: iconValue,
        );
        if (next == null) {
          continue;
        }
        if (next.deleteFile) {
          await _deleteIfExists(file);
        } else {
          await _writeIfChanged(file, next.contents);
        }
      } on Object {
        // A read-only home or missing XDG directories should not surface as a
        // shell failure.
      }
    }
  }

  /// Rewrites one GTK settings.ini so only the shell-owned marker and keys
  /// change. Returns null when nothing is written; [contents] is the full
  /// file to store and [deleteFile] marks a file that carried no user
  /// content at all.
  _GtkIniEdit? _transformGtkSettingsIni(
    String? existing, {
    required bool clearing,
    required String fontValue,
    required String iconValue,
  }) {
    // Migration (H3): a file that is exactly the shell's legacy whole-file
    // output is replaced by the managed layout, equivalent in effect.
    if (existing != null && _legacyGtkIniPattern.hasMatch(existing)) {
      debugPrint(
        'system_theme_propagation: migrated shell-owned settings.ini to '
        'managed-key layout',
      );
      existing = null;
    }

    // Drop the marker and the managed keys from the [Settings] group, keep
    // every other line byte for byte. A trailing newline survives as the
    // final empty element of split(), so joins restore the file exactly.
    var sawSettingsGroup = false;
    var inSettingsGroup = false;
    final kept = <String>[];
    for (final line in existing?.split('\n') ?? const <String>[]) {
      final trimmed = line.trim();
      if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
        inSettingsGroup = trimmed == '[Settings]';
        sawSettingsGroup = sawSettingsGroup || inSettingsGroup;
      }
      if (trimmed == _gtkManagedMarker) {
        continue;
      }
      if (inSettingsGroup &&
          _gtkManagedKeys.any(trimmed.startsWith) &&
          trimmed.contains('=')) {
        continue;
      }
      kept.add(line);
    }

    if (!clearing) {
      final managedBlock = <String>[
        _gtkManagedMarker,
        'gtk-font-name = $fontValue',
        'gtk-icon-theme-name = $iconValue',
      ];
      if (sawSettingsGroup) {
        // The managed keys belong inside the [Settings] group: ahead of the
        // first following group header, or at the end of the group's lines.
        var inGroup = false;
        var insertAt = kept.length;
        for (var index = 0; index < kept.length; index += 1) {
          final trimmed = kept[index].trim();
          final isHeader = trimmed.startsWith('[') && trimmed.endsWith(']');
          if (isHeader && trimmed == '[Settings]') {
            inGroup = true;
            continue;
          }
          if (isHeader && inGroup) {
            insertAt = index;
            break;
          }
        }
        if (insertAt == kept.length && kept.isNotEmpty && kept.last == '') {
          // Keep the managed keys ahead of the file's final newline.
          insertAt -= 1;
        }
        kept.insertAll(insertAt, managedBlock);
      } else {
        if (kept.isNotEmpty && kept.last.isNotEmpty) {
          kept.add('');
        }
        kept.addAll(['[Settings]', ...managedBlock, '']);
      }
    }

    final contents = kept.join('\n');
    final hasUserContent = kept.where((line) => line.trim().isNotEmpty).any((
      line,
    ) {
      final trimmed = line.trim();
      return trimmed != '[Settings]' &&
          trimmed != _gtkManagedMarker &&
          !_gtkManagedKeys.any(trimmed.startsWith);
    });
    if (clearing && !hasUserContent) {
      // Nothing user-authored ever lived here: an absent file stays absent
      // instead of leaving a stub behind.
      return const _GtkIniEdit(contents: '', deleteFile: true);
    }
    if (contents == (existing ?? '')) {
      return null;
    }
    return _GtkIniEdit(contents: contents, deleteFile: false);
  }

  Future<void> _gsettings(String key, String? value) async {
    try {
      // gsettings resets when the selection is empty instead of setting a
      // blank value, which would not restore the distribution default.
      if (value == null) {
        await Process.run('gsettings', [
          'reset',
          'org.gnome.desktop.interface',
          key,
        ]).timeout(_gsettingsTimeout);
      } else {
        await Process.run('gsettings', [
          'set',
          'org.gnome.desktop.interface',
          key,
          value,
        ]).timeout(_gsettingsTimeout);
      }
    } on Object {
      // gsettings is optional on systems without a GNOME-style stack; the
      // timeout folds a wedged dconf into the same failure path.
    }
  }

  Future<void> _deleteIfExists(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } on Object {
      // Best effort cleanup.
    }
  }

  Future<void> _writeIfChanged(File file, String contents) async {
    try {
      if (await file.exists() && await file.readAsString() == contents) {
        return;
      }
      await file.parent.create(recursive: true);
      await file.writeAsString(contents);
    } on Object {
      // A read-only home or missing XDG directories should not surface as a
      // shell failure.
    }
  }
}

class _GtkIniEdit {
  const _GtkIniEdit({required this.contents, required this.deleteFile});

  final String contents;
  final bool deleteFile;
}

/// Escapes a font family name for embedding in generated fontconfig XML.
String _escapeXml(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;')
      .replaceAll('\n', '&#10;')
      .replaceAll('\r', '&#13;');
}

/// Escapes a value for a GKeyFile `key = value` line. Newlines and
/// backslashes would otherwise break the line structure.
String _escapeIniValue(String value) {
  return value.replaceAll('\\', '\\\\').replaceAll('\n', '\\n');
}
