import 'dart:typed_data';

import 'package:denial_dart_shell/src/settings/settings_category_colors.dart';
import 'package:denial_dart_shell/src/settings/widgets/settings_navigation.dart';
import 'package:denial_dart_shell/src/theme/shell_color_scheme.dart';
import 'package:denial_dart_shell/src/theme/shell_theme.dart';
import 'package:denial_dart_shell/src/wallpaper/state/wallpaper_accent.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_color_utilities/material_color_utilities.dart'
    show Variant;

void main() {
  ByteData solidRgba(int r, int g, int b, {int pixelCount = 256}) {
    final data = ByteData(pixelCount * 4);
    for (var i = 0; i < pixelCount; i += 1) {
      data.setUint8(i * 4, r);
      data.setUint8(i * 4 + 1, g);
      data.setUint8(i * 4 + 2, b);
      data.setUint8(i * 4 + 3, 0xff);
    }
    return data;
  }

  ByteData noisyRgba({int pixelCount = 4096}) {
    // A checkerboard of saturated blue and warm gray keeps a clear dominant
    // hue while exercising Celebi clustering instead of a trivial path.
    final data = ByteData(pixelCount * 4);
    for (var i = 0; i < pixelCount; i += 1) {
      final vivid = i % 4 != 0;
      data.setUint8(i * 4, vivid ? 40 : 120);
      data.setUint8(i * 4 + 1, vivid ? 90 : 118);
      data.setUint8(i * 4 + 2, vivid ? 220 : 116);
      data.setUint8(i * 4 + 3, 0xff);
    }
    return data;
  }

  test('wallpaper extraction picks the dominant chromatic seed', () async {
    final seed = await dominantVibrantColor(noisyRgba());
    expect(seed, isNotNull);
    expect(seed!.b, greaterThan(seed.r));
    expect(seed.b, greaterThan(seed.g));
  });

  test('grayscale wallpapers fall back to the brand accent', () async {
    expect(await dominantVibrantColor(solidRgba(128, 128, 128)), isNull);
    expect(await dominantVibrantColor(solidRgba(20, 20, 20)), isNull);
    expect(await dominantVibrantColor(ByteData(0)), isNull);
  });

  test('scheme generation is deterministic for a seed/brightness/contrast '
      'triple', () {
    const seed = Color(0xff336699);
    final first = shellDynamicScheme(seed, brightness: Brightness.dark);
    final second = shellDynamicScheme(seed, brightness: Brightness.dark);
    expect(identical(first, second), isTrue);
    expect(first.variant, Variant.expressive);

    final dark = const ShellThemeData(accent: seed);
    final darkAgain = const ShellThemeData(accent: seed);
    expect(dark.colors, darkAgain.colors);
    expect(dark.accentPalette, darkAgain.accentPalette);
    expect(
      dark.colors.surfaceContainer,
      isNot(ShellColorScheme.dark.surfaceContainer),
      reason: 'surfaces must follow the seed, not the fixed neutral stack',
    );
  });

  test('different seeds produce different surface and accent roles', () {
    const blue = Color(0xff336699);
    const orange = Color(0xffb34700);
    final blueTheme = const ShellThemeData(accent: blue);
    final orangeTheme = const ShellThemeData(accent: orange);
    expect(
      blueTheme.colors.surfaceContainer,
      isNot(orangeTheme.colors.surfaceContainer),
    );
    expect(
      blueTheme.accentPalette.primary,
      isNot(orangeTheme.accentPalette.primary),
    );
    expect(
      blueTheme.accentPalette.tertiary,
      isNot(orangeTheme.accentPalette.tertiary),
    );
  });

  test('the error family is static and seed-independent', () {
    final first = ShellAccentPalette.from(
      const Color(0xff336699),
    );
    final second = ShellAccentPalette.from(
      const Color(0xff2e7d32),
    );
    expect(first.error, second.error);
    expect(first.errorContainer, second.errorContainer);
    expect(first.onError, second.onError);
    expect(first.error, isNot(first.primary));
  });

  test('contrastLevel participates in scheme construction', () {
    const seed = Color(0xff336699);
    final standard = const ShellThemeData(accent: seed);
    final raised = const ShellThemeData(accent: seed, contrastLevel: 1);
    expect(
      standard.colors.surfaceContainer,
      isNot(raised.colors.surfaceContainer),
    );
    expect(standard == raised, isFalse);
    expect(standard.hashCode == raised.hashCode, isFalse);
  });

  test('settings category hues and the shell accent share the expressive '
      'variant', () {
    const seed = Color(0xff7c3aed);
    final scheme = shellDynamicScheme(seed, brightness: Brightness.dark);
    final category = SettingsCategoryColors.seeds[SettingsPageId.audio]!;
    final categoryScheme = shellDynamicScheme(
      category,
      brightness: Brightness.dark,
    );
    expect(scheme.variant, Variant.expressive);
    expect(categoryScheme.variant, Variant.expressive);
    // The category pipeline resolves through the same cached helper, so the
    // same (seed, brightness) pair returns the identical scheme instance.
    expect(
      identical(
        categoryScheme,
        shellDynamicScheme(category, brightness: Brightness.dark),
      ),
      isTrue,
    );
  });

  test('light/dark and accent lerp midpoint is a sane interpolated scheme', () {
    const seedA = Color(0xff336699);
    const seedB = Color(0xffb34700);
    const darkA = ShellThemeData(accent: seedA);
    const lightB = ShellThemeData(
      colors: ShellColorScheme.light,
      accent: seedB,
    );

    final mid = ShellThemeData.lerp(darkA, lightB, 0.5);
    expect(mid.brightness, Brightness.light, reason: 'brightness snaps at 0.5');
    expect(
      mid.colors.surfaceContainer,
      Color.lerp(
        darkA.colors.surfaceContainer,
        lightB.colors.surfaceContainer,
        0.5,
      ),
    );
    expect(
      mid.colors.outlineVariant,
      Color.lerp(
        darkA.colors.outlineVariant,
        lightB.colors.outlineVariant,
        0.5,
      ),
    );
    expect(
      mid.accentPalette.secondaryContainer,
      Color.lerp(
        darkA.accentPalette.secondaryContainer,
        lightB.accentPalette.secondaryContainer,
        0.5,
      ),
    );
    expect(mid.accentSeed, Color.lerp(seedA, seedB, 0.5));
    expect(mid.contrastLevel, 0);
    // The midpoint must not be a passthrough of either endpoint.
    expect(mid.colors.surfaceContainer, isNot(darkA.colors.surfaceContainer));
    expect(mid.colors.surfaceContainer, isNot(lightB.colors.surfaceContainer));
  });

  test('lerp endpoints and short-circuits stay stable', () {
    const seedA = Color(0xff336699);
    const seedB = Color(0xffb34700);
    const a = ShellThemeData(accent: seedA);
    const b = ShellThemeData(accent: seedB);
    expect(identical(ShellThemeData.lerp(a, b, 0), a), isTrue);
    expect(identical(ShellThemeData.lerp(a, b, 1), b), isTrue);
    final mid = ShellThemeData.lerp(a, b, 0.5);
    expect(mid.colors.surfaceContainer.a, inInclusiveRange(0.9, 1.0));
    expect(mid.accentPalette.error, a.accentPalette.error);
  });

  test('the default brand seed still yields a complete tonal stack', () {
    const theme = ShellThemeData();
    final colors = theme.colors;
    expect(colors.textPrimary.a, 1);
    expect(colors.outline.a, 1);
    expect(colors.inverseSurface, isNot(colors.surfaceDim));
    final palette = theme.accentPalette;
    expect(palette.secondaryContainer.a, 1);
    expect(palette.tertiaryContainer.a, 1);
    expect(palette.errorContainer.a, 1);
    // Ordering sanity for the five surface tiers in dark mode.
    double tone(Color c) => (c.r + c.g + c.b) / 3;
    expect(tone(colors.surfaceContainerLowest), lessThan(tone(colors.surfaceContainerHigh)));
    expect(tone(colors.surfaceContainerHigh), lessThan(tone(colors.inverseSurface)));
  });
}
