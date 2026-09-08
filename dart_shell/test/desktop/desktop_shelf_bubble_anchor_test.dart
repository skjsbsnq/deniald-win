import 'dart:async';

import 'package:denial_dart_shell/l10n/generated/app_localizations.dart';
import 'package:denial_dart_shell/src/models/battery_status.dart';
import 'package:denial_dart_shell/src/models/display_layout.dart';
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
import 'package:denial_dart_shell/src/widgets/shell_backdrop_blur.dart';
import 'package:denial_dart_shell/src/widgets/shell_hover_pill.dart';
import 'package:flutter/material.dart';
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
  monitorId: 0,
  transform: 0,
  scale120: 120,
);

/// A two-output atlas: a left and a right 1200x800 output, each hosting its
/// own shelf clone. The ticker picks the left output as the main one.
const _twoOutputLayout = DisplayLayout(
  epoch: 1,
  globalOrigin: Offset.zero,
  logicalSize: Size(2400, 800),
  pixelSize: Size(2400, 800),
  engineScale: 1.0,
  tickerMonitorId: 0,
  systemBarMonitorId: 0,
  systemBarMonitorIds: <int>[0, 1],
  systemBarSide: SystemBarSide.bottom,
  systemBarThickness: 56.0,
  outputs: <DisplayOutput>[
    DisplayOutput(
      monitorId: 0,
      name: 'left',
      logicalRect: Rect.fromLTWH(0, 0, 1200, 800),
      pixelSize: Size(1200, 800),
      scale: 1.0,
      refreshRate: 60.0,
    ),
    DisplayOutput(
      monitorId: 1,
      name: 'right',
      logicalRect: Rect.fromLTWH(1200, 0, 1200, 800),
      pixelSize: Size(1200, 800),
      scale: 1.0,
      refreshRate: 60.0,
    ),
  ],
);

const _singleOutputLayout = DisplayLayout(
  epoch: 1,
  globalOrigin: Offset.zero,
  logicalSize: Size(1200, 800),
  pixelSize: Size(1200, 800),
  engineScale: 1.0,
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
      pixelSize: Size(1200, 800),
      scale: 1.0,
      refreshRate: 60.0,
    ),
  ],
);

/// Drives the dashboard hotkey the compositor dispatches, replayed through
/// the bridge's broadcast stream like the real wire dispatch.
class _BubbleAnchorTestBridge extends DenialBridge {
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

  Future<void> close() async {
    await _actions.close();
    dispose();
  }
}

class _BubbleAnchorShellController extends ShellController {
  _BubbleAnchorShellController({this.foregroundObjectId = 7});

  final int? foregroundObjectId;

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
      foregroundObjectId: foregroundObjectId,
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
    _BubbleAnchorTestBridge bridge, {
    required DisplayLayout displayLayout,
    required Size viewSize,
    int? foregroundObjectId = 7,
  }) async {
    final container = ProviderContainer(
      overrides: [
        denialBridgeProvider.overrideWithValue(bridge),
        shellControllerProvider.overrideWith(
          () => _BubbleAnchorShellController(
            foregroundObjectId: foregroundObjectId,
          ),
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
        // The real identity controller parks a 1-minute periodic timer; a
        // static fake keeps the pending-timer invariant checkable while the
        // dashboard bubble's Info page is mounted.
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
        .syncWindows(const [_testWindow], viewSize, 1.0);
    await tester.pumpAndSettle();
    return container;
  }

  // The tray button's pills are the only hover pills inside a system bar:
  // the first is the tray toggle, the second the clock capsule.
  Finder trayPill(int monitorId) => find
      .descendant(
        of: find.byKey(ValueKey<String>('system-bar-$monitorId')),
        matching: find.byType(ShellHoverPill),
      )
      .first;

  Finder clockPill(int monitorId) => find
      .descendant(
        of: find.byKey(ValueKey<String>('system-bar-$monitorId')),
        matching: find.byType(ShellHoverPill),
      )
      .last;

  // Each bubble subtree has exactly one ShellBackdropBlur: its surface. The
  // closed bubble renders nothing, so the finder names the open one.
  Finder bubbleSurface(String bubbleKey) => find.descendant(
    of: find.byKey(ValueKey<String>(bubbleKey)),
    matching: find.byType(ShellBackdropBlur),
  );

  testWidgets(
    'tray bubble docks to the corner of the output whose shelf opened it',
    (tester) async {
      tester.view.physicalSize = const Size(2400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final bridge = _BubbleAnchorTestBridge();
      addTearDown(bridge.close);
      final container = await pumpShell(
        tester,
        bridge,
        displayLayout: _twoOutputLayout,
        viewSize: const Size(2400, 800),
      );

      // The left shelf clone's tray button opens the bubble on the left
      // output: 8 dp from its right edge, 8 dp above its 56 dp shelf.
      await tester.tap(trayPill(0));
      await tester.pumpAndSettle();
      final leftRect = tester.getRect(
        bubbleSurface('shelf-unified-tray-bubble'),
      );
      expect(leftRect.right, moreOrLessEquals(1200 - 8, epsilon: 0.5));
      expect(leftRect.bottom, moreOrLessEquals(800 - 56 - 8, epsilon: 0.5));

      // Toggling the same button closes it again.
      await tester.tap(trayPill(0));
      await tester.pumpAndSettle();
      expect(container.read(desktopShelfBubblesProvider).trayExpanded, isFalse);

      // The right shelf clone docks the bubble on the right output instead
      // of the global canvas corner.
      await tester.tap(trayPill(1));
      await tester.pumpAndSettle();
      final rightRect = tester.getRect(
        bubbleSurface('shelf-unified-tray-bubble'),
      );
      expect(rightRect.right, moreOrLessEquals(2400 - 8, epsilon: 0.5));
      expect(rightRect.bottom, moreOrLessEquals(800 - 56 - 8, epsilon: 0.5));
      expect(container.read(desktopShelfBubblesProvider).anchorMonitorId, 1);
    },
  );

  testWidgets(
    'dashboard panel docks to the corner of the output whose shelf opened it',
    (tester) async {
      tester.view.physicalSize = const Size(2400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final bridge = _BubbleAnchorTestBridge();
      addTearDown(bridge.close);
      final container = await pumpShell(
        tester,
        bridge,
        displayLayout: _twoOutputLayout,
        viewSize: const Size(2400, 800),
      );

      // The panel is fully docked: 420x(800-56-24) at the output's corner.
      await tester.tap(clockPill(0));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(bubbleSurface('shelf-unified-dashboard-panel')),
        rectMoreOrLessEquals(
          const Rect.fromLTRB(1200 - 8 - 420, 16, 1200 - 8, 800 - 56 - 8),
          epsilon: 0.5,
        ),
      );

      // The clock capsule toggles, so re-anchoring means closing on one shelf
      // and opening on the other: the same single panel instance then docks
      // to the right output's corner instead of the global canvas corner.
      await tester.tap(clockPill(0));
      await tester.pumpAndSettle();
      await tester.tap(clockPill(1));
      await tester.pumpAndSettle();
      expect(
        container.read(desktopShelfBubblesProvider).dashboardExpanded,
        isTrue,
      );
      expect(
        tester.getRect(bubbleSurface('shelf-unified-dashboard-panel')),
        rectMoreOrLessEquals(
          const Rect.fromLTRB(2400 - 8 - 420, 16, 2400 - 8, 800 - 56 - 8),
          epsilon: 0.5,
        ),
      );
    },
  );

  testWidgets(
    'dashboard hotkey anchors the bubble to the focused window output',
    (tester) async {
      tester.view.physicalSize = const Size(2400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final bridge = _BubbleAnchorTestBridge();
      addTearDown(bridge.close);
      final container = await pumpShell(
        tester,
        bridge,
        displayLayout: _twoOutputLayout,
        viewSize: const Size(2400, 800),
      );

      // Move the focused window to the right output; the keyboard-opened
      // bubble follows it instead of the primary output. The second sync
      // carries a newer snapshot sequence, which is what lets the workspace
      // adopt the window's new monitor.
      container
          .read(desktopWorkspaceProvider.notifier)
          .syncWindows(
            const [_windowOnMonitor1],
            const Size(2400, 800),
            1.0,
            snapshotSequence: 2,
          );
      await tester.pumpAndSettle();

      bridge.emitDashboard();
      await tester.pumpAndSettle();
      expect(
        container.read(desktopShelfBubblesProvider).dashboardExpanded,
        isTrue,
      );
      expect(container.read(desktopShelfBubblesProvider).anchorMonitorId, 1);
      expect(
        tester.getRect(bubbleSurface('shelf-unified-dashboard-panel')),
        rectMoreOrLessEquals(
          const Rect.fromLTRB(2400 - 8 - 420, 16, 2400 - 8, 800 - 56 - 8),
          epsilon: 0.5,
        ),
      );
    },
  );

  testWidgets(
    'dashboard hotkey without a focused window anchors to the main output',
    (tester) async {
      tester.view.physicalSize = const Size(2400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final bridge = _BubbleAnchorTestBridge();
      addTearDown(bridge.close);
      final container = await pumpShell(
        tester,
        bridge,
        displayLayout: _twoOutputLayout,
        viewSize: const Size(2400, 800),
        foregroundObjectId: null,
      );

      bridge.emitDashboard();
      await tester.pumpAndSettle();
      expect(
        container.read(desktopShelfBubblesProvider).anchorMonitorId,
        isNull,
      );
      expect(
        tester.getRect(bubbleSurface('shelf-unified-dashboard-panel')),
        rectMoreOrLessEquals(
          const Rect.fromLTRB(1200 - 8 - 420, 16, 1200 - 8, 800 - 56 - 8),
          epsilon: 0.5,
        ),
      );
    },
  );

  testWidgets('single output keeps docking to the same corner as before', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final bridge = _BubbleAnchorTestBridge();
    addTearDown(bridge.close);
    await pumpShell(
      tester,
      bridge,
      displayLayout: _singleOutputLayout,
      viewSize: const Size(1200, 800),
    );

    // The pre-A07 formula: right 8 dp, bottom shelfHeight + 8 dp in the
    // full scene — the anchoring output equals the whole canvas here.
    await tester.tap(trayPill(0));
    await tester.pumpAndSettle();
    final rect = tester.getRect(bubbleSurface('shelf-unified-tray-bubble'));
    expect(rect.right, moreOrLessEquals(1200 - 8, epsilon: 0.5));
    expect(rect.bottom, moreOrLessEquals(800 - 56 - 8, epsilon: 0.5));
    expect(rect.left, moreOrLessEquals(rect.right - 420, epsilon: 0.5));
  });

  group('desktopShelfBubbleAnchorGeometry', () {
    const bars = <({int monitorId, Rect rect, SystemBarSide side})>[
      (
        monitorId: 0,
        rect: Rect.fromLTWH(0, 744, 1200, 56),
        side: SystemBarSide.bottom,
      ),
      (
        monitorId: 1,
        rect: Rect.fromLTWH(1200, 744, 1200, 56),
        side: SystemBarSide.bottom,
      ),
    ];

    test('layouts without monitor identity keep the canvas', () {
      final anchor = desktopShelfBubbleAnchorGeometry(
        anchorMonitorId: null,
        displayLayout: null,
        systemBars: const [],
        viewSize: const Size(1200, 800),
      );
      expect(anchor.outputRect, const Rect.fromLTWH(0, 0, 1200, 800));
      // ShelfLayer.defaultThickness.
      expect(anchor.shelfHeight, 56.0);
    });

    test('anchor output wins with its own shelf height', () {
      // A 60 dp tall second output clamps its shelf to 30 dp, distinct from
      // the left clone's 56 dp.
      const layout = DisplayLayout(
        epoch: 1,
        globalOrigin: Offset.zero,
        logicalSize: Size(1260, 800),
        pixelSize: Size(1260, 800),
        engineScale: 1.0,
        tickerMonitorId: 0,
        systemBarMonitorId: 0,
        systemBarMonitorIds: <int>[0, 1],
        systemBarSide: SystemBarSide.bottom,
        systemBarThickness: 56.0,
        outputs: <DisplayOutput>[
          DisplayOutput(
            monitorId: 0,
            name: 'left',
            logicalRect: Rect.fromLTWH(0, 0, 1200, 800),
            pixelSize: Size(1200, 800),
            scale: 1.0,
            refreshRate: 60.0,
          ),
          DisplayOutput(
            monitorId: 1,
            name: 'short',
            logicalRect: Rect.fromLTWH(1200, 740, 60, 60),
            pixelSize: Size(60, 60),
            scale: 1.0,
            refreshRate: 60.0,
          ),
        ],
      );
      final anchor = desktopShelfBubbleAnchorGeometry(
        anchorMonitorId: 1,
        displayLayout: layout,
        systemBars: const [
          (
            monitorId: 0,
            rect: Rect.fromLTWH(0, 744, 1200, 56),
            side: SystemBarSide.bottom,
          ),
          (
            monitorId: 1,
            rect: Rect.fromLTWH(1200, 770, 60, 30),
            side: SystemBarSide.bottom,
          ),
        ],
        viewSize: const Size(1260, 800),
      );
      expect(anchor.outputRect, const Rect.fromLTWH(1200, 740, 60, 60));
      expect(anchor.shelfHeight, 30.0);
    });

    test('stale anchor and null anchor fall back to the main output', () {
      final stale = desktopShelfBubbleAnchorGeometry(
        anchorMonitorId: 9,
        displayLayout: _twoOutputLayout,
        systemBars: bars,
        viewSize: const Size(2400, 800),
      );
      expect(stale.outputRect, const Rect.fromLTWH(0, 0, 1200, 800));
      expect(stale.shelfHeight, 56.0);

      final unanchored = desktopShelfBubbleAnchorGeometry(
        anchorMonitorId: null,
        displayLayout: _twoOutputLayout,
        systemBars: bars,
        viewSize: const Size(2400, 800),
      );
      expect(unanchored.outputRect, const Rect.fromLTWH(0, 0, 1200, 800));
      expect(unanchored.shelfHeight, 56.0);
    });
  });
}

const _windowOnMonitor1 = DenialWindow(
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
  geometryX: 1300,
  geometryY: 100,
  geometryWidth: 300,
  geometryHeight: 200,
  monitorId: 1,
  transform: 0,
  scale120: 120,
);

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
