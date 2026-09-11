import 'package:denial_dart_shell/l10n/generated/app_localizations.dart';
import 'package:denial_dart_shell/src/settings/shell_settings.dart';
import 'package:denial_dart_shell/src/settings/widgets/settings_appearance_page.dart';
import 'package:denial_dart_shell/src/settings/widgets/settings_controls.dart';
import 'package:denial_dart_shell/src/settings/widgets/settings_hero_preview_card.dart';
import 'package:denial_dart_shell/src/theme/backdrop_blur_level.dart';
import 'package:denial_dart_shell/src/theme/cursor_themes.dart';
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
        child: SizedBox(
          width: 800,
          height: 1200,
          child: child,
        ),
      ),
    ),
  );
}

void main() {
  group('SettingsAppearancePage modular cards and keys', () {
    testWidgets('renders all 7 card groups and all 9 automation keys', (tester) async {
      tester.view.physicalSize = const Size(1280, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      bool wallpaperOpened = false;
      bool blurToggled = false;
      double? cornerRadius;
      double? cardOpacity;

      await tester.pumpWidget(
        _wrap(
          SettingsAppearancePage(
            settings: const ShellAppearanceSettings(
              accentSource: ShellAccentSource.custom,
            ),
            extractedAccent: const Color(0xFF0097A7),
            wallpaper: WallpaperResource.defaultWallpaper,
            onOpenWallpaperSelector: () => wallpaperOpened = true,
            onColorSchemePreferenceChanged: (_) {},
            onAccentSourceChanged: (_) {},
            onOpenAccentPicker: () {},
            onCornerRadiusScaleChanged: (val) => cornerRadius = val,
            onPanelOpacityChanged: (_) {},
            onCardOpacityChanged: (val) => cardOpacity = val,
            onBackdropBlurEnabledChanged: (val) => blurToggled = val,
            onBackdropBlurLevelChanged: (_) {},
            onBackdropBlurOpacityThresholdChanged: (_) {},
            onFocusedWindowBorderEnabledChanged: (_) {},
            onFocusedOpacityChanged: (_) {},
            onUnfocusedOpacityChanged: (_) {},
            onCursorSizeChanged: (_) {},
            cursorThemes: const <ShellCursorThemeData>[],
            cursorCatalogLoading: false,
            onCursorThemeChanged: (_) {},
            onAllowClientCursorSurfacesChanged: (_) {},
            onImportCursorZip: null,
            onRemoveCursorTheme: (_) async {},
            onUiFontFamilyChanged: (_) {},
            onIconThemeNameChanged: (_) {},
            onReset: () {},
          ),
        ),
      );
      await tester.pump();

      // Verify 7 SettingsCardGroup instances
      expect(find.byType(SettingsCardGroup), findsNWidgets(7));

      // Verify Hero preview card at top
      expect(find.byType(SettingsHeroPreviewCard), findsOneWidget);

      // Verify 9 automation keys are present
      expect(find.byKey(settingsWallpaperTriggerKey), findsOneWidget);
      expect(find.byKey(settingsColorSchemeControlKey), findsOneWidget);
      expect(find.byKey(settingsAccentColorTriggerKey), findsOneWidget);
      expect(find.byKey(settingsBackdropBlurToggleKey), findsOneWidget);
      expect(find.byKey(settingsBackdropBlurSliderKey), findsOneWidget);
      expect(find.byKey(settingsBackdropBlurOpacityThresholdKey), findsOneWidget);
      expect(find.byKey(settingsCornerRoundnessSliderKey), findsOneWidget);
      expect(find.byKey(settingsCardOpacitySliderKey), findsOneWidget);
      expect(find.byKey(settingsCursorSizeSliderKey), findsOneWidget);

      // Test wallpaper trigger
      await tester.tap(find.byKey(settingsWallpaperTriggerKey));
      await tester.pumpAndSettle();
      expect(wallpaperOpened, isTrue);

      // Test blur toggle (initial value is true, so tapping toggles to false)
      await tester.tap(find.byKey(settingsBackdropBlurToggleKey));
      await tester.pumpAndSettle();
      expect(blurToggled, isFalse);
    });

    testWidgets('shows dynamic tonal swatches in wallpaper mode', (tester) async {
      tester.view.physicalSize = const Size(1280, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _wrap(
          SettingsAppearancePage(
            settings: const ShellAppearanceSettings(
              accentSource: ShellAccentSource.wallpaper,
            ),
            extractedAccent: const Color(0xFFDB2777),
            wallpaper: WallpaperResource.defaultWallpaper,
            onOpenWallpaperSelector: () {},
            onColorSchemePreferenceChanged: (_) {},
            onAccentSourceChanged: (_) {},
            onOpenAccentPicker: () {},
            onCornerRadiusScaleChanged: (_) {},
            onPanelOpacityChanged: (_) {},
            onCardOpacityChanged: (_) {},
            onBackdropBlurEnabledChanged: (_) {},
            onBackdropBlurLevelChanged: (_) {},
            onBackdropBlurOpacityThresholdChanged: (_) {},
            onFocusedWindowBorderEnabledChanged: (_) {},
            onFocusedOpacityChanged: (_) {},
            onUnfocusedOpacityChanged: (_) {},
            onCursorSizeChanged: (_) {},
            cursorThemes: const <ShellCursorThemeData>[],
            cursorCatalogLoading: false,
            onCursorThemeChanged: (_) {},
            onAllowClientCursorSurfacesChanged: (_) {},
            onImportCursorZip: null,
            onRemoveCursorTheme: (_) async {},
            onUiFontFamilyChanged: (_) {},
            onIconThemeNameChanged: (_) {},
            onReset: () {},
          ),
        ),
      );
      await tester.pump();

      // Custom color button is hidden in wallpaper mode
      expect(find.byKey(settingsAccentColorTriggerKey), findsNothing);

      // Dynamic tonal swatches are shown
      expect(find.bySemanticsLabel('Accent tone 1'), findsOneWidget);
      expect(find.bySemanticsLabel('Accent tone 2'), findsOneWidget);
      expect(find.bySemanticsLabel('Accent tone 3'), findsOneWidget);

      // Tap swatch 2 to select it
      await tester.tap(find.bySemanticsLabel('Accent tone 2'));
      await tester.pumpAndSettle();
    });

    testWidgets('renders cleanly in light theme', (tester) async {
      tester.view.physicalSize = const Size(1280, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _wrap(
          SettingsAppearancePage(
            settings: const ShellAppearanceSettings(
              colorSchemePreference: DesktopColorSchemePreference.preferLight,
            ),
            extractedAccent: const Color(0xFF2563EB),
            wallpaper: WallpaperResource.defaultWallpaper,
            onOpenWallpaperSelector: () {},
            onColorSchemePreferenceChanged: (_) {},
            onAccentSourceChanged: (_) {},
            onOpenAccentPicker: () {},
            onCornerRadiusScaleChanged: (_) {},
            onPanelOpacityChanged: (_) {},
            onCardOpacityChanged: (_) {},
            onBackdropBlurEnabledChanged: (_) {},
            onBackdropBlurLevelChanged: (_) {},
            onBackdropBlurOpacityThresholdChanged: (_) {},
            onFocusedWindowBorderEnabledChanged: (_) {},
            onFocusedOpacityChanged: (_) {},
            onUnfocusedOpacityChanged: (_) {},
            onCursorSizeChanged: (_) {},
            cursorThemes: const <ShellCursorThemeData>[],
            cursorCatalogLoading: false,
            onCursorThemeChanged: (_) {},
            onAllowClientCursorSurfacesChanged: (_) {},
            onImportCursorZip: null,
            onRemoveCursorTheme: (_) async {},
            onUiFontFamilyChanged: (_) {},
            onIconThemeNameChanged: (_) {},
            onReset: () {},
          ),
          theme: const ShellThemeData(colors: ShellColorScheme.light),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}
