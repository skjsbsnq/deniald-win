import 'package:denial_dart_shell/l10n/generated/app_localizations.dart';
import 'package:denial_dart_shell/src/models/display_layout.dart';
import 'package:denial_dart_shell/src/models/shell_popup_placement.dart';
import 'package:denial_dart_shell/src/models/suspend_mode.dart';
import 'package:denial_dart_shell/src/settings/shell_settings.dart';
import 'package:denial_dart_shell/src/settings/widgets/focused_border_color_picker.dart';
import 'package:denial_dart_shell/src/settings/widgets/settings_animations_page.dart';
import 'package:denial_dart_shell/src/settings/widgets/settings_appearance_page.dart';
import 'package:denial_dart_shell/src/settings/widgets/settings_controls.dart';
import 'package:denial_dart_shell/src/settings/widgets/settings_layout_page.dart';
import 'package:denial_dart_shell/src/settings/widgets/settings_lock_screen_page.dart';
import 'package:denial_dart_shell/src/settings/widgets/settings_navigation.dart';
import 'package:denial_dart_shell/src/settings/widgets/settings_overlays_page.dart';
import 'package:denial_dart_shell/src/settings/widgets/settings_power_page.dart';
import 'package:denial_dart_shell/src/state/cursor_theme.dart';
import 'package:denial_dart_shell/src/state/desktop_window_close_effect.dart';
import 'package:denial_dart_shell/src/state/suspend_modes.dart';
import 'package:denial_dart_shell/src/state/upower.dart';
import 'package:denial_dart_shell/src/theme/cursor_themes.dart';
import 'package:denial_dart_shell/src/theme/shell_color_scheme.dart';
import 'package:denial_dart_shell/src/theme/shell_theme.dart';
import 'package:denial_dart_shell/src/theme/tokens.dart';
import 'package:denial_dart_shell/src/wallpaper/state/wallpaper_accent.dart';
import 'package:denial_dart_shell/src/wallpaper/state/wallpaper_controller.dart';
import 'package:denial_dart_shell/src/wallpaper/wallpaper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/settings_harness.dart';

/// A single 1280x720 output, so the layout page renders a real display picker
/// instead of its unavailable fallback.
final DisplayLayout _display = DisplayLayout.fallback(
  const Size(1280, 720),
  1.0,
);

/// Keeps the appearance and lock screen pages off the wallpaper store and the
/// cursor-theme discovery: both providers perform file IO (a store watcher, a
/// fontconfig sweep) that a widget test must not touch.
List<Override> _isolatedOverrides() => <Override>[
  wallpaperControllerProvider.overrideWith(_StubWallpaperController.new),
  wallpaperAccentExtractorProvider.overrideWithValue(
    (WallpaperResource _) async => null,
  ),
  cursorThemeCatalogProvider.overrideWith(_StubCursorCatalog.new),
];

Finder _sliderFor(String label) => find.descendant(
  of: find.ancestor(
    of: find.text(label),
    matching: find.byType(SettingsSlider),
  ),
  matching: find.byType(Slider),
);

/// Directly mounted pages are taller than the default 800x600 surface, so the
/// controls under test would otherwise sit off screen.
void _useTallWindow(WidgetTester tester) {
  tester.view.physicalSize = const Size(1280, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  group('page smoke', () {
    testWidgets('appearance renders the migrated skeleton', (tester) async {
      await pumpSettingsApp(
        tester,
        initialPage: SettingsPageId.appearance,
        overrides: _isolatedOverrides(),
      );

      // The new page header owns the page title at 28pt and subtitle at 14pt (§3.8);
      // the old in-page eyebrow/title rows are gone.
      final titleStyles = tester
          .widgetList<Text>(find.text('Appearance'))
          .map((text) => text.style?.fontSize)
          .toList();
      expect(titleStyles, contains(28));

      final subtitleStyles = tester
          .widgetList<Text>(find.text('Make the desktop feel like yours.'))
          .map((text) => text.style?.fontSize)
          .toList();
      expect(subtitleStyles, contains(14));

      expect(find.byType(SettingsCardGroup), findsNWidgets(7));
      expect(find.text('Colour scheme'), findsOneWidget);
      expect(find.text('Wallpaper'), findsOneWidget);
      expect(find.text('Shell accent'), findsOneWidget);
      expect(find.text('Backdrop blur'), findsWidgets);
      expect(find.text('Shape'), findsOneWidget);
      expect(find.text('Cursor'), findsOneWidget);
      expect(find.text('Fonts & icons'), findsOneWidget);
      expect(find.text('Window opacity'), findsOneWidget);
    });

    testWidgets('layout renders its four group containers', (tester) async {
      await pumpSettingsApp(
        tester,
        initialPage: SettingsPageId.layout,
        displayLayout: _display,
      );

      expect(find.text('Give every window room to breathe.'), findsWidgets);
      expect(find.text('Window layout'), findsOneWidget);
      expect(find.text('Workspaces'), findsOneWidget);
      expect(find.text('ChromeOS shelf'), findsOneWidget);
      expect(find.text('System bar geometry'), findsOneWidget);
      expect(find.text('Window minimization'), findsOneWidget);
      expect(find.text('Maximized spacing'), findsOneWidget);
      expect(find.text('Clipboard tray'), findsOneWidget);
    });

    testWidgets('overlays renders all four editors with the shelf off', (
      tester,
    ) async {
      await pumpSettingsApp(
        tester,
        initialPage: SettingsPageId.overlays,
        initialSettings: const ShellSettings(
          layout: ShellLayoutSettings(useChromeOsShelf: false),
        ),
      );

      expect(find.text('Put shell controls where they belong.'), findsWidgets);
      expect(find.text('Applications'), findsOneWidget);
      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('System level display'), findsOneWidget);
      expect(find.byType(SettingsAnchorPicker), findsNWidgets(4));
    });

    testWidgets('lock screen renders its sliders and preview', (tester) async {
      await pumpSettingsApp(
        tester,
        initialPage: SettingsPageId.lockScreen,
        overrides: _isolatedOverrides(),
      );

      expect(
        find.text('A desktop lock screen, not a stretched phone.'),
        findsWidgets,
      );
      expect(find.text('Backdrop'), findsOneWidget);
      expect(find.text('Desktop status'), findsOneWidget);
      expect(find.byType(Slider), findsNWidgets(3));
    });

    testWidgets('animations renders its segmented controls and toggle', (
      tester,
    ) async {
      await pumpSettingsApp(
        tester,
        initialPage: SettingsPageId.animations,
      );

      expect(
        find.text('Motion that matches your desktop.'),
        findsWidgets,
      );
      expect(find.text('Window closing effect'), findsOneWidget);
      expect(find.text('Panel motion'), findsOneWidget);
      expect(find.text('Lock screen motion'), findsOneWidget);
      expect(
        find.byType(SettingsSegmentedControl<DesktopWindowCloseEffect>),
        findsOneWidget,
      );
    });

    testWidgets('power renders the idle sections and the suspend select', (
      tester,
    ) async {
      await pumpSettingsApp(
        tester,
        initialPage: SettingsPageId.power,
      );

      expect(
        find.text('Power that respects your workflow.'),
        findsWidgets,
      );
      expect(find.text('Automatic idle actions'), findsOneWidget);
      expect(find.text('Suspend mode'), findsOneWidget);
      expect(find.byKey(settingsSuspendModeKey), findsOneWidget);
    });

    testWidgets('every page lays out cleanly in both brightnesses', (
      tester,
    ) async {
      _useTallWindow(tester);
      final themes = <ShellThemeData>[
        const ShellThemeData(),
        const ShellThemeData(colors: ShellColorScheme.light),
      ];
      for (final theme in themes) {
        for (final page in _allPages()) {
          await tester.pumpWidget(_wrapPage(page, theme: theme));
          await tester.pump();
          expect(tester.takeException(), isNull);
        }
      }
    });
  });

  group('page interactions', () {
    testWidgets('appearance opens and closes the accent colour picker', (
      tester,
    ) async {
      await pumpSettingsApp(
        tester,
        initialPage: SettingsPageId.appearance,
        initialSettings: const ShellSettings(
          appearance: ShellAppearanceSettings(
            accentSource: ShellAccentSource.custom,
          ),
        ),
        overrides: _isolatedOverrides(),
      );

      expect(find.byKey(settingsAccentColorPickerKey), findsNothing);

      await tester.tap(find.byKey(settingsAccentColorTriggerKey));
      await tester.pumpAndSettle();
      expect(find.byKey(settingsAccentColorPickerKey), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(settingsAccentColorPickerKey), findsNothing);
    });

    testWidgets('overlays reports the picked anchor for the launcher', (
      tester,
    ) async {
      _useTallWindow(tester);
      ShellOverlaySurface? surface;
      ShellPopupPlacement? placement;
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          _wrapPage(
            SettingsOverlaysPage(
              settings: const ShellOverlaySettings(),
              useChromeOsShelf: false,
              onChanged: (nextSurface, nextPlacement) {
                surface = nextSurface;
                placement = nextPlacement;
              },
              onReset: () {},
            ),
          ),
        );
        await tester.pump();

        await tester.tap(find.bySemanticsLabel('Bottom right').first);
        await tester.pump();
      } finally {
        semantics.dispose();
      }

      expect(surface, ShellOverlaySurface.launcher);
      expect(placement?.anchor, ShellPopupAnchor.bottomRight);
    });

    testWidgets('lock screen reports clock scale drags', (tester) async {
      _useTallWindow(tester);
      double? scale;
      await tester.pumpWidget(
        _wrapPage(
          SettingsLockScreenPage(
            settings: const ShellLockScreenSettings(),
            wallpaper: WallpaperResource.defaultWallpaper,
            onUseWallpaperChanged: (_) {},
            onDimChanged: (_) {},
            onBlurChanged: (_) {},
            onClockScaleChanged: (value) => scale = value,
            onShowStatusChanged: (_) {},
            onReset: () {},
          ),
        ),
      );
      await tester.pump();

      await tester.drag(_sliderFor('Clock scale'), const Offset(150, 0));
      await tester.pump();

      expect(scale, isNotNull);
      expect(scale, greaterThan(1));
    });

    testWidgets('animations reports segmented close-effect changes', (
      tester,
    ) async {
      _useTallWindow(tester);
      DesktopWindowCloseEffect? effect;
      await tester.pumpWidget(
        _wrapPage(
          SettingsAnimationsPage(
            settings: const ShellAnimationSettings(),
            onCloseEffectChanged: (value) => effect = value,
            onDurationScaleChanged: (_) {},
            onPanelTravelChanged: (_) {},
            onLockAnimationChanged: (_) {},
            onReset: () {},
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Fade'));
      await tester.pump();

      expect(effect, DesktopWindowCloseEffect.fade);
    });

    testWidgets('power reports the chosen suspend mode', (tester) async {
      _useTallWindow(tester);
      SuspendMode? mode;
      await tester.pumpWidget(
        _wrapPage(_powerPage(onSuspendModeChanged: (value) => mode = value)),
      );
      // Resolve the async suspend-capability probe.
      await tester.pump();
      await tester.pump();

      expect(find.text('Suspend to RAM (deep)'), findsOneWidget);
      await tester.tap(find.text('Suspend to RAM (deep)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Suspend to idle (s2idle)'));
      await tester.pumpAndSettle();

      expect(mode, SuspendMode.s2idle);
    });
  });
}

Widget _wrapPage(Widget child, {ShellThemeData theme = const ShellThemeData()}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: Scaffold(
      backgroundColor: const Color(0xff121212),
      body: ShellTheme(data: theme, child: child),
    ),
  );
}

/// The six migrated pages with inert callbacks, used to check that each one
/// lays out cleanly in both brightnesses (§acceptance: no overflow errors).
List<Widget> _allPages() => <Widget>[
  SettingsAppearancePage(
    settings: const ShellAppearanceSettings(),
    extractedAccent: ShellBrandColors.defaultAccent,
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
  SettingsLayoutPage(
    settings: const ShellLayoutSettings(),
    displayLayout: _display,
    onWindowLayoutChanged: (_) {},
    onWorkspacesEnabledChanged: (_) {},
    onWorkspaceCountChanged: (_) {},
    onSystemBarChanged: (_, _) {},
    onSystemBarThicknessChanged: (_) {},
    onMaximizePaddingChanged: (_) {},
    onMinimizedWindowPlacementChanged: (_) {},
    onClipboardTrayEdgeChanged: (_) {},
    onClipboardTrayExtentChanged: (_) {},
    onReset: () {},
  ),
  SettingsOverlaysPage(
    settings: const ShellOverlaySettings(),
    useChromeOsShelf: false,
    onChanged: (_, _) {},
    onReset: () {},
  ),
  SettingsLockScreenPage(
    settings: const ShellLockScreenSettings(),
    wallpaper: WallpaperResource.defaultWallpaper,
    onUseWallpaperChanged: (_) {},
    onDimChanged: (_) {},
    onBlurChanged: (_) {},
    onClockScaleChanged: (_) {},
    onShowStatusChanged: (_) {},
    onReset: () {},
  ),
  SettingsAnimationsPage(
    settings: const ShellAnimationSettings(),
    onCloseEffectChanged: (_) {},
    onDurationScaleChanged: (_) {},
    onPanelTravelChanged: (_) {},
    onLockAnimationChanged: (_) {},
    onReset: () {},
  ),
  _powerPage(onSuspendModeChanged: (_) {}),
];

/// The power page is a [ConsumerWidget], so it needs its own provider scope;
/// the battery and suspend probes are pinned to avoid D-Bus and `/sys`.
Widget _powerPage({required ValueChanged<SuspendMode> onSuspendModeChanged}) {
  return ProviderScope(
    overrides: <Override>[
      upowerProvider.overrideWith(SettingsTestUPowerController.new),
      suspendModeCapabilitiesProvider.overrideWith(
        (ref) async => SuspendModeCapabilities.parse('s2idle [deep]\n'),
      ),
    ],
    child: SettingsPowerPage(
      settings: const ShellPowerSettings(),
      onLockEnabledChanged: (_) {},
      onLockTimeoutChanged: (_) {},
      onDpmsEnabledChanged: (_) {},
      onDpmsTimeoutChanged: (_) {},
      onSuspendEnabledChanged: (_) {},
      onSuspendTimeoutChanged: (_) {},
      onSuspendModeChanged: onSuspendModeChanged,
      onReset: () {},
    ),
  );
}

/// Serves the bundled cursor themes without touching the filesystem.
class _StubCursorCatalog extends CursorThemeCatalogController {
  @override
  Future<List<ShellCursorThemeData>> build() async => ShellCursorThemes.all;
}

/// Serves the initial wallpaper state without starting the store watcher.
class _StubWallpaperController extends WallpaperController {
  @override
  WallpaperExperienceState build() => WallpaperExperienceState.initial();
}
