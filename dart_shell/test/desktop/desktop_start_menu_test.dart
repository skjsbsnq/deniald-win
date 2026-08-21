import 'package:denial_dart_shell/src/desktop/controllers/desktop_tile_controller.dart';
import 'package:denial_dart_shell/src/desktop/desktop_start_menu.dart';
import 'package:denial_dart_shell/src/desktop/desktop_start_menu_app_list.dart';
import 'package:denial_dart_shell/src/desktop/desktop_start_menu_rail.dart';
import 'package:denial_dart_shell/src/desktop/desktop_tile_board.dart';
import 'package:denial_dart_shell/src/desktop/desktop_tile_cell.dart';
import 'package:denial_dart_shell/src/desktop/desktop_tile_menu.dart';
import 'package:denial_dart_shell/src/desktop/desktop_workspace.dart';
import 'package:denial_dart_shell/src/desktop/models/desktop_tile.dart';
import 'package:denial_dart_shell/src/launcher/controllers/home_grid_controller.dart';
import 'package:denial_dart_shell/src/launcher/models/desktop_app.dart';
import 'package:denial_dart_shell/src/launcher/models/home_grid_item.dart';
import 'package:denial_dart_shell/src/local_apps/local_flutter_application.dart';
import 'package:denial_dart_shell/src/localization/denial_localizations.dart';
import 'package:denial_dart_shell/src/models/shell_popup_placement.dart';
import 'package:denial_dart_shell/src/theme/shell_theme.dart';
import 'package:denial_dart_shell/src/wallpaper/state/wallpaper_accent.dart';
import 'package:denial_dart_shell/src/widgets/shell_surface_host.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const Size _panelSize = Size(680, 620);

void main() {
  group('letter grouping', () {
    test('Latin initials become their own heading', () {
      expect(startMenuGroupKey('Alacritty'), 'A');
      expect(startMenuGroupKey('firefox'), 'F');
      expect(startMenuGroupKey('  Zeno'), 'Z');
    });

    test('accented Latin folds onto the unaccented heading', () {
      expect(startMenuGroupKey('Épiphanie'), 'E');
      expect(startMenuGroupKey('Œuvre'), startMenuOtherGroupKey);
      expect(startMenuGroupKey('Łukasz'), 'L');
    });

    test('anything that is not a Latin letter lands in the catch-all', () {
      expect(startMenuGroupKey('夸克网盘'), startMenuOtherGroupKey);
      expect(startMenuGroupKey('1Password'), startMenuOtherGroupKey);
      expect(startMenuGroupKey('+Sheets'), startMenuOtherGroupKey);
      expect(startMenuGroupKey(''), startMenuOtherGroupKey);
      expect(startMenuGroupKey('   '), startMenuOtherGroupKey);
    });

    test('the catch-all leads and letters follow in order', () {
      final groups = groupStartMenuEntries(<DesktopStartMenuEntry>[
        DesktopStartMenuEntry.desktop(_app('Chromium')),
        DesktopStartMenuEntry.desktop(_app('夸克网盘')),
        DesktopStartMenuEntry.desktop(_app('Alacritty')),
      ]);

      expect(groups.map((group) => group.key), <String>[
        startMenuOtherGroupKey,
        'A',
        'C',
      ]);
    });

    test('entry order inside a group is the order it was given in', () {
      final groups = groupStartMenuEntries(<DesktopStartMenuEntry>[
        DesktopStartMenuEntry.desktop(_app('Alacritty')),
        DesktopStartMenuEntry.desktop(_app('Ardour')),
      ]);

      expect(groups.single.entries.map((entry) => entry.name), <String>[
        'Alacritty',
        'Ardour',
      ]);
    });
  });

  group('derived catalog', () {
    test('equal application inputs reuse the memoized catalog', () {
      final apps = <DesktopApp>[_app('Alacritty'), _app('Chromium')];
      const slots = <HomeGridItem?>[];
      final registry = LocalFlutterApplicationRegistry(
        const <LocalFlutterApplication>[],
      );
      final source = DesktopStartMenuCatalogSource(
        desktopApps: apps,
        slots: slots,
        localRegistry: registry,
        locale: const Locale('en'),
        localizedLocalEntries: const <DesktopStartMenuEntry>[],
      );
      final equalSource = DesktopStartMenuCatalogSource(
        desktopApps: apps,
        slots: slots,
        localRegistry: registry,
        locale: const Locale('en'),
        localizedLocalEntries: const <DesktopStartMenuEntry>[],
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final subscription = container.listen(
        desktopStartMenuCatalogProvider(source),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);

      expect(
        container.read(desktopStartMenuCatalogProvider(equalSource)),
        same(container.read(desktopStartMenuCatalogProvider(source))),
      );
    });

    test('a changed application list derives a fresh sorted catalog', () {
      final registry = LocalFlutterApplicationRegistry(
        const <LocalFlutterApplication>[],
      );
      const slots = <HomeGridItem?>[];
      final firstApps = <DesktopApp>[_app('Chromium')];
      final nextApps = <DesktopApp>[_app('Chromium'), _app('Alacritty')];
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final first = container.read(
        desktopStartMenuCatalogProvider(
          DesktopStartMenuCatalogSource(
            desktopApps: firstApps,
            slots: slots,
            localRegistry: registry,
            locale: const Locale('en'),
            localizedLocalEntries: const <DesktopStartMenuEntry>[],
          ),
        ),
      );
      final next = container.read(
        desktopStartMenuCatalogProvider(
          DesktopStartMenuCatalogSource(
            desktopApps: nextApps,
            slots: slots,
            localRegistry: registry,
            locale: const Locale('en'),
            localizedLocalEntries: const <DesktopStartMenuEntry>[],
          ),
        ),
      );

      expect(first.entries.map((entry) => entry.name), <String>['Chromium']);
      expect(next.entries.map((entry) => entry.name), <String>[
        'Alacritty',
        'Chromium',
      ]);
    });
  });

  group('placement', () {
    test('the panel and its hover trigger share one placement', () {
      const viewSize = Size(1707, 1067);
      const output = Rect.fromLTWH(0, 0, 1707, 1067);

      final panel = DesktopMetrics.launcherRect(viewSize, outputRect: output);
      final trigger = DesktopMetrics.launcherTriggerRect(
        viewSize,
        outputRect: output,
      );

      expect(
        ShellPopupPlacement.desktopStartMenu.anchor,
        ShellPopupAnchor.bottomLeft,
      );
      expect(panel.left, 14);
      expect(panel.bottom, 1067 - 14);
      // The trigger has to sit on the same edge as the panel; these used to be
      // two unrelated literals and drifted to opposite corners.
      expect(trigger.left, output.left);
      expect(trigger.bottom, output.bottom);
    });
  });

  group('layout', () {
    testWidgets('mounting the retained menu does not steal focus', (
      tester,
    ) async {
      await _pumpMenu(tester, apps: <DesktopApp>[_app('Alacritty')]);

      expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode
            .hasFocus,
        isFalse,
      );
    });

    testWidgets('three columns share the panel without overflowing', (
      tester,
    ) async {
      await _pumpMenu(tester, apps: <DesktopApp>[_app('Alacritty')]);

      expect(tester.getSize(find.byType(DesktopStartMenu)).width, 680);
      expect(
        tester.getSize(find.byType(DesktopStartMenuRail)).width,
        DesktopStartMenuRail.collapsedWidth,
      );
      expect(
        tester.getSize(find.byType(DesktopStartMenuAppList)).width,
        DesktopStartMenu.appListWidth,
      );
      expect(
        tester.getSize(find.byType(DesktopStartMenuTileArea)).width,
        greaterThanOrEqualTo(DesktopStartMenuTileArea.minWidth),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the columns leave room for the search strip below them', (
      tester,
    ) async {
      await _pumpMenu(tester, apps: <DesktopApp>[_app('Alacritty')]);

      final railBottom = tester
          .getRect(find.byType(DesktopStartMenuRail))
          .bottom;
      final searchTop = tester.getRect(find.byType(EditableText)).top;

      expect(railBottom, lessThanOrEqualTo(searchTop));
      expect(tester.getSize(find.byType(DesktopStartMenu)).height, 620);
    });

    testWidgets('the tile area explains how tiles get there', (tester) async {
      await _pumpMenu(tester, apps: <DesktopApp>[_app('Alacritty')]);

      expect(
        find.text('Right-click an application on the left to pin it here'),
        findsOneWidget,
      );
    });

    testWidgets('letter headings are rendered above their applications', (
      tester,
    ) async {
      await _pumpMenu(
        tester,
        apps: <DesktopApp>[_app('Alacritty'), _app('Chromium')],
      );

      expect(find.text('A'), findsOneWidget);
      expect(find.text('C'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('A')).dy,
        lessThan(tester.getTopLeft(find.text('Alacritty')).dy),
      );
    });

    testWidgets('an application row takes focus and Enter launches it', (
      tester,
    ) async {
      DesktopApp? launched;
      await _pumpMenu(
        tester,
        apps: <DesktopApp>[_app('Alacritty')],
        onLaunch: (app) => launched = app,
      );

      final row = tester.element(
        find
            .descendant(
              of: find.byKey(
                const ValueKey<String>('desktop-app-alacritty.desktop'),
              ),
              matching: find.byType(MouseRegion),
            )
            .first,
      );
      Focus.of(row).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);

      expect(launched?.name, 'Alacritty');
    });
  });

  group('icon rail', () {
    testWidgets('collapsed, the rail shows glyphs without labels', (
      tester,
    ) async {
      await _pumpMenu(tester, apps: <DesktopApp>[_app('Alacritty')]);

      expect(find.text('Documents'), findsNothing);
      expect(find.text('Pictures'), findsNothing);
    });

    testWidgets('the hamburger expands the rail over the app list', (
      tester,
    ) async {
      await _pumpMenu(tester, apps: <DesktopApp>[_app('Alacritty')]);

      await tester.tap(find.bySemanticsLabel('Expand'));
      await tester.pumpAndSettle();

      expect(find.text('Documents'), findsOneWidget);
      expect(find.text('Pictures'), findsOneWidget);
      expect(find.text('Power & session'), findsOneWidget);
      expect(
        tester.getSize(find.byType(DesktopStartMenuRail)).width,
        DesktopStartMenuRail.expandedWidth,
      );
      // Expanding must not squeeze the tile area below its floor, which is the
      // reason the rail covers the list instead of resizing it.
      expect(
        tester.getSize(find.byType(DesktopStartMenuTileArea)).width,
        greaterThanOrEqualTo(DesktopStartMenuTileArea.minWidth),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the settings entry hands off to the settings application', (
      tester,
    ) async {
      var opened = 0;
      await _pumpMenu(
        tester,
        apps: <DesktopApp>[_app('Alacritty')],
        onOpenSettings: () => opened += 1,
      );

      await tester.tap(find.bySemanticsLabel('Settings'));
      expect(opened, 1);
    });

    testWidgets('the account entry is a label, not a button', (tester) async {
      await _pumpMenu(tester, apps: <DesktopApp>[_app('Alacritty')]);

      await tester.tap(find.bySemanticsLabel('Expand'));
      await tester.pumpAndSettle();

      expect(find.text('User'), findsOneWidget);
      // Hamburger, Documents, Pictures, Settings, Power — the account cell is
      // the one rail entry with nothing to open.
      expect(
        find.descendant(
          of: find.byType(DesktopStartMenuRail),
          matching: find.byType(GestureDetector),
        ),
        findsNWidgets(5),
      );
    });
  });

  group('pinning', () {
    testWidgets('right-clicking an application row offers to pin it', (
      tester,
    ) async {
      await _pumpMenu(tester, apps: <DesktopApp>[_app('Alacritty')]);

      await _secondaryTap(tester, find.text('Alacritty'));

      expect(find.byType(DesktopTileMenu), findsOneWidget);
      expect(find.text('Pin to Start'), findsOneWidget);
      // Sizing a tile belongs to the tile, not to the list row that creates it.
      expect(find.text('Resize'), findsNothing);
    });

    testWidgets('pinning puts a medium tile in the tile area', (tester) async {
      final container = await _pumpMenu(
        tester,
        apps: <DesktopApp>[_app('Alacritty')],
      );

      expect(find.byType(DesktopTileBoardEmptyState), findsOneWidget);

      await _secondaryTap(tester, find.text('Alacritty'));
      await tester.tap(find.text('Pin to Start'));
      await tester.pumpAndSettle();

      final item = container
          .read(desktopTileControllerProvider)
          .requireValue
          .groups
          .single
          .slots[0]!;
      expect(item.id, 'app:alacritty.desktop');
      expect(item.colSpan, 2);
      expect(item.rowSpan, 2);
      expect(find.byType(DesktopTileCell), findsOneWidget);
      // The hint has done its job once a tile exists.
      expect(find.byType(DesktopTileBoardEmptyState), findsNothing);
    });

    testWidgets('an already pinned application offers to unpin instead', (
      tester,
    ) async {
      await _pumpMenu(
        tester,
        apps: <DesktopApp>[_app('Alacritty')],
        board: _boardWith(_app('Alacritty')),
      );

      await _secondaryTap(tester, _appListRow('Alacritty'));

      expect(find.text('Unpin from Start'), findsOneWidget);
      expect(find.text('Pin to Start'), findsNothing);
    });

    testWidgets('unpinning from the list clears the tile area', (tester) async {
      final container = await _pumpMenu(
        tester,
        apps: <DesktopApp>[_app('Alacritty')],
        board: _boardWith(_app('Alacritty')),
      );

      await _secondaryTap(tester, _appListRow('Alacritty'));
      await tester.tap(find.text('Unpin from Start'));
      await tester.pumpAndSettle();

      expect(
        container.read(desktopTileControllerProvider).requireValue.hasTiles,
        isFalse,
      );
      expect(find.byType(DesktopTileBoardEmptyState), findsOneWidget);
    });

    testWidgets('the tile area still keeps its width floor once filled', (
      tester,
    ) async {
      await _pumpMenu(
        tester,
        apps: <DesktopApp>[_app('Alacritty')],
        board: DesktopTileState(
          groups: <DesktopTileGroup>[
            DesktopTileGroup(
              name: 'Create',
              slots: <HomeGridItem?>[
                HomeGridItem.pinnedApp(
                  _app('Alacritty'),
                  colSpan: 4,
                  rowSpan: 2,
                ),
              ],
            ),
          ],
        ),
      );

      expect(tester.getSize(find.byType(DesktopStartMenu)).width, 680);
      expect(
        tester.getSize(find.byType(DesktopStartMenuTileArea)).width,
        greaterThanOrEqualTo(DesktopStartMenuTileArea.minWidth),
      );
      expect(tester.takeException(), isNull);
    });
    testWidgets('the panel holds still while its own context menu is open', (
      tester,
    ) async {
      var enters = 0;
      var exits = 0;
      await _pumpMenu(
        tester,
        apps: <DesktopApp>[_app('Alacritty')],
        onEnter: () => enters += 1,
        onExit: () => exits += 1,
      );

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(
        location: tester.getCenter(find.text('Alacritty')),
      );
      addTearDown(mouse.removePointer);
      await tester.pumpAndSettle();
      expect(enters, greaterThan(0), reason: 'the pointer should be inside');

      final entersBefore = enters;
      await _secondaryTap(tester, find.text('Alacritty'));

      // A menu surface covers the whole scene, so the mouse tracker reports the
      // pointer as having left the panel even though it has not moved. Passing
      // that on would arm the 220ms hover close and take the panel down — with
      // the menu inside it — before anything in the menu could be clicked.
      expect(find.text('Pin to Start'), findsOneWidget);
      expect(exits, 0);
      expect(
        enters,
        greaterThan(entersBefore),
        reason: 'a close already scheduled has to be called off',
      );
    });
  });
}

DesktopTileState _boardWith(DesktopApp app) {
  return DesktopTileState(
    groups: <DesktopTileGroup>[
      DesktopTileGroup(
        name: '',
        slots: <HomeGridItem?>[HomeGridItem.pinnedApp(app)],
      ),
    ],
  );
}

/// The list row for [name], which shares its label with the pinned tile.
Finder _appListRow(String name) {
  return find
      .descendant(
        of: find.byType(DesktopStartMenuAppList),
        matching: find.text(name),
      )
      .first;
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

Future<ProviderContainer> _pumpMenu(
  WidgetTester tester, {
  List<DesktopApp> apps = const <DesktopApp>[],
  VoidCallback? onOpenSettings,
  ValueChanged<DesktopApp>? onLaunch,
  DesktopTileState board = DesktopTileState.empty,
  VoidCallback? onEnter,
  VoidCallback? onExit,
}) async {
  tester.view.physicalSize = _panelSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final searchFocusNode = FocusNode();
  addTearDown(searchFocusNode.dispose);

  final container = ProviderContainer(
    overrides: [
      homeGridControllerProvider.overrideWith(
        () => _StubHomeGridController(apps),
      ),
      localFlutterApplicationsProvider.overrideWithValue(
        const <LocalFlutterApplication>[],
      ),
      shellAccentProvider.overrideWithValue(WallpaperAccent.fallback),
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
          // The pin board's tiles are Draggable, which floats its feedback in an
          // Overlay; the shell has one around the whole scene.
          child: Overlay(
            initialEntries: <OverlayEntry>[
              OverlayEntry(
                builder: (context) => ShellSurfaceHost(
                  child: DesktopStartMenu(
                    searchFocusNode: searchFocusNode,
                    onEnter: onEnter ?? () {},
                    onExit: onExit ?? () {},
                    onClose: () {},
                    onLaunch:
                        onLaunch ??
                        (_) => fail('launched an external application'),
                    onLaunchLocal: (_) => fail('launched a local application'),
                    onOpenSettings: onOpenSettings ?? () {},
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
