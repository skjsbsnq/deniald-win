import 'package:denial_dart_shell/src/theme/shell_color_scheme.dart';
import 'package:denial_dart_shell/src/theme/shell_text_theme.dart';
import 'package:denial_dart_shell/src/theme/shell_theme.dart';
import 'package:denial_dart_shell/src/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ShellSpacing', () {
    test('matches the M3E spacing ramp (spec §4)', () {
      expect(ShellSpacing.xs, 4);
      expect(ShellSpacing.sm, 8);
      expect(ShellSpacing.md, 12);
      expect(ShellSpacing.lg, 16);
      expect(ShellSpacing.xl, 24);
      expect(ShellSpacing.xxl, 32);
    });
  });

  group('ShellElevation', () {
    test('declares tonal levels 0 through 3 without shadow values', () {
      expect(ShellElevation.level0, 0);
      expect(ShellElevation.level1, 1);
      expect(ShellElevation.level2, 2);
      expect(ShellElevation.level3, 3);
      expect(
        ShellElevation.level0,
        lessThan(ShellElevation.level1),
      );
      expect(
        ShellElevation.level1,
        lessThan(ShellElevation.level2),
      );
      expect(
        ShellElevation.level2,
        lessThan(ShellElevation.level3),
      );
    });
  });

  group('M3E typescale prototypes', () {
    // (role name, style, expected sp size). A list, not a TextStyle-keyed map:
    // titleSmall and labelLarge share identical metrics (14sp/w500/20:14) and
    // would collapse into one map entry.
    const List<(String, TextStyle, double)> scale =
        <(String, TextStyle, double)>[
          ('displayLarge', ShellText.displayLarge, 57),
          ('displayMedium', ShellText.displayMedium, 45),
          ('displaySmall', ShellText.displaySmall, 36),
          ('headlineLarge', ShellText.headlineLarge, 32),
          ('headlineMedium', ShellText.headlineMedium, 28),
          ('headlineSmall', ShellText.headlineSmall, 24),
          ('titleLarge', ShellText.titleLarge, 22),
          ('titleMedium', ShellText.titleMedium, 16),
          ('titleSmall', ShellText.titleSmall, 14),
          ('bodyLarge', ShellText.bodyLarge, 16),
          ('bodyMedium', ShellText.bodyMedium, 14),
          ('bodySmall', ShellText.bodySmall, 12),
          ('labelLarge', ShellText.labelLarge, 14),
          ('labelMedium', ShellText.labelMedium, 12),
          ('labelSmall', ShellText.labelSmall, 11),
        ];

    test('all fifteen roles match the spec §3 size table', () {
      expect(scale, hasLength(15));
      for (final (String name, TextStyle style, double size) in scale) {
        expect(style.fontSize, size, reason: name);
        expect(style.fontSize! % 1, 0, reason: 'integer sp only (§D5)');
        expect(style.letterSpacing, 0, reason: '§D5');
        expect(style.fontFamilyFallback, ShellText.fallbackFontFamilies);
      }
    });

    test('emphasized variants reuse the size at w600', () {
      const List<(String, TextStyle, TextStyle)> emphasized =
          <(String, TextStyle, TextStyle)>[
            ('displayLarge', ShellText.displayLarge,
                ShellText.displayLargeEmphasized),
            ('displayMedium', ShellText.displayMedium,
                ShellText.displayMediumEmphasized),
            ('displaySmall', ShellText.displaySmall,
                ShellText.displaySmallEmphasized),
            ('headlineLarge', ShellText.headlineLarge,
                ShellText.headlineLargeEmphasized),
            ('headlineMedium', ShellText.headlineMedium,
                ShellText.headlineMediumEmphasized),
            ('headlineSmall', ShellText.headlineSmall,
                ShellText.headlineSmallEmphasized),
            ('titleLarge', ShellText.titleLarge,
                ShellText.titleLargeEmphasized),
            ('titleMedium', ShellText.titleMedium,
                ShellText.titleMediumEmphasized),
            ('titleSmall', ShellText.titleSmall,
                ShellText.titleSmallEmphasized),
            ('bodyLarge', ShellText.bodyLarge, ShellText.bodyLargeEmphasized),
            ('bodyMedium', ShellText.bodyMedium,
                ShellText.bodyMediumEmphasized),
            ('bodySmall', ShellText.bodySmall, ShellText.bodySmallEmphasized),
            ('labelLarge', ShellText.labelLarge,
                ShellText.labelLargeEmphasized),
            ('labelMedium', ShellText.labelMedium,
                ShellText.labelMediumEmphasized),
            ('labelSmall', ShellText.labelSmall,
                ShellText.labelSmallEmphasized),
          ];
      expect(emphasized, hasLength(15));
      for (final (String name, TextStyle plain, TextStyle heavy) in emphasized) {
        expect(heavy.fontSize, plain.fontSize, reason: name);
        expect(heavy.height, plain.height, reason: name);
        expect(heavy.fontWeight, FontWeight.w600, reason: name);
        expect(heavy.letterSpacing, 0, reason: name);
      }
    });
  });

  group('ShellTextTheme typescale roles', () {
    test('resolve the shell foreground and the configured family', () {
      const ShellColorScheme colors = ShellColorScheme.dark;
      final ShellTextTheme text = ShellTextTheme.from(
        colors,
        fontFamily: 'Test Family',
      );
      expect(text.displayLarge.fontSize, 57);
      expect(text.labelSmall.fontSize, 11);
      expect(text.displayLarge.color, colors.textPrimary);
      expect(text.labelSmallEmphasized.color, colors.textPrimary);
      expect(text.bodyMedium.fontFamily, 'Test Family');
      expect(text.displayLargeEmphasized.fontWeight, FontWeight.w600);
      expect(text.displayLargeEmphasized.fontFamily, 'Test Family');
    });

    test('lerp blends every new role (D9)', () {
      final ShellTextTheme dark = ShellTextTheme.from(ShellColorScheme.dark);
      final ShellTextTheme light = ShellTextTheme.from(ShellColorScheme.light);
      final ShellTextTheme mid = ShellTextTheme.lerp(dark, light, 0.5);

      expect(mid.displayLarge.fontSize, 57);
      expect(mid.labelSmall.fontSize, 11);
      expect(mid.displayLargeEmphasized.fontWeight, FontWeight.w600);
      expect(
        mid.displayLarge.color,
        Color.lerp(dark.displayLarge.color, light.displayLarge.color, 0.5),
      );
      expect(
        mid.bodyMediumEmphasized.color,
        Color.lerp(
          dark.bodyMediumEmphasized.color,
          light.bodyMediumEmphasized.color,
          0.5,
        ),
      );
      expect(
        mid.labelSmallEmphasized.color,
        Color.lerp(
          dark.labelSmallEmphasized.color,
          light.labelSmallEmphasized.color,
          0.5,
        ),
      );
      // Endpoint styles pass through unchanged.
      expect(
        ShellTextTheme.lerp(dark, light, 0).displayLarge.color,
        dark.displayLarge.color,
      );
      expect(
        ShellTextTheme.lerp(dark, light, 1).displayLarge.color,
        light.displayLarge.color,
      );
    });
  });

  group('materialTheme textTheme mount', () {
    test('maps the fifteen baseline roles onto TextTheme slots', () {
      // fontFamily is set explicitly: with a null family the mounted styles
      // leave `fontFamily` null and ThemeData's merge over the platform
      // default resolves 'Roboto' — comparing a concrete family keeps the
      // assertion deterministic on both sides.
      const ShellThemeData theme = ShellThemeData(fontFamily: 'Test Family');
      final ThemeData material = theme.toMaterialTheme();
      final ShellTextTheme text = theme.text;
      final TextTheme mounted = material.textTheme;

      // ThemeData merges the mounted theme over the platform default, so the
      // resolved styles carry default fields (debugLabel, textBaseline, …);
      // assert the token-controlled fields instead of object identity.
      final Map<TextStyle?, TextStyle> slots = <TextStyle?, TextStyle>{
        mounted.displayLarge: text.displayLarge,
        mounted.displayMedium: text.displayMedium,
        mounted.displaySmall: text.displaySmall,
        mounted.headlineLarge: text.headlineLarge,
        mounted.headlineMedium: text.headlineMedium,
        mounted.headlineSmall: text.headlineSmall,
        mounted.titleLarge: text.titleLarge,
        mounted.titleMedium: text.titleMedium,
        mounted.titleSmall: text.titleSmall,
        mounted.bodyLarge: text.bodyLarge,
        mounted.bodyMedium: text.bodyMedium,
        mounted.bodySmall: text.bodySmall,
        mounted.labelLarge: text.labelLarge,
        mounted.labelMedium: text.labelMedium,
        mounted.labelSmall: text.labelSmall,
      };
      for (final MapEntry<TextStyle?, TextStyle> entry in slots.entries) {
        final TextStyle resolved = entry.key!;
        final TextStyle expected = entry.value;
        expect(resolved.fontSize, expected.fontSize);
        expect(resolved.fontWeight, expected.fontWeight);
        expect(resolved.height, expected.height);
        expect(resolved.letterSpacing, expected.letterSpacing);
        expect(resolved.color, expected.color);
        expect(resolved.fontFamily, expected.fontFamily);
        expect(resolved.fontFamilyFallback, expected.fontFamilyFallback);
        expect(resolved.decoration, expected.decoration);
      }
    });

    test('mounted roles keep integer sizes and zero tracking', () {
      final TextTheme mounted = const ShellThemeData().toMaterialTheme().textTheme;
      expect(mounted.displayLarge!.fontSize, 57);
      expect(mounted.headlineMedium!.fontSize, 28);
      expect(mounted.bodyMedium!.fontSize, 14);
      expect(mounted.labelSmall!.fontSize, 11);
      for (final TextStyle? style in <TextStyle?>[
        mounted.displayLarge,
        mounted.headlineSmall,
        mounted.titleMedium,
        mounted.bodySmall,
        mounted.labelLarge,
      ]) {
        expect(style!.letterSpacing, 0);
        expect(style.color, const ShellThemeData().colors.textPrimary);
        expect(style.fontFamilyFallback, ShellText.fallbackFontFamilies);
      }
    });
  });
}
