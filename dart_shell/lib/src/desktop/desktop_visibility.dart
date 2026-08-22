import 'dart:math' as math;

import 'package:flutter/widgets.dart';

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
    required this.reports,
  });

  final List<int> visibleSurfaceIds;
  final List<VisibleRegionReport> reports;
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
  bool forceAll = false,
}) {
  final ids = <int>{};
  final reports = <VisibleRegionReport>[];
  if (outputRect.isEmpty || !_finiteRect(outputRect)) {
    for (final placement in placements) {
      final window = windowsById[placement.objectId];
      if (window == null) {
        continue;
      }
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
      reports: List<VisibleRegionReport>.unmodifiable(reports),
    );
  }

  final occluders = <Rect>[];
  for (final placement in placements.reversed) {
    final window = windowsById[placement.objectId];
    if (window == null) {
      continue;
    }
    final target = placement.contentRect.intersect(outputRect);
    if (target.isEmpty || window.visibleSurfaceIds.isEmpty) {
      continue;
    }

    final forced = forceAll || forcedWindowIds.contains(window.objectId);
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
    } else {
      final remaining = _subtractCoverage(target, occluders);
      if (remaining.isEmpty) {
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
      } else {
        final reason = remaining.length == 1 && remaining.first == target
            ? ConservativeVisibilityReason.visible
            : ConservativeVisibilityReason.partiallyOccluded;
        _retainWindow(
          ids,
          reports,
          layoutEpoch,
          outputId,
          window,
          _bounds(remaining),
          reason,
        );
      }
    }

    if (placement.dragging ||
        placement.shellDragging ||
        placement.shellResizing) {
      // Geometry in motion is not valid proof for a lower placement.
      continue;
    }
    final opaqueRegions = _knownOpaqueRegions(window, placement.contentRect);
    occluders.addAll(
      opaqueRegions
          .map(_outwardRect)
          .where((rect) => !rect.isEmpty && _finiteRect(rect)),
    );
  }

  return ConservativeVisibleRegions(
    visibleSurfaceIds: _sorted(ids),
    reports: List<VisibleRegionReport>.unmodifiable(reports),
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

List<Rect> _knownOpaqueRegions(DenialWindow window, Rect target) {
  if (target.isEmpty || window.isLocalFlutter || window.opacity < 1.0) {
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
  return _covers(target, regions) ? <Rect>[target] : regions;
}

List<Rect> _subtractCoverage(Rect source, Iterable<Rect> cuts) {
  var remaining = <Rect>[source];
  for (final cut in cuts) {
    if (remaining.isEmpty) {
      break;
    }
    final next = <Rect>[];
    for (final piece in remaining) {
      next.addAll(_subtractRect(piece, cut));
    }
    remaining = next;
  }
  return remaining;
}

bool _covers(Rect target, Iterable<Rect> regions) =>
    _subtractCoverage(target, regions).isEmpty;

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

Rect _outwardRect(Rect rect) => Rect.fromLTRB(
  math.min(rect.left, rect.right).floorToDouble(),
  math.min(rect.top, rect.bottom).floorToDouble(),
  math.max(rect.left, rect.right).ceilToDouble(),
  math.max(rect.top, rect.bottom).ceilToDouble(),
);

bool _finiteRect(Rect rect) =>
    rect.left.isFinite &&
    rect.top.isFinite &&
    rect.right.isFinite &&
    rect.bottom.isFinite;

List<int> _sorted(Set<int> ids) => ids.toList(growable: false)..sort();
