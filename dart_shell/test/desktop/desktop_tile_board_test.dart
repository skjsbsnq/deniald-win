import 'dart:io';

import 'package:denial_dart_shell/src/config/startup_environment.dart';
import 'package:denial_dart_shell/src/desktop/controllers/desktop_tile_controller.dart';
import 'package:denial_dart_shell/src/desktop/desktop_tile_board.dart';
import 'package:denial_dart_shell/src/desktop/desktop_tile_cell.dart';
import 'package:denial_dart_shell/src/desktop/desktop_tile_menu.dart';
import 'package:denial_dart_shell/src/desktop/models/desktop_tile.dart';
import 'package:denial_dart_shell/src/launcher/controllers/home_grid_controller.dart';
import 'package:denial_dart_shell/src/launcher/controllers/home_grid_layout.dart';
import 'package:denial_dart_shell/src/launcher/models/desktop_app.dart';
import 'package:denial_dart_shell/src/launcher/models/home_grid_item.dart';
import 'package:denial_dart_shell/src/local_apps/local_flutter_application.dart';
import 'package:denial_dart_shell/src/localization/denial_localizations.dart';
import 'package:denial_dart_shell/src/settings/settings_application.dart';
import 'package:denial_dart_shell/src/theme/shell_theme.dart';
import 'package:denial_dart_shell/src/wallpaper/state/wallpaper_accent.dart';
import 'package:denial_dart_shell/src/widgets/shell_surface_host.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('geometry', () {
    test('cells are square and separated by the seam', () {
      final geometry = DesktopTileGeometry.fit(340, columns: 6);

      expect(geometry.tileExtent, closeTo(53.33, 0.01));
      expect(geometry.gap, DesktopTileGeometry.gapExtent);

      final medium = geometry.rectFor(
        0,
        HomeGridItem.pinnedApp(_app('Alacritty')),
      );
      expect(medium.left, 0);
      expect(medium.top, 0);
      expect(medium.width, closeTo(110.67, 0.01));
      // A medium tile has to read as a square, which is why cells are square.
      expect(medium.height, closeTo(medium.width, 0.01));
    });

    test('a wide tile spans four columns of the same grid', () {
      final geometry = DesktopTileGeometry.fit(340, columns: 6);
      final wide = geometry.rectFor(
        0,
        HomeGridItem.pinnedApp(_app('Alacritty'), colSpan: 4, rowSpan: 2),
      );

      expect(wide.width, closeTo(geometry.tileExtent * 4 + 12, 0.01));
      expect(wide.height, closeTo(geometry.tileExtent * 2 + 4, 0.01));
    });

    test('an offset resolves to the slot it lands in', () {
      final geometry = DesktopTileGeometry.fit(340, columns: 6);

      expect(geometry.indexAt(Offset.zero, rows: 3), 0);
      expect(geometry.indexAt(const Offset(60, 4), rows: 3), 1);
      expect(geometry.indexAt(const Offset(4, 60), rows: 3), 6);
      expect(geometry.indexAt(const Offset(400, 4), rows: 3), isNull);
      expect(geometry.indexAt(const Offset(4, 400), rows: 3), isNull);
      expect(geometry.indexAt(const Offset(-4, 4), rows: 3), isNull);
    });

    test('the grid keeps one empty row past the last tile', () {
      final geometry = DesktopTileGeometry.fit(340, columns: 6);
      final slots = <HomeGridItem?>[HomeGridItem.pinnedApp(_app('Alacritty'))];

      // A 2x2 tile at slot 0 fills rows 0 and 1; the third row is the drop
      // target that makes a new bottom row reachable by dragging.
      expect(geometry.rowsFor(slots), 3);
      expect(geometry.rowsFor(const <HomeGridItem?>[]), 1);
    });
  });

  group('state equality', () {
    test('two boards holding the same tiles compare equal', () {
      final item = HomeGridItem.pinnedApp(_app('Alacritty'));
      final left = DesktopTileState(
        groups: <DesktopTileGroup>[
          DesktopTileGroup(name: 'Create', slots: <HomeGridItem?>[item, null]),
        ],
      );
      final right = DesktopTileState(
        groups: <DesktopTileGroup>[
          DesktopTileGroup(name: 'Create', slots: <HomeGridItem?>[item, null]),
        ],
      );

      expect(left, right);
      expect(left.hashCode, right.hashCode);
    });

    test('a renamed group or a moved tile compares unequal', () {
      final item = HomeGridItem.pinnedApp(_app('Alacritty'));
      final base = DesktopTileState(
        groups: <DesktopTileGroup>[
          DesktopTileGroup(name: 'Create', slots: <HomeGridItem?>[item, null]),
        ],
      );

      expect(
        base,
        isNot(
          DesktopTileState(
            groups: <DesktopTileGroup>[
              DesktopTileGroup(
                name: 'Work',
                slots: <HomeGridItem?>[item, null],
              ),
            ],
          ),
        ),
      );
      expect(
        base,
        isNot(
          DesktopTileState(
            groups: <DesktopTileGroup>[
              DesktopTileGroup(
                name: 'Create',
                slots: <HomeGridItem?>[null, item],
              ),
            ],
          ),
        ),
      );
    });

    test('slots compare by identity, which errs toward rebuilding', () {
      final left = DesktopTileGroup(
        name: '',
        slots: <HomeGridItem?>[HomeGridItem.pinnedApp(_app('Alacritty'))],
      );
      final right = DesktopTileGroup(
        name: '',
        slots: <HomeGridItem?>[HomeGridItem.pinnedApp(_app('Alacritty'))],
      );

      // Two separately built items describing the same application are not
      // identical, so this is deliberately unequal: HomeGridItem has no value
      // equality, and comparing unequal costs at worst one extra frame while
      // comparing equal would leave a stale board on screen.
      expect(left, isNot(right));
    });

    test('contains reports what is already on the board', () {
      final board = DesktopTileState(
        groups: <DesktopTileGroup>[
          DesktopTileGroup(
            name: '',
            slots: <HomeGridItem?>[HomeGridItem.pinnedApp(_app('Alacritty'))],
          ),
        ],
      );

      expect(board.contains('app:alacritty.desktop'), isTrue);
      expect(board.contains('app:chromium.desktop'), isFalse);
      expect(board.hasTiles, isTrue);
      expect(DesktopTileState.empty.hasTiles, isFalse);
    });
  });

  group('controller', () {
    test('a board with no saved file starts empty', () async {
      final container = await _container();

      final board = container.read(desktopTileControllerProvider).requireValue;
      expect(board.groups, isEmpty);
      expect(board.hasTiles, isFalse);
    });

    test('pinning drops a medium tile into the first free cell', () async {
      final container = await _container();
      final controller = container.read(desktopTileControllerProvider.notifier);

      controller.pinApp(_app('Alacritty'));

      final group = container
          .read(desktopTileControllerProvider)
          .requireValue
          .groups
          .single;
      expect(group.slots[0]!.id, 'app:alacritty.desktop');
      expect(group.slots[0]!.colSpan, 2);
      expect(group.slots[0]!.rowSpan, 2);
    });

    test(
      'a second application takes the next free cell, not the first',
      () async {
        final container = await _container();
        final controller = container.read(
          desktopTileControllerProvider.notifier,
        );

        controller.pinApp(_app('Alacritty'));
        controller.pinApp(_app('Chromium'));

        final group = container
            .read(desktopTileControllerProvider)
            .requireValue
            .groups
            .single;
        // A 2x2 tile at slot 0 occupies cells 0, 1, 6 and 7, so the next free
        // anchor in a six-column grid is slot 2.
        expect(group.slots[2]!.id, 'app:chromium.desktop');
        expect(group.tileCount, 2);
      },
    );

    test('pinning the same application twice changes nothing', () async {
      final container = await _container();
      final controller = container.read(desktopTileControllerProvider.notifier);

      controller.pinApp(_app('Alacritty'));
      controller.pinApp(_app('Alacritty'));

      expect(
        container
            .read(desktopTileControllerProvider)
            .requireValue
            .groups
            .single
            .tileCount,
        1,
      );
    });

    test('unpinning removes one tile and closes the gap behind it', () async {
      final container = await _container();
      final controller = container.read(desktopTileControllerProvider.notifier);

      controller.pinApp(_app('Alacritty'));
      controller.pinApp(_app('Chromium'));
      controller.pinApp(_app('Dolphin'));
      controller.unpin('app:alacritty.desktop');

      final group = container
          .read(desktopTileControllerProvider)
          .requireValue
          .groups
          .single;
      expect(group.tileCount, 2);
      // Windows 10 reflows a group when a tile leaves it rather than leaving a
      // hole where the tile was.
      expect(group.slots[0]!.id, 'app:chromium.desktop');
      expect(group.slots[2]!.id, 'app:dolphin.desktop');
    });

    test('emptying an unnamed group takes the group with it', () async {
      final container = await _container();
      final controller = container.read(desktopTileControllerProvider.notifier);

      controller.pinApp(_app('Alacritty'));
      controller.unpin('app:alacritty.desktop');

      // The board has to be able to reach a state with no groups at all, or the
      // hint that explains how tiles get there could never come back.
      expect(
        container.read(desktopTileControllerProvider).requireValue.groups,
        isEmpty,
      );
    });

    test('a named group survives losing its last tile', () async {
      final container = await _container();
      final controller = container.read(desktopTileControllerProvider.notifier);

      controller.pinApp(_app('Alacritty'));
      controller.renameGroup(0, 'Create');
      controller.unpin('app:alacritty.desktop');

      final groups = container
          .read(desktopTileControllerProvider)
          .requireValue
          .groups;
      expect(groups, hasLength(1));
      expect(groups.single.name, 'Create');
      expect(groups.single.tileCount, 0);
    });

    test('every one of the four sizes applies', () async {
      final container = await _container();
      final controller = container.read(desktopTileControllerProvider.notifier);
      controller.pinApp(_app('Alacritty'));

      for (final size in DesktopTileSize.values) {
        controller.resizeSlot(0, 0, size);
        final item = container
            .read(desktopTileControllerProvider)
            .requireValue
            .groups
            .single
            .slots[0]!;
        expect(item.colSpan, size.colSpan, reason: size.name);
        expect(item.rowSpan, size.rowSpan, reason: size.name);
        expect(DesktopTileSize.of(item), size);
      }
    });

    test(
      'a wide tile is refused where it would run past the last column',
      () async {
        final container = await _container();
        final controller = container.read(
          desktopTileControllerProvider.notifier,
        );
        controller.pinApp(_app('Alacritty'));
        controller.pinApp(_app('Chromium'));
        controller.pinApp(_app('Dolphin'));

        // The three medium tiles anchor at slots 0, 2 and 4, so Dolphin starts at
        // column 4 and four columns would reach column 8 of a six-column grid.
        // Refusing beats silently reflowing the board out from under the user.
        controller.resizeSlot(0, 4, DesktopTileSize.wide);

        final item = container
            .read(desktopTileControllerProvider)
            .requireValue
            .groups
            .single
            .slots[4]!;
        expect(item.colSpan, 2);
      },
    );

    test('a wide tile is accepted where the row still has room', () async {
      final container = await _container();
      final controller = container.read(desktopTileControllerProvider.notifier);
      controller.pinApp(_app('Alacritty'));
      controller.pinApp(_app('Chromium'));

      // Chromium anchors at column 2, and 2 + 4 lands exactly on the sixth
      // column, so this one has to be allowed.
      controller.resizeSlot(0, 2, DesktopTileSize.wide);

      expect(
        container
            .read(desktopTileControllerProvider)
            .requireValue
            .groups
            .single
            .slots[2]!
            .colSpan,
        4,
      );
    });

    test('resizing onto a neighbour is refused', () async {
      final container = await _container();
      final controller = container.read(desktopTileControllerProvider.notifier);
      controller.pinApp(_app('Alacritty'));
      controller.pinApp(_app('Chromium'));

      controller.resizeSlot(0, 0, DesktopTileSize.wide);

      expect(
        container
            .read(desktopTileControllerProvider)
            .requireValue
            .groups
            .single
            .slots[0]!
            .colSpan,
        2,
      );
    });

    test('a tile swaps with whatever it is dropped on', () async {
      final container = await _container();
      final controller = container.read(desktopTileControllerProvider.notifier);
      controller.pinApp(_app('Alacritty'));
      controller.pinApp(_app('Chromium'));

      expect(controller.canMoveSlot(0, 0, 2), isTrue);
      expect(controller.moveSlot(0, 0, 2), 2);

      final group = container
          .read(desktopTileControllerProvider)
          .requireValue
          .groups
          .single;
      expect(group.slots[0]!.id, 'app:chromium.desktop');
      expect(group.slots[2]!.id, 'app:alacritty.desktop');
    });

    test('a group can be renamed and named groups can be added', () async {
      final container = await _container();
      final controller = container.read(desktopTileControllerProvider.notifier);

      controller.pinApp(_app('Alacritty'));
      controller.renameGroup(0, 'Create');
      controller.addGroup('Play');

      final groups = container
          .read(desktopTileControllerProvider)
          .requireValue
          .groups;
      expect(groups.map((group) => group.name), <String>['Create', 'Play']);

      controller.removeGroupIfEmpty(1);
      expect(
        container
            .read(desktopTileControllerProvider)
            .requireValue
            .groups
            .map((group) => group.name),
        <String>['Create'],
      );
    });

    test('removeGroupIfEmpty leaves a group that still holds a tile', () async {
      final container = await _container();
      final controller = container.read(desktopTileControllerProvider.notifier);
      controller.pinApp(_app('Alacritty'));

      controller.removeGroupIfEmpty(0);

      expect(
        container.read(desktopTileControllerProvider).requireValue.groups,
        hasLength(1),
      );
    });

    test(
      'the board survives a restart, spans and group name included',
      () async {
        final directory = _tempDirectory();

        final first = await _container(directory: directory);
        final controller = first.read(desktopTileControllerProvider.notifier);
        controller.pinApp(_app('Alacritty'));
        controller.resizeSlot(0, 0, DesktopTileSize.wide);
        controller.renameGroup(0, 'Create');
        // The mutators persist without being awaited, so let the writes land.
        await Future<void>.delayed(Duration.zero);
        first.dispose();

        final second = await _container(directory: directory);
        final group = second
            .read(desktopTileControllerProvider)
            .requireValue
            .groups
            .single;

        expect(group.name, 'Create');
        expect(group.slots[0]!.id, 'app:alacritty.desktop');
        expect(group.slots[0]!.colSpan, 4);
        expect(group.slots[0]!.rowSpan, 2);
        expect(group.slots[0]!.app!.name, 'Alacritty');
      },
    );

    test('a shell-hosted application can be pinned and comes back', () async {
      final directory = _tempDirectory();

      final first = await _container(
        directory: directory,
        localApps: <LocalFlutterApplication>[denialSettingsApplication],
      );
      first
          .read(desktopTileControllerProvider.notifier)
          .pinLocalApp(denialSettingsApplication);
      await Future<void>.delayed(Duration.zero);
      first.dispose();

      final second = await _container(
        directory: directory,
        localApps: <LocalFlutterApplication>[denialSettingsApplication],
      );
      final item = second
          .read(desktopTileControllerProvider)
          .requireValue
          .groups
          .single
          .slots[0]!;

      expect(item.localApp, same(denialSettingsApplication));
      expect(item.app, isNull);
    });

    test(
      'a shell-hosted tile whose application left the bundle is dropped',
      () async {
        final directory = _tempDirectory();

        final first = await _container(
          directory: directory,
          localApps: <LocalFlutterApplication>[denialSettingsApplication],
        );
        first
            .read(desktopTileControllerProvider.notifier)
            .pinLocalApp(denialSettingsApplication);
        await Future<void>.delayed(Duration.zero);
        first.dispose();

        // Its widget tree is compiled in, so an id the registry no longer knows
        // can never render again — unlike an uninstalled .desktop entry, which
        // keeps its recorded name and falls back to the default icon.
        final second = await _container(directory: directory);
        expect(
          second.read(desktopTileControllerProvider).requireValue.hasTiles,
          isFalse,
        );
      },
    );

    test('the board does not grow tiles of its own', () async {
      final container = await _container(
        installedApps: <DesktopApp>[
          for (var index = 0; index < 50; index += 1) _app('App$index'),
        ],
      );
      await container.read(homeGridControllerProvider.future);

      // This is the whole reason the pin board is not HomeGridController: that
      // controller seeds itself from the installed-application scan and appends
      // to it on a timer, which would refill a board the user just emptied.
      expect(
        container.read(desktopTileControllerProvider).requireValue.groups,
        isEmpty,
      );
    });
  });

  group('board', () {
    testWidgets('tile groups are built lazily as they enter the viewport', (
      tester,
    ) async {
      final board = DesktopTileState(
        groups: <DesktopTileGroup>[
          for (var index = 0; index < 30; index += 1)
            DesktopTileGroup(name: 'Group $index', slots: const []),
        ],
      );
      await _pumpBoard(tester, board);

      expect(find.text('Group 0'), findsOneWidget);
      expect(find.text('Group 29'), findsNothing);

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -5000));
      await tester.pumpAndSettle();

      expect(find.text('Group 29'), findsOneWidget);
    });

    testWidgets('an empty board explains how tiles get there', (tester) async {
      await _pumpBoard(tester, DesktopTileState.empty);

      expect(find.byType(DesktopTileBoardEmptyState), findsOneWidget);
      expect(
        find.text('Right-click an application on the left to pin it here'),
        findsOneWidget,
      );
    });

    testWidgets('the hint gives way once something is pinned', (tester) async {
      await _pumpBoard(
        tester,
        _boardWith(<HomeGridItem?>[HomeGridItem.pinnedApp(_app('Alacritty'))]),
      );

      expect(find.byType(DesktopTileBoardEmptyState), findsNothing);
      expect(find.byType(DesktopTileCell), findsOneWidget);
      expect(find.text('Alacritty'), findsOneWidget);
    });

    testWidgets('all four sizes render without overflowing', (tester) async {
      await _pumpBoard(
        tester,
        _boardWith(<HomeGridItem?>[
          HomeGridItem.pinnedApp(_app('Alacritty'), colSpan: 4, rowSpan: 2),
          null,
          null,
          null,
          HomeGridItem.pinnedApp(_app('Bssh'), colSpan: 1, rowSpan: 1),
          HomeGridItem.pinnedApp(_app('Chromium'), colSpan: 1, rowSpan: 1),
          for (var index = 6; index < 12; index += 1) null,
          HomeGridItem.pinnedApp(_app('Dolphin'), colSpan: 4, rowSpan: 4),
        ]),
      );

      expect(find.byType(DesktopTileCell), findsNWidgets(4));
      // A single cell has no room for a label, so the two small tiles show only
      // their icons while the wide and large tiles are labelled.
      expect(find.text('Alacritty'), findsOneWidget);
      expect(find.text('Dolphin'), findsOneWidget);
      expect(find.text('Bssh'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a small tile stays inside its own cell', (tester) async {
      await _pumpBoard(
        tester,
        _boardWith(<HomeGridItem?>[
          HomeGridItem.pinnedApp(_app('Bssh'), colSpan: 1, rowSpan: 1),
        ]),
      );

      final cell = tester.getRect(find.byType(DesktopTileCell));
      final geometry = DesktopTileGeometry.fit(
        372 - 32,
        columns: DesktopTileController.columns,
      );

      expect(cell.width, closeTo(geometry.tileExtent, 1));
      expect(cell.height, closeTo(geometry.tileExtent, 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('an unnamed group offers a placeholder heading', (
      tester,
    ) async {
      await _pumpBoard(
        tester,
        _boardWith(<HomeGridItem?>[HomeGridItem.pinnedApp(_app('Alacritty'))]),
      );

      expect(find.text('Name group'), findsOneWidget);
    });

    testWidgets('a named group shows its name instead', (tester) async {
      await _pumpBoard(
        tester,
        DesktopTileState(
          groups: <DesktopTileGroup>[
            DesktopTileGroup(
              name: 'Create',
              slots: <HomeGridItem?>[HomeGridItem.pinnedApp(_app('Alacritty'))],
            ),
          ],
        ),
      );

      expect(find.text('Create'), findsOneWidget);
      expect(find.text('Name group'), findsNothing);
    });

    testWidgets('double-clicking a heading opens an input, Enter renames', (
      tester,
    ) async {
      final container = await _pumpBoard(
        tester,
        _boardWith(<HomeGridItem?>[HomeGridItem.pinnedApp(_app('Alacritty'))]),
      );

      await tester.tap(find.text('Name group'));
      await tester.pump(kDoubleTapMinTime);
      await tester.tap(find.text('Name group'));
      await tester.pumpAndSettle();

      expect(find.byType(EditableText), findsOneWidget);
      await tester.enterText(find.byType(EditableText), 'Create');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(
        container
            .read(desktopTileControllerProvider)
            .requireValue
            .groups
            .single
            .name,
        'Create',
      );
    });

    testWidgets('Escape abandons a rename', (tester) async {
      final container = await _pumpBoard(
        tester,
        DesktopTileState(
          groups: <DesktopTileGroup>[
            DesktopTileGroup(
              name: 'Create',
              slots: <HomeGridItem?>[HomeGridItem.pinnedApp(_app('Alacritty'))],
            ),
          ],
        ),
      );

      await tester.tap(find.text('Create'));
      await tester.pump(kDoubleTapMinTime);
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText), 'Discarded');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(
        container
            .read(desktopTileControllerProvider)
            .requireValue
            .groups
            .single
            .name,
        'Create',
      );
    });

    testWidgets('double-clicking a heading supports Chinese group name', (
      tester,
    ) async {
      final container = await _pumpBoard(
        tester,
        _boardWith(<HomeGridItem?>[HomeGridItem.pinnedApp(_app('Alacritty'))]),
      );

      await tester.tap(find.text('Name group'));
      await tester.pump(kDoubleTapMinTime);
      await tester.tap(find.text('Name group'));
      await tester.pumpAndSettle();

      expect(find.byType(EditableText), findsOneWidget);
      await tester.enterText(find.byType(EditableText), '生产力工具');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(
        container
            .read(desktopTileControllerProvider)
            .requireValue
            .groups
            .single
            .name,
        '生产力工具',
      );
      expect(find.text('生产力工具'), findsOneWidget);
    });

    testWidgets('right-clicking a tile offers unpin and all four sizes', (
      tester,
    ) async {
      await _pumpBoard(
        tester,
        _boardWith(<HomeGridItem?>[HomeGridItem.pinnedApp(_app('Alacritty'))]),
      );

      await _secondaryTap(tester, find.byType(DesktopTileCell));

      expect(find.byType(DesktopTileMenu), findsOneWidget);
      expect(find.text('Unpin from Start'), findsOneWidget);
      expect(find.text('Resize'), findsOneWidget);
      expect(find.text('Small'), findsOneWidget);
      expect(find.text('Medium'), findsOneWidget);
      expect(find.text('Wide'), findsOneWidget);
      expect(find.text('Large'), findsOneWidget);
      // Pinning belongs to the application list; a tile is already pinned.
      expect(find.text('Pin to Start'), findsNothing);
    });

    testWidgets('unpinning from a tile empties the board', (tester) async {
      final container = await _pumpBoard(
        tester,
        _boardWith(<HomeGridItem?>[HomeGridItem.pinnedApp(_app('Alacritty'))]),
      );

      await _secondaryTap(tester, find.byType(DesktopTileCell));
      await tester.tap(find.text('Unpin from Start'));
      await tester.pumpAndSettle();

      expect(
        container.read(desktopTileControllerProvider).requireValue.hasTiles,
        isFalse,
      );
      expect(find.byType(DesktopTileBoardEmptyState), findsOneWidget);
    });

    testWidgets('choosing a size from the menu resizes the tile', (
      tester,
    ) async {
      final container = await _pumpBoard(
        tester,
        _boardWith(<HomeGridItem?>[HomeGridItem.pinnedApp(_app('Alacritty'))]),
      );

      await _secondaryTap(tester, find.byType(DesktopTileCell));
      await tester.tap(find.text('Wide'));
      await tester.pumpAndSettle();

      final item = container
          .read(desktopTileControllerProvider)
          .requireValue
          .groups
          .single
          .slots[0]!;
      expect(item.colSpan, 4);
      expect(item.rowSpan, 2);
    });

    testWidgets('clicking a tile launches its application', (tester) async {
      DesktopApp? launched;
      await _pumpBoard(
        tester,
        _boardWith(<HomeGridItem?>[HomeGridItem.pinnedApp(_app('Alacritty'))]),
        onLaunch: (app) => launched = app,
      );

      await tester.tap(find.byType(DesktopTileCell));
      await tester.pump();

      expect(launched?.name, 'Alacritty');
    });

    testWidgets('a tile takes focus and Enter launches it', (tester) async {
      DesktopApp? launched;
      await _pumpBoard(
        tester,
        _boardWith(<HomeGridItem?>[HomeGridItem.pinnedApp(_app('Alacritty'))]),
        onLaunch: (app) => launched = app,
      );

      final cell = tester.element(
        find
            .descendant(
              of: find.byType(DesktopTileCell),
              matching: find.byType(MouseRegion),
            )
            .first,
      );
      Focus.of(cell).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);

      expect(launched?.name, 'Alacritty');
    });

    testWidgets('a mouse drag moves a tile without a long press', (
      tester,
    ) async {
      final container = await _pumpBoard(
        tester,
        _boardWith(<HomeGridItem?>[
          HomeGridItem.pinnedApp(_app('Alacritty')),
          null,
          HomeGridItem.pinnedApp(_app('Chromium')),
        ]),
      );

      final source = tester.getCenter(
        find.byKey(const ValueKey<String>('tile:app:alacritty.desktop')),
      );
      final target = tester.getCenter(
        find.byKey(const ValueKey<String>('tile:app:chromium.desktop')),
      );

      final gesture = await tester.startGesture(
        source,
        kind: PointerDeviceKind.mouse,
      );
      // No long-press delay: a mouse drag starts as soon as the pointer moves.
      await gesture.moveTo(target);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      final group = container
          .read(desktopTileControllerProvider)
          .requireValue
          .groups
          .single;
      expect(group.slots[0]!.id, 'app:chromium.desktop');
      expect(group.slots[2]!.id, 'app:alacritty.desktop');
    });
  });

  group('shared grid geometry stays put for the mobile home screen', () {
    test('omitting columns still reads the global column count', () {
      final item = HomeGridItem.batteryDischarge(colSpan: 4, rowSpan: 2);
      final previous = HomeGridLayout.columns;
      addTearDown(() => HomeGridLayout.columns = previous);

      HomeGridLayout.columns = 4;
      expect(HomeGridLayout.cellsFor(0, item), <int>[0, 1, 2, 3, 4, 5, 6, 7]);
      expect(HomeGridLayout.itemFitsAtColumn(item, 0), isTrue);
      expect(HomeGridLayout.itemFitsAtColumn(item, 1), isFalse);
      expect(HomeGridLayout.anchorForCell(5, <HomeGridItem?>[item]), 0);

      // The pin board asks for six columns of the same functions; the mobile
      // caller passes nothing and must be unaffected by that.
      expect(HomeGridLayout.cellsFor(0, item, columns: 6), <int>[
        0,
        1,
        2,
        3,
        6,
        7,
        8,
        9,
      ]);
      expect(HomeGridLayout.itemFitsAtColumn(item, 1, columns: 6), isTrue);
      expect(HomeGridLayout.columns, 4);
    });

    test('an application tile on the home screen still cannot be resized', () {
      final mobile = HomeGridItem.app(_app('Alacritty'));

      // The pin board's four sizes must not leak into the home screen, where
      // every application occupies exactly one cell.
      expect(mobile.resizable, isFalse);
      expect(mobile.minColSpan, 1);
      expect(mobile.maxColSpan, 1);
      expect(mobile.resize(colSpan: 4, rowSpan: 4), same(mobile));
      expect(
        HomeGridItem.localApp(denialSettingsApplication).resizable,
        isFalse,
      );
    });

    test('the widget tiles keep the bounds they had', () {
      final clock = HomeGridItem.clock();
      final battery = HomeGridItem.batteryDischarge();

      expect(clock.resizable, isTrue);
      expect(clock.minColSpan, 2);
      expect(clock.maxColSpan, 4);
      expect(clock.minRowSpan, 1);
      expect(clock.maxRowSpan, 3);
      expect(battery.resizable, isTrue);
      expect(battery.minColSpan, 2);
      expect(battery.maxColSpan, 4);
      expect(battery.minRowSpan, 1);
      expect(battery.maxRowSpan, 3);

      // Resizing still clamps to those bounds rather than taking the request.
      expect(clock.resize(colSpan: 9, rowSpan: 9).colSpan, 4);
      expect(clock.resize(colSpan: 0, rowSpan: 0).colSpan, 2);
    });

    test('a pinned tile is the one application tile that can be resized', () {
      final pinned = HomeGridItem.pinnedApp(_app('Alacritty'));

      expect(pinned.resizable, isTrue);
      expect(pinned.maxColSpan, 4);
      expect(pinned.maxRowSpan, 4);
      expect(pinned.resize(colSpan: 4, rowSpan: 2).colSpan, 4);
      expect(pinned.resize(colSpan: 9, rowSpan: 9).colSpan, 4);
    });
  });
}

DesktopApp _app(String name) {
  final id = '${name.toLowerCase()}.desktop';
  return DesktopApp(
    id: id,
    name: name,
    exec: '/usr/bin/${name.toLowerCase()}',
    desktopPath: '/usr/share/applications/$id',
    categories: const <String>[],
  );
}

DesktopTileState _boardWith(List<HomeGridItem?> slots) {
  return DesktopTileState(
    groups: <DesktopTileGroup>[DesktopTileGroup(name: '', slots: slots)],
  );
}

Directory _tempDirectory() {
  final directory = Directory.systemTemp.createTempSync('denial-tile-board');
  addTearDown(() => directory.deleteSync(recursive: true));
  return directory;
}

/// A container whose pin board reads and writes a throwaway directory.
Future<ProviderContainer> _container({
  Directory? directory,
  List<LocalFlutterApplication> localApps = const <LocalFlutterApplication>[],
  List<DesktopApp> installedApps = const <DesktopApp>[],
}) async {
  final configHome = directory ?? _tempDirectory();
  final container = ProviderContainer(
    overrides: [
      startupEnvironmentProvider.overrideWithValue(
        StartupEnvironment(<String, String>{
          'HOME': '/home/example',
          'XDG_CONFIG_HOME': configHome.path,
        }),
      ),
      localFlutterApplicationsProvider.overrideWithValue(localApps),
      homeGridControllerProvider.overrideWith(
        () => _StubHomeGridController(installedApps),
      ),
    ],
  );
  if (directory == null) {
    addTearDown(container.dispose);
  }
  await container.read(desktopTileControllerProvider.future);
  return container;
}

Future<ProviderContainer> _pumpBoard(
  WidgetTester tester,
  DesktopTileState board, {
  ValueChanged<DesktopApp>? onLaunch,
}) async {
  // The tile area's real width inside the 680px three-column panel.
  tester.view.physicalSize = const Size(372, 560);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(
    overrides: [
      desktopTileControllerProvider.overrideWith(
        () => _StubTileController(board),
      ),
    ],
  );
  addTearDown(container.dispose);
  await container.read(desktopTileControllerProvider.future);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: DenialLocalizationScope(
        locale: const Locale('en'),
        child: ShellTheme(
          data: const ShellThemeData(),
          // Draggable needs an Overlay to float its feedback in. The shell has
          // one around the whole scene (_ShellOverlayHost), so this mirrors the
          // production tree rather than adding scaffolding the shell lacks.
          child: Overlay(
            initialEntries: <OverlayEntry>[
              OverlayEntry(
                builder: (context) => ShellSurfaceHost(
                  child: DesktopTileBoard(
                    accent: WallpaperAccent.fallback,
                    onLaunch: onLaunch ?? (_) {},
                    onLaunchLocal: (_) {},
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> _secondaryTap(WidgetTester tester, Finder finder) async {
  final gesture = await tester.startGesture(
    tester.getCenter(finder),
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  await gesture.up();
  await tester.pumpAndSettle();
}

class _StubTileController extends DesktopTileController {
  _StubTileController(this.initial);

  final DesktopTileState initial;

  @override
  Future<DesktopTileState> build() async => initial;
}

class _StubHomeGridController extends HomeGridController {
  _StubHomeGridController(this.apps);

  final List<DesktopApp> apps;

  @override
  Future<HomeGridState> build() async {
    return HomeGridState(slots: const [], desktopApps: apps);
  }
}
