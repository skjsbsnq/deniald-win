import 'package:denial_dart_shell/src/desktop/desktop_input_layout_publisher.dart';
import 'package:denial_dart_shell/src/desktop/desktop_taskbar_preview.dart';
import 'package:denial_dart_shell/src/desktop/desktop_workspace.dart';
import 'package:denial_dart_shell/src/input/input_layout.dart';
import 'package:denial_dart_shell/src/models/denial_window.dart';
import 'package:denial_dart_shell/src/models/denial_window_event.dart';
import 'package:denial_dart_shell/src/models/display_layout.dart';
import 'package:denial_dart_shell/src/platform/denial_bridge.dart';
import 'package:denial_dart_shell/src/state/shell_controller.dart';
import 'package:denial_dart_shell/src/state/shell_state.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('position-only geometry changes are published to Rust', () {
    final tracker = DesktopWindowConfigureTracker();

    expect(
      tracker.update(
        1,
        const Rect.fromLTWH(100, 80, 800, 600),
        nativeDragActive: false,
      ),
      isNull,
      reason: 'the first native rectangle seeds the cache',
    );
    expect(
      tracker.update(
        1,
        const Rect.fromLTWH(10, 32, 800, 600),
        nativeDragActive: false,
      ),
      const Rect.fromLTWH(10, 32, 800, 600),
    );
  });

  test('shell-corrected initial geometry is configured once', () {
    final tracker = DesktopWindowConfigureTracker();

    expect(
      tracker.update(
        1,
        const Rect.fromLTWH(100, 35, 800, 600),
        nativeDragActive: false,
        configureInitial: true,
      ),
      const Rect.fromLTWH(100, 35, 800, 600),
    );
    expect(
      tracker.update(
        1,
        const Rect.fromLTWH(100, 35, 800, 600),
        nativeDragActive: false,
      ),
      isNull,
    );
  });

  test('native drag geometry is learned without being echoed', () {
    final tracker = DesktopWindowConfigureTracker();
    tracker.update(
      1,
      const Rect.fromLTWH(100, 80, 800, 600),
      nativeDragActive: false,
    );

    expect(
      tracker.update(
        1,
        const Rect.fromLTWH(240, 180, 800, 600),
        nativeDragActive: true,
      ),
      isNull,
    );
    expect(
      tracker.update(
        1,
        const Rect.fromLTWH(240, 180, 800, 600),
        nativeDragActive: false,
      ),
      isNull,
      reason: 'ending the drag must not echo its final native rectangle',
    );
  });

  group('window geometry crossing the bridge', () {
    // A titlebar drag moves the frame in Dart alone. Unless the position it
    // settles on is configured, Space::element_location in Rust keeps the
    // pre-drag origin, and the interactive move a client asks for next starts
    // from there — which teleports the window by the whole distance of the
    // preceding drag.
    testWidgets('a titlebar drag is configured once it settles', (
      tester,
    ) async {
      final harness = await _pumpPublisher(tester);

      harness.workspace.beginMove(_objectId);
      harness.workspace.moveBy(_objectId, const Offset(120, 80));
      await tester.pump();

      expect(
        harness.bridge.configured,
        isEmpty,
        reason: 'a drag in flight needs no configure of its own',
      );

      harness.workspace.endMove(_objectId);
      await tester.pump();

      expect(harness.bridge.configured, <Rect>[
        _nativeGeometry.shift(const Offset(120, 80)),
      ]);
    });

    testWidgets('a compositor grab is never echoed back', (tester) async {
      final harness = await _pumpPublisher(tester);

      for (final phase in <DenialWindowPlacementPhase>[
        DenialWindowPlacementPhase.begin,
        DenialWindowPlacementPhase.update,
        DenialWindowPlacementPhase.end,
      ]) {
        harness.workspace.applyNativePlacement(
          _objectId,
          DenialWindowPlacementEvent(
            sequence: 10 + phase.index,
            windowId: _windowId,
            contentRect: _nativeGeometry.shift(const Offset(60, 40)),
            monitorId: 1,
            workspaceId: 1,
            phase: phase,
            change: DenialWindowPlacementChange.move,
          ),
        );
        await tester.pump();
      }

      expect(harness.bridge.configured, isEmpty);
    });

    testWidgets(
      'minimized window is omitted from visibleSurfaceIds unless previewed',
      (tester) async {
        final harness = await _pumpPublisher(tester);

        expect(
          harness.bridge.publishedSnapshots.last.visibleSurfaceIds,
          contains(_objectId),
          reason: 'an un-minimized window is visible',
        );

        harness.workspace.minimize(_objectId);
        await tester.pump();

        expect(
          harness.bridge.publishedSnapshots.last.visibleSurfaceIds,
          isEmpty,
          reason:
              'a minimized window is omitted from visible surfaces by default',
        );

        harness.container
            .read(desktopTaskbarPreviewProvider.notifier)
            .scheduleShow(
              const DesktopTaskbarPreviewTarget(
                objectId: _objectId,
                buttonBounds: Rect.fromLTWH(0, 0, 100, 44),
                side: SystemBarSide.bottom,
              ),
            );
        await tester.pump(const Duration(milliseconds: 400));

        expect(
          harness.bridge.publishedSnapshots.last.visibleSurfaceIds,
          contains(_objectId),
          reason:
              'taskbar preview restores presentation visibility for sampling',
        );

        harness.container
            .read(desktopTaskbarPreviewProvider.notifier)
            .hideImmediately();
        await tester.pump();

        expect(
          harness.bridge.publishedSnapshots.last.visibleSurfaceIds,
          isEmpty,
          reason: 'closing preview stops sampling the minimized window',
        );
      },
    );
  });

  group('desktopFrameRingRegions', () {
    const canvas = Rect.fromLTWH(0, 0, 1707, 1067);
    // The shell frame is a 1 px border plus a 34 px titlebar on top.
    DesktopFrameRing ring(Rect frame) => DesktopFrameRing(
      frame: frame,
      content: Rect.fromLTRB(
        frame.left + 1,
        frame.top + 35,
        frame.right - 1,
        frame.bottom - 1,
      ),
    );

    bool covers(List<Rect> regions, Offset point) =>
        regions.any((region) => region.contains(point));

    test('restores a titlebar band overlapping a lower window', () {
      const upper = Rect.fromLTWH(300, 200, 600, 400);
      const lower = Rect.fromLTWH(200, 100, 600, 400);
      final regions = desktopFrameRingRegions(canvas, <DesktopFrameRing>[
        ring(upper),
        ring(lower),
      ]);

      // A point inside the upper window's titlebar that also sits inside the
      // lower window's client rectangle. Before this restore, the lower
      // window's cut removed it from the shell region and the click was routed
      // to the lower client.
      expect(covers(regions, const Offset(500, 215)), isTrue);
      // The upper window's own client area stays with the client.
      expect(covers(regions, const Offset(500, 400)), isFalse);
    });

    test('a higher window keeps ownership of pixels it paints over', () {
      const upper = Rect.fromLTWH(300, 200, 600, 400);
      const lower = Rect.fromLTWH(320, 400, 600, 400);
      final regions = desktopFrameRingRegions(canvas, <DesktopFrameRing>[
        ring(upper),
        ring(lower),
      ]);

      // The lower window's titlebar is buried under the upper window, so it
      // must not be restored — that would steal clicks from the upper client.
      expect(covers(regions, const Offset(500, 415)), isFalse);
      // Past the upper window's right edge the lower titlebar is visible again.
      expect(covers(regions, const Offset(910, 415)), isTrue);
    });

    test('rings are clipped to the canvas', () {
      final regions = desktopFrameRingRegions(canvas, <DesktopFrameRing>[
        ring(const Rect.fromLTWH(1600, 900, 400, 400)),
      ]);

      expect(regions, isNotEmpty);
      for (final region in regions) {
        expect(canvas.contains(region.topLeft), isTrue);
        expect(region.right, lessThanOrEqualTo(canvas.right));
        expect(region.bottom, lessThanOrEqualTo(canvas.bottom));
      }
    });
  });
}

const int _objectId = 1;
const int _windowId = 11;
const Size _viewSize = Size(2560, 1440);
const Rect _nativeGeometry = Rect.fromLTWH(400, 300, 640, 400);

Future<
  ({
    _ConfigureBridge bridge,
    DesktopWorkspaceController workspace,
    ProviderContainer container,
  })
>
_pumpPublisher(WidgetTester tester) async {
  final bridge = _ConfigureBridge();
  addTearDown(bridge.dispose);
  final container = ProviderContainer.test(
    overrides: [
      denialBridgeProvider.overrideWithValue(bridge),
      shellControllerProvider.overrideWithBuild(
        (ref, controller) => ShellState.initial().copyWith(
          windows: <DenialWindow>[_publisherWindow],
          windowSnapshotSequence: 1,
        ),
      ),
    ],
  );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MediaQuery(
        data: MediaQueryData(size: _viewSize, devicePixelRatio: 1.0),
        child: DesktopInputLayoutPublisher(child: SizedBox.expand()),
      ),
    ),
  );
  await tester.pump();

  expect(
    container.read(desktopWorkspaceProvider).placements[_objectId],
    isNotNull,
    reason: 'the publisher seeds placements from the window snapshot',
  );
  expect(
    bridge.configured,
    isEmpty,
    reason: 'a newly discovered window is native geometry, not shell geometry',
  );

  return (
    bridge: bridge,
    workspace: container.read(desktopWorkspaceProvider.notifier),
    container: container,
  );
}

final DenialWindow _publisherWindow = DenialWindow(
  objectId: _objectId,
  objectKind: 'root_surface',
  surfaceId: _objectId,
  windowId: _windowId,
  textureId: _objectId,
  title: 'Window',
  appId: 'test-publisher',
  width: 2560,
  height: 1440,
  surfaceX: 0,
  surfaceY: 0,
  surfaceWidth: 2560,
  surfaceHeight: 1440,
  textureSourceX: 0,
  textureSourceY: 0,
  textureSourceWidth: 2560,
  textureSourceHeight: 1440,
  geometryX: _nativeGeometry.left,
  geometryY: _nativeGeometry.top,
  geometryWidth: _nativeGeometry.width,
  geometryHeight: _nativeGeometry.height,
  monitorId: 1,
  transform: 0,
  scale120: 120,
);

class _ConfigureBridge extends DenialBridge {
  final List<Rect> configured = <Rect>[];
  final List<InputLayoutSnapshot> publishedSnapshots = <InputLayoutSnapshot>[];

  @override
  bool publishInputLayout(InputLayoutSnapshot snapshot) {
    publishedSnapshots.add(snapshot);
    return true;
  }

  @override
  void configureWindow(
    DenialWindow window,
    Rect contentRect, {
    bool exact = false,
  }) {
    configured.add(contentRect);
  }
}
