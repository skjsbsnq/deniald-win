import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../input/input_layout.dart';
import '../input/shell_interaction_registry.dart';
import '../models/denial_window.dart';
import '../state/desktop_window_switcher.dart';
import '../state/shell_controller.dart';
import 'desktop_taskbar_preview.dart';
import 'desktop_workspace.dart';

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
      );
    });
  }

  void _publish(
    Size viewSize,
    List<DenialWindow> windows,
    DesktopWorkspaceState desktop,
    ShellInteractionSnapshot interactions,
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
                      sampledSwitcherIds.contains(placement.objectId)) &&
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
    final visibleSurfaceIds = <int>{};
    for (final popup in inputMethodPopups) {
      visibleSurfaceIds.addAll(popup.visibleSurfaceIds);
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
    final previewTarget = ref.read(desktopTaskbarPreviewProvider);
    if (previewTarget != null) {
      final previewWindow = windowsById[previewTarget.objectId];
      if (previewWindow != null) {
        visibleSurfaceIds.addAll(previewWindow.visibleSurfaceIds);
      }
    }
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
        visibleSurfaceIds.addAll(window.visibleSurfaceIds);
        _configureWindowGeometry(window, placement);
        continue;
      }
      final window = windowsById[placement.objectId]!;
      visibleSurfaceIds.addAll(window.visibleSurfaceIds);
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

    _configureTracker.retainWindowIds(windowsById.keys.toSet());
    final snapshot = InputLayoutSnapshot(
      epoch: _epoch + 1,
      shellRegions: shellRegions,
      windows: inputWindows,
      visibleSurfaceIds: visibleSurfaceIds.toList(growable: false),
      keyboardCapture: interactions.capturesKeyboard,
      exclusiveShellMode: interactions.compositorExclusive,
    );
    if (_lastSnapshot?.hasSameRoutingAs(snapshot) ?? false) {
      return;
    }

    if (!ref.read(denialBridgeProvider).publishInputLayout(snapshot)) {
      return;
    }
    _epoch = snapshot.epoch;
    _lastSnapshot = snapshot;
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
      left: contentRect.left.round().clamp(0, 16384),
      top: contentRect.top.round().clamp(0, 16384),
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
  });

  final Rect frame;
  final Rect content;
  final List<Rect> popups;
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
