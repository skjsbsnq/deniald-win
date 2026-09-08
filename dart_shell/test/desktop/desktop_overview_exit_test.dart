import 'package:denial_dart_shell/src/desktop/desktop_shell.dart';
import 'package:denial_dart_shell/src/desktop/desktop_workspace.dart';
import 'package:denial_dart_shell/src/models/denial_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _leftMonitorWindow = DenialWindow(
  objectId: 7,
  objectKind: 'xdg',
  surfaceId: 17,
  windowId: 27,
  textureId: 37,
  title: 'Left',
  appId: 'org.example.left',
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

const _rightMonitorWindow = DenialWindow(
  objectId: 8,
  objectKind: 'xdg',
  surfaceId: 18,
  windowId: 28,
  textureId: 38,
  title: 'Right',
  appId: 'org.example.right',
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
  geometryX: 1500,
  geometryY: 100,
  geometryWidth: 300,
  geometryHeight: 200,
  monitorId: 2,
  transform: 0,
  scale120: 120,
);

/// Overview active on the left monitor of a two-monitor canvas.
DesktopWorkspaceState _overviewWorkspace() {
  return DesktopWorkspaceState(
    placements: <int, DesktopWindowPlacement>{
      7: const DesktopWindowPlacement(
        objectId: 7,
        frame: Rect.fromLTWH(100, 100, 300, 200),
        z: 1,
        monitorId: 1,
      ),
      8: const DesktopWindowPlacement(
        objectId: 8,
        frame: Rect.fromLTWH(1500, 100, 300, 200),
        z: 2,
        monitorId: 2,
      ),
    },
    nextZ: 3,
    viewSize: const Size(2400, 800),
    overview: DesktopOverviewState(
      monitorId: 1,
      bounds: const Rect.fromLTWH(0, 0, 1200, 800),
      backgroundBounds: const Rect.fromLTWH(0, 0, 1200, 800),
      frames: const <int, Rect>{
        7: Rect.fromLTWH(60, 250, 480, 320),
      },
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('desktopOverviewBarrierTap', () {
    test(
      'tap on empty background inside the target monitor dismisses the overview',
      () {
        var dismissals = 0;
        final activated = <int>[];
        desktopOverviewBarrierTap(
          workspace: _overviewWorkspace(),
          windows: const [_leftMonitorWindow, _rightMonitorWindow],
          position: const Offset(600, 400),
          onDismissOverview: () => dismissals += 1,
          onActivateWindow: (window) => activated.add(window.objectId),
        );
        expect(dismissals, 1);
        expect(activated, isEmpty);
      },
    );

    test(
      'tap inside the target monitor never activates, even over a placement',
      () {
        // Window previews own their taps above the barrier; any tap the
        // barrier still sees inside the target monitor is background.
        var dismissals = 0;
        final activated = <int>[];
        desktopOverviewBarrierTap(
          workspace: _overviewWorkspace(),
          windows: const [_leftMonitorWindow, _rightMonitorWindow],
          position: const Offset(200, 200),
          onDismissOverview: () => dismissals += 1,
          onActivateWindow: (window) => activated.add(window.objectId),
        );
        expect(dismissals, 1);
        expect(activated, isEmpty);
      },
    );

    test('tap on another output dismisses and activates the window there', () {
      var dismissals = 0;
      final activated = <int>[];
      desktopOverviewBarrierTap(
        workspace: _overviewWorkspace(),
        windows: const [_leftMonitorWindow, _rightMonitorWindow],
        position: const Offset(1650, 200),
        onDismissOverview: () => dismissals += 1,
        onActivateWindow: (window) => activated.add(window.objectId),
      );
      expect(dismissals, 1);
      expect(activated, <int>[8]);
    });

    test('tap on another output without a window only dismisses', () {
      var dismissals = 0;
      final activated = <int>[];
      desktopOverviewBarrierTap(
        workspace: _overviewWorkspace(),
        windows: const [_leftMonitorWindow, _rightMonitorWindow],
        position: const Offset(2000, 600),
        onDismissOverview: () => dismissals += 1,
        onActivateWindow: (window) => activated.add(window.objectId),
      );
      expect(dismissals, 1);
      expect(activated, isEmpty);
    });

    test('tap without an active overview does nothing', () {
      var dismissals = 0;
      final activated = <int>[];
      desktopOverviewBarrierTap(
        workspace: DesktopWorkspaceState(
          placements: const <int, DesktopWindowPlacement>{},
          nextZ: 1,
          viewSize: const Size(2400, 800),
        ),
        windows: const [_leftMonitorWindow],
        position: const Offset(600, 400),
        onDismissOverview: () => dismissals += 1,
        onActivateWindow: (window) => activated.add(window.objectId),
      );
      expect(dismissals, 0);
      expect(activated, isEmpty);
    });
  });

  group('DesktopOverviewEscapeScope', () {
    testWidgets('Escape dismisses while the overview is active', (tester) async {
      var escapes = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: DesktopOverviewEscapeScope(
            active: true,
            onEscape: () => escapes++,
          ),
        ),
      );
      await tester.pump();

      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'desktop-overview-escape',
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
      expect(escapes, 1);
    });

    testWidgets('Escape is ignored while the overview is inactive', (
      tester,
    ) async {
      var escapes = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: DesktopOverviewEscapeScope(
            active: false,
            onEscape: () => escapes++,
          ),
        ),
      );
      await tester.pump();

      expect(FocusManager.instance.primaryFocus?.debugLabel, isNot(
        'desktop-overview-escape',
      ));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
      expect(escapes, 0);
    });

    testWidgets('activation claims the keyboard focus', (tester) async {
      var escapes = 0;
      Widget scene(bool active) {
        return MaterialApp(
          home: DesktopOverviewEscapeScope(
            active: active,
            onEscape: () => escapes++,
          ),
        );
      }

      await tester.pumpWidget(scene(false));
      await tester.pump();
      expect(FocusManager.instance.primaryFocus?.debugLabel, isNot(
        'desktop-overview-escape',
      ));

      await tester.pumpWidget(scene(true));
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'desktop-overview-escape',
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
      expect(escapes, 1);
    });
  });
}
