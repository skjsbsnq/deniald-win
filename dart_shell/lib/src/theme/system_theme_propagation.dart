import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../settings/shell_settings.dart';

/// Mirrors the shell's font and icon theme choices into system-level
/// configuration so GTK, Qt, and fontconfig clients follow along.
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

  Future<void> apply(ShellAppearanceSettings appearance) async {
    await Future.wait<void>([
      _applyFontConfig(appearance.uiFontFamily),
      _applyGsettings(appearance),
      _applyGtkSettingsIni(appearance),
    ]);
  }

  Future<void> _applyFontConfig(String uiFontFamily) async {
    final directory = Directory(p.join(_configHome, 'fontconfig'));
    final file = File(p.join(directory.path, 'fonts.conf'));
    if (uiFontFamily.isEmpty) {
      await _deleteIfExists(file);
      return;
    }
    final cjk = 'Source Han Sans CN';
    // Prepending the selected family to both generic aliases makes it the
    // effective default for every fontconfig client, not just monospace.
    await _writeIfChanged(
      file,
      '<?xml version="1.0"?>\n'
      '<!DOCTYPE fontconfig SYSTEM "fonts.dtd">\n'
      '<fontconfig>\n'
      '  <alias><family>sans-serif</family><prefer>\n'
      '    <family>$uiFontFamily</family>\n'
      '    <family>$cjk</family>\n'
      '  </prefer></alias>\n'
      '  <alias><family>monospace</family><prefer>\n'
      '    <family>$uiFontFamily</family>\n'
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
    for (final gtkVersion in const ['gtk-3.0', 'gtk-4.0']) {
      final directory = Directory(p.join(_configHome, gtkVersion));
      final file = File(p.join(directory.path, 'settings.ini'));
      if (appearance.uiFontFamily.isEmpty && appearance.iconThemeName.isEmpty) {
        await _deleteIfExists(file);
        continue;
      }
      await _writeIfChanged(
        file,
        '[Settings]\n'
        'gtk-font-name = ${appearance.uiFontFamily.isEmpty ? 'Sans 11' : '${appearance.uiFontFamily} 11'}\n'
        'gtk-icon-theme-name = ${appearance.iconThemeName.isEmpty ? 'Adwaita' : appearance.iconThemeName}\n',
      );
    }
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
        ]);
      } else {
        await Process.run('gsettings', [
          'set',
          'org.gnome.desktop.interface',
          key,
          value,
        ]);
      }
    } on Object {
      // gsettings is optional on systems without a GNOME-style stack.
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
