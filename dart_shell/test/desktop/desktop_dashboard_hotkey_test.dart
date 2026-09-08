import 'dart:async';

import 'package:denial_dart_shell/l10n/generated/app_localizations.dart';
import 'package:denial_dart_shell/src/models/battery_status.dart';
import 'package:denial_dart_shell/src/models/denial_window.dart';
import 'package:denial_dart_shell/src/models/system_tray_item.dart';
import 'package:denial_dart_shell/src/desktop/desktop_shell.dart';
import 'package:denial_dart_shell/src/desktop/desktop_workspace.dart';
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
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// Drives the dashboard hotkey the compositor dispatches, replayed through
/// the bridge's broadcast stream like the real wire dispatch.
class _DashboardHotkeyBridge extends DenialBridge {
  final StreamController<DenialShellActionEvent> _actions =
      StreamController<DenialShellActionEvent>.broadcast(sync: true);

  @override
  Stream<DenialShellActionEvent> get shellActions => _actions.stream;

  void emitDashboard() => _actions.add(
    DenialShellActionEvent(
      action: DenialShellAction.dashboard,
      monitorId: null,
      requestId: 0,
      textureId: null,
    ),
  );

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

class _DashboardHotkeyShellController extends ShellController {
  @override
  ShellState build() {
    return ShellState(
      windows: const <DenialWindow>[_testWindow],
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

class _ShelfLayoutSettingsController extends ShellSettingsController {
  @override
  ShellSettings build() {
    return const ShellSettings(
      layout: ShellLayoutSettings(useChromeOsShelf: true),
    );
  }
}

class _LegacyLayoutSettingsController extends ShellSettingsController {
  @override
  ShellSettings build() {
    return const ShellSettings(
      layout: ShellLayoutSettings(useChromeOsShelf: false),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> pumpShell(
    WidgetTester tester,
    _DashboardHotkeyBridge bridge, {
    required ShellSettingsController settingsController,
  }) async {
    final container = ProviderContainer(
      overrides: [
        denialBridgeProvider.overrideWithValue(bridge),
        shellControllerProvider.overrideWith(
          () => _DashboardHotkeyShellController(),
        ),
        shellSettingsProvider.overrideWith(() => settingsController),
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
          (ref, controller) => null,
        ),
        // The real identity controller parks a 1-minute periodic timer that
        // trips the pending-timer invariant at teardown; a static fake keeps
        // the dashboard bubble content deterministic.
        systemIdentityProvider.overrideWith(_FakeSystemIdentity.new),
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
    // The workspace needs a window sync so the shell has a scene to manage.
    container
        .read(desktopWorkspaceProvider.notifier)
        .syncWindows(const [_testWindow], const Size(1200, 800), 1.0);
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets(
    'shelf mode: dashboard hotkey toggles the unified dashboard bubble',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final bridge = _DashboardHotkeyBridge();
      addTearDown(bridge.close);
      final container = await pumpShell(
        tester,
        bridge,
        settingsController: _ShelfLayoutSettingsController(),
      );

      // The first press expands the unified dashboard bubble, matching the
      // clock button's toggle semantics.
      bridge.emitDashboard();
      await tester.pumpAndSettle();
      expect(
        container.read(desktopShelfBubblesProvider).dashboardExpanded,
        isTrue,
      );
      // The shelf path must not drive the legacy panel state machine.
      expect(container.read(desktopWorkspaceProvider).panel, DesktopPanel.none);

      // The second press collapses it.
      bridge.emitDashboard();
      await tester.pumpAndSettle();
      expect(
        container.read(desktopShelfBubblesProvider).dashboardExpanded,
        isFalse,
      );
    },
  );

  testWidgets(
    'shelf mode: dashboard hotkey closes an open tray bubble (mutual exclusion)',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final bridge = _DashboardHotkeyBridge();
      addTearDown(bridge.close);
      final container = await pumpShell(
        tester,
        bridge,
        settingsController: _ShelfLayoutSettingsController(),
      );

      container.read(desktopShelfBubblesProvider.notifier).toggleTray();
      await tester.pumpAndSettle();
      expect(container.read(desktopShelfBubblesProvider).trayExpanded, isTrue);

      bridge.emitDashboard();
      await tester.pumpAndSettle();
      expect(
        container.read(desktopShelfBubblesProvider).trayExpanded,
        isFalse,
      );
      expect(
        container.read(desktopShelfBubblesProvider).dashboardExpanded,
        isTrue,
      );
    },
  );

  testWidgets(
    'shelf mode: dashboard hotkey while the overview is open closes it and '
    'expands the bubble',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final bridge = _DashboardHotkeyBridge();
      addTearDown(bridge.close);
      final container = await pumpShell(
        tester,
        bridge,
        settingsController: _ShelfLayoutSettingsController(),
      );

      // Enter the overview through the shell action, as the overview hotkey
      // does; the shell resolves the target monitor from the window list.
      bridge.emit(DenialShellAction.overview);
      await tester.pumpAndSettle();
      expect(container.read(desktopWorkspaceProvider).overviewActive, isTrue);

      bridge.emitDashboard();
      await tester.pumpAndSettle();
      expect(container.read(desktopWorkspaceProvider).overviewActive, isFalse);
      expect(
        container.read(desktopShelfBubblesProvider).dashboardExpanded,
        isTrue,
      );
    },
  );

  testWidgets(
    'non-shelf mode: dashboard hotkey keeps driving the legacy panel',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final bridge = _DashboardHotkeyBridge();
      addTearDown(bridge.close);
      final container = await pumpShell(
        tester,
        bridge,
        settingsController: _LegacyLayoutSettingsController(),
      );

      bridge.emitDashboard();
      await tester.pumpAndSettle();
      expect(
        container.read(desktopWorkspaceProvider).dashboardOpen,
        isTrue,
      );
      // The legacy path must not touch the shelf bubble state.
      expect(
        container.read(desktopShelfBubblesProvider).dashboardExpanded,
        isFalse,
      );

      bridge.emitDashboard();
      await tester.pumpAndSettle();
      expect(
        container.read(desktopWorkspaceProvider).dashboardOpen,
        isFalse,
      );
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

class _FakeSystemIdentity extends SystemIdentityController {
  @override
  SystemIdentityState build() => const SystemIdentityState();
}
