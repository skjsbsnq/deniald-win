import 'package:denial_dart_shell/src/desktop/desktop_visibility.dart';
import 'package:denial_dart_shell/src/desktop/desktop_workspace.dart';
import 'package:denial_dart_shell/src/models/denial_window.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _output = Rect.fromLTWH(0, 0, 100, 100);

void main() {
  test('empty placement produces no visible surfaces', () {
    final result = computeConservativeVisibleRegions(
      layoutEpoch: 4,
      outputId: 1,
      outputRect: _output,
      placements: const <DesktopWindowPlacement>[],
      windowsById: const <int, DenialWindow>{},
    );

    expect(result.visibleSurfaceIds, isEmpty);
  });

  test('opaque upper window fully occludes the lower window', () {
    final lower = _window(1, const Rect.fromLTWH(0, 0, 100, 100));
    final upper = _window(
      2,
      const Rect.fromLTWH(0, 0, 100, 100),
      opacityClass: DenialWindowOpacityClass.fullyOpaque,
    );
    final result = _compute(<DenialWindow>[lower, upper]);

    expect(result.visibleSurfaceIds, <int>[2]);
    expect(
      result.reports.where((report) => report.surfaceId == 1).single.reason,
      ConservativeVisibilityReason.fullyOccluded,
    );
  });

  test('partial coverage retains the lower window', () {
    final result = _compute(<DenialWindow>[
      _window(1, const Rect.fromLTWH(0, 0, 100, 100)),
      _window(
        2,
        const Rect.fromLTWH(0, 0, 50, 100),
        opacityClass: DenialWindowOpacityClass.fullyOpaque,
      ),
    ]);

    expect(result.visibleSurfaceIds, <int>[1, 2]);
    expect(
      result.reports.where((report) => report.surfaceId == 1).single.reason,
      ConservativeVisibilityReason.partiallyOccluded,
    );
  });

  test('transparency and transforms never prove occlusion', () {
    final transparent = _window(
      2,
      const Rect.fromLTWH(0, 0, 100, 100),
      opacityClass: DenialWindowOpacityClass.contentTranslucent,
    );
    final transformed = _window(
      3,
      const Rect.fromLTWH(0, 0, 100, 100),
      opacityClass: DenialWindowOpacityClass.fullyOpaque,
      transform: 1,
    );
    final result = _compute(<DenialWindow>[
      _window(1, const Rect.fromLTWH(0, 0, 100, 100)),
      transparent,
      transformed,
    ]);

    expect(result.visibleSurfaceIds, <int>[1, 2, 3]);
  });

  test('one-pixel gap is retained', () {
    final result = _compute(<DenialWindow>[
      _window(1, const Rect.fromLTWH(0, 0, 100, 100)),
      _window(
        2,
        const Rect.fromLTWH(0, 0, 99, 100),
        opacityClass: DenialWindowOpacityClass.fullyOpaque,
      ),
    ]);

    expect(result.visibleSurfaceIds, <int>[1, 2]);
  });

  test('forced consumer retains an otherwise covered window', () {
    final result = _compute(
      <DenialWindow>[
        _window(1, const Rect.fromLTWH(0, 0, 100, 100)),
        _window(
          2,
          const Rect.fromLTWH(0, 0, 100, 100),
          opacityClass: DenialWindowOpacityClass.fullyOpaque,
        ),
      ],
      forcedWindowIds: const <int>{1},
    );

    expect(result.visibleSurfaceIds, <int>[1, 2]);
    expect(
      result.reports.where((report) => report.surfaceId == 1).single.reason,
      ConservativeVisibilityReason.forcedConsumer,
    );
  });

  test('report carries output and layout epoch', () {
    final result = _compute(<DenialWindow>[
      _window(1, const Rect.fromLTWH(0, 0, 10, 10)),
    ]);

    final report = result.reports.single;
    expect(report.layoutEpoch, 9);
    expect(report.outputId, 7);
    expect(report.region, const Rect.fromLTWH(0, 0, 10, 10));
  });

  test('one hundred geometry epochs never regress', () {
    var previousEpoch = -1;
    for (var epoch = 0; epoch < 100; epoch += 1) {
      final result = computeConservativeVisibleRegions(
        layoutEpoch: epoch,
        outputId: 7,
        outputRect: _output,
        placements: <DesktopWindowPlacement>[
          DesktopWindowPlacement(
            objectId: 1,
            frame: Rect.fromLTWH(epoch.toDouble() % 5, 0, 10, 10),
            z: 0,
            monitorId: 1,
            serverSideDecorated: false,
          ),
        ],
        windowsById: <int, DenialWindow>{
          1: _window(1, const Rect.fromLTWH(0, 0, 10, 10)),
        },
      );
      expect(result.reports.single.layoutEpoch, greaterThan(previousEpoch));
      previousEpoch = result.reports.single.layoutEpoch;
    }
  });

  test('unknown output retains all surfaces', () {
    final result = computeConservativeVisibleRegions(
      layoutEpoch: 1,
      outputId: -1,
      outputRect: Rect.zero,
      placements: <DesktopWindowPlacement>[
        DesktopWindowPlacement(
          objectId: 1,
          frame: _output,
          z: 0,
          monitorId: 1,
          serverSideDecorated: false,
        ),
      ],
      windowsById: <int, DenialWindow>{
        1: _window(
          1,
          _output,
          opacityClass: DenialWindowOpacityClass.fullyOpaque,
        ),
      },
    );

    expect(result.visibleSurfaceIds, <int>[1]);
    expect(
      result.reports.single.reason,
      ConservativeVisibilityReason.unknownOutput,
    );
  });
}

ConservativeVisibleRegions _compute(
  List<DenialWindow> windows, {
  Set<int> forcedWindowIds = const <int>{},
}) {
  final placements = <DesktopWindowPlacement>[
    for (var index = 0; index < windows.length; index += 1)
      DesktopWindowPlacement(
        objectId: windows[index].objectId,
        frame: windows[index].geometry!,
        z: index,
        monitorId: 1,
        serverSideDecorated: false,
      ),
  ];
  return computeConservativeVisibleRegions(
    layoutEpoch: 9,
    outputId: 7,
    outputRect: _output,
    placements: placements,
    windowsById: <int, DenialWindow>{
      for (final window in windows) window.objectId: window,
    },
    forcedWindowIds: forcedWindowIds,
  );
}

DenialWindow _window(
  int id,
  Rect geometry, {
  DenialWindowOpacityClass opacityClass =
      DenialWindowOpacityClass.contentTranslucent,
  int transform = 0,
}) {
  return DenialWindow(
    objectId: id,
    objectKind: 'surface',
    surfaceId: id,
    windowId: id,
    textureId: id,
    title: 'window-$id',
    appId: 'test.$id',
    width: geometry.width.round(),
    height: geometry.height.round(),
    surfaceX: geometry.left,
    surfaceY: geometry.top,
    surfaceWidth: geometry.width,
    surfaceHeight: geometry.height,
    textureSourceX: 0,
    textureSourceY: 0,
    textureSourceWidth: geometry.width,
    textureSourceHeight: geometry.height,
    geometryX: geometry.left,
    geometryY: geometry.top,
    geometryWidth: geometry.width,
    geometryHeight: geometry.height,
    monitorId: 1,
    transform: transform,
    scale120: 120,
    serverSideDecorated: false,
    opacityClass: opacityClass,
  );
}
