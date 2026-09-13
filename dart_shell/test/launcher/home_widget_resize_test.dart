import 'package:denial_dart_shell/src/launcher/controllers/home_grid_controller.dart';
import 'package:denial_dart_shell/src/launcher/models/home_clock_info.dart';
import 'package:denial_dart_shell/src/launcher/models/home_grid_item.dart';
import 'package:denial_dart_shell/src/launcher/widgets/home_app_page.dart';
import 'package:denial_dart_shell/src/launcher/widgets/home_tiles.dart';
import 'package:denial_dart_shell/src/localization/denial_localizations.dart';
import 'package:denial_dart_shell/src/theme/shell_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The fork's resize handle is a 64x64 opaque gesture target whose visible
/// 56x56 grip sits at its bottom-right. The icon marks the grip centre, so
/// the expanded target's top-left is 36px up-left of it and a point 4px into
/// the target still falls outside the visible grip.
const Offset _handleIconCenterToTargetTopLeft = Offset(36, 36);
const Offset _insideExpandedTarget = Offset(4, 4);

class _ResizeEvents {
  Offset? start;
  Offset? latest;
  int ended = 0;
  int moveModeEvents = 0;
  int resizeModeStarts = 0;
  HomeGridItem? resizeModeItem;
  int? resizeModeAt;
}

Widget _resizeTree({
  required _ResizeEvents events,
  required int? resizeModeIndex,
  required PageController pages,
}) => ProviderScope(
  overrides: [
    homeClockProvider.overrideWithValue(
      HomeClockInfo(
        now: DateTime(2026, 9, 5, 12),
        locale: 'en',
        power: HomePowerStatus.unknown,
      ),
    ),
  ],
  child: DenialLocalizationScope(
    locale: const Locale('en'),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: ShellTheme(
        data: const ShellThemeData(),
        child: DefaultTextStyle(
          style: const TextStyle(fontSize: 14),
          child: PageView(
            controller: pages,
            children: [
              HomeAppPage(
                slots: [HomeGridItem.clock()],
                startIndex: 0,
                pageSize: 16,
                columns: 4,
                gap: 12,
                tileWidth: 80,
                tileHeight: 120,
                draggingSourceIndex: null,
                resizeModeIndex: resizeModeIndex,
                onLaunch: (_) {},
                onDragStart: (_, _, _, _, _) => events.moveModeEvents++,
                onDragEnd: (_) => events.moveModeEvents++,
                onDragUpdate: (_) => events.moveModeEvents++,
                onResizeModeStart:
                    (item, index, _, _) {
                      events.resizeModeStarts++;
                      events.resizeModeItem = item;
                      events.resizeModeAt = index;
                    },
                onResizeModeMove: (_, _, _, _, _) => events.moveModeEvents++,
                onResizeModeEnd: () {},
                onResizeStart:
                    (_, _, _, details) => events.start = details.globalPosition,
                onResizeUpdate:
                    (details) => events.latest = details.globalPosition,
                onResizeEnd: () => events.ended++,
              ),
              const SizedBox.expand(),
            ],
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('dragging the enlarged resize handle keeps its drag and page', (
    tester,
  ) async {
    final resampling = tester.binding.resamplingEnabled;
    tester.binding.resamplingEnabled = false;
    addTearDown(() => tester.binding.resamplingEnabled = resampling);
    final pages = PageController();
    addTearDown(pages.dispose);
    final events = _ResizeEvents();
    await tester.pumpWidget(
      _resizeTree(events: events, resizeModeIndex: 0, pages: pages),
    );
    final iconCenter = tester.getCenter(
      find.byIcon(Icons.open_in_full_rounded),
    );
    final origin =
        iconCenter - _handleIconCenterToTargetTopLeft + _insideExpandedTarget;
    final pointer = await tester.startGesture(origin);
    // Stay well under the long-press deadline: this is a quick grab.
    await tester.pump(const Duration(milliseconds: 50));
    await pointer.moveBy(const Offset(-70, 0));
    await tester.pump();
    expect(events.start, origin + const Offset(-70, 0));
    expect(events.moveModeEvents, 0);
    expect(events.resizeModeStarts, 0);
    expect(pages.offset, 0);
    await pointer.moveBy(const Offset(35, 0));
    await tester.pump();
    expect(events.latest, origin + const Offset(-35, 0));
    expect(events.moveModeEvents, 0);
    expect(pages.offset, 0);
    await pointer.cancel();
    await tester.pump();
    expect(events.ended, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('holding the resize handle cancels the drag, not move mode', (
    tester,
  ) async {
    final resampling = tester.binding.resamplingEnabled;
    tester.binding.resamplingEnabled = false;
    addTearDown(() => tester.binding.resamplingEnabled = resampling);
    final pages = PageController();
    addTearDown(pages.dispose);
    final events = _ResizeEvents();
    await tester.pumpWidget(
      _resizeTree(events: events, resizeModeIndex: 0, pages: pages),
    );
    final iconCenter = tester.getCenter(
      find.byIcon(Icons.open_in_full_rounded),
    );
    final origin =
        iconCenter - _handleIconCenterToTargetTopLeft + _insideExpandedTarget;
    final pointer = await tester.startGesture(origin);
    // Past the long-press deadline the handle's own recognizer claims the
    // pointer so the enclosing tile never enters move mode; the price is
    // that the pending resize drag is cancelled instead of surviving.
    await tester.pump(const Duration(milliseconds: 700));
    expect(events.start, isNull);
    expect(events.ended, 1);
    expect(events.moveModeEvents, 0);
    expect(events.resizeModeStarts, 0);
    expect(pages.offset, 0);
    await pointer.moveBy(const Offset(-70, 0));
    await tester.pump();
    expect(events.start, isNull);
    expect(events.latest, isNull);
    expect(events.ended, 1);
    expect(events.moveModeEvents, 0);
    expect(pages.offset, 0);
    await pointer.up();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('the resize handle only exists while resize mode is active', (
    tester,
  ) async {
    final resampling = tester.binding.resamplingEnabled;
    tester.binding.resamplingEnabled = false;
    addTearDown(() => tester.binding.resamplingEnabled = resampling);
    final pages = PageController();
    addTearDown(pages.dispose);
    final events = _ResizeEvents();
    await tester.pumpWidget(
      _resizeTree(events: events, resizeModeIndex: null, pages: pages),
    );
    expect(find.byIcon(Icons.open_in_full_rounded), findsNothing);
    // Long-pressing a resizable tile is what requests resize mode in the
    // first place; it must not be mistaken for an item move.
    final tileCenter = tester.getCenter(find.byType(HomeClockWidget));
    final pointer = await tester.startGesture(tileCenter);
    await tester.pump(const Duration(milliseconds: 600));
    expect(events.resizeModeStarts, 1);
    expect(events.resizeModeItem?.id, 'widget:clock');
    expect(events.resizeModeAt, 0);
    expect(events.moveModeEvents, 0);
    await pointer.up();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
