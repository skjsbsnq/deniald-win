import 'package:denial_dart_shell/l10n/generated/app_localizations.dart';
import 'package:denial_dart_shell/src/launcher/models/desktop_app.dart';
import 'package:denial_dart_shell/src/models/input_device_capabilities.dart';
import 'package:denial_dart_shell/src/models/keyboard_configuration.dart';
import 'package:denial_dart_shell/src/models/shortcut_configuration.dart';
import 'package:denial_dart_shell/src/settings/shell_settings.dart';
import 'package:denial_dart_shell/src/settings/widgets/settings_controls.dart';
import 'package:denial_dart_shell/src/settings/widgets/settings_environment_page.dart';
import 'package:denial_dart_shell/src/settings/widgets/settings_keyboard_page.dart';
import 'package:denial_dart_shell/src/settings/widgets/settings_language_page.dart';
import 'package:denial_dart_shell/src/settings/widgets/settings_shortcut_editor.dart';
import 'package:denial_dart_shell/src/settings/widgets/settings_shortcuts_page.dart';
import 'package:denial_dart_shell/src/settings/widgets/settings_touchpad_page.dart';
import 'package:denial_dart_shell/src/settings/widgets/settings_weather_page.dart';
import 'package:denial_dart_shell/src/state/input_device_capabilities.dart';
import 'package:denial_dart_shell/src/state/keyboard_configuration.dart';
import 'package:denial_dart_shell/src/state/shortcut_configuration.dart';
import 'package:denial_dart_shell/src/theme/shell_color_scheme.dart';
import 'package:denial_dart_shell/src/theme/shell_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

// Page titles, exactly as the l10n bundle resolves them in `en`.
const String _keyboardTitle =
    'Configure the physical keyboard used by Flutter, Wayland, and Xwayland.';
const String _touchpadTitle = 'Tune mouse and touchpad behavior.';
const String _shortcutsTitle =
    'Choose what Denial does when a shortcut is pressed.';
const String _languageTitle = 'Choose the language Denial uses.';
const String _weatherTitle = 'Weather, where you want it.';
const String _environmentTitle =
    'Customize the environment of applications launched by Denial.';

/// Directly mounted pages are taller than the default 800x600 surface, so the
/// controls under test would otherwise sit off screen.
void _useTallWindow(WidgetTester tester) {
  tester.view.physicalSize = const Size(1280, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// The migrated skeleton paints the page title through the new header at 28pt
/// (`02-VISUAL-SPEC.md` §3.8).
void _expectPageTitle(WidgetTester tester, String title) {
  final titleStyles = tester
      .widgetList<Text>(find.text(title))
      .map((text) => text.style?.fontSize)
      .toList();
  expect(titleStyles, contains(28));
}

void main() {
  group('page smoke', () {
    testWidgets('keyboard renders the migrated skeleton', (tester) async {
      _useTallWindow(tester);
      await tester.pumpWidget(_keyboardPage());
      await tester.pump();

      _expectPageTitle(tester, _keyboardTitle);
      expect(find.byType(SettingsCardGroup), findsWidgets);
      expect(find.text('Layouts and variants'), findsOneWidget);
      expect(find.text('Key repeat'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('touchpad renders its sliders and toggles', (tester) async {
      _useTallWindow(tester);
      await tester.pumpWidget(_touchpadPage());
      await tester.pump();

      _expectPageTitle(tester, _touchpadTitle);
      expect(find.byType(SettingsCardGroup), findsWidgets);
      expect(find.text('Tap to click'), findsOneWidget);
      expect(find.text('Reverse two-finger scrolling'), findsOneWidget);
      expect(find.byKey(settingsTapToClickToggleKey), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shortcuts renders the list and add action', (tester) async {
      _useTallWindow(tester);
      await tester.pumpWidget(_shortcutsPage());
      await tester.pump();

      _expectPageTitle(tester, _shortcutsTitle);
      expect(find.text('Add shortcut'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('language renders the interface selector', (tester) async {
      _useTallWindow(tester);
      await tester.pumpWidget(_languagePage());
      await tester.pump();

      _expectPageTitle(tester, _languageTitle);
      expect(find.text('Interface language'), findsOneWidget);
      expect(find.text('English'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('weather renders its mode and unit groups', (tester) async {
      _useTallWindow(tester);
      await tester.pumpWidget(_weatherPage());
      await tester.pump();

      _expectPageTitle(tester, _weatherTitle);
      expect(find.byType(SettingsCardGroup), findsWidgets);
      expect(find.text('Location'), findsOneWidget);
      expect(find.text('Temperature unit'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('environment renders the editor and scope list', (tester) async {
      _useTallWindow(tester);
      await tester.pumpWidget(_environmentPage());
      await tester.pump();

      _expectPageTitle(tester, _environmentTitle);
      expect(find.text('Applications'), findsOneWidget);
      expect(find.text('Add an override'), findsOneWidget);
      // The header and the scope tile both name the global scope.
      expect(find.text('All applications'), findsWidgets);
      expect(tester.takeException(), isNull);
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
          // Each page brings its own provider overrides; a fresh key forces the
          // scope to rebuild instead of mutating the previous container.
          await tester.pumpWidget(
            _wrapPage(
              KeyedSubtree(key: UniqueKey(), child: page),
              theme: theme,
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
        }
      }
    });
  });

  group('page interactions', () {
    testWidgets('keyboard applies the edited configuration', (tester) async {
      _useTallWindow(tester);
      final controller = _StubKeyboardController();
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            keyboardConfigurationProvider.overrideWith(() => controller),
          ],
          child: _wrapPage(const SettingsKeyboardPage()),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Apply keyboard settings'));
      await tester.pump();

      expect(controller.applied, isNotNull);
      expect(controller.applied!.repeatDelayMs, 600);
    });

    testWidgets('touchpad reports tap-to-click changes', (tester) async {
      _useTallWindow(tester);
      final controller = _StubInputController();
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            inputDeviceCapabilitiesProvider.overrideWith(() => controller),
          ],
          child: _wrapPage(const SettingsTouchpadPage()),
        ),
      );
      await tester.pump();

      await tester.tap(find.byType(SettingsToggle).first);
      await tester.pump();

      expect(controller.tapToClick, isTrue);
    });

    testWidgets('shortcuts opens the editor and cancels it with escape', (
      tester,
    ) async {
      _useTallWindow(tester);
      final controller = _StubShortcutController();
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            shortcutConfigurationProvider.overrideWith(() => controller),
          ],
          child: _wrapPage(const SettingsShortcutsPage()),
        ),
      );
      await tester.pump();

      expect(find.byType(SettingsShortcutEditor), findsNothing);

      await tester.tap(find.text('Add shortcut'));
      await tester.pump();
      expect(find.byType(SettingsShortcutEditor), findsOneWidget);

      // Let the editor's validation debounce resolve before dismissing.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byType(SettingsShortcutEditor), findsNothing);
    });

    testWidgets('language reports the chosen locale', (tester) async {
      _useTallWindow(tester);
      ShellLocalePreference? picked;
      await tester.pumpWidget(
        _wrapPage(
          SettingsLanguagePage(
            settings: const ShellLocalizationSettings(),
            onChanged: (value) => picked = value,
            onReset: _noop,
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('English'));
      await tester.pump();

      expect(picked, ShellLocalePreference.english);
    });

    testWidgets('weather search field accepts and clears input', (
      tester,
    ) async {
      _useTallWindow(tester);
      await tester.pumpWidget(
        ProviderScope(
          child: _wrapPage(
            SettingsWeatherPage(
              settings: const ShellWeatherSettings(
                locationMode: ShellWeatherLocationMode.manual,
              ),
              onLocationModeChanged: _noopMode,
              onManualLocationChanged: _noopLocation,
              onTemperatureUnitChanged: _noopUnit,
              onReset: _noop,
            ),
          ),
        ),
      );
      await tester.pump();

      final field = find.byKey(settingsWeatherSearchFieldKey);
      expect(field, findsOneWidget);

      // Typing schedules the debounced geocoding search; clearing cancels it
      // before any request leaves the field.
      await tester.enterText(field, 'Shen');
      await tester.pump();
      await tester.enterText(field, '');
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('environment reports a saved variable', (tester) async {
      _useTallWindow(tester);
      String? desktopFileId;
      String? previousName;
      String? savedName;
      String? savedValue;
      await tester.pumpWidget(
        _wrapPage(
          SettingsEnvironmentPage(
            settings: const ShellApplicationEnvironmentSettings(),
            applications: const <DesktopApp>[],
            onSave: (scope, previous, name, value) {
              desktopFileId = scope;
              previousName = previous;
              savedName = name;
              savedValue = value;
            },
            onDelete: (_, _) {},
            onReset: _noop,
            onResetScope: _noopScope,
          ),
        ),
      );
      await tester.pump();

      await tester.enterText(
        find.byKey(settingsEnvironmentNameFieldKey),
        'FOO',
      );
      await tester.enterText(
        find.byKey(settingsEnvironmentValueFieldKey),
        'bar',
      );
      await tester.pump();

      await tester.tap(find.byKey(settingsEnvironmentSaveButtonKey));
      await tester.pump();

      expect(desktopFileId, isNull);
      expect(previousName, isNull);
      expect(savedName, 'FOO');
      expect(savedValue, 'bar');
    });
  });
}

void _noop() {}

void _noopMode(ShellWeatherLocationMode mode) {}

void _noopLocation(ShellManualLocation? location) {}

void _noopUnit(ShellTemperatureUnit unit) {}

void _noopScope(String? desktopFileId) {}

Widget _keyboardPage() => ProviderScope(
  overrides: <Override>[
    keyboardConfigurationProvider.overrideWith(_StubKeyboardController.new),
  ],
  child: _wrapPage(const SettingsKeyboardPage()),
);

Widget _touchpadPage() => ProviderScope(
  overrides: <Override>[
    inputDeviceCapabilitiesProvider.overrideWith(_StubInputController.new),
  ],
  child: _wrapPage(const SettingsTouchpadPage()),
);

Widget _shortcutsPage() => ProviderScope(
  overrides: <Override>[
    shortcutConfigurationProvider.overrideWith(_StubShortcutController.new),
  ],
  child: _wrapPage(const SettingsShortcutsPage()),
);

Widget _languagePage() => _wrapPage(
  SettingsLanguagePage(
    settings: const ShellLocalizationSettings(),
    onChanged: _noopLocale,
    onReset: _noop,
  ),
);

Widget _weatherPage() => ProviderScope(
  child: _wrapPage(
    SettingsWeatherPage(
      settings: const ShellWeatherSettings(),
      onLocationModeChanged: _noopMode,
      onManualLocationChanged: _noopLocation,
      onTemperatureUnitChanged: _noopUnit,
      onReset: _noop,
    ),
  ),
);

Widget _environmentPage() => _wrapPage(
  SettingsEnvironmentPage(
    settings: const ShellApplicationEnvironmentSettings(),
    applications: const <DesktopApp>[],
    onSave: (_, _, _, _) {},
    onDelete: (_, _) {},
    onReset: _noop,
    onResetScope: _noopScope,
  ),
);

void _noopLocale(ShellLocalePreference locale) {}

/// The six migrated pages with inert callbacks, used to check that each one
/// lays out cleanly in both brightnesses (§acceptance: no overflow errors).
List<Widget> _allPages() => <Widget>[
  _keyboardPage(),
  _touchpadPage(),
  _shortcutsPage(),
  _languagePage(),
  _weatherPage(),
  _environmentPage(),
];

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

/// Serves a ready keyboard configuration without reaching the bridge.
class _StubKeyboardController extends KeyboardConfigurationController {
  DenialKeyboardConfiguration? applied;

  @override
  KeyboardConfigurationState build() =>
      const KeyboardConfigurationState(
        configuration: DenialKeyboardConfiguration.defaults(),
      );

  @override
  Future<bool> configure(DenialKeyboardConfiguration requested) async {
    applied = requested;
    return true;
  }
}

/// Serves pointer capabilities and records tap-to-click writes locally.
class _StubInputController extends InputDeviceCapabilitiesController {
  bool? tapToClick;

  @override
  InputDeviceCapabilitiesState build() =>
      const InputDeviceCapabilitiesState(
        capabilities: DenialInputDeviceCapabilities(
          revision: 1,
          hasMouse: true,
          mouseSpeed: mouseSpeedDefault,
          hasTouchpad: true,
          tapToClickEnabled: false,
          naturalScrollEnabled: false,
          scrollSpeedFactor: touchpadScrollSpeedFactorDefault,
        ),
      );

  @override
  void setTapToClick(bool enabled) {
    tapToClick = enabled;
  }
}

/// Serves an empty shortcut document and validates every draft as valid.
class _StubShortcutController extends ShortcutConfigurationController {
  @override
  ShortcutConfigurationState build() => ShortcutConfigurationState(
    configuration: DenialShortcutConfiguration(
      revision: 1,
      shortcuts: const <DenialShortcutBinding>[],
      supportedActions: DenialShortcutAction.values,
      supportedInputs: const <DenialShortcutInput>[],
    ),
    loading: false,
  );

  @override
  Future<DenialShortcutValidation> validateShortcut({
    required DenialShortcutBinding shortcut,
    String? existingShortcut,
  }) async {
    return DenialShortcutValidation(
      revision: 1,
      kind: DenialShortcutValidationKind.valid,
      canonical: shortcut.shortcut,
    );
  }
}
