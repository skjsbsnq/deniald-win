import 'dart:async';

import 'package:denial_dart_shell/l10n/generated/app_localizations.dart';
import 'package:denial_dart_shell/src/desktop/desktop_shell.dart';
import 'package:denial_dart_shell/src/desktop/desktop_workspace.dart';
import 'package:denial_dart_shell/src/local_apps/local_flutter_window_host.dart';
import 'package:denial_dart_shell/src/models/battery_status.dart';
import 'package:denial_dart_shell/src/models/display_layout.dart';
import 'package:denial_dart_shell/src/models/denial_window.dart';
import 'package:denial_dart_shell/src/models/system_tray_item.dart';
import 'package:denial_dart_shell/src/platform/denial_bridge.dart';
import 'package:denial_dart_shell/src/settings/settings_controller.dart';
import 'package:denial_dart_shell/src/settings/shell_settings.dart';
import 'package:denial_dart_shell/src/state/bluetooth.dart';
import 'package:denial_dart_shell/src/state/desktop_notifications.dart';
import 'package:denial_dart_shell/src/state/desktop_power_modes.dart';
import 'package:denial_dart_shell/src/state/display_layout.dart';
import 'package:denial_dart_shell/src/state/network_connectivity.dart';
import 'package:denial_dart_shell/src/state/quick_settings.dart';
import 'package:denial_dart_shell/src/state/shell_controller.dart';
import 'package:denial_dart_shell/src/state/shell_state.dart';
import 'package:denial_dart_shell/src/state/system_identity.dart';
import 'package:denial_dart_shell/src/state/system_status.dart';
import 'package:denial_dart_shell/src/state/system_tray.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// An embedded local Flutter application whose committed content rect,
/// 100,100 -> 401,301, lands off the device pixel grid at a 1.5 ratio:
/// 401 * 1.5 = 601.5 and 301 * 1.5 = 451.5 both round up, so the aligned
/// content area is a third of a logical pixel larger per axis than the raw
/// placement size. Before B04 the app laid out to the raw size and a
/// BoxFit.fill stretched it by ~1.0011/1.0017 independently per axis.
const _localFlutterWindow = DenialWindow(
  objectId: 7,
  objectKind: 'xdg',
  surfaceId: 17,
  windowId: 27,
  textureId: 37,
  title: 'Embedded',
  appId: 'org.example.embedded',
  width: 301,
  height: 201,
  surfaceX: 0,
  surfaceY: 0,
  surfaceWidth: 301,
  surfaceHeight: 201,
  textureSourceX: 0,
  textureSourceY: 0,
  textureSourceWidth: 301,
  textureSourceHeight: 201,
  geometryX: 100,
  geometryY: 100,
  geometryWidth: 301,
  geometryHeight: 201,
  monitorId: 0,
  transform: 0,
  scale120: 180,
  contentKind: DenialWindowContentKind.localFlutter,
);

/// The same window after an off-grid resize to 403x203: 503 * 1.5 = 754.5
/// and 303 * 1.5 = 454.5 both round up as well.
const _resizedLocalFlutterWindow = DenialWindow(
  objectId: 7,
  objectKind: 'xdg',
  surfaceId: 17,
  windowId: 27,
  textureId: 37,
  title: 'Embedded',
  appId: 'org.example.embedded',
  width: 403,
  height: 203,
  surfaceX: 0,
  surfaceY: 0,
  surfaceWidth: 403,
  surfaceHeight: 203,
  textureSourceX: 0,
  textureSourceY: 0,
  textureSourceWidth: 403,
  textureSourceHeight: 203,
  geometryX: 100,
  geometryY: 100,
  geometryWidth: 403,
  geometryHeight: 203,
  monitorId: 0,
  transform: 0,
  scale120: 180,
  contentKind: DenialWindowContentKind.localFlutter,
);

/// A 1200x800 logical output behind a 1.5 device pixel ratio.
const _fractionalScaleLayout = DisplayLayout(
  epoch: 1,
  globalOrigin: Offset.zero,
  logicalSize: Size(1200, 800),
  pixelSize: Size(1800, 1200),
  engineScale: 1.5,
  tickerMonitorId: 0,
  systemBarMonitorId: 0,
  systemBarMonitorIds: <int>[0],
  systemBarSide: SystemBarSide.bottom,
  systemBarThickness: 56.0,
  outputs: <DisplayOutput>[
    DisplayOutput(
      monitorId: 0,
      name: 'default',
      logicalRect: Rect.fromLTWH(0, 0, 1200, 800),
      pixelSize: Size(1800, 1200),
      scale: 1.5,
      refreshRate: 60.0,
    ),
  ],
);

class _LocalWindowTestBridge extends DenialBridge {
  final StreamController<DenialShellActionEvent> _actions =
      StreamController<DenialShellActionEvent>.broadcast(sync: true);

  @override
  Stream<DenialShellActionEvent> get shellActions => _actions.stream;

  Future<void> close() async {
    await _actions.close();
    dispose();
  }
}

class _LocalWindowShellController extends ShellController {
  @override
  ShellState build() {
    return ShellState(
      windows: const <DenialWindow>[_localFlutterWindow],
      windowSnapshotSequence: 1,
      overviewVisible: false,
      gestureDrag: Offset.zero,
      quickSettingsVisible: false,
      quickSettingsDrag: Offset.zero,
      quickSettingsDragActive: false,
      edgePanelVisible: false,
      edgePanelDrag: Offset.zero,
      edgePanelDragActive: false,
      edgePanelViewportScroll: 0.0,
      locked: false,
      lockLayerVisible: false,
      foregroundObjectId: 7,
      launchingObjectId: null,
      launchRequest: null,
      homeTransitionActive: false,
    );
  }
}

class _ShelfSettingsController extends ShellSettingsController {
  @override
  ShellSettings build() {
    return const ShellSettings(
      layout: ShellLayoutSettings(useChromeOsShelf: true),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> pumpShell(
    WidgetTester tester,
    _LocalWindowTestBridge bridge,
  ) async {
    tester.view.physicalSize = const Size(1800, 1200);
    tester.view.devicePixelRatio = 1.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer(
      overrides: [
        denialBridgeProvider.overrideWithValue(bridge),
        shellControllerProvider.overrideWith(_LocalWindowShellController.new),
        shellSettingsProvider.overrideWith(_ShelfSettingsController.new),
        // The real controllers reach into host sockets and periodic timers;
        // static fakes keep the pending-timer invariant checkable.
        quickSettingsProvider.overrideWith(_FakeQuickSettings.new),
        networkConnectivityProvider.overrideWith(_FakeNetwork.new),
        bluetoothProvider.overrideWith(_FakeBluetooth.new),
        batteryProvider.overrideWith(_FakeBattery.new),
        desktopNotificationsProvider.overrideWith(_FakeNotifications.new),
        systemTrayProvider.overrideWith(_FakeSystemTray.new),
        desktopPowerModesProvider.overrideWith(_FakePowerModes.new),
        displayLayoutProvider.overrideWithBuild(
          (ref, controller) => _fractionalScaleLayout,
        ),
        systemIdentityProvider.overrideWith(_FakeSystemIdentity.new),
        clockProvider.overrideWith(
          (ref) => Stream<DateTime>.value(DateTime(2026, 9, 9, 14, 30)),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: const DesktopShell(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // The workspace needs a window sync so the shell has a scene to manage.
    container
        .read(desktopWorkspaceProvider.notifier)
        .syncWindows(const [_localFlutterWindow], const Size(1200, 800), 1.5);
    await tester.pumpAndSettle();
    return container;
  }

  Finder hostFittedBox() => find.ancestor(
    of: find.byType(LocalFlutterWindowHost),
    matching: find.byType(FittedBox),
  );

  testWidgets(
    'embedded app lays out to the aligned content area at exactly 1:1',
    (tester) async {
      final bridge = _LocalWindowTestBridge();
      addTearDown(bridge.close);
      await pumpShell(tester, bridge);

      final host = find.byType(LocalFlutterWindowHost);
      expect(host, findsOneWidget);
      expect(hostFittedBox(), findsOneWidget);
      // The transient clamp must stay uniform: a fill would stretch x and y
      // independently whenever the committed geometry and the aligned frame
      // disagree, distorting every glyph in the app.
      expect(tester.widget<FittedBox>(hostFittedBox()).fit, BoxFit.contain);

      // The app lays out to the aligned area, not the raw 301x201 rect the
      // placement reports: round(601.5) = 602 and round(451.5) = 452.
      final hostSize = tester.getSize(host);
      expect(hostSize.width, closeTo(602 / 1.5 - 100, 0.001));
      expect(hostSize.height, closeTo(452 / 1.5 - 100, 0.001));

      // Layout size equals the available content area on both axes, so the
      // steady state applies no scale at all rather than a uniform one.
      final fittedSize = tester.getSize(hostFittedBox());
      expect(fittedSize.width, closeTo(hostSize.width, 0.001));
      expect(fittedSize.height, closeTo(hostSize.height, 0.001));
    },
  );

  testWidgets('an off-grid resize settles back to 1:1', (tester) async {
    final bridge = _LocalWindowTestBridge();
    addTearDown(bridge.close);
    final container = await pumpShell(tester, bridge);

    // Grow the committed geometry to another off-grid rect: round(754.5) =
    // 755 and round(454.5) = 455. The second sync carries a newer snapshot
    // sequence, which is what lets the workspace adopt the new geometry.
    container
        .read(desktopWorkspaceProvider.notifier)
        .syncWindows(
          const [_resizedLocalFlutterWindow],
          const Size(1200, 800),
          1.5,
          snapshotSequence: 2,
        );
    await tester.pumpAndSettle();

    final host = find.byType(LocalFlutterWindowHost);
    final hostSize = tester.getSize(host);
    expect(hostSize.width, closeTo(755 / 1.5 - 100, 0.001));
    expect(hostSize.height, closeTo(455 / 1.5 - 100, 0.001));
    final fittedSize = tester.getSize(hostFittedBox());
    expect(fittedSize.width, closeTo(hostSize.width, 0.001));
    expect(fittedSize.height, closeTo(hostSize.height, 0.001));
  });
}

class _FakeQuickSettings extends QuickSettingsController {
  @override
  QuickSettingsState build() => QuickSettingsState.initial();
}

class _FakeNetwork extends NetworkConnectivityController {
  @override
  NetworkConnectivityState build() =>
      NetworkConnectivityState.initial().copyWith(initializing: false);
}

class _FakeBluetooth extends BluetoothController {
  @override
  BluetoothState build() =>
      BluetoothState.initial().copyWith(initializing: false);
}

class _FakeBattery extends BatteryController {
  @override
  BatteryStatus build() =>
      const BatteryStatus(capacity: 87, charging: false, full: true);
}

class _FakeNotifications extends DesktopNotificationsController {
  @override
  DesktopNotificationsState build() => const DesktopNotificationsState();
}

class _FakeSystemTray extends SystemTrayController {
  @override
  List<SystemTrayItem> build() => const <SystemTrayItem>[];
}

class _FakePowerModes extends DesktopPowerModesController {
  @override
  DesktopPowerModesState build() => DesktopPowerModesState.initial();

  @override
  Future<void> refreshIfStale() async {}
}

class _FakeSystemIdentity extends SystemIdentityController {
  @override
  SystemIdentityState build() => const SystemIdentityState();
}
