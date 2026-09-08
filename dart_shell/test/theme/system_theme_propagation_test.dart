import 'dart:io';

import 'package:denial_dart_shell/src/settings/shell_settings.dart';
import 'package:denial_dart_shell/src/theme/system_theme_propagation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  // Every test runs against a throwaway HOME so user config is never
  // touched (constraint H1).
  late Directory home;
  late SystemThemePropagation propagation;

  setUp(() {
    home = Directory.systemTemp.createTempSync('denial-theme-propagation');
    propagation = SystemThemePropagation(homeDirectory: home.path);
  });

  tearDown(() {
    home.deleteSync(recursive: true);
  });

  File fontconfigFragment() =>
      File(p.join(home.path, '.config/fontconfig/conf.d/60-denial.conf'));

  File gtkIni(String version) =>
      File(p.join(home.path, '.config/$version/settings.ini'));

  const applyFont = ShellAppearanceSettings(uiFontFamily: 'Inter');

  Future<void> writeIfExists(String path, String contents) async {
    final file = File(p.join(home.path, path));
    await file.parent.create(recursive: true);
    await file.writeAsString(contents);
  }

  test('a fresh home gets fragments, never user top-level files', () async {
    await propagation.apply(applyFont);

    expect(fontconfigFragment().existsSync(), isTrue);
    expect(
      File(p.join(home.path, '.config/fontconfig/fonts.conf')).existsSync(),
      isFalse,
    );
    final gtk = await gtkIni('gtk-3.0').readAsString();
    expect(
      gtk,
      '[Settings]\n'
      '# Managed by the Denial shell.\n'
      'gtk-font-name = Inter 11\n'
      'gtk-icon-theme-name = Adwaita\n',
    );
    expect(
      await gtkIni('gtk-4.0').readAsString(),
      gtk,
      reason: 'both GTK generations carry the same managed keys',
    );
  });

  test('user-authored fonts.conf and settings.ini are preserved byte for '
      'byte', () async {
    const userFontsConf =
        '<?xml version="1.0"?>\n'
        '<!DOCTYPE fontconfig SYSTEM "fonts.dtd">\n'
        '<fontconfig>\n'
        '  <match target="pattern">\n'
        '    <test name="family"><string>Arial</string></test>\n'
        '    <edit name="family" mode="assign" binding="strong">\n'
        '      <string>Liberation Sans</string>\n'
        '    </edit>\n'
        '  </match>\n'
        '</fontconfig>\n';
    const userGtkIni =
        '[Settings]\n'
        'gtk-application-prefer-dark-theme=1\n'
        'gtk-enable-animations=0\n';
    await writeIfExists('.config/fontconfig/fonts.conf', userFontsConf);
    await writeIfExists('.config/gtk-3.0/settings.ini', userGtkIni);
    await writeIfExists('.config/gtk-4.0/settings.ini', userGtkIni);

    await propagation.apply(
      const ShellAppearanceSettings(
        uiFontFamily: 'Inter',
        iconThemeName: 'Papirus',
      ),
    );

    // The user files are untouched byte for byte; the shell keys live in
    // their own places.
    expect(
      await File(
        p.join(home.path, '.config/fontconfig/fonts.conf'),
      ).readAsString(),
      userFontsConf,
    );
    final gtk3 = await gtkIni('gtk-3.0').readAsString();
    expect(gtk3, contains('gtk-application-prefer-dark-theme=1\n'));
    expect(gtk3, contains('gtk-enable-animations=0\n'));
    expect(gtk3, contains('gtk-font-name = Inter 11\n'));
    expect(gtk3, contains('gtk-icon-theme-name = Papirus\n'));
    expect(gtk3, contains('# Managed by the Denial shell.\n'));
    // User keys keep their position ahead of the managed block.
    expect(
      gtk3.indexOf('gtk-application-prefer-dark-theme') <
          gtk3.indexOf('# Managed by the Denial shell.'),
      isTrue,
    );
    expect(fontconfigFragment().existsSync(), isTrue);
  });

  test('shell-owned legacy whole files migrate to the new layout', () async {
    const legacyFontsConf =
        '<?xml version="1.0"?>\n'
        '<!DOCTYPE fontconfig SYSTEM "fonts.dtd">\n'
        '<fontconfig>\n'
        '  <alias><family>sans-serif</family><prefer>\n'
        '    <family>Inter</family>\n'
        '    <family>Source Han Sans CN</family>\n'
        '  </prefer></alias>\n'
        '  <alias><family>monospace</family><prefer>\n'
        '    <family>Inter</family>\n'
        '    <family>Source Han Sans CN</family>\n'
        '  </prefer></alias>\n'
        '</fontconfig>\n';
    const legacyGtkIni =
        '[Settings]\n'
        'gtk-font-name = Inter 11\n'
        'gtk-icon-theme-name = Adwaita\n';
    await writeIfExists('.config/fontconfig/fonts.conf', legacyFontsConf);
    await writeIfExists('.config/gtk-3.0/settings.ini', legacyGtkIni);
    await writeIfExists('.config/gtk-4.0/settings.ini', legacyGtkIni);

    await propagation.apply(applyFont);

    // The shell-authored master file is replaced by the equivalent fragment.
    expect(
      File(p.join(home.path, '.config/fontconfig/fonts.conf')).existsSync(),
      isFalse,
    );
    expect(
      await fontconfigFragment().readAsString(),
      legacyFontsConf,
      reason: 'the fragment is byte-identical to the migrated legacy file',
    );
    // The legacy whole-file INI keeps only the managed block; the key set
    // and values are equivalent to the legacy output.
    final gtk3 = await gtkIni('gtk-3.0').readAsString();
    expect(
      gtk3,
      '[Settings]\n'
      '# Managed by the Denial shell.\n'
      'gtk-font-name = Inter 11\n'
      'gtk-icon-theme-name = Adwaita\n',
    );
  });

  test('a legacy fonts.conf carrying user content beyond the shell layout is '
      'kept, not migrated', () async {
    const userFontsConf =
        '<?xml version="1.0"?>\n'
        '<!DOCTYPE fontconfig SYSTEM "fonts.dtd">\n'
        '<fontconfig>\n'
        '  <alias><family>sans-serif</family><prefer>\n'
        '    <family>Inter</family>\n'
        '    <family>Source Han Sans CN</family>\n'
        '  </prefer></alias>\n'
        '  <!-- hand-tuned hinting -->\n'
        '  <match target="font">\n'
        '    <edit name="hintstyle" mode="assign">\n'
        '      <const>hintslight</const>\n'
        '    </edit>\n'
        '  </match>\n'
        '</fontconfig>\n';
    await writeIfExists('.config/fontconfig/fonts.conf', userFontsConf);

    await propagation.apply(applyFont);

    expect(
      await File(
        p.join(home.path, '.config/fontconfig/fonts.conf'),
      ).readAsString(),
      userFontsConf,
    );
    expect(fontconfigFragment().existsSync(), isTrue);
  });

  test('clearing the selection removes fragments and managed keys but keeps '
      'user content', () async {
    const userGtkIni =
        '[Settings]\n'
        'gtk-application-prefer-dark-theme=1\n'
        'gtk-theme-name = Adwaita-dark\n';
    await writeIfExists('.config/gtk-3.0/settings.ini', userGtkIni);
    await writeIfExists('.config/gtk-4.0/settings.ini', userGtkIni);

    await propagation.apply(
      const ShellAppearanceSettings(uiFontFamily: 'Inter'),
    );
    await propagation.apply(const ShellAppearanceSettings());

    expect(fontconfigFragment().existsSync(), isFalse);
    expect(
      File(p.join(home.path, '.config/fontconfig/fonts.conf')).existsSync(),
      isFalse,
    );
    expect(await gtkIni('gtk-3.0').readAsString(), userGtkIni);
    expect(await gtkIni('gtk-4.0').readAsString(), userGtkIni);
  });

  test('clearing from a shell-only file removes the file entirely', () async {
    await propagation.apply(applyFont);
    expect(gtkIni('gtk-3.0').existsSync(), isTrue);

    await propagation.apply(const ShellAppearanceSettings());

    expect(fontconfigFragment().existsSync(), isFalse);
    expect(gtkIni('gtk-3.0').existsSync(), isFalse);
    expect(gtkIni('gtk-4.0').existsSync(), isFalse);
  });

  test(
    'font families needing escapes generate well-formed XML and INI',
    () async {
      await propagation.apply(
        const ShellAppearanceSettings(
          uiFontFamily: 'A&B<C>"D\'E\nF',
          iconThemeName: 'Icons\\Theme',
        ),
      );

      // The fontconfig fragment escapes all XML-special characters and the
      // embedded newline round-trips as a character reference.
      final fragment = await fontconfigFragment().readAsString();
      expect(
        fragment,
        contains('<family>A&amp;B&lt;C&gt;&quot;D&apos;E&#10;F</family>'),
      );
      expect(fragment, isNot(contains('<family>A&B')));
      expect(fragment, startsWith('<?xml version="1.0"?>'));
      expect(fragment, endsWith('</fontconfig>\n'));

      // The INI value keeps one physical line per key; the newline becomes an
      // escape sequence and the icon theme's backslash is doubled.
      final gtk = await gtkIni('gtk-3.0').readAsString();
      final lines = gtk.split('\n');
      expect(
        lines.where((line) => line.startsWith('gtk-font-name = ')).single,
        'gtk-font-name = A&B<C>"D\'E\\nF 11',
      );
      expect(
        lines.where((line) => line.startsWith('gtk-icon-theme-name = ')).single,
        'gtk-icon-theme-name = Icons\\\\Theme',
      );
    },
  );

  test('re-applying the same selection is a no-op write', () async {
    await propagation.apply(applyFont);
    final fragmentBefore = await fontconfigFragment().lastModified();
    final gtkBefore = await gtkIni('gtk-3.0').readAsString();

    await propagation.apply(applyFont);

    expect(await fontconfigFragment().lastModified(), fragmentBefore);
    expect(await gtkIni('gtk-3.0').readAsString(), gtkBefore);
  });

  test(
    'a user settings.ini without a [Settings] group appends the group',
    () async {
      const userIni = '# notes\n';
      await writeIfExists('.config/gtk-3.0/settings.ini', userIni);

      await propagation.apply(applyFont);

      final gtk = await gtkIni('gtk-3.0').readAsString();
      expect(gtk, startsWith('# notes\n'));
      expect(gtk, contains('[Settings]\n# Managed by the Denial shell.\n'));
      expect(gtk, contains('gtk-font-name = Inter 11\n'));
    },
  );
}
