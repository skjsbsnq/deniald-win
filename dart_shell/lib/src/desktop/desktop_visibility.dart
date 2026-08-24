import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/denial_window.dart';
import 'desktop_workspace.dart';

/// Reasons are intentionally strings: this report is diagnostic state owned
/// by Dart and is not part of the wire contract yet.
abstract final class ConservativeVisibilityReason {
  static const String visible = 'visible';
  static const String partiallyOccluded = 'partially-occluded';
  static const String fullyOccluded = 'fully-occluded';
  static const String forcedConsumer = 'forced-consumer';
  static const String unknownOutput = 'unknown-output';
  static const String complexityLimit = 'complexity-limit';
}

/// Bounds the rectangle subtraction work performed during a visibility pass.
///
/// Visibility is recomputed while windows move. Once either limit is reached,
/// the pass keeps every remaining window visible instead of allowing geometry
/// fragmentation to become a new frame-time spike.
abstract final class ConservativeVisibilityLimits {
  static const int maxOccluders = 32;
  static const int maxFragments = 128;
}

@immutable
class VisibleRegionReport {
  const VisibleRegionReport({
    required this.layoutEpoch,
    required this.outputId,
    required this.surfaceId,
    required this.region,
    required this.reason,
  });

  final int layoutEpoch;
  final int outputId;
  final int surfaceId;
  final Rect region;
  final String reason;
}

@immutable
class ConservativeVisibleRegions {
  const ConservativeVisibleRegions({
    required this.visibleSurfaceIds,
    required this.visibleWindowIds,
    required this.consideredWindowIds,
    required this.fullyOccludedWindowIds,
    required this.reports,
    this.degraded = false,
  });

  final List<int> visibleSurfaceIds;
  final List<int> visibleWindowIds;
  final List<int> consideredWindowIds;
  final List<int> fullyOccludedWindowIds;
  final List<VisibleRegionReport> reports;
  final bool degraded;
}

@immutable
class DesktopVisibilityInput {
  const DesktopVisibilityInput({required this.window, required this.placement});

  final DenialWindow window;
  final DesktopWindowPlacement placement;

  bool matches({
    required DenialWindow window,
    required DesktopWindowPlacement placement,
  }) {
    return _samePlacement(this.placement, placement) &&
        this.window.hasSameSceneDescriptionAs(window) &&
        this.window.opacityClass == window.opacityClass;
  }
}

class DesktopVisibilitySnapshot {
  DesktopVisibilitySnapshot({
    required this.layoutEpoch,
    required this.outputLayoutEpoch,
    required this.sceneRevision,
    required Map<int, DesktopVisibilityInput> inputs,
    required Iterable<int> visibleSurfaceIds,
    required Iterable<int> forcedWindowIds,
    required this.forceAll,
    required Iterable<int> fullyOccludedWindowIds,
    required this.degraded,
  }) : inputs = Map<int, DesktopVisibilityInput>.unmodifiable(inputs),
       visibleSurfaceIds = List<int>.unmodifiable(visibleSurfaceIds),
       forcedWindowIds = Set<int>.unmodifiable(forcedWindowIds),
       fullyOccludedWindowIds = Set<int>.unmodifiable(fullyOccludedWindowIds);

  DesktopVisibilitySnapshot.empty()
    : layoutEpoch = -1,
      outputLayoutEpoch = -1,
      sceneRevision = -1,
      inputs = const <int, DesktopVisibilityInput>{},
      visibleSurfaceIds = const <int>[],
      forcedWindowIds = const <int>{},
      forceAll = true,
      fullyOccludedWindowIds = const <int>{},
      degraded = true;

  final int layoutEpoch;
  final int outputLayoutEpoch;
  final int sceneRevision;
  final Map<int, DesktopVisibilityInput> inputs;
  final List<int> visibleSurfaceIds;
  final Set<int> forcedWindowIds;
  final bool forceAll;
  final Set<int> fullyOccludedWindowIds;
  final bool degraded;

  /// Returns false only when the exact geometry/metadata used for the pass is
  /// still current and the window was proven fully covered.
  bool shouldPaintClientContent({
    required int objectId,
    required DenialWindow window,
    required DesktopWindowPlacement placement,
    required int layoutEpoch,
    required int outputLayoutEpoch,
    int? sceneRevision,
    required bool forceAll,
    bool specialConsumer = false,
  }) {
    if (forceAll ||
        this.forceAll ||
        specialConsumer ||
        forcedWindowIds.contains(objectId) ||
        degraded ||
        this.layoutEpoch != layoutEpoch ||
        this.outputLayoutEpoch != outputLayoutEpoch ||
        (sceneRevision != null && this.sceneRevision != sceneRevision)) {
      return true;
    }
    final input = inputs[objectId];
    return input == null ||
        !input.matches(window: window, placement: placement) ||
        !fullyOccludedWindowIds.contains(objectId);
  }

  bool sameAs(DesktopVisibilitySnapshot other) {
    if (layoutEpoch != other.layoutEpoch ||
        outputLayoutEpoch != other.outputLayoutEpoch ||
        sceneRevision != other.sceneRevision ||
        visibleSurfaceIds.length != other.visibleSurfaceIds.length ||
        forceAll != other.forceAll ||
        forcedWindowIds.length != other.forcedWindowIds.length ||
        degraded != other.degraded ||
        fullyOccludedWindowIds.length != other.fullyOccludedWindowIds.length ||
        inputs.length != other.inputs.length) {
      return false;
    }
    for (var index = 0; index < visibleSurfaceIds.length; index += 1) {
      if (visibleSurfaceIds[index] != other.visibleSurfaceIds[index]) {
        return false;
      }
    }
    for (final id in forcedWindowIds) {
      if (!other.forcedWindowIds.contains(id)) {
        return false;
      }
    }
    for (final id in fullyOccludedWindowIds) {
      if (!other.fullyOccludedWindowIds.contains(id)) {
        return false;
      }
    }
    for (final entry in inputs.entries) {
      final otherInput = other.inputs[entry.key];
      if (otherInput == null ||
          !entry.value.matches(
            window: otherInput.window,
            placement: otherInput.placement,
          )) {
        return false;
      }
    }
    return true;
  }
}

DesktopVisibilitySnapshot computeDesktopVisibilitySnapshot({
  required int layoutEpoch,
  required int outputLayoutEpoch,
  int? sceneRevision,
  required List<DesktopWindowPlacement> placements,
  required Map<int, DenialWindow> windowsById,
  required Iterable<({int id, Rect rect})> outputRects,
  Set<int> forcedWindowIds = const <int>{},
  Set<int> shellTranslucentWindowIds = const <int>{},
  bool forceAll = false,
}) {
  final outputs = outputRects.toList(growable: false);
  final consideredWindowIds = <int>{};
  final visibleWindowIds = <int>{};
  final visibleSurfaceIds = <int>{};
  var degraded = false;
  for (final output in outputs) {
    final result = computeConservativeVisibleRegions(
      layoutEpoch: layoutEpoch,
      outputId: output.id,
      outputRect: output.rect,
      placements: placements,
      windowsById: windowsById,
      forcedWindowIds: forcedWindowIds,
      shellTranslucentWindowIds: shellTranslucentWindowIds,
      forceAll: forceAll,
    );
    consideredWindowIds.addAll(result.consideredWindowIds);
    visibleWindowIds.addAll(result.visibleWindowIds);
    visibleSurfaceIds.addAll(result.visibleSurfaceIds);
    degraded = degraded || result.degraded;
  }

  final inputs = <int, DesktopVisibilityInput>{};
  for (final placement in placements) {
    final window = windowsById[placement.objectId];
    if (window != null && consideredWindowIds.contains(placement.objectId)) {
      inputs[placement.objectId] = DesktopVisibilityInput(
        window: window,
        placement: placement,
      );
    }
  }
  final effectiveSceneRevision =
      sceneRevision ??
      desktopVisibilitySceneRevision(
        placements: placements,
        windowsById: windowsById,
        outputRects: outputs,
        forcedWindowIds: forcedWindowIds,
        shellTranslucentWindowIds: shellTranslucentWindowIds,
        forceAll: forceAll,
      );
  return DesktopVisibilitySnapshot(
    layoutEpoch: layoutEpoch,
    outputLayoutEpoch: outputLayoutEpoch,
    sceneRevision: effectiveSceneRevision,
    inputs: inputs,
    visibleSurfaceIds: (visibleSurfaceIds.toList(growable: false)..sort()),
    forcedWindowIds: forcedWindowIds,
    forceAll: forceAll,
    fullyOccludedWindowIds: consideredWindowIds.difference(visibleWindowIds),
    degraded: degraded,
  );
}

int desktopVisibilitySceneRevision({
  required List<DesktopWindowPlacement> placements,
  required Map<int, DenialWindow> windowsById,
  required Iterable<({int id, Rect rect})> outputRects,
  Set<int> forcedWindowIds = const <int>{},
  Set<int> shellTranslucentWindowIds = const <int>{},
  bool forceAll = false,
}) {
  final windowEntries = windowsById.entries.toList(growable: false)
    ..sort((left, right) => left.key.compareTo(right.key));
  final outputs = outputRects.toList(growable: false)
    ..sort((left, right) => left.id.compareTo(right.id));
  final forcedIds = forcedWindowIds.toList(growable: false)..sort();
  final translucentIds = shellTranslucentWindowIds.toList(growable: false)
    ..sort();
  return Object.hash(
    forceAll,
    Object.hashAll(forcedIds),
    Object.hashAll(translucentIds),
    Object.hashAll(
      placements.map(
        (placement) => Object.hash(
          placement.objectId,
          placement.frame,
          placement.contentRect,
          placement.z,
          placement.monitorId,
          placement.workspaceId,
          placement.minimized,
          placement.maximized,
          placement.fullscreen,
          placement.serverSideDecorated,
          placement.dragging,
          placement.resizing,
          placement.nativeGrab,
          placement.devicePixelRatio,
        ),
      ),
    ),
    Object.hashAll(
      windowEntries.map((entry) => Object.hash(entry.key, entry.value)),
    ),
    Object.hashAll(
      outputs.map((output) => Object.hash(output.id, output.rect)),
    ),
  );
}

List<({int id, Rect rect})> desktopVisibilityOutputRects({
  required Size viewSize,
  required Set<int> monitorIds,
  Iterable<({int id, Rect rect})> configuredOutputs =
      const <({int id, Rect rect})>[],
}) {
  final canvas = Offset.zero & viewSize;
  final configured = configuredOutputs.toList(growable: false);
  final outputs = configured
      .map((output) => (id: output.id, rect: output.rect.intersect(canvas)))
      .where((output) => !output.rect.isEmpty)
      .toList(growable: false);
  if (configured.isNotEmpty && outputs.isEmpty) {
    return <({int id, Rect rect})>[(id: -1, rect: Rect.zero)];
  }
  if (outputs.isNotEmpty) {
    final configuredIds = outputs.map((output) => output.id).toSet();
    if (monitorIds.every(configuredIds.contains)) {
      return outputs;
    }
    // A missing output description makes ownership ambiguous. Retain all
    // clients for this pass instead of applying one output's result globally.
    return <({int id, Rect rect})>[(id: -1, rect: Rect.zero)];
  }
  if (monitorIds.length <= 1) {
    return <({int id, Rect rect})>[
      (id: monitorIds.isEmpty ? -1 : monitorIds.first, rect: canvas),
    ];
  }
  return <({int id, Rect rect})>[(id: -1, rect: Rect.zero)];
}

final desktopVisibilityProvider =
    NotifierProvider<DesktopVisibilityController, DesktopVisibilitySnapshot>(
      DesktopVisibilityController.new,
    );

class DesktopVisibilityController extends Notifier<DesktopVisibilitySnapshot> {
  @override
  DesktopVisibilitySnapshot build() => DesktopVisibilitySnapshot.empty();

  void publish(DesktopVisibilitySnapshot snapshot) {
    if (!state.sameAs(snapshot)) {
      state = snapshot;
    }
  }
}

/// Computes a conservative, output-scoped visibility result.
///
/// [placements] must be ordered from back to front. A client is removed only
/// when the remaining region is proven covered by known opaque, axis-aligned
/// content from a higher placement. Unknown metadata, unstable geometry and
/// special consumers all retain the client's surfaces.
ConservativeVisibleRegions computeConservativeVisibleRegions({
  required int layoutEpoch,
  required int outputId,
  required Rect outputRect,
  required List<DesktopWindowPlacement> placements,
  required Map<int, DenialWindow> windowsById,
  Set<int> forcedWindowIds = const <int>{},
  Set<int> shellTranslucentWindowIds = const <int>{},
  bool forceAll = false,
}) {
  final ids = <int>{};
  final visibleWindowIds = <int>{};
  final consideredWindowIds = <int>{};
  final fullyOccludedWindowIds = <int>{};
  final reports = <VisibleRegionReport>[];
  if (outputRect.isEmpty || !_finiteRect(outputRect)) {
    for (final placement in placements) {
      final window = windowsById[placement.objectId];
      if (window == null) {
        continue;
      }
      consideredWindowIds.add(window.objectId);
      visibleWindowIds.add(window.objectId);
      _retainWindow(
        ids,
        reports,
        layoutEpoch,
        outputId,
        window,
        outputRect,
        ConservativeVisibilityReason.unknownOutput,
      );
    }
    return ConservativeVisibleRegions(
      visibleSurfaceIds: _sorted(ids),
      visibleWindowIds: _sorted(visibleWindowIds),
      consideredWindowIds: _sorted(consideredWindowIds),
      fullyOccludedWindowIds: const <int>[],
      reports: List<VisibleRegionReport>.unmodifiable(reports),
    );
  }

  final occluders = <Rect>[];
  var degraded = false;
  for (final placement in placements.reversed) {
    final window = windowsById[placement.objectId];
    if (window == null) {
      continue;
    }
    final target = placement.contentRect.intersect(outputRect);
    if (target.isEmpty || window.visibleSurfaceIds.isEmpty) {
      continue;
    }
    consideredWindowIds.add(window.objectId);

    final forced =
        forceAll ||
        forcedWindowIds.contains(window.objectId) ||
        placement.dragging ||
        _hasSpecialSurfaceConsumer(window);
    if (forced) {
      _retainWindow(
        ids,
        reports,
        layoutEpoch,
        outputId,
        window,
        target,
        ConservativeVisibilityReason.forcedConsumer,
      );
      visibleWindowIds.add(window.objectId);
    } else {
      final remaining = _subtractCoverage(target, occluders);
      if (remaining.degraded) {
        degraded = true;
      }
      if (degraded) {
        _retainWindow(
          ids,
          reports,
          layoutEpoch,
          outputId,
          window,
          target,
          ConservativeVisibilityReason.complexityLimit,
        );
        visibleWindowIds.add(window.objectId);
      } else if (remaining.isEmpty) {
        // Popup/subsurface consumers are retained even when the toplevel is
        // covered; a later task can refine this to popup-specific geometry.
        final popupIds = window.popupSurfaceLayers
            .where((layer) => layer.textureId > 0)
            .map((layer) => layer.surfaceId);
        for (final surfaceId in popupIds) {
          ids.add(surfaceId);
          reports.add(
            VisibleRegionReport(
              layoutEpoch: layoutEpoch,
              outputId: outputId,
              surfaceId: surfaceId,
              region: Rect.zero,
              reason: ConservativeVisibilityReason.forcedConsumer,
            ),
          );
        }
        for (final surfaceId in window.mainVisibleSurfaceIds) {
          reports.add(
            VisibleRegionReport(
              layoutEpoch: layoutEpoch,
              outputId: outputId,
              surfaceId: surfaceId,
              region: Rect.zero,
              reason: ConservativeVisibilityReason.fullyOccluded,
            ),
          );
        }
        if (window.mainVisibleSurfaceIds.isNotEmpty) {
          fullyOccludedWindowIds.add(window.objectId);
        }
      } else {
        final reason =
            remaining.regions.length == 1 && remaining.regions.first == target
            ? ConservativeVisibilityReason.visible
            : ConservativeVisibilityReason.partiallyOccluded;
        _retainWindow(
          ids,
          reports,
          layoutEpoch,
          outputId,
          window,
          _bounds(remaining.regions),
          reason,
        );
        visibleWindowIds.add(window.objectId);
      }
    }

    if (placement.dragging ||
        placement.shellDragging ||
        placement.shellResizing) {
      // Geometry in motion is not valid proof for a lower placement.
      continue;
    }
    if (placement.minimized) {
      // Minimized windows may be retained for a preview, but their native
      // placement is not an occluder in the desktop scene.
      continue;
    }
    final opaqueRegions = _knownOpaqueRegions(
      window,
      placement.contentRect,
      shellTranslucent: shellTranslucentWindowIds.contains(window.objectId),
    );
    for (final region in opaqueRegions) {
      final rect = _inwardRect(region);
      if (rect.isEmpty || !_finiteRect(rect)) {
        continue;
      }
      if (occluders.length >= ConservativeVisibilityLimits.maxOccluders) {
        degraded = true;
        break;
      }
      occluders.add(rect);
    }
  }

  if (degraded) {
    // A degraded pass is diagnostic only. Its partial result must not affect
    // input routing or the paint gate, so restore every sampled surface.
    for (final placement in placements) {
      final window = windowsById[placement.objectId];
      if (window == null || window.visibleSurfaceIds.isEmpty) {
        continue;
      }
      visibleWindowIds.add(window.objectId);
      ids.addAll(window.visibleSurfaceIds);
    }
    fullyOccludedWindowIds.clear();
    reports.clear();
    for (final placement in placements) {
      final window = windowsById[placement.objectId];
      if (window == null || window.visibleSurfaceIds.isEmpty) {
        continue;
      }
      _retainWindow(
        ids,
        reports,
        layoutEpoch,
        outputId,
        window,
        placement.contentRect.intersect(outputRect),
        ConservativeVisibilityReason.complexityLimit,
      );
    }
  }

  return ConservativeVisibleRegions(
    visibleSurfaceIds: _sorted(ids),
    visibleWindowIds: _sorted(visibleWindowIds),
    consideredWindowIds: _sorted(consideredWindowIds),
    fullyOccludedWindowIds: _sorted(fullyOccludedWindowIds),
    reports: List<VisibleRegionReport>.unmodifiable(reports),
    degraded: degraded,
  );
}

void _retainWindow(
  Set<int> ids,
  List<VisibleRegionReport> reports,
  int layoutEpoch,
  int outputId,
  DenialWindow window,
  Rect region,
  String reason,
) {
  for (final surfaceId in window.visibleSurfaceIds) {
    if (surfaceId <= 0) {
      continue;
    }
    ids.add(surfaceId);
    reports.add(
      VisibleRegionReport(
        layoutEpoch: layoutEpoch,
        outputId: outputId,
        surfaceId: surfaceId,
        region: region,
        reason: reason,
      ),
    );
  }
}

List<Rect> _knownOpaqueRegions(
  DenialWindow window,
  Rect target, {
  bool shellTranslucent = false,
}) {
  if (target.isEmpty ||
      shellTranslucent ||
      window.isLocalFlutter ||
      window.opacity < 1.0) {
    return const <Rect>[];
  }
  if (window.surfaceLayers.isEmpty) {
    return window.isOpaque && window.transform == 0
        ? <Rect>[target]
        : const <Rect>[];
  }
  final regions = <Rect>[];
  for (final layer in window.mainSurfaceLayers) {
    if (layer.textureId <= 0 ||
        !layer.opaque ||
        layer.opacity < 1.0 ||
        layer.transform != 0 ||
        layer.surfaceWidth <= 0.0 ||
        layer.surfaceHeight <= 0.0) {
      continue;
    }
    final mapped = window.mapSurfaceRect(layer, target).intersect(target);
    if (!mapped.isEmpty && _finiteRect(mapped)) {
      regions.add(mapped);
    }
  }
  if (regions.length > ConservativeVisibilityLimits.maxOccluders) {
    return regions;
  }
  final coverage = _subtractCoverage(target, regions);
  return coverage.degraded
      ? regions
      : coverage.isEmpty
      ? <Rect>[target]
      : regions;
}

bool _hasSpecialSurfaceConsumer(DenialWindow window) {
  return window.popupSurfaceLayers.isNotEmpty ||
      window.mainSurfaceLayers.any(
        (layer) => layer.role == DenialSurfaceRole.subsurface,
      );
}

_CoverageSubtraction _subtractCoverage(Rect source, Iterable<Rect> cuts) {
  var remaining = <Rect>[source];
  for (final cut in cuts) {
    if (remaining.isEmpty) {
      break;
    }
    final next = <Rect>[];
    for (final piece in remaining) {
      next.addAll(_subtractRect(piece, cut));
      if (next.length > ConservativeVisibilityLimits.maxFragments) {
        return const _CoverageSubtraction.degraded();
      }
    }
    remaining = next;
  }
  return _CoverageSubtraction(remaining);
}

List<Rect> _subtractRect(Rect source, Rect cut) {
  final intersection = source.intersect(cut);
  if (intersection.isEmpty) {
    return <Rect>[source];
  }
  final pieces = <Rect>[];
  if (intersection.top > source.top) {
    pieces.add(
      Rect.fromLTRB(source.left, source.top, source.right, intersection.top),
    );
  }
  if (intersection.bottom < source.bottom) {
    pieces.add(
      Rect.fromLTRB(
        source.left,
        intersection.bottom,
        source.right,
        source.bottom,
      ),
    );
  }
  if (intersection.left > source.left) {
    pieces.add(
      Rect.fromLTRB(
        source.left,
        intersection.top,
        intersection.left,
        intersection.bottom,
      ),
    );
  }
  if (intersection.right < source.right) {
    pieces.add(
      Rect.fromLTRB(
        intersection.right,
        intersection.top,
        source.right,
        intersection.bottom,
      ),
    );
  }
  return pieces.where((piece) => !piece.isEmpty).toList(growable: false);
}

Rect _bounds(List<Rect> regions) {
  var result = regions.first;
  for (final region in regions.skip(1)) {
    result = result.expandToInclude(region);
  }
  return result;
}

Rect _inwardRect(Rect rect) => Rect.fromLTRB(
  math.min(rect.left, rect.right).ceilToDouble(),
  math.min(rect.top, rect.bottom).ceilToDouble(),
  math.max(rect.left, rect.right).floorToDouble(),
  math.max(rect.top, rect.bottom).floorToDouble(),
);

bool _finiteRect(Rect rect) =>
    rect.left.isFinite &&
    rect.top.isFinite &&
    rect.right.isFinite &&
    rect.bottom.isFinite;

List<int> _sorted(Set<int> ids) => ids.toList(growable: false)..sort();

bool _samePlacement(DesktopWindowPlacement left, DesktopWindowPlacement right) {
  return left.objectId == right.objectId &&
      left.frame == right.frame &&
      left.z == right.z &&
      left.monitorId == right.monitorId &&
      left.workspaceId == right.workspaceId &&
      left.minimized == right.minimized &&
      left.maximized == right.maximized &&
      left.fullscreen == right.fullscreen &&
      left.serverSideDecorated == right.serverSideDecorated &&
      left.dragging == right.dragging &&
      left.resizing == right.resizing &&
      left.nativeGrab == right.nativeGrab &&
      left.devicePixelRatio == right.devicePixelRatio &&
      left.restoreFrame == right.restoreFrame &&
      left.fullscreenRestoreFrame == right.fullscreenRestoreFrame;
}

@immutable
class _CoverageSubtraction {
  const _CoverageSubtraction(this.regions) : degraded = false;

  const _CoverageSubtraction.degraded()
    : regions = const <Rect>[],
      degraded = true;

  final List<Rect> regions;
  final bool degraded;

  bool get isEmpty => !degraded && regions.isEmpty;
}
