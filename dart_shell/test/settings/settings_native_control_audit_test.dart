import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// T25 — the settings surface must not paint native Material controls.
///
/// The Settings control family (`settings_controls.dart` /
/// `settings_buttons.dart`) replaces every stock Material widget the reference
/// photo does not allow. This audit scans `lib/src/settings/**` sources so a
/// reintroduced `ListTile`, `FilledButton`, outlined text field, or progress
/// indicator fails the suite instead of slipping through review.
///
/// Deliberate exemptions:
///
/// * A raw `TextField`/`TextFormField` is allowed only as the borderless inner
///   editor inside a custom-painted control: `SettingsTextField`
///   (settings_controls.dart), the search capsule (settings_search_bar.dart),
///   and the inline display-scale editor (settings_displays_page.dart). Each
///   keeps `InputBorder.none`; `OutlineInputBorder` is banned outright.
/// * `Material(` remains permitted for non-painting hosts: the
///   `MaterialType.transparency` overlay shim in the anchored menu and the
///   root surface of the Settings application.
void main() {
  final banned = <String, RegExp>{
    'ListTile': RegExp(r'\bListTile\('),
    'Divider': RegExp(r'(?<![A-Za-z])Divider\('),
    'SegmentedButton': RegExp(r'(?<![A-Za-z])SegmentedButton\('),
    'CircularProgressIndicator': RegExp(r'\bCircularProgressIndicator\('),
    'LinearProgressIndicator': RegExp(r'\bLinearProgressIndicator\('),
    'FilledButton': RegExp(r'(?<![A-Za-z])FilledButton\('),
    'OutlinedButton': RegExp(r'(?<![A-Za-z])OutlinedButton\('),
    'ElevatedButton': RegExp(r'(?<![A-Za-z])ElevatedButton\('),
    'IconButton': RegExp(r'(?<![A-Za-z])IconButton\('),
    'OutlineInputBorder': RegExp(r'\bOutlineInputBorder\('),
    'TextField/TextFormField': RegExp(r'(?<![A-Za-z])TextFormField\(|(?<![A-Za-z])TextField\('),
  };

  /// Files where a borderless inner `TextField`/`TextFormField` is part of a
  /// custom-painted control rather than an ad-hoc Material field.
  const innerFieldExemptions = <String>{
    'settings_controls.dart',
    'settings_search_bar.dart',
    'settings_displays_page.dart',
  };

  test('settings sources contain no native Material controls', () {
    final settingsDir = Directory('lib/src/settings');
    expect(settingsDir.existsSync(), isTrue);

    final violations = <String>[];
    for (final entity in settingsDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final fileName = entity.uri.pathSegments.last;
      final source = entity.readAsStringSync();
      banned.forEach((name, pattern) {
        if (name == 'TextField/TextFormField' &&
            innerFieldExemptions.contains(fileName)) {
          return;
        }
        for (final match in pattern.allMatches(source)) {
          final line = '\n'.allMatches(source.substring(0, match.start)).length +
              1;
          violations.add('${entity.path}:$line uses $name');
        }
      });
    }

    expect(violations, isEmpty, reason: violations.join('\n'));
  });
}
