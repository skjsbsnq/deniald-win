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

  test('fractional occluder edges are shrunk inward conservatively', () {
    final result = _compute(<DenialWindow>[
      _window(1, const Rect.fromLTWH(0, 0, 100, 100)),
      _window(
        2,
        const Rect.fromLTRB(0.2, 0.2, 99.8, 99.8),
        opacityClass: DenialWindowOpacityClass.fullyOpaque,
      ),
    ]);

    expect(result.visibleSurfaceIds, <int>[1, 2]);
    expect(
      result.reports.where((report) => report.surfaceId == 1).single.reason,
      ConservativeVisibilityReason.partiallyOccluded,
    );
  });

  test('complexity limit degrades to retaining every surface', () {
    final windows = <DenialWindow>[
      _window(1, const Rect.fromLTWH(0, 0, 100, 100)),
      for (
        var id = 2;
        id <= ConservativeVisibilityLimits.maxOccluders + 2;
        id += 1
      )
        _window(
          id,
          const Rect.fromLTWH(0, 0, 100, 100),
          opacityClass: DenialWindowOpacityClass.fullyOpaque,
        ),
    ];
    final result = _compute(windows);

    expect(result.degraded, isTrue);
    expect(result.fullyOccludedWindowIds, isEmpty);
    expect(result.visibleSurfaceIds.length, windows.length);
    expect(
      result.reports.every(
        (report) =>
            report.reason == ConservativeVisibilityReason.complexityLimit,
      ),
      isTrue,
    );
  });

  test(
    'fragment complexity limit also degrades to retaining every surface',
    () {
      final windows = <DenialWindow>[
        _window(1, const Rect.fromLTWH(0, 0, 100, 100)),
        for (var index = 0; index < 16; index += 1)
          _window(
            2 + index,
            Rect.fromLTWH(2.0 + index * 3.0, 0, 1, 100),
            opacityClass: DenialWindowOpacityClass.fullyOpaque,
          ),
        for (var index = 0; index < 16; index += 1)
          _window(
            18 + index,
            Rect.fromLTWH(0, 2.0 + index * 3.0, 100, 1),
            opacityClass: DenialWindowOpacityClass.fullyOpaque,
          ),
      ];
      final result = _compute(windows);

      expect(result.degraded, isTrue);
      expect(result.fullyOccludedWindowIds, isEmpty);
      expect(result.visibleSurfaceIds.length, windows.length);
    },
  );

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

  test(
    'desktop snapshot only suppresses an exact current fully covered window',
    () {
      final windows = <DenialWindow>[
        _window(1, const Rect.fromLTWH(0, 0, 100, 100)),
        _window(
          2,
          const Rect.fromLTWH(0, 0, 100, 100),
          opacityClass: DenialWindowOpacityClass.fullyOpaque,
        ),
      ];
      final placements = _placements(windows);
      final windowsById = <int, DenialWindow>{
        for (final window in windows) window.objectId: window,
      };
      final snapshot = computeDesktopVisibilitySnapshot(
        layoutEpoch: 9,
        outputLayoutEpoch: 4,
        placements: placements,
        windowsById: windowsById,
        outputRects: const <({int id, Rect rect})>[(id: 1, rect: _output)],
      );

      expect(snapshot.fullyOccludedWindowIds, contains(1));
      expect(
        snapshot.shouldPaintClientContent(
          objectId: 1,
          window: windows[0],
          placement: placements[0],
          layoutEpoch: 9,
          outputLayoutEpoch: 4,
          forceAll: false,
        ),
        isFalse,
      );
      expect(
        snapshot.shouldPaintClientContent(
          objectId: 1,
          window: windows[0],
          placement: placements[0].copyWith(
            frame: const Rect.fromLTWH(1, 0, 100, 100),
          ),
          layoutEpoch: 9,
          outputLayoutEpoch: 4,
          forceAll: false,
        ),
        isTrue,
      );
      expect(
        snapshot.shouldPaintClientContent(
          objectId: 1,
          window: windows[0],
          placement: placements[0],
          layoutEpoch: 10,
          outputLayoutEpoch: 4,
          forceAll: false,
        ),
        isTrue,
      );
    },
  );

  test('special consumers and unknown output never suppress painting', () {
    final windows = <DenialWindow>[
      _window(1, const Rect.fromLTWH(0, 0, 100, 100)),
      _window(
        2,
        const Rect.fromLTWH(0, 0, 100, 100),
        opacityClass: DenialWindowOpacityClass.fullyOpaque,
      ),
    ];
    final placements = _placements(windows);
    final windowsById = <int, DenialWindow>{
      for (final window in windows) window.objectId: window,
    };
    final snapshot = computeDesktopVisibilitySnapshot(
      layoutEpoch: 9,
      outputLayoutEpoch: 4,
      placements: placements,
      windowsById: windowsById,
      outputRects: const <({int id, Rect rect})>[(id: -1, rect: Rect.zero)],
      forcedWindowIds: const <int>{1},
    );

    expect(snapshot.fullyOccludedWindowIds, isEmpty);
    expect(
      snapshot.shouldPaintClientContent(
        objectId: 1,
        window: windows[0],
        placement: placements[0],
        layoutEpoch: 9,
        outputLayoutEpoch: 4,
        forceAll: false,
        specialConsumer: true,
      ),
      isTrue,
    );
  });

  test('popup surfaces remain sampled when their toplevel is covered', () {
    final lower = _window(
      1,
      const Rect.fromLTWH(0, 0, 100, 100),
      surfaceLayers: <DenialSurfaceLayer>[
        _layer(surfaceId: 1, role: DenialSurfaceRole.root, opaque: true),
        _layer(
          surfaceId: 3,
          role: DenialSurfaceRole.popup,
          popupRootSurfaceId: 3,
        ),
      ],
      opacityClass: DenialWindowOpacityClass.fullyOpaque,
    );
    final upper = _window(
      2,
      const Rect.fromLTWH(0, 0, 100, 100),
      opacityClass: DenialWindowOpacityClass.fullyOpaque,
    );
    final result = _compute(<DenialWindow>[lower, upper]);

    expect(result.visibleSurfaceIds, <int>[1, 2, 3]);
    expect(result.fullyOccludedWindowIds, isEmpty);
  });

  test('shell translucency is not accepted as an opaque occluder', () {
    final windows = <DenialWindow>[
      _window(1, const Rect.fromLTWH(0, 0, 100, 100)),
      _window(
        2,
        const Rect.fromLTWH(0, 0, 100, 100),
        opacityClass: DenialWindowOpacityClass.fullyOpaque,
      ),
    ];
    final placements = _placements(windows);
    final result = computeConservativeVisibleRegions(
      layoutEpoch: 9,
      outputId: 7,
      outputRect: _output,
      placements: placements,
      windowsById: <int, DenialWindow>{
        for (final window in windows) window.objectId: window,
      },
      shellTranslucentWindowIds: const <int>{2},
    );

    expect(result.visibleSurfaceIds, <int>[1, 2]);
  });

  test('visibility is isolated per output', () {
    final windows = <DenialWindow>[
      _window(1, const Rect.fromLTWH(0, 0, 100, 100)),
      _window(2, const Rect.fromLTWH(100, 0, 100, 100)),
      _window(
        3,
        const Rect.fromLTWH(100, 0, 100, 100),
        opacityClass: DenialWindowOpacityClass.fullyOpaque,
      ),
    ];
    final snapshot = computeDesktopVisibilitySnapshot(
      layoutEpoch: 9,
      outputLayoutEpoch: 4,
      placements: _placements(windows),
      windowsById: <int, DenialWindow>{
        for (final window in windows) window.objectId: window,
      },
      outputRects: const <({int id, Rect rect})>[
        (id: 1, rect: Rect.fromLTWH(0, 0, 100, 100)),
        (id: 2, rect: Rect.fromLTWH(100, 0, 100, 100)),
      ],
    );

    expect(snapshot.fullyOccludedWindowIds, <int>[2]);
    expect(snapshot.visibleSurfaceIds, <int>[1, 3]);
  });

  test('missing output ownership degrades to full visibility', () {
    final windows = <DenialWindow>[
      _window(1, const Rect.fromLTWH(0, 0, 100, 100)),
      _window(
        2,
        const Rect.fromLTWH(0, 0, 100, 100),
        opacityClass: DenialWindowOpacityClass.fullyOpaque,
      ),
    ];
    final outputs = desktopVisibilityOutputRects(
      viewSize: const Size(100, 100),
      monitorIds: const <int>{1, 2},
      configuredOutputs: const <({int id, Rect rect})>[
        (id: 1, rect: Rect.fromLTWH(0, 0, 100, 100)),
      ],
    );
    final snapshot = computeDesktopVisibilitySnapshot(
      layoutEpoch: 9,
      outputLayoutEpoch: 4,
      placements: _placements(windows),
      windowsById: <int, DenialWindow>{
        for (final window in windows) window.objectId: window,
      },
      outputRects: outputs,
    );

    expect(snapshot.fullyOccludedWindowIds, isEmpty);
    expect(snapshot.visibleSurfaceIds, <int>[1, 2]);
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

List<DesktopWindowPlacement> _placements(List<DenialWindow> windows) {
  return <DesktopWindowPlacement>[
    for (var index = 0; index < windows.length; index += 1)
      DesktopWindowPlacement(
        objectId: windows[index].objectId,
        frame: windows[index].geometry!,
        z: index,
        monitorId: 1,
        serverSideDecorated: false,
      ),
  ];
}

DenialWindow _window(
  int id,
  Rect geometry, {
  DenialWindowOpacityClass opacityClass =
      DenialWindowOpacityClass.contentTranslucent,
  int transform = 0,
  List<DenialSurfaceLayer> surfaceLayers = const <DenialSurfaceLayer>[],
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
    surfaceLayers: surfaceLayers,
    opacityClass: opacityClass,
  );
}

DenialSurfaceLayer _layer({
  required int surfaceId,
  required DenialSurfaceRole role,
  bool opaque = false,
  int popupRootSurfaceId = 0,
}) {
  return DenialSurfaceLayer(
    surfaceId: surfaceId,
    parentSurfaceId: 0,
    popupRootSurfaceId: popupRootSurfaceId,
    role: role,
    textureId: surfaceId,
    width: 100,
    height: 100,
    surfaceX: 0,
    surfaceY: 0,
    surfaceWidth: 100,
    surfaceHeight: 100,
    textureSourceX: 0,
    textureSourceY: 0,
    textureSourceWidth: 100,
    textureSourceHeight: 100,
    transform: 0,
    scale120: 120,
    compositionOrder: surfaceId,
    opaque: opaque,
  );
}
