import 'package:denial_dart_shell/l10n/generated/app_localizations.dart';
import 'package:denial_dart_shell/src/models/display_layout.dart';
import 'package:denial_dart_shell/src/models/output_configuration.dart';
import 'package:denial_dart_shell/src/models/ui_development.dart';
import 'package:denial_dart_shell/src/settings/widgets/settings_about_page.dart';
import 'package:denial_dart_shell/src/settings/widgets/settings_controls.dart';
import 'package:denial_dart_shell/src/settings/widgets/settings_developer_page.dart';
import 'package:denial_dart_shell/src/settings/widgets/settings_displays_page.dart';
import 'package:denial_dart_shell/src/settings/widgets/settings_navigation.dart';
import 'package:denial_dart_shell/src/settings/widgets/settings_system_pages.dart';
import 'package:denial_dart_shell/src/state/app_audio.dart';
import 'package:denial_dart_shell/src/state/bluetooth.dart';
import 'package:denial_dart_shell/src/state/display_brightness.dart';
import 'package:denial_dart_shell/src/state/display_layout.dart';
import 'package:denial_dart_shell/src/state/network_connectivity.dart';
import 'package:denial_dart_shell/src/state/output_configuration.dart';
import 'package:denial_dart_shell/src/state/quick_settings.dart';
import 'package:denial_dart_shell/src/state/ui_development.dart';
import 'package:denial_dart_shell/src/theme/shell_color_scheme.dart';
import 'package:denial_dart_shell/src/theme/shell_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/settings_harness.dart';

// Page titles, exactly as the l10n bundle resolves them in `en`.
const String _displaysTitle = 'Displays and video.';
const String _networkTitle = 'Network connections.';
const String _bluetoothTitle = 'Bluetooth devices.';
const String _audioTitle = 'Audio for the whole desktop.';
const String _developerTitle =
    'Edit the complete Flutter desktop, reload it live, then promote it to '
    'an optimized build.';
const String _aboutTitle = 'About';

/// A two-monitor desktop layout used by the brightness card.
final DisplayLayout _displayLayout = DisplayLayout.fallback(
  const Size(2560, 1440),
  1.0,
);

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

Future<ProviderContainer> _pumpPage(
  WidgetTester tester,
  Widget page, {
  List<Override> overrides = const <Override>[],
  ShellThemeData theme = const ShellThemeData(),
}) async {
  _useTallWindow(tester);
  final container = ProviderContainer(overrides: overrides);
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          backgroundColor: const Color(0xff121212),
          body: ShellTheme(data: theme, child: page),
        ),
      ),
    ),
  );
  await tester.pump();
  return container;
}

void main() {
  group('page smoke', () {
    testWidgets('displays renders the migrated skeleton', (tester) async {
      await _pumpPage(
        tester,
        const SettingsDisplaysPage(),
        overrides: _displayOverrides(),
      );

      _expectPageTitle(tester, _displaysTitle);
      expect(find.byType(SettingsCardGroup), findsWidgets);
      expect(find.text('Monitor configuration'), findsOneWidget);
      expect(find.text('Brightness'), findsOneWidget);
      // The monitor editor only renders with more than one draft output.
      expect(find.byKey(settingsMonitorLayoutEditorKey), findsOneWidget);
      // The bespoke dropdowns are gone: the resolution selector is now the
      // shared labelled menu field.
      expect(
        find.byKey(const ValueKey<String>('DP-1-resolution-1920x1080')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('network renders the wifi groups', (tester) async {
      await _pumpPage(
        tester,
        const SettingsNetworkPage(),
        overrides: _networkOverrides(),
      );

      _expectPageTitle(tester, _networkTitle);
      expect(find.byType(SettingsCardGroup), findsWidgets);
      expect(find.text('Wi-Fi'), findsOneWidget);
      expect(find.text('Available networks'), findsOneWidget);
      expect(find.byType(SettingsToggle), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('bluetooth renders the radio and device groups', (
      tester,
    ) async {
      await _pumpPage(
        tester,
        const SettingsBluetoothPage(),
        overrides: _bluetoothOverrides(),
      );

      _expectPageTitle(tester, _bluetoothTitle);
      expect(find.byType(SettingsCardGroup), findsWidgets);
      expect(find.text('Bluetooth radio'), findsOneWidget);
      expect(find.text('Devices'), findsOneWidget);
      expect(find.byType(SettingsToggle), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('audio renders the master output and application audio', (
      tester,
    ) async {
      await _pumpPage(
        tester,
        const SettingsAudioPage(),
        overrides: _audioOverrides(),
      );

      _expectPageTitle(tester, _audioTitle);
      expect(find.byType(SettingsCardGroup), findsWidgets);
      expect(find.text('Master output'), findsOneWidget);
      expect(find.text('Application audio'), findsOneWidget);
      expect(find.byType(SettingsSlider), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('developer renders every settings group', (tester) async {
      await _pumpPage(
        tester,
        _developerPage(),
        overrides: _developerOverrides(),
      );

      _expectPageTitle(tester, _developerTitle);
      expect(find.byType(SettingsCardGroup), findsWidgets);
      expect(find.text('Flutter shell runtime'), findsOneWidget);
      expect(find.text('Source workspace'), findsOneWidget);
      expect(find.text('Live session'), findsOneWidget);
      expect(find.text('Connection & diagnostics'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('about keeps the hero while using the page skeleton', (
      tester,
    ) async {
      await _pumpPage(tester, const SettingsAboutPage());

      _expectPageTitle(tester, _aboutTitle);
      expect(find.byKey(settingsAboutWordmarkKey), findsOneWidget);
      expect(find.text('A Flutter-native Wayland compositor.'), findsOneWidget);
      expect(find.text('Doctor Logix'), findsOneWidget);
      expect(find.byType(SettingsCardGroup), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('every page lays out cleanly in both brightnesses', (
      tester,
    ) async {
      final themes = <ShellThemeData>[
        const ShellThemeData(),
        const ShellThemeData(colors: ShellColorScheme.light),
      ];
      for (final theme in themes) {
        for (final (page, overrides) in _allPages()) {
          await _pumpPage(tester, page, overrides: overrides, theme: theme);
          expect(tester.takeException(), isNull);
        }
      }
    });
  });

  group('page interactions', () {
    testWidgets('displays shows the confirmation dialog and keeps changes', (
      tester,
    ) async {
      var kept = false;
      _useTallWindow(tester);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: ShellTheme(
              data: const ShellThemeData(),
              child: SettingsDisplayConfirmationDialog(
                confirmation: DenialOutputConfirmation(
                  token: 7,
                  deadlineUnixMilliseconds:
                      DateTime.now().millisecondsSinceEpoch + 60000,
                ),
                busy: false,
                onKeep: () => kept = true,
                onRevert: () {},
                onExpired: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(settingsDisplayConfirmationDialogKey),
        findsOneWidget,
      );
      await tester.tap(find.byKey(settingsKeepDisplayConfigurationKey));
      await tester.pump();
      expect(kept, isTrue);

      // Tear the dialog down explicitly so its countdown timer is cancelled.
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('displays surfaces a pending confirmation through the shell', (
      tester,
    ) async {
      final container = await pumpSettingsApp(
        tester,
        initialPage: SettingsPageId.displays,
        displayLayout: _displayLayout,
        overrides: <Override>[
          outputConfigurationProvider.overrideWith(
            _PendingConfirmationController.new,
          ),
          displayBrightnessProvider.overrideWith(
            _StubDisplayBrightnessController.new,
          ),
        ],
      );

      // The application host renders the dialog whenever the configuration
      // carries a `pendingConfirmation`.
      expect(
        find.byKey(settingsDisplayConfirmationDialogKey),
        findsOneWidget,
      );

      await tester.tap(find.byKey(settingsKeepDisplayConfigurationKey));
      await tester.pump();

      final notifier = container.read(outputConfigurationProvider.notifier);
      expect(notifier, isA<_PendingConfirmationController>());
      expect((notifier as _PendingConfirmationController).kept, isTrue);

      // Dispose the dialog explicitly so its countdown timer is cancelled.
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('displays resolution menu reports the picked mode', (
      tester,
    ) async {
      final container = await _pumpPage(
        tester,
        const SettingsDisplaysPage(),
        overrides: _displayOverrides(),
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('DP-1-resolution-1920x1080')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('2560 × 1440'), findsOneWidget);
      await tester.tap(find.text('2560 × 1440'));
      await tester.pump();

      final output = container
          .read(outputConfigurationProvider)
          .draftOutputs
          .first;
      expect(output.effectiveMode.width, 2560);
      expect(output.effectiveMode.height, 1440);
    });

    testWidgets('displays tolerates a transform absent from the menu choices', (
      tester,
    ) async {
      await _pumpPage(
        tester,
        const SettingsDisplaysPage(),
        overrides: <Override>[
          outputConfigurationProvider.overrideWith(
            _FlippedOutputConfigurationController.new,
          ),
          displayBrightnessProvider.overrideWith(
            _StubDisplayBrightnessController.new,
          ),
          displayLayoutProvider.overrideWithBuild(
            (ref, controller) => _displayLayout,
          ),
        ],
      );

      // `flipped` is deliberately absent from the rotation menu choices, so
      // the shared menu must fall back to the value's own representation
      // instead of throwing while resolving the selected entry (r55 defence).
      expect(find.text('DenialOutputTransform.flipped'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('displays scale control still submits a valid value', (
      tester,
    ) async {
      double? changed;
      await _pumpPage(
        tester,
        SettingsDisplayScaleControl(
          scale: 1,
          enabled: true,
          onChanged: (value) => changed = value,
        ),
      );

      await tester.enterText(
        find.byKey(settingsDisplayScaleFieldKey),
        '125',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(changed, 1.25);
    });

    testWidgets('developer workspace field accepts input without error', (
      tester,
    ) async {
      await _pumpPage(
        tester,
        _developerPage(),
        overrides: _developerOverrides(),
      );

      await tester.enterText(
        find.byKey(settingsDeveloperWorkspaceFieldKey),
        '/home/dev/DenialUI',
      );
      await tester.pump();

      final field = tester.widget<TextField>(
        find.byKey(settingsDeveloperWorkspaceFieldKey),
      );
      expect(field.controller?.text, '/home/dev/DenialUI');
      expect(tester.takeException(), isNull);
    });
  });
}

/// The six migrated pages with their provider stubs, used to check that each
/// one lays out cleanly in both brightnesses (no overflow errors).
List<(Widget, List<Override>)> _allPages() => <(Widget, List<Override>)>[
  (const SettingsDisplaysPage(), _displayOverrides()),
  (const SettingsNetworkPage(), _networkOverrides()),
  (const SettingsBluetoothPage(), _bluetoothOverrides()),
  (const SettingsAudioPage(), _audioOverrides()),
  (_developerPage(), _developerOverrides()),
  (const SettingsAboutPage(), const <Override>[]),
];

List<Override> _displayOverrides() => <Override>[
  outputConfigurationProvider.overrideWith(
    _StubOutputConfigurationController.new,
  ),
  displayBrightnessProvider.overrideWith(
    _StubDisplayBrightnessController.new,
  ),
  displayLayoutProvider.overrideWithBuild((ref, controller) => _displayLayout),
];

List<Override> _networkOverrides() => <Override>[
  networkConnectivityProvider.overrideWith(_StubNetworkController.new),
];

List<Override> _bluetoothOverrides() => <Override>[
  bluetoothProvider.overrideWith(_StubBluetoothController.new),
];

List<Override> _audioOverrides() => <Override>[
  appAudioProvider.overrideWith(_StubAppAudioController.new),
  quickSettingsProvider.overrideWith(_StubQuickSettingsController.new),
];

List<Override> _developerOverrides() => <Override>[
  uiDevelopmentProvider.overrideWith(_StubUiDevelopmentController.new),
  uiWorkspaceSetupProvider.overrideWithValue(const _StubWorkspaceSetup()),
];

/// The developer page is a plain [StatefulWidget], so it reads its controller
/// from the enclosing scope instead of the application host.
Widget _developerPage() => Consumer(
  builder: (context, ref, _) => SettingsDeveloperPage(
    state: ref.watch(uiDevelopmentProvider),
    controller: ref.read(uiDevelopmentProvider.notifier),
    workspaceSetup: ref.watch(uiWorkspaceSetupProvider),
  ),
);

const DenialOutputCapabilities _capabilities = DenialOutputCapabilities(
  apply: true,
  position: true,
  mode: true,
  scale: true,
  transform: true,
  adaptiveSync: true,
  persistent: false,
);

const DenialOutputMode _mode1080 = DenialOutputMode(
  width: 1920,
  height: 1080,
  refreshMillihz: 60000,
  preferred: true,
);

const DenialOutputMode _mode1440 = DenialOutputMode(
  width: 2560,
  height: 1440,
  refreshMillihz: 144000,
  preferred: false,
);

const DenialOutput _output = DenialOutput(
  monitorId: 1,
  name: 'DP-1',
  description: 'DP-1',
  connected: true,
  enabled: true,
  powered: true,
  x: 0,
  y: 0,
  logicalWidth: 1920,
  logicalHeight: 1080,
  scale: 1,
  transform: DenialOutputTransform.normal,
  adaptiveSyncSupported: true,
  adaptiveSync: false,
  currentMode: _mode1080,
  modes: <DenialOutputMode>[_mode1080, _mode1440],
);

/// A second monitor keeps the arrangement editor mounted so this batch also
/// exercises the monitor canvas.
const DenialOutput _secondOutput = DenialOutput(
  monitorId: 2,
  name: 'DP-2',
  description: 'DP-2',
  connected: true,
  enabled: true,
  powered: true,
  x: 1920,
  y: 0,
  logicalWidth: 1920,
  logicalHeight: 1080,
  scale: 1,
  transform: DenialOutputTransform.normal,
  adaptiveSyncSupported: false,
  adaptiveSync: false,
  currentMode: _mode1080,
  modes: <DenialOutputMode>[_mode1080, _mode1440],
);

const DenialOutputConfiguration _configuration = DenialOutputConfiguration(
  serial: 1,
  capabilities: _capabilities,
  outputs: <DenialOutput>[_output, _secondOutput],
  primaryOutput: 'DP-1',
);

/// Serves a ready output configuration without reaching the compositor socket.
class _StubOutputConfigurationController extends OutputConfigurationController {
  @override
  OutputConfigurationState build() => OutputConfigurationState(
    configuration: _configuration,
    draftOutputs: _configuration.outputs,
    draftPrimaryOutput: _configuration.primaryOutput,
    selectedName: _output.name,
  );
}

/// Serves a topology that already carries a pending confirmation, so the
/// application host mounts the confirmation dialog. The confirmation requests
/// are recorded locally instead of reaching the compositor socket.
class _PendingConfirmationController extends _StubOutputConfigurationController {
  bool kept = false;
  bool reverted = false;

  @override
  OutputConfigurationState build() => OutputConfigurationState(
    configuration: DenialOutputConfiguration(
      serial: 1,
      capabilities: _capabilities,
      outputs: _configuration.outputs,
      primaryOutput: _configuration.primaryOutput,
      pendingConfirmation: DenialOutputConfirmation(
        token: 11,
        deadlineUnixMilliseconds:
            DateTime.now().millisecondsSinceEpoch + 60000,
      ),
    ),
    draftOutputs: _configuration.outputs,
    draftPrimaryOutput: _configuration.primaryOutput,
    selectedName: _output.name,
  );

  @override
  Future<bool> keepChanges() async {
    kept = true;
    return true;
  }

  @override
  Future<bool> rollbackChanges() async {
    reverted = true;
    return true;
  }

  @override
  Future<bool> apply() async => false;

  // The host schedules a refresh when it reveals a pending confirmation; the
  // base implementation would touch the uninitialised `_bridge` and rely on a
  // swallowed `LateInitializationError`, so keep it inert here.
  @override
  Future<void> refresh() async {}
}

/// Serves the same topology with a flipped transform, which is not one of the
/// rotation menu choices. This exercises the menu's unmatched-value fallback.
class _FlippedOutputConfigurationController
    extends OutputConfigurationController {
  @override
  OutputConfigurationState build() {
    final outputs = <DenialOutput>[
      _output.copyWith(transform: DenialOutputTransform.flipped),
      _secondOutput,
    ];
    return OutputConfigurationState(
      configuration: DenialOutputConfiguration(
        serial: 1,
        capabilities: _capabilities,
        outputs: outputs,
        primaryOutput: 'DP-1',
      ),
      draftOutputs: outputs,
      draftPrimaryOutput: 'DP-1',
      selectedName: 'DP-1',
    );
  }
}

/// Serves static brightness levels without probing the backlight devices.
class _StubDisplayBrightnessController extends DisplayBrightnessController {
  @override
  DisplayBrightnessState build() => const DisplayBrightnessState(
    levels: <int, double>{0: 0.72},
    loading: <int>{},
  );
}

class _StubNetworkController extends NetworkConnectivityController {
  @override
  NetworkConnectivityState build() => NetworkConnectivityState.initial();
}

class _StubBluetoothController extends BluetoothController {
  @override
  BluetoothState build() => BluetoothState.initial();
}

/// Serves an empty application-audio list without subscribing to the mixer.
class _StubAppAudioController extends AppAudioController {
  @override
  AppAudioState build() => const AppAudioState.initial();

  @override
  void refresh() {}
}

/// Serves static quick settings without starting the brightness/volume
/// propagation timers.
class _StubQuickSettingsController extends QuickSettingsController {
  @override
  QuickSettingsState build() => QuickSettingsState.initial();
}

class _StubUiDevelopmentController extends UiDevelopmentController {
  @override
  DenialUiDevelopmentState build() => DenialUiDevelopmentState.connecting();
}

class _StubWorkspaceSetup implements UiWorkspaceSetupService {
  const _StubWorkspaceSetup();

  @override
  bool get available => true;

  @override
  Future<void> setup() async {}
}
