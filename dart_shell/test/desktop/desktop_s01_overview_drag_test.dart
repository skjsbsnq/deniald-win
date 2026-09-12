import 'dart:math' as math;

import 'package:denial_dart_shell/src/desktop/desktop_workspace.dart';
import 'package:denial_dart_shell/src/models/denial_window.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

DenialWindow _window(int objectId, int monitorId, double x, double y) {
  return DenialWindow(
    objectId: objectId,
    objectKind: 'xdg',
    surfaceId: objectId + 100,
    windowId: objectId + 200,
    textureId: objectId + 300,
    title: 'W$objectId',
    appId: 'test.app$objectId',
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
    geometryX: x,
    geometryY: y,
    geometryWidth: 300,
    geometryHeight: 200,
    monitorId: monitorId,
    transform: 0,
    scale120: 120,
  );
}

/// Mirrors the controller's `_clampFrame` at devicePixelRatio 1: snap each
/// edge to whole pixels, then pin the frame inside the (bounded) work area.
Rect _clampReplica(Rect frame, Size viewSize, {Rect? bounds}) {
  final canvas = Offset.zero & viewSize;
  final requested = bounds?.intersect(canvas);
  final workArea = requested == null || requested.isEmpty ? canvas : requested;
  final workLeft = workArea.left.roundToDouble();
  final workTop = workArea.top.roundToDouble();
  final workRight = workArea.right.roundToDouble();
  final workBottom = workArea.bottom.roundToDouble();
  final width = math.min(frame.width, workRight - workLeft).roundToDouble();
  final height = math.min(frame.height, workBottom - workTop).roundToDouble();
  final left = frame.left
      .roundToDouble()
      .clamp(workLeft, math.max(workLeft, workRight - width))
      .toDouble();
  final top = frame.top
      .roundToDouble()
      .clamp(workTop, math.max(workTop, workBottom - height))
      .toDouble();
  return Rect.fromLTWH(left, top, width, height);
}

void main() {
  const viewSize = Size(2400, 800);
  const monitorBounds = Rect.fromLTWH(0, 0, 1200, 800);
  const outputBounds = <int, Rect>{
    1: Rect.fromLTWH(0, 0, 1200, 800),
    2: Rect.fromLTWH(1200, 0, 1200, 800),
  };

  ProviderContainer containerWithOverview() {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final workspace = container.read(desktopWorkspaceProvider.notifier);
    workspace.syncWindows(
      [
        _window(7, 1, 100, 100),
        _window(8, 1, 500, 120),
        _window(9, 2, 1500, 100),
      ],
      viewSize,
      1,
      snapshotSequence: 1,
    );
    workspace.toggleOverview(
      monitorId: 1,
      bounds: monitorBounds,
      backgroundBounds: monitorBounds,
      objectIds: const {7, 8},
    );
    return container;
  }

  test('drag deltas publish to the retained channel, not provider state', () {
    final container = containerWithOverview();
    final workspace = container.read(desktopWorkspaceProvider.notifier);
    workspace.beginOverviewDrag(7);

    final before = container.read(desktopWorkspaceProvider);
    var emissions = 0;
    final subscription = container.listen(
      desktopWorkspaceProvider,
      (previous, next) => emissions += 1,
    );
    addTearDown(subscription.close);
    var otherNotifications = 0;
    final offsets = container.read(desktopOverviewDragOffsetsProvider);
    offsets.translationFor(8).addListener(() => otherNotifications += 1);

    workspace.moveOverviewBy(7, const Offset(24, 12));
    workspace.moveOverviewBy(7, const Offset(-8, 40));
    workspace.moveOverviewBy(7, const Offset(3, -5));

    expect(emissions, 0);
    expect(container.read(desktopWorkspaceProvider), same(before));
    expect(otherNotifications, 0);

    final committed = before.overview!.frames[7]!;
    final live = committed.shift(offsets.translationOf(7));
    // The live rect keeps the arranged size; only its origin follows the
    // clamped pointer delta.
    expect(
      live.topLeft,
      _clampReplica(committed.shift(const Offset(19, 47)), viewSize).topLeft,
    );
    expect(live.size, committed.size);
    // The committed overview layout keeps the arranged slot for the drag.
    expect(before.overview!.frames[7], committed);
  });

  test('a clamped delta still stays on the retained channel', () {
    final container = containerWithOverview();
    final workspace = container.read(desktopWorkspaceProvider.notifier);
    workspace.beginOverviewDrag(7);
    final committed = container
        .read(desktopWorkspaceProvider)
        .overview!
        .frames[7]!;

    var emissions = 0;
    final subscription = container.listen(
      desktopWorkspaceProvider,
      (previous, next) => emissions += 1,
    );
    addTearDown(subscription.close);

    workspace.moveOverviewBy(7, const Offset(-5000, -5000));

    expect(emissions, 0);
    final offsets = container.read(desktopOverviewDragOffsetsProvider);
    final live = committed.shift(offsets.translationOf(7));
    expect(live.left, 0.0);
    expect(live.top, 0.0);
    expect(
      live.topLeft,
      _clampReplica(
        committed.shift(const Offset(-5000, -5000)),
        viewSize,
      ).topLeft,
    );
  });

  test('moving a window that is not dragging is a no-op', () {
    final container = containerWithOverview();
    final workspace = container.read(desktopWorkspaceProvider.notifier);
    final before = container.read(desktopWorkspaceProvider);

    workspace.moveOverviewBy(8, const Offset(30, 30));

    expect(container.read(desktopWorkspaceProvider), same(before));
    expect(
      container.read(desktopOverviewDragOffsetsProvider).translationOf(8),
      Offset.zero,
    );
  });

  test(
    'dropping commits one state write and transfers to the target monitor',
    () {
      final container = containerWithOverview();
      final workspace = container.read(desktopWorkspaceProvider.notifier);
      workspace.beginOverviewDrag(7);
      final committed = container
          .read(desktopWorkspaceProvider)
          .overview!
          .frames[7]!;

      // Drag the preview's centre onto the second monitor.
      const target = Offset(1800, 400);
      final delta = target - committed.center;
      workspace.moveOverviewBy(7, delta);

      final offsets = container.read(desktopOverviewDragOffsetsProvider);
      final live = committed.shift(offsets.translationOf(7));
      final before = container.read(desktopWorkspaceProvider);
      final placement = before.placements[7]!;

      var emissions = 0;
      final subscription = container.listen(
        desktopWorkspaceProvider,
        (previous, next) => emissions += 1,
      );
      addTearDown(subscription.close);

      final transferred = workspace.endOverviewDrag(
        7,
        outputBounds: outputBounds,
        workAreas: outputBounds,
      );

      expect(transferred, isTrue);
      expect(emissions, 1);
      final after = container.read(desktopWorkspaceProvider);
      expect(after.overviewActive, isFalse);
      final dropped = after.placements[7]!;
      expect(dropped.monitorId, 2);
      expect(dropped.dragging, isFalse);
      expect(
        dropped.frame,
        _clampReplica(
          Rect.fromCenter(
            center: live.center,
            width: placement.frame.width,
            height: placement.frame.height,
          ),
          viewSize,
          bounds: outputBounds[2],
        ),
      );
      // The other windows' placements are reused untouched.
      expect(after.placements[8], same(before.placements[8]));
      expect(after.placements[9], same(before.placements[9]));
      // The channel resets but retains the release origin for the handoff.
      expect(offsets.translationOf(7), Offset.zero);
      expect(offsets.settleTranslationFor(7), live.topLeft - committed.topLeft);
    },
  );

  test('dropping outside every output restores the arranged frame', () {
    final container = containerWithOverview();
    final workspace = container.read(desktopWorkspaceProvider.notifier);
    workspace.beginOverviewDrag(7);
    final committed = container
        .read(desktopWorkspaceProvider)
        .overview!
        .frames[7]!;

    var emissions = 0;
    final subscription = container.listen(
      desktopWorkspaceProvider,
      (previous, next) => emissions += 1,
    );
    addTearDown(subscription.close);

    final transferred = workspace.endOverviewDrag(
      7,
      outputBounds: const {},
      workAreas: const {},
    );

    expect(transferred, isFalse);
    expect(emissions, 1);
    final after = container.read(desktopWorkspaceProvider);
    expect(after.overviewActive, isTrue);
    expect(after.overview!.frames[7], committed);
    expect(after.placements[7]!.dragging, isFalse);
  });

  test(
    'cancelling commits one state write and restores the arranged frame',
    () {
      final container = containerWithOverview();
      final workspace = container.read(desktopWorkspaceProvider.notifier);
      final restingZ = container
          .read(desktopWorkspaceProvider)
          .placements[7]!
          .z;
      workspace.beginOverviewDrag(7);
      final committed = container
          .read(desktopWorkspaceProvider)
          .overview!
          .frames[7]!;
      workspace.moveOverviewBy(7, const Offset(40, 24));

      final offsets = container.read(desktopOverviewDragOffsetsProvider);
      final lastOffset = offsets.translationOf(7);
      expect(lastOffset, isNot(Offset.zero));

      var emissions = 0;
      final subscription = container.listen(
        desktopWorkspaceProvider,
        (previous, next) => emissions += 1,
      );
      addTearDown(subscription.close);

      workspace.cancelOverviewDrag(7);

      expect(emissions, 1);
      final after = container.read(desktopWorkspaceProvider);
      expect(after.overviewActive, isTrue);
      expect(after.overview!.frames[7], committed);
      final placement = after.placements[7]!;
      expect(placement.dragging, isFalse);
      expect(placement.z, restingZ);
      expect(offsets.translationOf(7), Offset.zero);
      expect(offsets.settleTranslationFor(7), lastOffset);
    },
  );

  test('closing the overview settles an in-flight drag once', () {
    final container = containerWithOverview();
    final workspace = container.read(desktopWorkspaceProvider.notifier);
    workspace.beginOverviewDrag(7);
    workspace.moveOverviewBy(7, const Offset(16, 8));

    final offsets = container.read(desktopOverviewDragOffsetsProvider);
    final lastOffset = offsets.translationOf(7);

    var emissions = 0;
    final subscription = container.listen(
      desktopWorkspaceProvider,
      (previous, next) => emissions += 1,
    );
    addTearDown(subscription.close);

    workspace.closeOverview();

    expect(emissions, 1);
    final after = container.read(desktopWorkspaceProvider);
    expect(after.overviewActive, isFalse);
    expect(after.placements[7]!.dragging, isFalse);
    expect(offsets.translationOf(7), Offset.zero);
    expect(offsets.settleTranslationFor(7), lastOffset);
  });

  test('a syncWindows overview collapse settles an in-flight drag', () {
    final container = containerWithOverview();
    final workspace = container.read(desktopWorkspaceProvider.notifier);
    final restingZ = container.read(desktopWorkspaceProvider).placements[7]!.z;
    workspace.beginOverviewDrag(7);
    workspace.moveOverviewBy(7, const Offset(30, 18));

    final offsets = container.read(desktopOverviewDragOffsetsProvider);
    final lastOffset = offsets.translationOf(7);
    expect(lastOffset, isNot(Offset.zero));

    var emissions = 0;
    final subscription = container.listen(
      desktopWorkspaceProvider,
      (previous, next) => emissions += 1,
    );
    addTearDown(subscription.close);

    // A viewport change collapses the overview mid-gesture.
    workspace.syncWindows(
      [
        _window(7, 1, 100, 100),
        _window(8, 1, 500, 120),
        _window(9, 2, 1500, 100),
      ],
      const Size(1600, 900),
      1,
      snapshotSequence: 2,
    );

    expect(emissions, 1);
    final after = container.read(desktopWorkspaceProvider);
    expect(after.overviewActive, isFalse);
    final placement = after.placements[7]!;
    expect(placement.dragging, isFalse);
    expect(placement.z, restingZ);
    expect(offsets.translationOf(7), Offset.zero);
    expect(offsets.settleTranslationFor(7), lastOffset);
  });

  test('a stale settle stays inert after the drag was cancelled', () {
    final container = containerWithOverview();
    final workspace = container.read(desktopWorkspaceProvider.notifier);
    workspace.beginOverviewDrag(7);
    workspace.moveOverviewBy(7, const Offset(40, 24));
    workspace.cancelOverviewDrag(7);

    final offsets = container.read(desktopOverviewDragOffsetsProvider);
    final staleSettle = offsets.settleTranslationFor(7);
    expect(staleSettle, isNotNull);
    expect(offsets.translationOf(7), Offset.zero);

    // The window then closes while it is still listed in the overview.
    // The post-cancel placement already carries dragging=false, so
    // downstream consumers may not treat the retained offset as live,
    // and the removal itself must not re-settle it.
    workspace.syncWindows(
      [_window(8, 1, 500, 120), _window(9, 2, 1500, 100)],
      viewSize,
      1,
      snapshotSequence: 2,
    );

    final after = container.read(desktopWorkspaceProvider);
    expect(after.placements.containsKey(7), isFalse);
    expect(after.overviewActive, isTrue);
    expect(offsets.translationOf(7), Offset.zero);
    expect(offsets.settleTranslationFor(7), staleSettle);
  });

  test('a mid-drag window removal keeps its live offset reachable', () {
    final container = containerWithOverview();
    final workspace = container.read(desktopWorkspaceProvider.notifier);
    workspace.beginOverviewDrag(7);
    workspace.moveOverviewBy(7, const Offset(40, 24));

    final offsets = container.read(desktopOverviewDragOffsetsProvider);
    final liveOffset = offsets.translationOf(7);
    expect(liveOffset, isNot(Offset.zero));

    // The dragged window leaves `next` before the restore loop runs, so no
    // finish is staged: the live offset remains readable for the close
    // animation handoff and no premature settle is recorded.
    workspace.syncWindows(
      [_window(8, 1, 500, 120), _window(9, 2, 1500, 100)],
      viewSize,
      1,
      snapshotSequence: 2,
    );

    final after = container.read(desktopWorkspaceProvider);
    expect(after.placements.containsKey(7), isFalse);
    expect(after.overviewActive, isTrue);
    expect(offsets.translationOf(7), liveOffset);
    expect(offsets.settleTranslationFor(7), isNull);
  });

  test(
    'a settle offset survives reopening the overview until the next drag',
    () {
      final container = containerWithOverview();
      final workspace = container.read(desktopWorkspaceProvider.notifier);
      workspace.beginOverviewDrag(7);
      workspace.moveOverviewBy(7, const Offset(40, 24));
      workspace.cancelOverviewDrag(7);

      final offsets = container.read(desktopOverviewDragOffsetsProvider);
      final settle = offsets.settleTranslationFor(7);
      expect(settle, isNotNull);

      // Closing then reopening the overview must not erase the settle before
      // the release animation's didUpdateWidget has consumed it.
      workspace.closeOverview();
      workspace.toggleOverview(
        monitorId: 1,
        bounds: monitorBounds,
        backgroundBounds: monitorBounds,
        objectIds: const {7, 8},
      );
      expect(offsets.settleTranslationFor(7), settle);

      // The next gesture's start owns the cleanup.
      workspace.beginOverviewDrag(7);
      expect(offsets.settleTranslationFor(7), isNull);
    },
  );

  test('the channel resets when a new overview session starts', () {
    final offsets = DesktopOverviewDragOffsets();
    addTearDown(offsets.dispose);

    offsets.start(7);
    offsets.update(7, const Offset(10, 10));
    expect(offsets.translationFor(7).value, const Offset(10, 10));

    offsets.finish(7);
    expect(offsets.translationFor(7).value, Offset.zero);
    expect(offsets.settleTranslationFor(7), const Offset(10, 10));

    // A repeated boundary must not erase the settle before the widget layer
    // has consumed it for the release animation.
    offsets.finish(7);
    expect(offsets.settleTranslationFor(7), const Offset(10, 10));

    offsets.start(7);
    expect(offsets.settleTranslationFor(7), isNull);

    offsets.update(7, const Offset(5, 5));
    offsets.clear();
    expect(offsets.translationFor(7).value, Offset.zero);
    expect(offsets.settleTranslationFor(7), isNull);
  });
}
