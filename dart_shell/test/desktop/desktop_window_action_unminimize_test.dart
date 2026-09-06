import 'dart:async';

import 'package:denial_dart_shell/src/desktop/desktop_window_coordinator.dart';
import 'package:denial_dart_shell/src/desktop/desktop_workspace.dart';
import 'package:denial_dart_shell/src/models/denial_window.dart';
import 'package:denial_dart_shell/src/models/denial_window_event.dart';
import 'package:denial_dart_shell/src/platform/denial_bridge.dart';
import 'package:denial_dart_shell/src/state/shell_controller.dart';
import 'package:denial_dart_shell/src/state/shell_state.dart';
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
  geometryX: 10,
  geometryY: 20,
  geometryWidth: 300,
  geometryHeight: 200,
  monitorId: 1,
  transform: 0,
  scale120: 120,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('unminimize echo keeps a maximized window maximized', () {
    final bridge = _WindowActionTestBridge();
    addTearDown(bridge.close);
    final container = ProviderContainer.test(
      overrides: [
        denialBridgeProvider.overrideWithValue(bridge),
        shellControllerProvider.overrideWith(
          () => _WindowActionShellController(foregroundObjectId: 7),
        ),
      ],
    );
    addTearDown(container.dispose);
    final workspace = container.read(desktopWorkspaceProvider.notifier);
    workspace.syncWindows(
      const [_testWindow],
      const Size(1200, 800),
      1,
      snapshotSequence: 1,
    );
    workspace.maximize(7, bounds: const Rect.fromLTWH(0, 0, 1200, 744));
    expect(
      container.read(desktopWorkspaceProvider).placements[7]!.maximized,
      isTrue,
    );

    // Shelf/switcher reactivation of a minimized window: the local
    // activation clears the minimized flag before the native echo arrives…
    workspace.minimize(7);
    workspace.activate(7);
    expect(
      container.read(desktopWorkspaceProvider).placements[7]!.minimized,
      isFalse,
    );
    expect(
      container.read(desktopWorkspaceProvider).placements[7]!.maximized,
      isTrue,
    );

    // …and the echo that then arrives is Unminimize (the activation echo for
    // a window leaving the minimized set), not Restore. It must leave the
    // maximized state intact instead of falling into the restore branch that
    // unmaximizes the window.
    bridge.emitWindowEvent(
      DenialWindowActionEvent(
        windowId: 27,
        action: DenialWindowAction.unminimize,
      ),
    );

    final placement = container.read(desktopWorkspaceProvider).placements[7]!;
    expect(placement.minimized, isFalse);
    expect(placement.maximized, isTrue);
  });

  test('restore echo still unmaximizes a non-minimized window', () {
    final bridge = _WindowActionTestBridge();
    addTearDown(bridge.close);
    final container = ProviderContainer.test(
      overrides: [
        denialBridgeProvider.overrideWithValue(bridge),
        shellControllerProvider.overrideWith(
          () => _WindowActionShellController(foregroundObjectId: 7),
        ),
      ],
    );
    addTearDown(container.dispose);
    // Materialize the coordinator so its bridge subscription is live before
    // the events are emitted.
    container.read(desktopWindowCoordinatorProvider);
    final workspace = container.read(desktopWorkspaceProvider.notifier);
    workspace.syncWindows(
      const [_testWindow],
      const Size(1200, 800),
      1,
      snapshotSequence: 1,
    );
    workspace.maximize(7, bounds: const Rect.fromLTWH(0, 0, 1200, 744));
    expect(
      container.read(desktopWorkspaceProvider).placements[7]!.maximized,
      isTrue,
    );

    // An unmaximize_request echo must keep its original semantics.
    bridge.emitWindowEvent(
      DenialWindowActionEvent(windowId: 27, action: DenialWindowAction.restore),
    );

    expect(
      container.read(desktopWorkspaceProvider).placements[7]!.maximized,
      isFalse,
    );
  });
}

/// Replays native window events into the coordinator through the bridge's
/// broadcast stream, exactly like the real wire dispatch.
class _WindowActionTestBridge extends DenialBridge {
  final StreamController<DenialWindowEvent> _events =
      StreamController<DenialWindowEvent>.broadcast(sync: true);

  @override
  Stream<DenialWindowEvent> get windowEvents => _events.stream;

  void emitWindowEvent(DenialWindowEvent event) => _events.add(event);

  Future<void> close() async {
    await _events.close();
    dispose();
  }
}

class _WindowActionShellController extends ShellController {
  _WindowActionShellController({this.foregroundObjectId});

  final int? foregroundObjectId;

  @override
  ShellState build() {
    return ShellState(
      windows: const [_testWindow],
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
