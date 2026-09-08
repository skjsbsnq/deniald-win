import 'dart:async';

import 'package:denial_dart_shell/l10n/generated/app_localizations.dart';
import 'package:denial_dart_shell/src/models/battery_status.dart';
import 'package:denial_dart_shell/src/models/display_layout.dart';
import 'package:denial_dart_shell/src/desktop/desktop_shell.dart';
import 'package:denial_dart_shell/src/desktop/desktop_workspace.dart';
import 'package:denial_dart_shell/src/models/denial_window.dart';
import 'package:denial_dart_shell/src/models/system_tray_item.dart';
import 'package:denial_dart_shell/src/platform/denial_bridge.dart';
import 'package:denial_dart_shell/src/settings/settings_controller.dart';
import 'package:denial_dart_shell/src/settings/shell_settings.dart';
import 'package:denial_dart_shell/src/state/bluetooth.dart';
import 'package:denial_dart_shell/src/state/clipboard_tray.dart';
import 'package:denial_dart_shell/src/state/desktop_notifications.dart';
import 'package:denial_dart_shell/src/state/desktop_power_modes.dart';
import 'package:denial_dart_shell/src/state/display_layout.dart';
import 'package:denial_dart_shell/src/state/network_connectivity.dart';
import 'package:denial_dart_shell/src/state/quick_settings.dart';
import 'package:denial_dart_shell/src/state/shell_controller.dart';
import 'package:denial_dart_shell/src/state/shell_state.dart';
import 'package:denial_dart_shell/src/state/system_status.dart';
import 'package:denial_dart_shell/src/state/system_tray.dart';
import 'package:denial_dart_shell/src/widgets/shell_hover_pill.dart';
import 'package:flutter/material.dart';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _testWindow = DenialWindow(
  objectId: 7,
  objectKind: 'xdg',
  surfaceId: 17,
  windowId: 27,
  textureId: 37,
  title: 'Client',
  appId: 'org.example.client',
  width: 300,
  height: 200,
  surfaceX: 0,
  surfaceY: 0,
  surfaceWidth: 300,
  surfaceHeight: 200,
  textureSourceX: 0,
  textureSourceY: 0,
  textureSourceWidth: 300,
  textureSourceHeight: 200,
  geometryX: 100,
  geometryY: 100,
  geometryWidth: 300,
  geometryHeight: 200,
  monitorId: 1,
  transform: 0,
  scale120: 120,
);

/// The test window on monitor 0, so a display-layout-backed shell can match
/// the window to the output that hosts it.
const _testWindowOnMonitor0 = DenialWindow(
  objectId: 7,
  objectKind: 'xdg',
  surfaceId: 17,
  windowId: 27,
  textureId: 37,
  title: 'Client',
  appId: 'org.example.client',
  width: 300,
  height: 200,
  surfaceX: 0,
  surfaceY: 0,
  surfaceWidth: 300,
  surfaceHeight: 200,
  textureSourceX: 0,
  textureSourceY: 0,
  textureSourceWidth: 300,
  textureSourceHeight: 200,
  geometryX: 100,
  geometryY: 100,
  geometryWidth: 300,
  geometryHeight: 200,
  monitorId: 0,
  transform: 0,
  scale120: 120,
);

/// Drives the exact keyboard entry points the compositor dispatches: Super
/// (applications), the dashboard hotkey, and the clipboard hotkey, replayed
/// through the bridge's broadcast stream like the real wire dispatch.
class _SurfaceMutexTestBridge extends DenialBridge {
  final StreamController<DenialShellActionEvent> _actions =
      StreamController<DenialShellActionEvent>.broadcast(sync: true);

  @override
  Stream<DenialShellActionEvent> get shellActions => _actions.stream;

  void emit(DenialShellAction action, {int? monitorId}) => _actions.add(
    DenialShellActionEvent(
      action: action,
      monitorId: monitorId,
      requestId: 0,
      textureId: null,
    ),
  );

  Future<void> close() async {
    await _actions.close();
    dispose();
  }
}

class _SurfaceMutexShellController extends ShellController {
  _SurfaceMutexShellController({this.window = _testWindow});

  final DenialWindow window;

  @override
  ShellState build() {
    return ShellState(
      windows: [window],
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
    _SurfaceMutexTestBridge bridge, {
    DisplayLayout? displayLayout,
    DenialWindow window = _testWindow,
  }) async {
    final container = ProviderContainer(
      overrides: [
        denialBridgeProvider.overrideWithValue(bridge),
        shellControllerProvider.overrideWith(
          () => _SurfaceMutexShellController(window: window),
        ),
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
          (ref, controller) => displayLayout,
        ),
        clockProvider.overrideWith(
          (ref) => Stream<DateTime>.value(DateTime(2026, 9, 8, 14, 30)),
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
    // The workspace needs a window sync so the overview can resolve a target.
    container
        .read(desktopWorkspaceProvider.notifier)
        .syncWindows([window], const Size(1200, 800), 1.0);
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets(
    'Super closes an open tray bubble and opens the launcher in one action',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final bridge = _SurfaceMutexTestBridge();
      addTearDown(bridge.close);
      final container = await pumpShell(tester, bridge);

      container.read(desktopShelfBubblesProvider.notifier).toggleTray();
      await tester.pumpAndSettle();
      expect(container.read(desktopShelfBubblesProvider).trayExpanded, isTrue);

      bridge.emit(DenialShellAction.applications);
      await tester.pumpAndSettle();

      expect(container.read(desktopShelfBubblesProvider).trayExpanded, isFalse);
      expect(container.read(desktopWorkspaceProvider).launcherOpen, isTrue);
    },
  );

  testWidgets(
    'clipboard hotkey closes an open tray bubble and opens the tray',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final bridge = _SurfaceMutexTestBridge();
      addTearDown(bridge.close);
      final container = await pumpShell(tester, bridge);

      container.read(desktopShelfBubblesProvider.notifier).toggleDashboard();
      await tester.pumpAndSettle();
      expect(
        container.read(desktopShelfBubblesProvider).dashboardExpanded,
        isTrue,
      );

      bridge.emit(DenialShellAction.clipboard);
      await tester.pumpAndSettle();

      expect(
        container.read(desktopShelfBubblesProvider).dashboardExpanded,
        isFalse,
      );
      expect(container.read(clipboardTrayProvider).open, isTrue);
    },
  );

  testWidgets(
    'Super while the overview is open closes it and opens the launcher',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final bridge = _SurfaceMutexTestBridge();
      addTearDown(bridge.close);
      final container = await pumpShell(tester, bridge);

      bridge.emit(DenialShellAction.overview);
      await tester.pumpAndSettle();
      expect(container.read(desktopWorkspaceProvider).overviewActive, isTrue);

      bridge.emit(DenialShellAction.applications);
      await tester.pumpAndSettle();

      expect(container.read(desktopWorkspaceProvider).overviewActive, isFalse);
      expect(container.read(desktopWorkspaceProvider).launcherOpen, isTrue);
    },
  );

  testWidgets(
    'dashboard hotkey while the overview is open closes it and opens the dashboard',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final bridge = _SurfaceMutexTestBridge();
      addTearDown(bridge.close);
      final container = await pumpShell(tester, bridge);

      bridge.emit(DenialShellAction.overview);
      await tester.pumpAndSettle();
      expect(container.read(desktopWorkspaceProvider).overviewActive, isTrue);

      bridge.emit(DenialShellAction.dashboard);
      await tester.pumpAndSettle();

      expect(container.read(desktopWorkspaceProvider).overviewActive, isFalse);
      expect(container.read(desktopWorkspaceProvider).dashboardOpen, isTrue);
    },
  );

  testWidgets(
    'entering the overview closes an open tray bubble; it stays closed on exit',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final bridge = _SurfaceMutexTestBridge();
      addTearDown(bridge.close);
      final container = await pumpShell(tester, bridge);

      container.read(desktopShelfBubblesProvider.notifier).toggleTray();
      await tester.pumpAndSettle();
      expect(container.read(desktopShelfBubblesProvider).trayExpanded, isTrue);

      bridge.emit(DenialShellAction.overview);
      await tester.pumpAndSettle();
      expect(container.read(desktopWorkspaceProvider).overviewActive, isTrue);
      expect(container.read(desktopShelfBubblesProvider).trayExpanded, isFalse);

      // Escape closes the overview; the bubble must not reappear.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(container.read(desktopWorkspaceProvider).overviewActive, isFalse);
      expect(container.read(desktopShelfBubblesProvider).trayExpanded, isFalse);
    },
  );

  testWidgets(
    'bubbles, launcher, and clipboard keep their lone toggles working',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final bridge = _SurfaceMutexTestBridge();
      addTearDown(bridge.close);
      final container = await pumpShell(tester, bridge);

      // Super alone toggles the launcher open, then closed.
      bridge.emit(DenialShellAction.applications);
      await tester.pumpAndSettle();
      expect(container.read(desktopWorkspaceProvider).launcherOpen, isTrue);
      bridge.emit(DenialShellAction.applications);
      await tester.pumpAndSettle();
      expect(container.read(desktopWorkspaceProvider).launcherOpen, isFalse);

      // The clipboard hotkey alone toggles the tray open, then closed.
      bridge.emit(DenialShellAction.clipboard);
      await tester.pumpAndSettle();
      expect(container.read(clipboardTrayProvider).open, isTrue);
      bridge.emit(DenialShellAction.clipboard);
      await tester.pumpAndSettle();
      expect(container.read(clipboardTrayProvider).open, isFalse);

      // The two bubbles toggle independently but never coexist: opening one
      // clears the other.
      final bubbles = container.read(desktopShelfBubblesProvider.notifier);
      bubbles.toggleTray();
      expect(container.read(desktopShelfBubblesProvider).trayExpanded, isTrue);
      bubbles.toggleDashboard();
      expect(
        container.read(desktopShelfBubblesProvider).dashboardExpanded,
        isTrue,
      );
      expect(container.read(desktopShelfBubblesProvider).trayExpanded, isFalse);
      bubbles.toggleTray();
      expect(container.read(desktopShelfBubblesProvider).trayExpanded, isTrue);
      expect(
        container.read(desktopShelfBubblesProvider).dashboardExpanded,
        isFalse,
      );
      bubbles.toggleTray();
      expect(container.read(desktopShelfBubblesProvider).trayExpanded, isFalse);
      expect(
        container.read(desktopShelfBubblesProvider).dashboardExpanded,
        isFalse,
      );
    },
  );

  testWidgets(
    'shelf tray button during the overview: first tap exits, second opens',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final bridge = _SurfaceMutexTestBridge();
      addTearDown(bridge.close);
      // A real display layout mounts the shelf, which the overview barrier
      // covers (COR-11): the first tap on the tray button exits the
      // overview, and only the second tap reaches the button itself.
      final container = await pumpShell(
        tester,
        bridge,
        window: _testWindowOnMonitor0,
        displayLayout: const DisplayLayout(
          epoch: 1,
          globalOrigin: Offset.zero,
          logicalSize: Size(1200, 800),
          pixelSize: Size(1200, 800),
          engineScale: 1.0,
          tickerMonitorId: 0,
          systemBarMonitorId: 0,
          systemBarMonitorIds: <int>[0],
          systemBarSide: SystemBarSide.top,
          systemBarThickness: 56.0,
          outputs: <DisplayOutput>[
            DisplayOutput(
              monitorId: 0,
              name: 'default',
              logicalRect: Rect.fromLTWH(0, 0, 1200, 800),
              pixelSize: Size(1200, 800),
              scale: 1.0,
              refreshRate: 60.0,
            ),
          ],
        ),
      );

      // The shelf-tray-button key names the whole unified tray button; its
      // first hover pill is the tray toggle.
      final trayPill = find
          .descendant(
            of: find.byKey(const ValueKey('shelf-tray-button')),
            matching: find.byType(ShellHoverPill),
          )
          .first;
      expect(trayPill, findsOneWidget);

      // Control: without the overview the pill toggles the tray bubble.
      await tester.tap(trayPill);
      await tester.pumpAndSettle();
      expect(container.read(desktopShelfBubblesProvider).trayExpanded, isTrue);
      expect(
        container.read(desktopShelfBubblesProvider).dashboardExpanded,
        isFalse,
      );
      await tester.tap(trayPill);
      await tester.pumpAndSettle();
      expect(container.read(desktopShelfBubblesProvider).trayExpanded, isFalse);

      bridge.emit(DenialShellAction.overview);
      await tester.pumpAndSettle();
      expect(container.read(desktopWorkspaceProvider).overviewActive, isTrue);

      // The overview barrier covers the shelf (COR-11), so the first tap
      // exits the overview instead of reaching the button.
      await tester.tap(trayPill, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(container.read(desktopWorkspaceProvider).overviewActive, isFalse);
      expect(container.read(desktopShelfBubblesProvider).trayExpanded, isFalse);

      // The second tap reaches the button and opens the bubble.
      await tester.tap(trayPill);
      await tester.pumpAndSettle();
      expect(container.read(desktopWorkspaceProvider).overviewActive, isFalse);
      expect(container.read(desktopShelfBubblesProvider).trayExpanded, isTrue);
    },
  );
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
