import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../input/input_layout.dart';
import '../input/shell_interaction_registry.dart';
import '../input/shell_visual_registry.dart';
import '../models/denial_window.dart';
import '../state/desktop_window_switcher.dart';
import '../state/shell_controller.dart';
import '../state/shell_render_mode.dart';
import 'desktop_taskbar_preview.dart';
import 'desktop_visibility.dart';
import 'desktop_workspace.dart';
import '../platform/denial_wire.dart' as wire;
import '../models/display_layout.dart';
import '../state/display_layout.dart';

class DesktopInputLayoutPublisher extends ConsumerStatefulWidget {
  const DesktopInputLayoutPublisher({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<DesktopInputLayoutPublisher> createState() =>
      _DesktopInputLayoutPublisherState();
}

class _DesktopInputLayoutPublisherState
    extends ConsumerState<DesktopInputLayoutPublisher> {
  final DesktopWindowConfigureTracker _configureTracker =
      DesktopWindowConfigureTracker();
  bool _scheduled = false;
  int _epoch = 0;
  int _certificateEpoch = 0;
  int _shellRevision = 0;
  String? _lastCertificateKey;
  String? _lastClientCertificateKey;
  Rect _lastShellVisibleBounds = Rect.zero;
  int _lastShellVisualRevision = 0;
  InputLayoutSnapshot? _lastSnapshot;

  @override
  Widget build(BuildContext context) {
    ref.watch(
      shellControllerProvider.select(
        (state) => (state.windows, state.windowSnapshotSequence),
      ),
    );
    ref.watch(desktopWorkspaceProvider);
    ref.watch(desktopWindowSwitcherProvider);
    ref.watch(shellInteractionRegistryProvider);
    ref.watch(shellVisualRegistryProvider);
    ref.watch(shellRenderModeProvider);
    ref.watch(
      desktopTaskbarPreviewProvider.select((target) => target?.objectId),
    );
    _schedulePublish(
      MediaQuery.sizeOf(context),
      MediaQuery.devicePixelRatioOf(context),
    );
    return widget.child;
  }

  void _schedulePublish(Size viewSize, double devicePixelRatio) {
    if (_scheduled) {
      return;
    }
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) {
        return;
      }

      final shell = ref.read(shellControllerProvider);
      final windows = shell.windows;
      ref
          .read(desktopWorkspaceProvider.notifier)
          .syncWindows(
            windows,
            viewSize,
            devicePixelRatio,
            snapshotSequence: shell.windowSnapshotSequence,
          );
      _publish(
        viewSize,
        ref.read(shellControllerProvider).windows,
        ref.read(desktopWorkspaceProvider),
        ref.read(shellInteractionRegistryProvider),
        shell.windowSnapshotSequence,
      );
    });
  }

  void _publish(
    Size viewSize,
    List<DenialWindow> windows,
    DesktopWorkspaceState desktop,
    ShellInteractionSnapshot interactions,
    int layoutEpoch,
  ) {
    if (viewSize.width <= 0.0 || viewSize.height <= 0.0) {
      return;
    }

    final windowsById = <int, DenialWindow>{
      for (final window in windows)
        if (window.isUserApp) window.objectId: window,
    };
    final inputMethodPopups = windows
        .where((window) => window.isInputMethodPopup && window.geometry != null)
        .toList(growable: false);
    final switcher = ref.read(desktopWindowSwitcherProvider);
    final previewTarget = ref.read(desktopTaskbarPreviewProvider);
    final sampledSwitcherIds =
        interactions.capturesFullScene && (switcher?.isSelecting ?? false)
        ? switcher!.objectIds.toSet()
        : const <int>{};
    final placements =
        desktop.placements.values
            .where(
              (placement) =>
                  (!placement.minimized ||
                      desktop.isInOverview(placement.objectId) ||
                      sampledSwitcherIds.contains(placement.objectId) ||
                      previewTarget?.objectId == placement.objectId) &&
                  windowsById.containsKey(placement.objectId),
            )
            .toList(growable: false)
          ..sort((a, b) => compareDesktopWindowStack(a, b, windowsById));

    final canvas = Offset.zero & viewSize;
    var shellRegions = <Rect>[canvas];
    // Hover panels must not take pointer ownership of the whole scene. Changing
    // ownership while leaving a hot edge can synthesize another edge enter and
    // make the launcher repeatedly open and close over client windows.
    if (!interactions.capturesFullScene) {
      for (final popup in inputMethodPopups) {
        shellRegions = _subtractFromAll(shellRegions, popup.geometry!);
      }
      for (final placement in placements) {
        final visualContentRect = placement.contentRect;
        shellRegions = _subtractFromAll(shellRegions, visualContentRect);
        final window = windowsById[placement.objectId]!;
        for (final popup in window.popupRoots) {
          shellRegions = _subtractFromAll(
            shellRegions,
            window.mapSurfaceRect(popup, visualContentRect),
          );
        }
      }
      // The cuts above are z-order blind, so a lower window's content rect also
      // erases the shell-drawn frame ring of every window stacked above it.
      shellRegions.addAll(
        desktopFrameRingRegions(canvas, <DesktopFrameRing>[
          for (final placement in placements.reversed)
            DesktopFrameRing(
              frame: placement.frame,
              content: placement.contentRect,
              resizeHotZones: desktopResizeHotZones(placement),
              popups: <Rect>[
                for (final popup in windowsById[placement.objectId]!.popupRoots)
                  windowsById[placement.objectId]!.mapSurfaceRect(
                    popup,
                    placement.contentRect,
                  ),
              ],
            ),
        ]),
      );
      shellRegions.addAll(
        desktopResizeHotZoneRegions(canvas, <DesktopFrameRing>[
          for (final placement in placements.reversed)
            DesktopFrameRing(
              frame: placement.frame,
              content: placement.contentRect,
              resizeHotZones: desktopResizeHotZones(placement),
              popups: <Rect>[
                for (final popup in windowsById[placement.objectId]!.popupRoots)
                  windowsById[placement.objectId]!.mapSurfaceRect(
                    popup,
                    placement.contentRect,
                  ),
              ],
            ),
        ]),
      );
    }
    for (final region in interactions.childRegions) {
      final clipped = region.intersect(canvas);
      if (!clipped.isEmpty) {
        shellRegions.add(clipped);
      }
    }

    final inputWindows = <InputWindowRegion>[];
    for (final popup in inputMethodPopups) {
      if (!interactions.capturesFullScene) {
        inputWindows.add(
          InputWindowRegion(
            window: popup,
            surfaceId: popup.objectId,
            rect: popup.geometry!,
            sourceRect: popup.contentCoordinateRect,
            z: 0x7fffffff,
            geometryLocked: true,
          ),
        );
      }
    }
    // Minimized windows do not need continuous presentation sampling unless
    // an active taskbar preview is currently hovering over them.
    final zStride = placements.fold<int>(2, (stride, placement) {
      final layers = windowsById[placement.objectId]!.surfaceLayers.length + 2;
      return math.max(stride, layers);
    });
    final placementOrder = <int, int>{
      for (var index = 0; index < placements.length; index += 1)
        placements[index].objectId: index,
    };
    // The wire hit tester consumes the first matching window. Build this list
    // in its final topmost-first order so the codec normally needs neither a
    // defensive copy nor another sort.
    for (final placement in placements.reversed) {
      if (interactions.capturesFullScene) {
        final window = windowsById[placement.objectId]!;
        _configureWindowGeometry(window, placement);
        continue;
      }
      final window = windowsById[placement.objectId]!;
      final visualContentRect = placement.contentRect;
      final sourceRect = window.contentCoordinateRect;
      final baseZ = placementOrder[placement.objectId]! * zStride;
      final popupRoots = window.popupRoots.toList(growable: false).reversed;
      for (final popup in popupRoots) {
        inputWindows.add(
          InputWindowRegion(
            window: window,
            surfaceId: popup.surfaceId,
            rect: window.mapSurfaceRect(popup, visualContentRect),
            sourceRect: Rect.fromLTWH(
              0.0,
              0.0,
              popup.surfaceWidth,
              popup.surfaceHeight,
            ),
            z: baseZ + popup.compositionOrder + 1,
            geometryLocked: placement.fullscreen,
          ),
        );
      }
      inputWindows.add(
        InputWindowRegion(
          window: window,
          // A logical window region routes through the complete toplevel
          // surface tree. The primary texture may be a full-window child and
          // is a rendering choice, not an input target.
          surfaceId: window.objectId,
          rect: visualContentRect,
          sourceRect: sourceRect,
          z: baseZ,
          geometryLocked: placement.fullscreen,
        ),
      );
      _configureWindowGeometry(window, placement);
    }

    final forcedWindowIds = <int>{
      if (previewTarget != null) previewTarget.objectId,
    };
    // The current wire carries a global canvas, not output-scoped geometry.
    // A single-output scene can safely use that canvas. With multiple monitor
    // IDs, output ownership is unknown, so the evaluator must retain all
    // clients until an output-scoped report is added to the wire.
    final monitorIds = placements
        .map((placement) => placement.monitorId)
        .toSet();
    final outputRects = monitorIds.length <= 1
        ? <({int id, Rect rect})>[
            (id: monitorIds.isEmpty ? -1 : monitorIds.first, rect: canvas),
          ]
        : <({int id, Rect rect})>[(id: -1, rect: Rect.zero)];
    final visibility = <int>{};
    for (final output in outputRects) {
      visibility.addAll(
        computeConservativeVisibleRegions(
          layoutEpoch: layoutEpoch,
          outputId: output.id,
          outputRect: output.rect,
          placements: placements,
          windowsById: windowsById,
          forcedWindowIds: forcedWindowIds,
          forceAll: interactions.capturesFullScene,
        ).visibleSurfaceIds,
      );
    }
    for (final popup in inputMethodPopups) {
      visibility.addAll(popup.visibleSurfaceIds);
    }

    _configureTracker.retainWindowIds(windowsById.keys.toSet());
    final snapshot = InputLayoutSnapshot(
      epoch: _epoch + 1,
      shellRegions: shellRegions,
      windows: inputWindows,
      visibleSurfaceIds: visibility.toList(growable: false)..sort(),
      visibilityEpoch: layoutEpoch,
      keyboardCapture: interactions.capturesKeyboard,
      exclusiveShellMode: interactions.compositorExclusive,
    );
    final routingChanged =
        !(_lastSnapshot?.hasSameRoutingAs(snapshot) ?? false);
    if (routingChanged &&
        !ref.read(denialBridgeProvider).publishInputLayout(snapshot)) {
      return;
    }
    _publishCompositionCertificate(
      viewSize: viewSize,
      windows: windows,
      placements: placements,
      interactions: interactions,
      layoutEpoch: layoutEpoch,
      outputLayout: ref.read(displayLayoutProvider),
      previewActive: previewTarget != null || desktop.overviewActive,
    );
    if (routingChanged) {
      _epoch = snapshot.epoch;
      _lastSnapshot = snapshot;
    }
  }

  void _publishCompositionCertificate({
    required Size viewSize,
    required List<DenialWindow> windows,
    required List<DesktopWindowPlacement> placements,
    required ShellInteractionSnapshot interactions,
    required int layoutEpoch,
    required DisplayLayout? outputLayout,
    required bool previewActive,
  }) {
    final bridge = ref.read(denialBridgeProvider);
    final visuals = ref.read(shellVisualRegistryProvider);
    final output = outputLayout?.outputs.length == 1
        ? outputLayout!.outputs.single
        : null;
    DesktopWindowPlacement? candidate;
    if (output != null) {
      for (final placement in placements.reversed) {
        if (placement.monitorId == output.monitorId && placement.fullscreen) {
          candidate = placement;
          break;
        }
      }
    }
    DenialWindow? window;
    if (candidate != null) {
      for (final item in windows) {
        if (item.objectId == candidate.objectId) {
          window = item;
          break;
        }
      }
    }
    final eligibleShape =
        output != null &&
        candidate != null &&
        window != null &&
        candidate.fullscreen &&
        !candidate.minimized &&
        !interactions.capturesFullScene &&
        !previewActive &&
        window.isUserApp &&
        window.popupRoots.isEmpty &&
        window.surfaceLayers.length == 1 &&
        window.isOpaque &&
        window.transform == 0 &&
        _coversOutput(candidate.contentRect, output.logicalRect) &&
        window.contentCoordinateRect.width > 0.0 &&
        window.contentCoordinateRect.height > 0.0;
    final canvas = Offset.zero & viewSize;
    final visibleRects = visuals.orderedSurfaces
        .map((surface) => surface.bounds.intersect(canvas))
        .where((rect) => !rect.isEmpty)
        .toList(growable: false);
    final shellVisibleBounds = _unionRects(visibleRects);
    final visualRevision = visuals.revision;
    final shellDamage = visualRevision == _lastShellVisualRevision
        ? Rect.zero
        : _unionRects(<Rect>[_lastShellVisibleBounds, shellVisibleBounds]);
    final overlayCompatible = eligibleShape && !visuals.requiresClientSampling;
    final overlayRendering =
        output != null &&
        ref.read(shellRenderModeProvider).overlayEnabledFor(output.monitorId);
    final clientCertificateKey = <Object?>[
      layoutEpoch,
      output?.monitorId ?? 0,
      outputLayout?.epoch ?? layoutEpoch,
      eligibleShape ? window.objectId : 0,
      eligibleShape,
      previewActive,
      interactions.capturesFullScene,
      candidate?.dragging ?? false,
      overlayCompatible,
    ].join(':');
    if (_lastClientCertificateKey != clientCertificateKey) {
      _lastClientCertificateKey = clientCertificateKey;
      _certificateEpoch += 1;
    }
    final certificateKey = <Object?>[
      clientCertificateKey,
      visualRevision,
      shellVisibleBounds,
      overlayRendering,
    ].join(':');
    if (_lastCertificateKey == certificateKey) {
      return;
    }
    _lastCertificateKey = certificateKey;
    _shellRevision += 1;
    final certificate = wire.DenialCompositionCertificate(
      certificateEpoch: _certificateEpoch,
      layoutEpoch: layoutEpoch,
      outputId: output?.monitorId ?? 0,
      outputConfigurationEpoch: outputLayout?.epoch ?? layoutEpoch,
      soleRootSurfaceId: eligibleShape ? window.objectId : 0,
      surfaceTreeRevision: eligibleShape ? 1 : 0,
      bufferRevision: eligibleShape ? 1 : 0,
      sourceRect: eligibleShape ? window.contentCoordinateRect : Rect.zero,
      destinationRect: eligibleShape ? candidate.contentRect : Rect.zero,
      outputPixelSize: output?.pixelSize ?? viewSize,
      scale: output?.scale ?? 1.0,
      transform: output == null ? 0 : 0,
      knownOpaque: eligibleShape,
      shellFullyTransparent: eligibleShape && shellVisibleBounds.isEmpty,
      requiresClientSampling: !eligibleShape || visuals.requiresClientSampling,
      hasPopup: window?.popupRoots.isNotEmpty ?? false,
      hasSubsurface: (window?.surfaceLayers.length ?? 0) > 1,
      hasDragIcon: candidate?.dragging ?? false,
      hasIme: false,
      hasPreview: previewActive,
      hasCapture: interactions.capturesFullScene,
      hasEffect: visuals.requiresClientSampling,
      colorClass: wire.CompositionColorClass.Unknown,
      reasonFlags: eligibleShape ? 0 : 1,
      engineGeneration: 1,
      shellDamage: shellDamage,
      shellVisibleBounds: shellVisibleBounds,
      shellRevision: _shellRevision,
      overlayCompatible: overlayCompatible,
      overlayRendering: overlayRendering,
    );
    if (bridge.publishCompositionCertificate(certificate)) {
      _lastShellVisibleBounds = shellVisibleBounds;
      _lastShellVisualRevision = visualRevision;
    }
  }

  Rect _unionRects(Iterable<Rect> rects) {
    Rect result = Rect.zero;
    for (final rect in rects) {
      if (rect.isEmpty) {
        continue;
      }
      result = result.isEmpty ? rect : result.expandToInclude(rect);
    }
    return result;
  }

  bool _coversOutput(Rect candidate, Rect output) {
    const epsilon = 1.0;
    return (candidate.left - output.left).abs() <= epsilon &&
        (candidate.top - output.top).abs() <= epsilon &&
        (candidate.right - output.right).abs() <= epsilon &&
        (candidate.bottom - output.bottom).abs() <= epsilon;
  }

  void _configureWindowGeometry(
    DenialWindow window,
    DesktopWindowPlacement placement,
  ) {
    if (placement.shellDragging) {
      // A titlebar drag repositions the frame in Dart on every pointer move,
      // and only input routing and composition — both republished here each
      // frame — depend on it until the pointer is released. Reporting each step
      // would configure the client at pointer rate for nothing; reporting the
      // rectangle without sending it would be worse still, because the tracker
      // caches whatever it is handed and would then treat the final position as
      // already configured and never send it at all. Skip the drag outright and
      // let the position Rust needs go out when [DesktopWorkspaceController.
      // endMove] clears the flag.
      return;
    }
    final configuredGeometry = _configureTracker.update(
      window.objectId,
      placement.contentRect,
      nativeDragActive: placement.nativeGrab,
      configureInitial: placement.shellCorrectedInitialGeometry,
    );
    if (configuredGeometry == null) {
      return;
    }
    ref.read(denialBridgeProvider).configureWindow(window, configuredGeometry);
  }
}

/// Tracks complete shell-authored window rectangles crossing the native
/// bridge. Location is part of the identity: dropping a position-only update
/// leaves Rust hit testing and Flutter composition on different coordinates.
class DesktopWindowConfigureTracker {
  final Map<int, ({int left, int top, int width, int height})> _configured =
      <int, ({int left, int top, int width, int height})>{};

  Rect? update(
    int objectId,
    Rect contentRect, {
    required bool nativeDragActive,
    bool configureInitial = false,
  }) {
    final geometry = (
      left: contentRect.left.round().clamp(-16384, 16384),
      top: contentRect.top.round().clamp(-16384, 16384),
      width: contentRect.width.round().clamp(64, 16384),
      height: contentRect.height.round().clamp(64, 16384),
    );
    final previous = _configured[objectId];
    _configured[objectId] = geometry;
    if (previous == null) {
      // The native compositor owns initial placement and sizing. Seed from
      // the received geometry instead of echoing a newly discovered window,
      // unless the shell deliberately corrected the initial geometry to keep
      // its titlebar visible.
      return configureInitial
          ? Rect.fromLTWH(
              geometry.left.toDouble(),
              geometry.top.toDouble(),
              geometry.width.toDouble(),
              geometry.height.toDouble(),
            )
          : null;
    }
    if (nativeDragActive) {
      // Rust is the sole writer during a native move/resize grab.
      return null;
    }
    if (previous == geometry) {
      return null;
    }
    return Rect.fromLTWH(
      geometry.left.toDouble(),
      geometry.top.toDouble(),
      geometry.width.toDouble(),
      geometry.height.toDouble(),
    );
  }

  void retainWindowIds(Set<int> activeObjectIds) {
    _configured.removeWhere(
      (objectId, _) => !activeObjectIds.contains(objectId),
    );
  }
}

/// One window's shell-drawn outer frame paired with the client rectangle it
/// encloses, plus any client popups that paint above the frame.
@immutable
class DesktopFrameRing {
  const DesktopFrameRing({
    required this.frame,
    required this.content,
    this.popups = const <Rect>[],
    this.resizeHotZones = const <Rect>[],
  });

  final Rect frame;
  final Rect content;
  final List<Rect> popups;
  final List<Rect> resizeHotZones;
}

/// The shell paints each window's border and titlebar band itself, so those
/// pixels are shell input targets. Subtracting every window's client rectangle
/// from the shell region is z-order blind and erases them wherever they overlap
/// a *lower* window's client rectangle — after which clicking the upper
/// window's titlebar routes to the client underneath and the click is lost.
///
/// Restore each ring, minus whatever a higher window paints over it. Overlap
/// among the results is harmless: the compositor treats the shell region as a
/// union.
///
/// [stack] must be ordered topmost first.
List<Rect> desktopFrameRingRegions(Rect canvas, List<DesktopFrameRing> stack) {
  final restored = <Rect>[];
  final obstructions = <Rect>[];
  for (final entry in stack) {
    var ring = _subtractRect(entry.frame, entry.content);
    for (final obstruction in obstructions) {
      ring = _subtractFromAll(ring, obstruction);
    }
    for (final piece in ring) {
      final clipped = piece.intersect(canvas);
      if (!clipped.isEmpty) {
        restored.add(clipped);
      }
    }
    obstructions.add(entry.frame);
    obstructions.addAll(entry.popups);
  }
  return restored;
}

/// Returns visible resize bands in the same topmost-first order as the frame
/// ring. A lower window's edge must not steal a pointer from a higher window's
/// client or frame.
List<Rect> desktopResizeHotZoneRegions(
  Rect canvas,
  List<DesktopFrameRing> stack,
) {
  final restored = <Rect>[];
  final obstructions = <Rect>[];
  for (final entry in stack) {
    var zones = entry.resizeHotZones;
    for (final obstruction in obstructions) {
      zones = _subtractFromAll(zones, obstruction);
    }
    for (final zone in zones) {
      final clipped = zone.intersect(canvas);
      if (!clipped.isEmpty) {
        restored.add(clipped);
      }
    }
    obstructions.add(entry.frame);
    obstructions.addAll(entry.popups);
  }
  return restored;
}

List<Rect> _subtractFromAll(List<Rect> regions, Rect cut) {
  final result = <Rect>[];
  for (final region in regions) {
    result.addAll(_subtractRect(region, cut));
  }
  return result;
}

List<Rect> _subtractRect(Rect source, Rect cut) {
  final overlap = source.intersect(cut);
  if (overlap.isEmpty) {
    return <Rect>[source];
  }

  final result = <Rect>[];
  void add(Rect rect) {
    if (rect.width > 0.0 && rect.height > 0.0) {
      result.add(rect);
    }
  }

  add(Rect.fromLTRB(source.left, source.top, source.right, overlap.top));
  add(Rect.fromLTRB(source.left, overlap.bottom, source.right, source.bottom));
  add(Rect.fromLTRB(source.left, overlap.top, overlap.left, overlap.bottom));
  add(Rect.fromLTRB(overlap.right, overlap.top, source.right, overlap.bottom));
  return result;
}
