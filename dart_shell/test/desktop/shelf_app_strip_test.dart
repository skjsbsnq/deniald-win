import 'package:denial_dart_shell/src/desktop/desktop_workspace.dart';
import 'package:denial_dart_shell/src/desktop/shelf/shelf_app_strip.dart';
import 'package:denial_dart_shell/src/launcher/controllers/home_grid_controller.dart';
import 'package:denial_dart_shell/src/launcher/models/home_grid_item.dart';
import 'package:denial_dart_shell/src/local_apps/local_flutter_application.dart';
import 'package:denial_dart_shell/src/models/denial_window.dart';
import 'package:denial_dart_shell/src/platform/denial_bridge.dart';
import 'package:denial_dart_shell/src/state/pinned_apps.dart';
import 'package:denial_dart_shell/src/state/shell_controller.dart';
import 'package:denial_dart_shell/src/state/shell_state.dart';
import 'package:denial_dart_shell/src/theme/shell_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _firstWindow = DenialWindow(
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
  geometryX: 10,
  geometryY: 20,
  geometryWidth: 300,
  geometryHeight: 200,
  monitorId: 1,
  transform: 0,
  scale120: 120,
);

const _secondWindow = DenialWindow(
  objectId: 8,
  objectKind: 'xdg',
  surfaceId: 18,
  windowId: 28,
  textureId: 38,
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
  geometryX: 330,
  geometryY: 20,
  geometryWidth: 300,
  geometryHeight: 200,
  monitorId: 1,
  transform: 0,
  scale120: 120,
);

void main() {
  testWidgets('shelf press cycles activate, minimize, and re-activate', (
    tester,
  ) async {
    final bridge = _ShelfTestBridge();
    addTearDown(bridge.dispose);
    final shell = _ShelfShellController(
      bridge,
      windows: const [_firstWindow],
    );
    await tester.pumpWidget(_stripScene(bridge, shell));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ShelfAppStrip)),
    );
    container
        .read(desktopWorkspaceProvider.notifier)
        .syncWindows(
          const [_firstWindow],
          const Size(800, 600),
          1,
          snapshotSequence: 1,
        );
    await tester.pump();

    final button = find.byKey(
      const ValueKey<String>('shelf-app-org.example.client'),
    );

    // Press 1: not foreground yet, so the press activates and focuses.
    await tester.tap(button);
    await tester.pump();
    expect(bridge.focused, <int>[27]);
    expect(bridge.minimized, isEmpty);
    expect(
      container.read(desktopWorkspaceProvider).placements[7]!.minimized,
      isFalse,
    );
    expect(container.read(shellControllerProvider).foregroundObjectId, 7);

    // Press 2: foreground, so the press minimizes locally and through the
    // protocol.
    await tester.tap(button);
    await tester.pump();
    expect(bridge.minimized, <int>[27]);
    expect(
      container.read(desktopWorkspaceProvider).placements[7]!.minimized,
      isTrue,
    );
    // The stale foreground survives until the native minimize echo arrives.
    expect(container.read(shellControllerProvider).foregroundObjectId, 7);

    // The coordinator clears the stale foreground when the echoed minimize
    // action event arrives.
    container
        .read(shellControllerProvider.notifier)
        .releaseWindowFocus(_firstWindow);
    await tester.pump();
    expect(container.read(shellControllerProvider).foregroundObjectId, isNull);

    // Press 3: without the stale foreground the press activates again
    // instead of wedging on an already-minimized window.
    await tester.tap(button);
    await tester.pump();
    expect(bridge.focused, <int>[27, 27]);
    expect(bridge.minimized, <int>[27]);
    expect(
      container.read(desktopWorkspaceProvider).placements[7]!.minimized,
      isFalse,
    );
  });

  testWidgets('shelf press cycles between sibling windows', (tester) async {
    final bridge = _ShelfTestBridge();
    addTearDown(bridge.dispose);
    final shell = _ShelfShellController(bridge, foregroundObjectId: 7);
    await tester.pumpWidget(_stripScene(bridge, shell));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ShelfAppStrip)),
    );
    container
        .read(desktopWorkspaceProvider.notifier)
        .syncWindows(
          const [_firstWindow, _secondWindow],
          const Size(800, 600),
          1,
          snapshotSequence: 1,
        );
    await tester.pump();

    final button = find.byKey(
      const ValueKey<String>('shelf-app-org.example.client'),
    );

    await tester.tap(button);
    await tester.pump();
    expect(bridge.focused, <int>[28]);
    expect(bridge.minimized, isEmpty);

    await tester.tap(button);
    await tester.pump();
    expect(bridge.focused, <int>[28, 27]);
    expect(bridge.minimized, isEmpty);
  });
}

Widget _stripScene(DenialBridge bridge, ShellController shell) {
  return ProviderScope(
    overrides: [
      denialBridgeProvider.overrideWithValue(bridge),
      shellControllerProvider.overrideWith(() => shell),
      pinnedAppsProvider.overrideWith(_ShelfPinnedApps.new),
      homeGridControllerProvider.overrideWith(_ShelfHomeGrid.new),
      localFlutterApplicationRegistryProvider.overrideWithValue(
        LocalFlutterApplicationRegistry(const <LocalFlutterApplication>[]),
      ),
    ],
    child: MaterialApp(
      home: ShellTheme(
        data: const ShellThemeData(),
        child: const Center(child: ShelfAppStrip()),
      ),
    ),
  );
}

class _ShelfTestBridge extends DenialBridge {
  final List<int> minimized = <int>[];
  final List<int> focused = <int>[];

  @override
  void minimizeWindow(DenialWindow window) => minimized.add(window.windowId);

  @override
  void focusWindow(DenialWindow window) => focused.add(window.windowId);
}

class _ShelfShellController extends ShellController {
  _ShelfShellController(
    this.bridge, {
    this.foregroundObjectId,
    this.windows = const <DenialWindow>[_firstWindow, _secondWindow],
  });

  final DenialBridge bridge;
  final int? foregroundObjectId;
  final List<DenialWindow> windows;

  @override
  ShellState build() {
    return ShellState(
      windows: windows,
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

  @override
  void focusWindow(DenialWindow window) {
    if (!window.isUserApp) {
      return;
    }
    bridge.focusWindow(window);
    state = state.copyWith(foregroundObjectId: window.objectId);
  }
}

class _ShelfPinnedApps extends PinnedAppsController {
  @override
  List<String> build() => const <String>[];
}

class _ShelfHomeGrid extends HomeGridController {
  @override
  Future<HomeGridState> build() async =>
      HomeGridState(slots: <HomeGridItem?>[]);
}
