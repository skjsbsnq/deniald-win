import 'package:denial_dart_shell/l10n/generated/app_localizations.dart';
import 'package:denial_dart_shell/src/settings/shell_settings.dart';
import 'package:denial_dart_shell/src/settings/widgets/settings_hero_preview_card.dart';
import 'package:denial_dart_shell/src/theme/shell_color_scheme.dart';
import 'package:denial_dart_shell/src/theme/shell_theme.dart';
import 'package:denial_dart_shell/src/theme/tokens.dart';
import 'package:denial_dart_shell/src/wallpaper/wallpaper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(
  Widget child, {
  ShellThemeData theme = const ShellThemeData(),
}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: Scaffold(
      body: ShellTheme(
        data: theme,
        child: Center(
          child: SizedBox(
            width: 500,
            child: child,
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('SettingsHeroPreviewCard', () {
    testWidgets('renders with 160dp height and 20dp corner radius', (tester) async {
      await tester.pumpWidget(
        _wrap(
          SettingsHeroPreviewCard(
            wallpaper: WallpaperResource.defaultWallpaper,
            onOpenWallpaperSelector: () {},
            colorSchemePreference: DesktopColorSchemePreference.preferDark,
            accentColor: ShellBrandColors.defaultAccent,
          ),
        ),
      );

      final heroFinder = find.byType(SettingsHeroPreviewCard);
      expect(heroFinder, findsOneWidget);

      final size = tester.getSize(heroFinder);
      expect(size.height, 160.0);

      // Verify corner radius of 20dp (ShellShapeScale.largeIncreased)
      final container = tester.widget<Container>(
        find.descendant(
          of: heroFinder,
          matching: find.byWidgetPredicate(
            (w) => w is Container && w.decoration is BoxDecoration,
          ),
        ).first,
      );
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.borderRadius, BorderRadius.circular(20.0));
    });

    testWidgets('triggers wallpaper selector on button tap', (tester) async {
      bool opened = false;
      await tester.pumpWidget(
        _wrap(
          SettingsHeroPreviewCard(
            wallpaper: WallpaperResource.defaultWallpaper,
            onOpenWallpaperSelector: () => opened = true,
            colorSchemePreference: DesktopColorSchemePreference.preferDark,
            accentColor: ShellBrandColors.defaultAccent,
          ),
        ),
      );

      expect(opened, isFalse);

      final buttonFinder = find.byKey(settingsWallpaperTriggerKey);
      expect(buttonFinder, findsOneWidget);

      await tester.tap(buttonFinder);
      await tester.pumpAndSettle();

      expect(opened, isTrue);
    });

    testWidgets('renders cleanly in dark and light themes without overflow', (tester) async {
      final themes = <ShellThemeData>[
        const ShellThemeData(),
        const ShellThemeData(colors: ShellColorScheme.light),
      ];

      for (final theme in themes) {
        for (final pref in DesktopColorSchemePreference.values) {
          await tester.pumpWidget(
            _wrap(
              SettingsHeroPreviewCard(
                wallpaper: WallpaperResource.defaultWallpaper,
                onOpenWallpaperSelector: () {},
                colorSchemePreference: pref,
                accentColor: const Color(0xFFDB2777),
              ),
              theme: theme,
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
        }
      }
    });

    testWidgets('adapts corner radius to theme cornerRadiusScale', (tester) async {
      const scale = 1.5;
      await tester.pumpWidget(
        _wrap(
          SettingsHeroPreviewCard(
            wallpaper: WallpaperResource.defaultWallpaper,
            onOpenWallpaperSelector: () {},
            colorSchemePreference: DesktopColorSchemePreference.preferDark,
            accentColor: ShellBrandColors.defaultAccent,
          ),
          theme: const ShellThemeData(cornerRadiusScale: scale),
        ),
      );

      final heroFinder = find.byType(SettingsHeroPreviewCard);
      final container = tester.widget<Container>(
        find.descendant(
          of: heroFinder,
          matching: find.byWidgetPredicate(
            (w) => w is Container && w.decoration is BoxDecoration,
          ),
        ).first,
      );
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.borderRadius, BorderRadius.circular(20.0 * scale));
    });
  });
}
