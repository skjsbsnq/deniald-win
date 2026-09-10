import 'package:denial_dart_shell/l10n/generated/app_localizations.dart';
import 'package:denial_dart_shell/src/models/output_configuration.dart';
import 'package:denial_dart_shell/src/models/suspend_mode.dart';
import 'package:denial_dart_shell/src/platform/denial_bridge.dart';
import 'package:denial_dart_shell/src/settings/settings_application.dart';
import 'package:denial_dart_shell/src/settings/settings_controller.dart';
import 'package:denial_dart_shell/src/settings/shell_settings.dart';
import 'package:denial_dart_shell/src/settings/widgets/settings_navigation.dart';
import 'package:denial_dart_shell/src/state/display_layout.dart';
import 'package:denial_dart_shell/src/state/shell_controller.dart';
import 'package:denial_dart_shell/src/state/suspend_modes.dart';
import 'package:denial_dart_shell/src/state/upower.dart';
import 'package:denial_dart_shell/src/theme/shell_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

/// Logical window size used by the Settings harness.
///
/// Tall enough that the desktop navigation list renders all eighteen
/// destinations without scrolling, so navigation tests can assert that every
/// destination is present rather than only the visible subset.
const Size settingsHarnessWindowSize = Size(1280, 1024);

/// Pumps the real [DenialSettingsApplication] inside a deterministic test
/// environment.
///
/// Three categories of providers are pinned so a Settings surface can be
/// rendered without touching a compositor socket, D-Bus, `/sys`, or the
/// settings file:
///
/// * the platform bridge, replaced by [SettingsTestBridge];
/// * the shell-scene controllers the application reads opportunistically
///   (display layout, output configuration), replaced with static values;
/// * the settings document controller, replaced by
///   [SettingsTestSettingsController], which bypasses `settingsStoreProvider`
///   and therefore also skips `SystemThemePropagation`.
///
/// Any provider a specific test needs can be layered on top through
/// [overrides]. The returned container lets a test drive providers (for
/// example the one-shot [settingsPageOpenRequestProvider]).
Future<ProviderContainer> pumpSettingsApp(
  WidgetTester tester, {
  SettingsPageId initialPage = SettingsPageId.about,
  List<Override> overrides = const <Override>[],
}) async {
  tester.view.physicalSize = settingsHarnessWindowSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final bridge = SettingsTestBridge();
  addTearDown(bridge.close);

  final container = ProviderContainer(
    overrides: <Override>[
      denialBridgeProvider.overrideWithValue(bridge),
      // The real controller retries over a socket and owns a retry timer.
      displayLayoutProvider.overrideWithBuild((ref, controller) => null),
      shellSettingsProvider.overrideWith(SettingsTestSettingsController.new),
      // Battery and suspend-capability reads reach D-Bus and `/sys`; the
      // static fakes keep the pending-timer invariant checkable.
      upowerProvider.overrideWith(SettingsTestUPowerController.new),
      suspendModeCapabilitiesProvider.overrideWith(
        (ref) async => const SuspendModeCapabilities.unavailable(),
      ),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: AnimatedShellTheme(
        data: const ShellThemeData(),
        duration: Duration.zero,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: DenialSettingsApplication(initialPage: initialPage),
        ),
      ),
    ),
  );
  await tester.pump();
  return container;
}

/// A [DenialBridge] that answers every Settings-scope call locally.
class SettingsTestBridge extends DenialBridge {
  /// Output configuration surfaces reach the compositor control socket.
  @override
  Future<DenialOutputConfiguration> readOutputConfiguration() async {
    throw StateError('SettingsTestBridge has no output configuration');
  }

  void close() => dispose();
}

/// Serves default [ShellSettings] without a settings document store.
///
/// Bypassing `settingsStoreProvider` also skips `SystemThemePropagation`,
/// which would shell out to fontconfig and gsettings.
class SettingsTestSettingsController extends ShellSettingsController {
  @override
  ShellSettings build() => const ShellSettings();
}

/// UPower state that never probes the system bus.
class SettingsTestUPowerController extends UPowerController {
  @override
  UPowerState build() => UPowerState.initial().copyWith(loading: false);
}
