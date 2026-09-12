import 'package:denial_dart_shell/src/settings/settings_category_colors.dart';
import 'package:denial_dart_shell/src/settings/widgets/settings_navigation.dart';
import 'package:denial_dart_shell/src/theme/shell_color_scheme.dart';
import 'package:denial_dart_shell/src/theme/shell_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('every page resolves a container and foreground pair', (
    tester,
  ) async {
    final resolved = await _withTheme(tester, ShellColorScheme.dark, (context) {
      return <SettingsPageId, SettingsCategoryHue>{
        for (final page in SettingsPageId.values)
          page: SettingsCategoryColors.of(context, page),
      };
    });

    expect(resolved.length, SettingsPageId.values.length);
    for (final page in SettingsPageId.values) {
      final hue = resolved[page]!;
      expect(hue.container.a, greaterThan(0), reason: '${page.name} container');
      expect(
        hue.onContainer.a,
        greaterThan(0),
        reason: '${page.name} foreground',
      );
    }
  });

  testWidgets('about stays neutral instead of claiming a hue', (tester) async {
    final hue = await _withTheme(
      tester,
      ShellColorScheme.dark,
      (context) => SettingsCategoryColors.of(context, SettingsPageId.about),
    );

    expect(
      SettingsCategoryColors.seeds.containsKey(SettingsPageId.about),
      isFalse,
    );
    // The neutral pair borrows the resolved (seed-derived) surface roles, so
    // compare against the theme's effective scheme rather than the const base.
    final resolved = const ShellThemeData(
      colors: ShellColorScheme.dark,
    ).colors;
    expect(hue.container, resolved.surfaceContainerHigh);
    expect(hue.onContainer, resolved.textSecondary);
  });

  testWidgets('the seed table matches the verified spec hues', (tester) async {
    expect(SettingsCategoryColors.seeds, <SettingsPageId, Color>{
      SettingsPageId.network: const Color(0xff0097a7),
      SettingsPageId.bluetooth: const Color(0xff2563eb),
      SettingsPageId.displays: const Color(0xff4f46e5),
      SettingsPageId.audio: const Color(0xff7c3aed),
      SettingsPageId.appearance: const Color(0xffdb2777),
      SettingsPageId.animations: const Color(0xffe11d48),
      SettingsPageId.lockScreen: const Color(0xffdc2626),
      SettingsPageId.layout: const Color(0xff1d4ed8),
      SettingsPageId.overlays: const Color(0xff0284c7),
      SettingsPageId.weather: const Color(0xffea580c),
      SettingsPageId.power: const Color(0xffd97706),
      SettingsPageId.keyboard: const Color(0xff16a34a),
      SettingsPageId.touchpad: const Color(0xff0d9488),
      SettingsPageId.shortcuts: const Color(0xff059669),
      SettingsPageId.language: const Color(0xffb45309),
      SettingsPageId.environment: const Color(0xff475569),
      SettingsPageId.developer: const Color(0xff0f766e),
    });
  });

  testWidgets('derived hues are cached per seed and brightness', (
    tester,
  ) async {
    final first = await _withTheme(
      tester,
      ShellColorScheme.dark,
      (context) => SettingsCategoryColors.of(context, SettingsPageId.audio),
    );
    final second = await _withTheme(
      tester,
      ShellColorScheme.dark,
      (context) => SettingsCategoryColors.of(context, SettingsPageId.audio),
    );

    expect(identical(first, second), isTrue);
    expect(identical(first.container, second.container), isTrue);
    expect(identical(first.onContainer, second.onContainer), isTrue);
  });

  testWidgets('light and dark brightnesses keep separate derived hues', (
    tester,
  ) async {
    final dark = await _withTheme(
      tester,
      ShellColorScheme.dark,
      (context) => SettingsCategoryColors.of(context, SettingsPageId.audio),
    );
    final light = await _withTheme(
      tester,
      ShellColorScheme.light,
      (context) => SettingsCategoryColors.of(context, SettingsPageId.audio),
    );

    expect(identical(dark, light), isFalse);
    expect(dark.container, isNot(light.container));
    expect(dark.onContainer, isNot(light.onContainer));
  });
}

Future<T> _withTheme<T>(
  WidgetTester tester,
  ShellColorScheme colors,
  T Function(BuildContext context) read,
) async {
  late T result;
  await tester.pumpWidget(
    ShellTheme(
      data: ShellThemeData(colors: colors),
      child: Builder(
        builder: (context) {
          result = read(context);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return result;
}
