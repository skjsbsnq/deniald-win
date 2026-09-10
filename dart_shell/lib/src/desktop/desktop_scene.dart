part of 'desktop_shell.dart';

/// Owns the two ChromeOS-shelf bubble expansions (tray and dashboard) as one
/// unit so every surface-opening path can close them from a single source.
///
/// Desktop surfaces are mutually exclusive: opening the launcher, the
/// dashboard panel, the clipboard tray, or the overview closes both bubbles;
/// opening a bubble closes the panels and the other bubble. The bubbles live
/// outside the [DesktopPanel] state machine, so this controller is the one
/// place that knows both notifiers, and the shell's transient-surface helper
/// calls [close] whenever any peer surface opens.
///
/// The overview additionally closes (not merely hides) the bubbles, so they
/// never reappear on overview exit.
final desktopShelfBubblesProvider =
    NotifierProvider<DesktopShelfBubblesController, DesktopShelfBubblesState>(
      DesktopShelfBubblesController.new,
    );

@immutable
class DesktopShelfBubblesState {
  const DesktopShelfBubblesState({
    this.trayExpanded = false,
    this.dashboardExpanded = false,
    this.anchorMonitorId,
  });

  final bool trayExpanded;
  final bool dashboardExpanded;

  /// The output whose shelf clone opened the open bubble, so it docks to
  /// that output instead of the global canvas corner. Kept while the
  /// closing spring settles so the bubble never jumps outputs
  /// mid-animation; null anchors to the primary output.
  final int? anchorMonitorId;
}

class DesktopShelfBubblesController extends Notifier<DesktopShelfBubblesState> {
  @override
  DesktopShelfBubblesState build() => const DesktopShelfBubblesState();

  void toggleTray({int? anchorMonitorId}) {
    if (state.trayExpanded) {
      state = DesktopShelfBubblesState(anchorMonitorId: state.anchorMonitorId);
    } else {
      state = DesktopShelfBubblesState(
        trayExpanded: true,
        anchorMonitorId: anchorMonitorId,
      );
    }
  }

  void toggleDashboard({int? anchorMonitorId}) {
    if (state.dashboardExpanded) {
      state = DesktopShelfBubblesState(anchorMonitorId: state.anchorMonitorId);
    } else {
      state = DesktopShelfBubblesState(
        dashboardExpanded: true,
        anchorMonitorId: anchorMonitorId,
      );
    }
  }

  void close() {
    if (state.trayExpanded || state.dashboardExpanded) {
      state = DesktopShelfBubblesState(anchorMonitorId: state.anchorMonitorId);
    }
  }
}

typedef _DesktopHomeSceneLayout = ({
  List<HomeGridItem> widgets,
  Map<String, Rect> widgetFrames,
  Map<int, Rect> windowFrames,
});

/// Docking geometry for the ChromeOS-shelf bubbles: the logical rect of the
/// output whose shelf clone opened the bubble — the primary output when
/// keyboard entry opened it — plus that output's shelf strip height, so the
/// bubble stays flush with the shelf the user actually clicked on
/// multi-output layouts. Layouts without monitor identity keep docking to
/// the whole canvas, which is the single-output behavior.
({Rect outputRect, double shelfHeight}) desktopShelfBubbleAnchorGeometry({
  required int? anchorMonitorId,
  required DisplayLayout? displayLayout,
  required List<({int monitorId, Rect rect, SystemBarSide side})> systemBars,
  required Size viewSize,
}) {
  final canvas = Offset.zero & viewSize;
  DisplayOutput? output;
  if (anchorMonitorId != null) {
    for (final candidate in displayLayout?.outputs ?? const <DisplayOutput>[]) {
      if (candidate.monitorId == anchorMonitorId) {
        output = candidate;
        break;
      }
    }
  }
  output ??= displayLayout?.mainOutput;
  final requestedRect = output?.logicalRect.intersect(canvas);
  final outputRect = requestedRect == null || requestedRect.isEmpty
      ? canvas
      : requestedRect;

  double? shelfHeight;
  for (final bar in systemBars) {
    if (bar.rect.isEmpty) {
      continue;
    }
    if (output != null && bar.monitorId == output.monitorId) {
      shelfHeight = bar.rect.height;
      break;
    }
    shelfHeight ??= bar.rect.height;
  }
  return (
    outputRect: outputRect,
    shelfHeight: shelfHeight ?? ShelfLayer.defaultThickness,
  );
}

typedef _DesktopHomePlacementSignature = ({
  Rect frame,
  int monitorId,
  int z,
  bool fullscreen,
  bool serverSideDecorated,
});

typedef _DesktopHomeWidgetSignature = ({
  String id,
  HomeGridItemType type,
  int colSpan,
  int rowSpan,
});

class _DesktopHomeLayoutCache {
  _DesktopHomeLayoutCache({
    required this.viewSize,
    required this.displayLayout,
    required this.minimizedWindowPlacement,
    required Iterable<DesktopWindowPlacement> placements,
    required List<HomeGridItem?>? homeSlots,
    required this.hasBatteryData,
    required this.layout,
  }) : minimizedPlacements = <int, _DesktopHomePlacementSignature>{
         for (final placement in placements)
           if (placement.minimized)
             placement.objectId: (
               frame: placement.frame,
               monitorId: placement.monitorId,
               z: placement.z,
               fullscreen: placement.fullscreen,
               serverSideDecorated: placement.serverSideDecorated,
             ),
       },
       widgets = <_DesktopHomeWidgetSignature>[
         for (final item
             in homeSlots?.whereType<HomeGridItem>() ?? const <HomeGridItem>[])
           if (item.type != HomeGridItemType.app &&
               (item.type != HomeGridItemType.batteryDischarge ||
                   hasBatteryData))
             (
               id: item.id,
               type: item.type,
               colSpan: item.colSpan,
               rowSpan: item.rowSpan,
             ),
       ];

  final Size viewSize;
  final DisplayLayout? displayLayout;
  final MinimizedWindowPlacement minimizedWindowPlacement;
  final bool hasBatteryData;
  final Map<int, _DesktopHomePlacementSignature> minimizedPlacements;
  final List<_DesktopHomeWidgetSignature> widgets;
  final _DesktopHomeSceneLayout layout;

  bool matches({
    required Size viewSize,
    required DisplayLayout? displayLayout,
    required MinimizedWindowPlacement minimizedWindowPlacement,
    required Iterable<DesktopWindowPlacement> placements,
    required List<HomeGridItem?>? homeSlots,
    required bool hasBatteryData,
  }) {
    if (this.viewSize != viewSize ||
        !identical(this.displayLayout, displayLayout) ||
        this.minimizedWindowPlacement != minimizedWindowPlacement ||
        this.hasBatteryData != hasBatteryData) {
      return false;
    }

    var minimizedCount = 0;
    for (final placement in placements) {
      if (!placement.minimized) {
        continue;
      }
      minimizedCount += 1;
      final cached = minimizedPlacements[placement.objectId];
      if (cached == null ||
          cached.frame != placement.frame ||
          cached.monitorId != placement.monitorId ||
          cached.z != placement.z ||
          cached.fullscreen != placement.fullscreen ||
          cached.serverSideDecorated != placement.serverSideDecorated) {
        return false;
      }
    }
    if (minimizedCount != minimizedPlacements.length) {
      return false;
    }

    var widgetIndex = 0;
    for (final item
        in homeSlots?.whereType<HomeGridItem>() ?? const <HomeGridItem>[]) {
      if (item.type == HomeGridItemType.app ||
          (item.type == HomeGridItemType.batteryDischarge && !hasBatteryData)) {
        continue;
      }
      if (widgetIndex >= widgets.length) {
        return false;
      }
      final cached = widgets[widgetIndex];
      if (cached.id != item.id ||
          cached.type != item.type ||
          cached.colSpan != item.colSpan ||
          cached.rowSpan != item.rowSpan) {
        return false;
      }
      widgetIndex += 1;
    }
    return widgetIndex == widgets.length;
  }
}

String _desktopHomeWidgetKey(String id) => 'home-widget:$id';
String _desktopHomeWindowKey(int objectId) => 'home-window:$objectId';

_DesktopHomeSceneLayout _layoutDesktopHome({
  required Size viewSize,
  required DisplayLayout? displayLayout,
  required MinimizedWindowPlacement minimizedWindowPlacement,
  required Iterable<DesktopWindowPlacement> placements,
  required List<HomeGridItem?>? homeSlots,
  required bool hasBatteryData,
}) {
  final canvas = Offset.zero & viewSize;
  if (canvas.isEmpty) {
    return (
      widgets: const <HomeGridItem>[],
      widgetFrames: const <String, Rect>{},
      windowFrames: const <int, Rect>{},
    );
  }

  final widgets = <HomeGridItem>[];
  final seenWidgetIds = <String>{};
  for (final item
      in homeSlots?.whereType<HomeGridItem>() ?? const <HomeGridItem>[]) {
    if (item.type != HomeGridItemType.app &&
        (item.type != HomeGridItemType.batteryDischarge || hasBatteryData) &&
        seenWidgetIds.add(item.id)) {
      widgets.add(item);
    }
  }

  final minimized =
      placements
          .where((placement) => placement.minimized)
          .toList(growable: false)
        ..sort((left, right) {
          final zOrder = left.z.compareTo(right.z);
          return zOrder != 0 ? zOrder : left.objectId.compareTo(right.objectId);
        });
  final nativeOutputs = displayLayout?.outputs ?? const <DisplayOutput>[];
  final outputAreas = <({int monitorId, Rect bounds})>[
    for (final output in nativeOutputs)
      if ((displayLayout?.workAreaOf(output) ?? output.logicalRect).intersect(
            canvas,
          )
          case final bounds when !bounds.isEmpty)
        (monitorId: output.monitorId, bounds: bounds),
  ];
  if (outputAreas.isEmpty) {
    outputAreas.add((
      monitorId: minimized.isEmpty ? 0 : minimized.first.monitorId,
      bounds: canvas,
    ));
  }
  final mainMonitorId =
      displayLayout?.mainOutput?.monitorId ?? outputAreas.first.monitorId;
  final fallbackArea = outputAreas.firstWhere(
    (area) => area.monitorId == mainMonitorId,
    orElse: () => outputAreas.first,
  );
  final placementsByMonitor = <int, List<DesktopWindowPlacement>>{};
  for (final placement in minimized) {
    ({int monitorId, Rect bounds})? area;
    for (final candidate in outputAreas) {
      if (candidate.monitorId == placement.monitorId) {
        area = candidate;
        break;
      }
    }
    if (area == null) {
      for (final candidate in outputAreas) {
        if (candidate.bounds.contains(placement.frame.center)) {
          area = candidate;
          break;
        }
      }
    }
    area ??= fallbackArea;
    placementsByMonitor
        .putIfAbsent(area.monitorId, () => <DesktopWindowPlacement>[])
        .add(placement);
  }

  final widgetFrames = <String, Rect>{};
  final windowFrames = <int, Rect>{};
  final showMinimizedWindowsOnDesktop =
      minimizedWindowPlacement == MinimizedWindowPlacement.desktop;
  for (final area in outputAreas) {
    final outputWindows = showMinimizedWindowsOnDesktop
        ? placementsByMonitor[area.monitorId] ??
              const <DesktopWindowPlacement>[]
        : const <DesktopWindowPlacement>[];
    final denseWindowMode = DesktopHomeLayout.usesDenseWindowMode(
      outputWindows.length,
    );
    final outputWidgets =
        area.monitorId == fallbackArea.monitorId && !denseWindowMode
        ? widgets
        : const <HomeGridItem>[];
    final frames = DesktopHomeLayout.arrange(
      bounds: area.bounds,
      dense: denseWindowMode,
      items: <DesktopHomeLayoutItem>[
        for (final item in outputWidgets)
          DesktopHomeLayoutItem(
            id: _desktopHomeWidgetKey(item.id),
            preferredAspectRatio: item.colSpan / item.rowSpan,
          ),
        for (final placement in outputWindows)
          DesktopHomeLayoutItem(
            id: _desktopHomeWindowKey(placement.objectId),
            contentAspectRatio:
                placement.contentRect.width / placement.contentRect.height,
            frameInset: placement.serverSideDecorated
                ? DesktopMetrics.frameBorder
                : 0.0,
          ),
      ],
    );
    for (final item in outputWidgets) {
      final frame = frames[_desktopHomeWidgetKey(item.id)];
      if (frame != null) {
        widgetFrames[item.id] = frame;
      }
    }
    for (final placement in outputWindows) {
      final frame = frames[_desktopHomeWindowKey(placement.objectId)];
      if (frame != null) {
        windowFrames[placement.objectId] = frame;
      }
    }
  }
  if (!showMinimizedWindowsOnDesktop) {
    for (final placement in minimized) {
      windowFrames[placement.objectId] = DesktopHomeLayout.offscreenFrame(
        bounds: canvas,
        source: placement.frame,
      );
    }
  }
  return (
    widgets: List<HomeGridItem>.unmodifiable(
      widgets.where((item) => widgetFrames.containsKey(item.id)),
    ),
    widgetFrames: Map<String, Rect>.unmodifiable(widgetFrames),
    windowFrames: Map<int, Rect>.unmodifiable(windowFrames),
  );
}

List<Widget> _buildDesktopWindowLayers({
  required List<DesktopWindowPlacement> placements,
  required Map<int, DenialWindow> windowsById,
  required DesktopWorkspaceState desktop,
  required bool desktopPlane,
  required DesktopMinimizeLayerHandoffController minimizeLayerHandoff,
  required DesktopMinimizedPlacementTransitionController
  minimizedPlacementTransition,
  required Map<int, Rect> minimizedPlacementExitFrames,
  required Rect minimizeOffscreenBounds,
  required MinimizedWindowPlacement minimizedWindowPlacement,
  required Map<int, Rect> desktopWidgetFrames,
  required DesktopWindowSwitcherState? switcher,
  required Rect switcherStageBounds,
  required int topZ,
  required bool reduceMotion,
  required double devicePixelRatio,
  required ValueChanged<DenialWindow> onActivateWindow,
  required ValueChanged<DenialWindow> onBeginOverviewDrag,
  required void Function(DenialWindow window, Offset delta)
  onUpdateOverviewDrag,
  required ValueChanged<DenialWindow> onEndOverviewDrag,
  required ValueChanged<DenialWindow> onCancelOverviewDrag,
}) {
  final layers = <Widget>[];
  for (final placement in placements) {
    // Windows of another workspace are only on screen while their monitor's
    // slide transition still presents the outgoing or incoming workspace.
    if (!placement.minimized && !desktop.isPlacementPresented(placement)) {
      continue;
    }
    final window = windowsById[placement.objectId]!;
    final overview = desktop.isInOverview(placement.objectId);
    final switching =
        !overview &&
        DesktopWindowSwitcherLayout.contains(switcher, placement.objectId);
    final minimizedIdle = placement.minimized && !overview && !switching;
    final minimizingForeground =
        minimizedIdle &&
        minimizeLayerHandoff.keepsOnForeground(placement.objectId);
    final usesDesktopPlane = minimizedIdle && !minimizingForeground;
    final configuredDesktopPlacement =
        minimizedWindowPlacement == MinimizedWindowPlacement.desktop;
    final usesDesktopPlacement = minimizedPlacementTransition
        .usesDesktopPlacement(
          placement.objectId,
          configuredDesktop: configuredDesktopPlacement,
        );
    final desktopWidget =
        minimizedIdle && usesDesktopPlane && usesDesktopPlacement;
    final offscreenMinimized =
        minimizedIdle && usesDesktopPlane && !usesDesktopPlacement;
    final placementEntering = minimizedPlacementTransition.entersDesktop(
      placement.objectId,
    );
    final desktopWidgetEntering =
        desktopWidget &&
        (minimizeLayerHandoff.slidesIntoDesktop(placement.objectId) ||
            placementEntering);
    final desktopWidgetExiting =
        desktopWidget &&
        minimizedPlacementTransition.exitsDesktop(placement.objectId);
    final desktopWidgetTransitionDuration =
        placementEntering || desktopWidgetExiting
        ? Motion.desktopWindowPlacementTransition
        : Motion.desktopWindowWidgetEnter;
    final suppressPositionAnimation =
        desktopWidgetEntering ||
        (minimizedIdle &&
            minimizedPlacementTransition.commitsOffscreen(placement.objectId));
    if (usesDesktopPlane != desktopPlane) {
      continue;
    }
    final arrangedFrame = minimizingForeground
        ? DesktopHomeLayout.offscreenFrame(
            bounds: minimizeOffscreenBounds,
            source: placement.frame,
          )
        : desktopWidgetExiting
        ? minimizedPlacementExitFrames[placement.objectId]
        : minimizedIdle
        ? desktopWidgetFrames[placement.objectId]
        : switching
        ? DesktopWindowSwitcherLayout.visualFrame(
            placement: placement,
            switcher: switcher,
            stageBounds: switcherStageBounds,
            desktopWidgetFrame: desktopWidgetFrames[placement.objectId],
          )
        : desktop.visualFrame(placement);
    if (arrangedFrame == null || arrangedFrame.isEmpty) {
      continue;
    }
    final frame = desktopPixelAlignedWindowFrame(
      frame: arrangedFrame,
      contentInset: placement.frameBorder,
      devicePixelRatio: devicePixelRatio,
      enabled: !overview && !switching && !minimizedIdle,
      alignSize: true,
    );
    final visible =
        minimizingForeground ||
        desktopWidget ||
        overview ||
        (switching
            ? DesktopWindowSwitcherLayout.isVisible(
                placement: placement,
                switcher: switcher,
              )
            : !offscreenMinimized);
    final motionDuration = reduceMotion
        ? Duration.zero
        : minimizedIdle
        ? Motion.desktopWindowWidget
        : switching
        ? DesktopWindowSwitcherLayout.motionDuration(switcher!)
        : overview
        ? Motion.overviewOpen
        : Motion.overviewClose;
    final active = switching
        ? DesktopWindowSwitcherLayout.isSelected(switcher, placement.objectId)
        : !overview && !placement.minimized && placement.z == topZ;
    layers.add(
      _DesktopWindowFrame(
        key: ValueKey<int>(placement.objectId),
        window: window,
        placement: placement,
        frame: frame,
        minimized: !visible,
        desktopWidget: desktopWidget,
        offscreenMinimized: minimizingForeground || offscreenMinimized,
        desktopWidgetEntering: desktopWidgetEntering,
        desktopWidgetExiting: desktopWidgetExiting,
        desktopWidgetTransitionDuration: desktopWidgetTransitionDuration,
        suppressPositionAnimation: suppressPositionAnimation,
        overviewActive: desktop.overviewActive,
        overview: overview,
        switching: switching,
        motionDuration: motionDuration,
        active: active,
        onOverviewTap: () => onActivateWindow(window),
        onOverviewDragStart: () => onBeginOverviewDrag(window),
        onOverviewDragUpdate: (delta) => onUpdateOverviewDrag(window, delta),
        onOverviewDragEnd: () => onEndOverviewDrag(window),
        onOverviewDragCancel: () => onCancelOverviewDrag(window),
      ),
    );
    if (!desktopWidget) {
      layers.add(
        _DesktopPopupSurfaceLayers(
          key: ValueKey<String>('desktop-popup-layers-${placement.objectId}'),
          window: window,
          placement: placement,
          frame: frame,
          minimized: !visible,
          offscreenMinimized: minimizingForeground || offscreenMinimized,
          overviewActive: desktop.overviewActive,
          overview: overview,
          switching: switching,
          motionDuration: motionDuration,
        ),
      );
    }
  }
  return layers;
}

class _DesktopScene extends ConsumerStatefulWidget {
  const _DesktopScene({
    required this.viewSize,
    required this.windows,
    required this.desktop,
    required this.closeEffect,
    required this.minimizedWindowPlacement,
    required this.panelTravel,
    required this.panelDurationScale,
    required this.windowSwitcher,
    required this.displayLayout,
    required this.frameTimingOptions,
    required this.wallpaperSelectorVisible,
    required this.shellOutputRect,
    required this.mainOutputRect,
    required this.applicationSearchFocusNode,
    required this.onOpenLauncher,
    required this.onDismissLauncher,
    required this.onOpenDashboard,
    required this.onOpenWallpaperSelector,
    required this.onCloseWallpaperSelector,
    required this.onOpenAppVolumeManager,
    required this.onOpenSettings,
    required this.onOpenPowerSettings,
    required this.onCancelPanelClose,
    required this.onSchedulePanelClose,
    required this.onPanelOpened,
    required this.onLaunchApp,
    required this.onLaunchLocalApp,
    required this.onActivateWindow,
    required this.onOverviewBarrierTap,
    required this.onToggleOverview,
    required this.onBeginOverviewDrag,
    required this.onUpdateOverviewDrag,
    required this.onEndOverviewDrag,
    required this.onCancelOverviewDrag,
    required this.onCloseLeaseComplete,
  });

  final Size viewSize;
  final List<DenialWindow> windows;
  final DesktopWorkspaceState desktop;
  final DesktopWindowCloseEffect closeEffect;
  final MinimizedWindowPlacement minimizedWindowPlacement;
  final double panelTravel;
  final double panelDurationScale;
  final DesktopWindowSwitcherState? windowSwitcher;
  final DisplayLayout? displayLayout;
  final ShellFrameTimingOptions frameTimingOptions;
  final bool wallpaperSelectorVisible;
  final Rect? shellOutputRect;
  final Rect? mainOutputRect;
  final FocusNode applicationSearchFocusNode;
  final VoidCallback onOpenLauncher;
  final VoidCallback onDismissLauncher;
  final VoidCallback onOpenDashboard;
  final VoidCallback onOpenWallpaperSelector;
  final VoidCallback onCloseWallpaperSelector;
  final VoidCallback onOpenAppVolumeManager;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenPowerSettings;
  final VoidCallback onCancelPanelClose;
  final VoidCallback onSchedulePanelClose;
  final VoidCallback onPanelOpened;
  final ValueChanged<DesktopApp> onLaunchApp;
  final ValueChanged<LocalFlutterApplication> onLaunchLocalApp;
  final ValueChanged<DenialWindow> onActivateWindow;
  final ValueChanged<Offset> onOverviewBarrierTap;
  final VoidCallback onToggleOverview;
  final ValueChanged<DenialWindow> onBeginOverviewDrag;
  final void Function(DenialWindow window, Offset delta) onUpdateOverviewDrag;
  final ValueChanged<DenialWindow> onEndOverviewDrag;
  final ValueChanged<DenialWindow> onCancelOverviewDrag;
  final ValueChanged<int> onCloseLeaseComplete;

  @override
  ConsumerState<_DesktopScene> createState() => _DesktopSceneState();
}

class _DesktopSceneState extends ConsumerState<_DesktopScene> {
  final Map<int, _ClosingDesktopWindow> _closingWindows =
      <int, _ClosingDesktopWindow>{};
  final Map<int, Rect> _minimizedPlacementExitFrames = <int, Rect>{};
  late final DesktopMinimizeLayerHandoffController _minimizeLayerHandoff;
  late final DesktopMinimizedPlacementTransitionController
  _minimizedPlacementTransition;
  int _nextCloseId = 1;
  _DesktopHomeLayoutCache? _homeLayoutCache;
  _DesktopSceneTopologyCache? _topologyCache;
  // Tray and dashboard expansions are notifier-backed so toggling them
  // rebuilds only the tray button and the bubbles instead of the whole
  // desktop scene. The notifiers mirror the provider state because
  // [ShelfLayer] and the bubble layers listen to [ValueListenable]s.
  late final ValueNotifier<bool> _shelfTrayExpanded = ValueNotifier<bool>(
    false,
  );
  late final ValueNotifier<bool> _shelfDashboardExpanded = ValueNotifier<bool>(
    false,
  );

  @override
  void initState() {
    super.initState();
    // The bubble expansions live in the provider so the shell can close them
    // from its transient-surface helper; mirror them into the local
    // ValueNotifiers that the shelf and bubble layers already listen to.
    ref.listenManual(desktopShelfBubblesProvider, (previous, next) {
      _shelfTrayExpanded.value = next.trayExpanded;
      _shelfDashboardExpanded.value = next.dashboardExpanded;
    }, fireImmediately: true);
    _minimizeLayerHandoff = DesktopMinimizeLayerHandoffController(
      handoffDelay: Motion.desktopWindowLayerHandoff,
      desktopEntryDuration: Motion.desktopWindowWidgetEnter,
      onChanged: () {
        if (mounted) {
          setState(() {});
        }
      },
    );
    _minimizedPlacementTransition =
        DesktopMinimizedPlacementTransitionController(
          duration: Motion.desktopWindowPlacementTransition,
          onChanged: () {
            if (!mounted) {
              return;
            }
            _minimizedPlacementExitFrames.removeWhere(
              (objectId, _) =>
                  !_minimizedPlacementTransition.exitsDesktop(objectId),
            );
            setState(() {});
          },
        );
  }

  _DesktopSceneTopology _cachedTopology({
    required List<DenialWindow> windows,
    required Map<int, DesktopWindowPlacement> placementMap,
    required DesktopWindowSwitcherState? windowSwitcher,
  }) {
    final cached = _topologyCache;
    if (cached != null &&
        cached.matches(windows, placementMap, windowSwitcher)) {
      return cached.topology;
    }
    final windowsById = <int, DenialWindow>{
      for (final window in windows) window.objectId: window,
    };
    final inputMethodPopups = windows
        .where((window) => window.isInputMethodPopup)
        .toList(growable: false);
    final placements =
        placementMap.values
            .where((placement) => windowsById.containsKey(placement.objectId))
            .toList(growable: false)
          ..sort(
            (a, b) => DesktopWindowSwitcherLayout.compare(
              a,
              b,
              windowsById,
              windowSwitcher,
            ),
          );
    final topology = (
      windowsById: windowsById,
      inputMethodPopups: inputMethodPopups,
      placements: placements,
      topZ: placements
          .where((placement) => !placement.minimized)
          .fold<int>(0, (value, placement) => math.max(value, placement.z)),
    );
    _topologyCache = _DesktopSceneTopologyCache(
      windows: windows,
      placementMap: placementMap,
      windowSwitcher: windowSwitcher,
      topology: topology,
    );
    return topology;
  }

  @override
  void didUpdateWidget(covariant _DesktopScene oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Entering the overview closes the shelf bubbles outright instead of
    // hiding them, so they do not pop back when the overview exits. The
    // overview barrier below never paints while the bubbles are open, so
    // deferring the close past this frame cannot leak a visible bubble.
    if (widget.desktop.overviewActive && !oldWidget.desktop.overviewActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.desktop.overviewActive) {
          ref.read(desktopShelfBubblesProvider.notifier).close();
        }
      });
    }
    final activeObjectIds = <int>{
      for (final window in widget.windows) window.objectId,
    };
    _minimizeLayerHandoff.retainOnly(activeObjectIds);
    final animateMinimize = !MediaQuery.disableAnimationsOf(context);
    for (final placement in widget.desktop.placements.values) {
      final previous = oldWidget.desktop.placements[placement.objectId];
      if (!placement.minimized) {
        _minimizeLayerHandoff.cancel(placement.objectId);
      } else if (previous?.minimized == false) {
        _minimizeLayerHandoff.begin(
          placement.objectId,
          animate: animateMinimize,
        );
      }
    }
    final minimizedObjectIds = <int>{
      for (final placement in widget.desktop.placements.values)
        if (placement.minimized && activeObjectIds.contains(placement.objectId))
          placement.objectId,
    };
    _minimizedPlacementTransition.retainOnly(minimizedObjectIds);
    _minimizedPlacementExitFrames.removeWhere(
      (objectId, _) => !minimizedObjectIds.contains(objectId),
    );
    if (oldWidget.minimizedWindowPlacement != widget.minimizedWindowPlacement) {
      final settledObjectIds = minimizedObjectIds
          .where(
            (objectId) => !_minimizeLayerHandoff.keepsOnForeground(objectId),
          )
          .toSet();
      final toDesktop =
          widget.minimizedWindowPlacement == MinimizedWindowPlacement.desktop;
      if (toDesktop) {
        _minimizedPlacementExitFrames.clear();
        _minimizedPlacementTransition.begin(
          settledObjectIds,
          toDesktop: true,
          animate: animateMinimize,
        );
      } else if (animateMinimize) {
        final previousFrames =
            _homeLayoutCache?.layout.windowFrames ?? const <int, Rect>{};
        _minimizedPlacementExitFrames
          ..clear()
          ..addEntries(
            settledObjectIds
                .where(previousFrames.containsKey)
                .map(
                  (objectId) => MapEntry(objectId, previousFrames[objectId]!),
                ),
          );
        _minimizedPlacementTransition.begin(
          _minimizedPlacementExitFrames.keys,
          toDesktop: false,
          animate: true,
        );
      } else {
        _minimizedPlacementExitFrames.clear();
        _minimizedPlacementTransition.begin(
          const <int>[],
          toDesktop: false,
          animate: false,
        );
      }
    }
    for (final window in oldWidget.windows.where(
      (window) => window.isUserApp,
    )) {
      if (activeObjectIds.contains(window.objectId)) {
        continue;
      }
      final placement = oldWidget.desktop.placements[window.objectId];
      if (widget.closeEffect == DesktopWindowCloseEffect.none ||
          !window.isUserApp ||
          window.suppressAnimations ||
          placement == null ||
          placement.minimized) {
        widget.onCloseLeaseComplete(window.windowId);
        continue;
      }
      final frame = oldWidget.desktop.visualFrame(placement);
      if (frame.isEmpty) {
        widget.onCloseLeaseComplete(window.windowId);
        continue;
      }
      final closeId = _nextCloseId++;
      _closingWindows[closeId] = _ClosingDesktopWindow(
        id: closeId,
        window: window,
        frame: frame,
        fullscreen:
            placement.fullscreen &&
            !oldWidget.desktop.isInOverview(window.objectId),
        effect: widget.closeEffect,
      );
    }
  }

  void _completeCloseAnimation(int closeId) {
    if (!mounted) {
      return;
    }
    final closing = _closingWindows[closeId];
    if (closing == null) {
      return;
    }
    setState(() => _closingWindows.remove(closeId));
    widget.onCloseLeaseComplete(closing.window.windowId);
  }

  _DesktopHomeSceneLayout _cachedDesktopHomeLayout({
    required Size viewSize,
    required DisplayLayout? displayLayout,
    required MinimizedWindowPlacement minimizedWindowPlacement,
    required Iterable<DesktopWindowPlacement> placements,
    required List<HomeGridItem?>? homeSlots,
    required bool hasBatteryData,
  }) {
    final cached = _homeLayoutCache;
    if (cached != null &&
        cached.matches(
          viewSize: viewSize,
          displayLayout: displayLayout,
          minimizedWindowPlacement: minimizedWindowPlacement,
          placements: placements,
          homeSlots: homeSlots,
          hasBatteryData: hasBatteryData,
        )) {
      return cached.layout;
    }
    final layout = _layoutDesktopHome(
      viewSize: viewSize,
      displayLayout: displayLayout,
      minimizedWindowPlacement: minimizedWindowPlacement,
      placements: placements,
      homeSlots: homeSlots,
      hasBatteryData: hasBatteryData,
    );
    _homeLayoutCache = _DesktopHomeLayoutCache(
      viewSize: viewSize,
      displayLayout: displayLayout,
      minimizedWindowPlacement: minimizedWindowPlacement,
      placements: placements,
      homeSlots: homeSlots,
      hasBatteryData: hasBatteryData,
      layout: layout,
    );
    return layout;
  }

  @override
  void dispose() {
    _minimizeLayerHandoff.dispose();
    _minimizedPlacementTransition.dispose();
    _shelfTrayExpanded.dispose();
    _shelfDashboardExpanded.dispose();
    _minimizedPlacementExitFrames.clear();
    for (final closing in _closingWindows.values) {
      widget.onCloseLeaseComplete(closing.window.windowId);
    }
    _closingWindows.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewSize = widget.viewSize;
    final windows = widget.windows;
    final desktop = widget.desktop;
    final windowSwitcher = widget.windowSwitcher;
    final displayLayout = widget.displayLayout;
    final minimizedWindowPlacement = widget.minimizedWindowPlacement;
    final frameTimingOptions = widget.frameTimingOptions;
    final wallpaperSelectorVisible = widget.wallpaperSelectorVisible;
    final shellOutputRect = widget.shellOutputRect;
    final mainOutputRect = widget.mainOutputRect;
    final applicationSearchFocusNode = widget.applicationSearchFocusNode;
    final onOpenLauncher = widget.onOpenLauncher;
    final onDismissLauncher = widget.onDismissLauncher;
    final onOpenDashboard = widget.onOpenDashboard;
    final onOpenSettings = widget.onOpenSettings;
    final onOpenPowerSettings = widget.onOpenPowerSettings;
    final onOpenWallpaperSelector = widget.onOpenWallpaperSelector;
    final onCloseWallpaperSelector = widget.onCloseWallpaperSelector;
    final onOpenAppVolumeManager = widget.onOpenAppVolumeManager;
    final onCancelPanelClose = widget.onCancelPanelClose;
    final onSchedulePanelClose = widget.onSchedulePanelClose;
    final onLaunchApp = widget.onLaunchApp;
    final onLaunchLocalApp = widget.onLaunchLocalApp;
    final onActivateWindow = widget.onActivateWindow;
    final onOverviewBarrierTap = widget.onOverviewBarrierTap;
    final onBeginOverviewDrag = widget.onBeginOverviewDrag;
    final onUpdateOverviewDrag = widget.onUpdateOverviewDrag;
    final onEndOverviewDrag = widget.onEndOverviewDrag;
    final onCancelOverviewDrag = widget.onCancelOverviewDrag;
    final topology = _cachedTopology(
      windows: windows,
      placementMap: desktop.placements,
      windowSwitcher: windowSwitcher,
    );
    final windowsById = topology.windowsById;
    final inputMethodPopups = topology.inputMethodPopups;
    final placements = topology.placements
        .where(
          (placement) =>
              placement.minimized || desktop.isPlacementPresented(placement),
        )
        .toList(growable: false);
    final homeSlots = ref.watch(
      homeGridControllerProvider.select((state) => state.asData?.value.slots),
    );
    final hasBatteryData = ref.watch(
      homeBatteryDischargeProvider.select(
        (series) =>
            series.asData?.value.points.any(
              (point) =>
                  point.capacity != null ||
                  point.currentMa != null ||
                  point.voltageMv != null ||
                  point.powerMw != null,
            ) ??
            false,
      ),
    );
    final useChromeOsShelf = ref.watch(
      shellSettingsProvider.select((s) => s.layout.useChromeOsShelf),
    );
    // The provider (not a local notifier) backs the bubble expansions so the
    // shell's transient-surface helper can close them from outside the scene.
    // Watching here rebuilds only the shelf button strip and bubbles.
    final bubblesState = ref.watch(desktopShelfBubblesProvider);
    final shelfBubbles = ref.read(desktopShelfBubblesProvider.notifier);
    final homeLayout = _cachedDesktopHomeLayout(
      viewSize: viewSize,
      displayLayout: displayLayout,
      minimizedWindowPlacement: minimizedWindowPlacement,
      placements: placements,
      homeSlots: homeSlots,
      hasBatteryData: hasBatteryData,
    );
    // Rising above another workspace's window must not raise the shell's
    // z-order for windows the user cannot see.
    final topZ = placements
        .where(
          (placement) =>
              !placement.minimized &&
              desktop.isPlacementOnActiveWorkspace(placement),
        )
        .fold<int>(0, (value, placement) => math.max(value, placement.z));
    final systemBars = _systemBarGeometries(viewSize, displayLayout);
    // True fullscreen owns the complete output, so the bar yields instead of
    // floating above the fullscreen surface.
    final List<({int monitorId, Rect rect, SystemBarSide side})>
    visibleSystemBars;
    if (desktop.overviewActive) {
      visibleSystemBars = systemBars;
    } else {
      final fullscreenMonitorIds = <int>{
        for (final placement in placements)
          if (placement.fullscreen && !placement.minimized) placement.monitorId,
      };
      visibleSystemBars = fullscreenMonitorIds.isEmpty
          ? systemBars
          : systemBars
                .where((bar) => !fullscreenMonitorIds.contains(bar.monitorId))
                .toList(growable: false);
    }
    final canvas = Offset.zero & viewSize;
    // Bubbles dock to the output whose shelf opened them; keyboard entry
    // resolves the same geometry through the primary output.
    final bubbleAnchor = desktopShelfBubbleAnchorGeometry(
      anchorMonitorId: bubblesState.anchorMonitorId,
      displayLayout: displayLayout,
      systemBars: systemBars,
      viewSize: viewSize,
    );
    final requestedDisplayRect = mainOutputRect?.intersect(canvas);
    final mainDisplayRect =
        requestedDisplayRect == null || requestedDisplayRect.isEmpty
        ? canvas
        : requestedDisplayRect;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    final selectorMotionDuration = reduceMotion
        ? Duration.zero
        : Motion.wallpaperSelector;
    final switcherStageBounds = windowSwitcher == null
        ? Rect.zero
        : _windowSwitcherStageBounds(
            viewSize: viewSize,
            displayLayout: displayLayout,
            desktop: desktop,
            switcher: windowSwitcher,
          );

    return Stack(
      fit: StackFit.expand,
      children: [
        const ShellWallpaper(),
        Positioned.fill(
          child: IgnorePointer(
            ignoring: wallpaperSelectorVisible,
            child: AnimatedOpacity(
              duration: selectorMotionDuration,
              curve: Motion.md3EmphasizedAccelerate,
              opacity: wallpaperSelectorVisible ? 0.0 : 1.0,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _DesktopWidgetCanvas(
                    widgets: homeLayout.widgets,
                    frames: homeLayout.widgetFrames,
                  ),
                  ..._buildDesktopWindowLayers(
                    placements: placements,
                    windowsById: windowsById,
                    desktop: desktop,
                    desktopPlane: true,
                    minimizeLayerHandoff: _minimizeLayerHandoff,
                    minimizedPlacementTransition: _minimizedPlacementTransition,
                    minimizedPlacementExitFrames: _minimizedPlacementExitFrames,
                    minimizeOffscreenBounds: canvas,
                    minimizedWindowPlacement: minimizedWindowPlacement,
                    desktopWidgetFrames: homeLayout.windowFrames,
                    switcher: windowSwitcher,
                    switcherStageBounds: switcherStageBounds,
                    topZ: topZ,
                    reduceMotion: reduceMotion,
                    devicePixelRatio: devicePixelRatio,
                    onActivateWindow: onActivateWindow,
                    onBeginOverviewDrag: onBeginOverviewDrag,
                    onUpdateOverviewDrag: onUpdateOverviewDrag,
                    onEndOverviewDrag: onEndOverviewDrag,
                    onCancelOverviewDrag: onCancelOverviewDrag,
                  ),
                  // The bar belongs to the wallpaper plane. Any window moved
                  // into its reserved strip paints and receives input above it.
                  for (final bar in visibleSystemBars)
                    Positioned.fromRect(
                      key: ValueKey<String>('system-bar-${bar.monitorId}'),
                      rect: bar.rect,
                      child: useChromeOsShelf
                          ? ShelfLayer(
                              height: bar.rect.height,
                              monitorId: bar.monitorId,
                              onLauncherPressed: () {
                                shelfBubbles.close();
                                onOpenLauncher();
                              },
                              trayExpanded: _shelfTrayExpanded,
                              onTrayPressed: () {
                                if (!ref
                                    .read(desktopShelfBubblesProvider)
                                    .trayExpanded) {
                                  onDismissLauncher();
                                  // A bubble owns the screen above the
                                  // overview, so opening it dismisses the
                                  // overview instead of stacking on it.
                                  if (desktop.overviewActive) {
                                    ref
                                        .read(desktopWorkspaceProvider.notifier)
                                        .closeOverview();
                                  }
                                }
                                shelfBubbles.toggleTray(
                                  anchorMonitorId: bar.monitorId,
                                );
                              },
                              calendarExpanded: _shelfDashboardExpanded,
                              onClockPressed: () {
                                if (!ref
                                    .read(desktopShelfBubblesProvider)
                                    .dashboardExpanded) {
                                  onDismissLauncher();
                                  // Same mutual exclusion as the tray button.
                                  if (desktop.overviewActive) {
                                    ref
                                        .read(desktopWorkspaceProvider.notifier)
                                        .closeOverview();
                                  }
                                }
                                shelfBubbles.toggleDashboard(
                                  anchorMonitorId: bar.monitorId,
                                );
                              },
                            )
                          : DesktopSystemBar(
                              side: bar.side,
                              onOpenPowerSettings: onOpenPowerSettings,
                            ),
                    ),
                  Positioned.fill(
                    child: ShellInputRegion(
                      debugLabel: 'Desktop overview',
                      active: desktop.overviewActive,
                      pointerPolicy: ShellPointerPolicy.fullScene,
                      keyboardPolicy: ShellKeyboardPolicy.capture,
                      compositorPolicy: ShellCompositorPolicy.exclusive,
                      child: DesktopOverviewEscapeScope(
                        active: desktop.overviewActive,
                        onEscape: widget.onToggleOverview,
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: _DesktopOverviewBarrier(
                      active: desktop.overviewActive,
                      onTap: onOverviewBarrierTap,
                    ),
                  ),
                  if (windowSwitcher != null)
                    DesktopWindowSwitcherBackdrop(
                      switcher: windowSwitcher,
                      bounds: switcherStageBounds,
                    ),
                  ..._buildDesktopWindowLayers(
                    placements: placements,
                    windowsById: windowsById,
                    desktop: desktop,
                    desktopPlane: false,
                    minimizeLayerHandoff: _minimizeLayerHandoff,
                    minimizedPlacementTransition: _minimizedPlacementTransition,
                    minimizedPlacementExitFrames: _minimizedPlacementExitFrames,
                    minimizeOffscreenBounds: canvas,
                    minimizedWindowPlacement: minimizedWindowPlacement,
                    desktopWidgetFrames: homeLayout.windowFrames,
                    switcher: windowSwitcher,
                    switcherStageBounds: switcherStageBounds,
                    topZ: topZ,
                    reduceMotion: reduceMotion,
                    devicePixelRatio: devicePixelRatio,
                    onActivateWindow: onActivateWindow,
                    onBeginOverviewDrag: onBeginOverviewDrag,
                    onUpdateOverviewDrag: onUpdateOverviewDrag,
                    onEndOverviewDrag: onEndOverviewDrag,
                    onCancelOverviewDrag: onCancelOverviewDrag,
                  ),
                  for (final closing in _closingWindows.values)
                    Positioned.fromRect(
                      key: ValueKey<String>(
                        'desktop-closing-window-${closing.id}',
                      ),
                      rect: closing.frame,
                      child: _DesktopClosingWindowFrame(
                        closing: closing,
                        onCompleted: () => _completeCloseAnimation(closing.id),
                      ),
                    ),
                  if (windowSwitcher != null)
                    DesktopWindowSwitcherLayer(
                      key: ValueKey<String>(
                        'desktop-window-switcher-${windowSwitcher.sessionId}',
                      ),
                      switcher: windowSwitcher,
                      selectedWindow:
                          windowsById[windowSwitcher.selectedObjectId],
                      stageBounds: switcherStageBounds,
                    ),
                  const Positioned.fill(child: SystemTrayMenuDismissLayer()),
                  _DesktopPanelOverlay(
                    viewSize: viewSize,
                    shellOutputRect: shellOutputRect,
                    panelTravel: widget.panelTravel,
                    panelDurationScale: widget.panelDurationScale,
                    applicationSearchFocusNode: applicationSearchFocusNode,
                    onOpenLauncher: onOpenLauncher,
                    onDismissLauncher: onDismissLauncher,
                    onOpenDashboard: onOpenDashboard,
                    onOpenWallpaperSelector: onOpenWallpaperSelector,
                    onOpenAppVolumeManager: onOpenAppVolumeManager,
                    onOpenSettings: onOpenSettings,
                    onCancelPanelClose: onCancelPanelClose,
                    onSchedulePanelClose: onSchedulePanelClose,
                    onPanelOpened: widget.onPanelOpened,
                    onLaunchApp: onLaunchApp,
                    onLaunchLocalApp: onLaunchLocalApp,
                  ),
                  if (useChromeOsShelf)
                    Positioned.fill(
                      child: ValueListenableBuilder<bool>(
                        valueListenable: _shelfTrayExpanded,
                        builder: (context, shelfTrayExpanded, _) {
                          final trayVisible = shelfTrayExpanded;
                          return ShellInputRegion(
                            debugLabel: 'Unified tray bubble',
                            active: trayVisible,
                            pointerPolicy: ShellPointerPolicy.fullScene,
                            keyboardPolicy: trayVisible
                                ? ShellKeyboardPolicy.capture
                                : ShellKeyboardPolicy.none,
                            child: IgnorePointer(
                              ignoring: !shelfTrayExpanded,
                              child: UnifiedTrayBubble(
                                key: const ValueKey<String>(
                                  'shelf-unified-tray-bubble',
                                ),
                                visible: trayVisible,
                                onDismiss: () => shelfBubbles.close(),
                                onOpenOverview: () {
                                  shelfBubbles.close();
                                  widget.onToggleOverview();
                                },
                                shelfHeight: bubbleAnchor.shelfHeight,
                                outputRect: bubbleAnchor.outputRect,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  if (useChromeOsShelf)
                    Positioned.fill(
                      child: ValueListenableBuilder<bool>(
                        valueListenable: _shelfDashboardExpanded,
                        builder: (context, shelfDashboardExpanded, _) {
                          final dashboardVisible = shelfDashboardExpanded;
                          return ShellInputRegion(
                            debugLabel: 'Unified dashboard panel',
                            active: dashboardVisible,
                            pointerPolicy: ShellPointerPolicy.fullScene,
                            keyboardPolicy: dashboardVisible
                                ? ShellKeyboardPolicy.capture
                                : ShellKeyboardPolicy.none,
                            child: IgnorePointer(
                              ignoring: !shelfDashboardExpanded,
                              child: UnifiedDashboardPanel(
                                key: const ValueKey<String>(
                                  'shelf-unified-dashboard-panel',
                                ),
                                visible: dashboardVisible,
                                onDismiss: () => shelfBubbles.close(),
                                shelfHeight: bubbleAnchor.shelfHeight,
                                outputRect: bubbleAnchor.outputRect,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  for (final popup in inputMethodPopups)
                    if (popup.geometry case final geometry?)
                      RetainedAnimatedPositioned(
                        key: ValueKey<String>(
                          'desktop-input-method-popup-${popup.objectId}',
                        ),
                        duration: reduceMotion
                            ? Duration.zero
                            : Motion.inputMethodPopup,
                        curve: Motion.standard,
                        rect: geometry,
                        child: IgnorePointer(
                          child: WindowSurfaceTree(
                            window: popup,
                            includePopups: true,
                          ),
                        ),
                      ),
                  if (frameTimingOptions.showOverlay)
                    Positioned(
                      top: 12,
                      right: 12,
                      child: ShellFrameTimingOverlayStack(
                        windows: windows,
                        showImportedTextureCharts:
                            frameTimingOptions.showImportedTextureCharts,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const ClipboardTrayLayer(),
        Positioned.fill(
          child: ShellInputRegion(
            debugLabel: 'Wallpaper selector',
            active: wallpaperSelectorVisible,
            pointerPolicy: ShellPointerPolicy.fullScene,
            keyboardPolicy: ShellKeyboardPolicy.capture,
            compositorPolicy: ShellCompositorPolicy.exclusive,
            child: WallpaperSelectorOverlay(
              visible: wallpaperSelectorVisible,
              displayRect: mainDisplayRect,
              onDismiss: onCloseWallpaperSelector,
            ),
          ),
        ),
      ],
    );
  }
}

/// Claims the captured keyboard while the desktop overview is active so
/// Escape can dismiss the overview.
///
/// The overview's [ShellInputRegion] routes native keyboard into the shell,
/// but key events still travel Flutter's focus tree, so the surface needs a
/// focus scope that answers Escape — the launcher and the shelf bubbles
/// already follow this convention. Pointer input stays ignored: window
/// previews sit above this scope and own their own taps.
class DesktopOverviewEscapeScope extends StatefulWidget {
  const DesktopOverviewEscapeScope({
    required this.active,
    required this.onEscape,
    super.key,
  });

  final bool active;
  final VoidCallback onEscape;

  @override
  State<DesktopOverviewEscapeScope> createState() =>
      _DesktopOverviewEscapeScopeState();
}

class _DesktopOverviewEscapeScopeState
    extends State<DesktopOverviewEscapeScope> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'desktop-overview-escape');

  @override
  void initState() {
    super.initState();
    if (widget.active) {
      _requestFocus();
    }
  }

  @override
  void didUpdateWidget(covariant DesktopOverviewEscapeScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _requestFocus();
    }
  }

  void _requestFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.active && !_focusNode.hasFocus) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (widget.active &&
        event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onEscape();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Focus(
        focusNode: _focusNode,
        onKeyEvent: _handleKeyEvent,
        child: const SizedBox.expand(),
      ),
    );
  }
}
