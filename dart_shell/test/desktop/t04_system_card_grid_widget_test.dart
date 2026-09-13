import 'package:denial_dart_shell/l10n/generated/app_localizations.dart';
import 'package:denial_dart_shell/src/desktop/shelf/dashboard/system/system_card_grid_view.dart';
import 'package:denial_dart_shell/src/desktop/shelf/dashboard/system/system_card_tile.dart';
import 'package:denial_dart_shell/src/desktop/shelf/dashboard/views/system_view.dart';
import 'package:denial_dart_shell/src/models/battery_status.dart';
import 'package:denial_dart_shell/src/services/system_card_store.dart';
import 'package:denial_dart_shell/src/state/system_extended_status.dart';
import 'package:denial_dart_shell/src/state/system_status.dart';
import 'package:denial_dart_shell/src/theme/shell_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const items = <SystemCardGridItem>[
    SystemCardGridItem(id: 'cpu', child: _FakeCard('cpu')),
    SystemCardGridItem(id: 'memory', child: _FakeCard('memory')),
    SystemCardGridItem(id: 'network', child: _FakeCard('network')),
    SystemCardGridItem(id: 'battery', child: _FakeCard('battery')),
  ];

  const itemsWithoutMemory = <SystemCardGridItem>[
    SystemCardGridItem(id: 'cpu', child: _FakeCard('cpu')),
    SystemCardGridItem(id: 'network', child: _FakeCard('network')),
    SystemCardGridItem(id: 'battery', child: _FakeCard('battery')),
  ];

  Widget gridHost(List<SystemCardGridItem> gridItems) =>
      SizedBox(width: 412, child: SystemCardGridView(items: gridItems));

  Future<void> pumpGrid(
    WidgetTester tester, {
    _MemorySystemCardStore? store,
    List<SystemCardGridItem> gridItems = items,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          systemCardStoreProvider.overrideWithValue(
            store ?? _MemorySystemCardStore(),
          ),
        ],
        child: _wrap(gridHost(gridItems)),
      ),
    );
    await tester.pump();
    // Let the async hydration land, then settle the snap-in.
    await tester.pumpAndSettle();
  }

  // Same element tree shape, so the grid's State — and its drag session —
  // survives the item-list swap.
  Future<void> repumpGrid(
    WidgetTester tester,
    List<SystemCardGridItem> gridItems,
  ) {
    return tester.pumpWidget(
      ProviderScope(
        overrides: [
          systemCardStoreProvider.overrideWithValue(
            _MemorySystemCardStore(),
          ),
        ],
        child: _wrap(gridHost(gridItems)),
      ),
    );
  }

  // Cards center their content, so positions are read off the tile shell,
  // not the label text.
  Offset tileTopLeft(WidgetTester tester, String label) =>
      tester.getTopLeft(find.widgetWithText(SystemCardTile, label));

  testWidgets('mounts every catalog tile on the canvas', (tester) async {
    await pumpGrid(tester);
    expect(find.byType(SystemCardTile), findsNWidgets(4));
    expect(find.text('cpu'), findsOneWidget);
    expect(find.text('memory'), findsOneWidget);
    // Default anchors: memory sits in the right column next to cpu.
    expect(tileTopLeft(tester, 'cpu'), Offset.zero);
    final memoryTopLeft = tileTopLeft(tester, 'memory');
    expect(memoryTopLeft.dx, 280);
    expect(memoryTopLeft.dy, 0);
  });

  testWidgets('pointer drag moves the card and persists the layout', (
    tester,
  ) async {
    final store = _MemorySystemCardStore();
    await pumpGrid(tester, store: store);

    final cpuBefore = tileTopLeft(tester, 'cpu');
    final memoryBefore = tileTopLeft(tester, 'memory');
    expect(memoryBefore.dx, 280);

    // Immediate drag, the clavis DragHandler equivalent: the session opens
    // on the first real move — no hold is needed — then pulls memory left
    // onto the cpu slot.
    final gesture = await tester.startGesture(
      tester.getCenter(find.widgetWithText(SystemCardTile, 'memory')),
    );
    await gesture.moveBy(const Offset(-200, 40));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    final memoryAfter = tileTopLeft(tester, 'memory');
    expect(memoryAfter.dx, lessThan(280));
    // cpu was displaced from the top-left slot it used to occupy.
    final cpuAfter = tileTopLeft(tester, 'cpu');
    expect(cpuAfter != cpuBefore, isTrue);

    // The release committed through the debounced store.
    expect(store.writes, greaterThanOrEqualTo(1));
    expect(store.saved, isNotNull);
    expect(
      store.saved!.tiles.any((t) => t.id == 'memory' && t.x < 280),
      isTrue,
    );
  });

  testWidgets('keyboard arrows nudge, Enter commits, Esc cancels', (
    tester,
  ) async {
    final store = _MemorySystemCardStore();
    await pumpGrid(tester, store: store);

    final cpuBefore = tileTopLeft(tester, 'cpu');

    // Tap focuses the tile, then one 8 px nudge right.
    await tester.tap(find.text('cpu'));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    final cpuAfter = tileTopLeft(tester, 'cpu');
    expect(cpuAfter.dx, cpuBefore.dx + 8);
    expect(store.writes, 1);

    // A canceled session restores the committed position.
    final writesBefore = store.writes;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(tileTopLeft(tester, 'cpu'), cpuAfter);
    expect(store.writes, writesBefore);
  });

  testWidgets('a card removed mid-drag resets the session', (tester) async {
    await pumpGrid(tester);

    // Start a pointer drag on memory and pull it off its slot.
    final gesture = await tester.startGesture(
      tester.getCenter(find.widgetWithText(SystemCardTile, 'memory')),
    );
    await gesture.moveBy(const Offset(-40, 0));
    await tester.pump();

    // A shrinking provider id set (e.g. a gpu vanishing between polls)
    // unmounts the source tile mid-gesture: its onDragEnd/onDragCancel die
    // with it. Regression: the controller stayed in `dragging` forever and
    // rejected every later beginDrag/beginKeyboard.
    await repumpGrid(tester, itemsWithoutMemory);
    await tester.pumpAndSettle();
    await gesture.up();

    // Proof the session reset: a fresh drag on cpu must actually move it.
    final cpuBefore = tileTopLeft(tester, 'cpu');
    final retry = await tester.startGesture(
      tester.getCenter(find.widgetWithText(SystemCardTile, 'cpu')),
    );
    await retry.moveBy(const Offset(0, 200));
    await tester.pump();
    await retry.up();
    await tester.pumpAndSettle();
    expect(tileTopLeft(tester, 'cpu') != cpuBefore, isTrue);
  });

  testWidgets('a card removed during the settle completes the session', (
    tester,
  ) async {
    await pumpGrid(tester);

    final gesture = await tester.startGesture(
      tester.getCenter(find.widgetWithText(SystemCardTile, 'memory')),
    );
    await gesture.moveBy(const Offset(-40, 0));
    await tester.pump();
    await gesture.up();
    // One frame lands the release: the controller is in `finishing` with
    // the ghost flying to the committed slot.
    await tester.pump();

    // Removing the item now orphans the ghost's onEnd — without the reset
    // the controller would sit in `finishing` forever.
    await repumpGrid(tester, itemsWithoutMemory);
    await tester.pumpAndSettle();

    // Proof of idle: a keyboard nudge on cpu commits +8 px.
    final cpuBefore = tileTopLeft(tester, 'cpu');
    await tester.tap(find.text('cpu'));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(tileTopLeft(tester, 'cpu').dx, cpuBefore.dx + 8);
  });

  testWidgets('an unknown item id asserts instead of rendering a stub', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          systemCardStoreProvider.overrideWithValue(
            _MemorySystemCardStore(),
          ),
        ],
        child: _wrap(
          gridHost(
            const <SystemCardGridItem>[
              SystemCardGridItem(id: 'cpu', child: _FakeCard('cpu')),
              SystemCardGridItem(id: 'bogus', child: _FakeCard('bogus')),
            ],
          ),
        ),
      ),
    );
    // 'bogus' is not in SystemCardCatalog: the resolved layout has no tile
    // for it, which must surface as an assertion, not a silent 0x0 tile.
    expect(tester.takeException(), isA<AssertionError>());
  });

  testWidgets('real SystemView mounts its cards inside the grid', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          systemCardStoreProvider.overrideWithValue(
            _MemorySystemCardStore(),
          ),
          cpuUsageProvider.overrideWith(
            (ref) => const LoadSeries(
              current: 0.42,
              history: <double>[0.2, 0.3, 0.35, 0.42],
              temperatureC: 47,
            ),
          ),
          gpuUsageProvider.overrideWith(
            (ref) => const <GpuLoad>[
              GpuLoad(
                id: 'card0',
                label: 'AMD',
                series: LoadSeries(
                  current: 0.10,
                  history: <double>[0.08, 0.10],
                  temperatureC: 52,
                ),
              ),
            ],
          ),
          systemExtendedStatusProvider.overrideWith(
            _EmptyExtendedStatusController.new,
          ),
          batteryProvider.overrideWith(_NoBatteryController.new),
        ],
        child: _wrap(
          const SizedBox(width: 420, height: 640, child: SystemView()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // _FakeCard shells cannot reproduce real card content: mounting the
    // actual SystemView is what surfaces the 2x1-tile _MetricChip overflow
    // regression (a RenderFlex overflow throws during pump, failing the
    // test before any assertion runs).
    expect(find.byType(SystemCardTile), findsNWidgets(6));
    expect(find.text('CPU'), findsOneWidget);
    expect(find.textContaining('cores'), findsOneWidget);
    expect(find.text('47°C'), findsOneWidget);
    expect(find.text('AMD'), findsOneWidget);
  });
}

class _FakeCard extends StatelessWidget {
  const _FakeCard(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: ColoredBox(
        color: const Color(0xff334455),
        child: Center(child: Text(label)),
      ),
    );
  }
}

class _EmptyExtendedStatusController extends SystemExtendedStatusController {
  @override
  SystemExtendedStatus build() => const SystemExtendedStatus();
}

class _NoBatteryController extends BatteryController {
  @override
  BatteryStatus build() => BatteryStatus.unknown;
}

class _MemorySystemCardStore implements SystemCardStore {
  SavedSystemCardLayout? saved;
  int writes = 0;

  @override
  Future<SavedSystemCardLayout?> read() async => saved;

  @override
  Future<void> write(SavedSystemCardLayout layout) async {
    saved = layout;
    writes += 1;
  }

  @override
  void dispose() {}
}

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: Scaffold(
      backgroundColor: const Color(0xff121212),
      body: ShellTheme(data: const ShellThemeData(), child: child),
    ),
  );
}
