import 'package:denial_dart_shell/l10n/generated/app_localizations.dart';
import 'package:denial_dart_shell/src/desktop/desktop_shell.dart';
import 'package:denial_dart_shell/src/launcher/controllers/application_recents_controller.dart';
import 'package:denial_dart_shell/src/launcher/controllers/home_grid_controller.dart';
import 'package:denial_dart_shell/src/launcher/models/home_grid_item.dart';
import 'package:denial_dart_shell/src/launcher/repositories/application_recents_repository.dart';
import 'package:denial_dart_shell/src/local_apps/local_flutter_application.dart';
import 'package:denial_dart_shell/src/settings/settings_controller.dart';
import 'package:denial_dart_shell/src/settings/shell_settings.dart';
import 'package:denial_dart_shell/src/theme/shell_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// COR-1 (A02) turned out to be a false alarm on this fork: the grid
// delegate's real column formula matches the navigation formula. These tests
// pin that contract so the two can never drift apart again:
//
//   navigation:  _crossAxisCountFor     = ceil(width / (_tileExtent + _tileSpacing))
//   grid:        MaxCrossAxisExtent     = ceil(width / (maxCrossAxisExtent + crossAxisSpacing))
//
// with both parameter pairs set to the same constants (112 + 8).
const int _appCount = 20;

LocalFlutterApplication _app(int index) {
  return LocalFlutterApplication(
    id: 'app${index.toString().padLeft(2, '0')}',
    title: 'app${index.toString().padLeft(2, '0')}',
    categories: const <String>[],
    icon: Icons.ac_unit,
    defaultSize: const Size(400, 300),
    minimumSize: const Size(200, 200),
    builder: (_, _) => const SizedBox.shrink(),
  );
}

String _appId(int index) => 'app${index.toString().padLeft(2, '0')}';

Future<void> _pressKey(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(key);
  await tester.sendKeyUpEvent(key);
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The bubble takes min(view - 16, 600) and its 8px inner padding leaves the
  // catalog grid at min(view - 32, 584) logical pixels. In this harness the
  // launcher fills the given width directly, so these sizes sweep distinct
  // column counts of ceil(width / 120).
  const surfaces = <({double width, int expectedColumns})>[
    (width: 352.0, expectedColumns: 3),
    (width: 500.0, expectedColumns: 5),
    (width: 600.0, expectedColumns: 5),
  ];

  for (final surface in surfaces) {
    testWidgets(
      'keyboard navigation matches the rendered columns at ${surface.width}px',
      (tester) async {
        tester.view.physicalSize = Size(surface.width, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final searchFocusNode = FocusNode(debugLabel: 'search');
        addTearDown(searchFocusNode.dispose);
        LocalFlutterApplication? launched;
        await tester.pumpWidget(
          _launcherScene(
            searchFocusNode,
            surfaceWidth: surface.width,
            onLaunchLocal: (app) => launched = app,
          ),
        );
        await tester.pumpAndSettle();

        // Measure the real column count from the laid-out tiles: every tile
        // sharing the first row's top edge is one column.
        var firstRowTop = 0.0;
        var columns = 0;
        var rows = 1;
        var previousTop = 0.0;
        for (var index = 0; index < _appCount; index += 1) {
          final finder = find.byKey(
            ValueKey<String>('desktop-app-local:${_appId(index)}'),
          );
          if (finder.evaluate().isEmpty) {
            continue; // Tile scrolled off stage; the first rows suffice.
          }
          final rect = tester.getRect(finder);
          if (columns == 0) {
            firstRowTop = rect.top;
            previousTop = rect.top;
          }
          if (rect.top == firstRowTop) {
            columns += 1;
          } else if (rect.top != previousTop) {
            rows += 1;
            previousTop = rect.top;
          }
        }
        // The grid's own formula: ceil(width / (112 + 8)). If this expectation
        // fails, the delegate constants and the navigation constants have
        // drifted apart — check _tileExtent/_tileSpacing usage in
        // desktop_application_launcher.dart.
        expect(columns, surface.expectedColumns);
        expect(rows, greaterThan(1), reason: 'test needs two rows');

        // ArrowDown from the first tile must select the tile directly below
        // it: one rendered row further in the same column. The catalog is
        // sorted by id, so index N sits at row N ~/ columns.
        await _pressKey(tester, LogicalKeyboardKey.arrowDown);
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pump();
        expect(launched?.id, _appId(columns));

        // Reset and ArrowRight to the last column of the first row: the
        // horizontal traversal that a mismatched count used to break.
        for (var index = 0; index < columns; index += 1) {
          await _pressKey(tester, LogicalKeyboardKey.arrowLeft);
        }
        for (var index = 0; index < columns - 1; index += 1) {
          await _pressKey(tester, LogicalKeyboardKey.arrowRight);
        }
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pump();
        expect(launched?.id, _appId(columns - 1));
      },
    );
  }
}

Widget _launcherScene(
  FocusNode searchFocusNode, {
  required double surfaceWidth,
  required ValueChanged<LocalFlutterApplication> onLaunchLocal,
}) {
  return ProviderScope(
    overrides: [
      localFlutterApplicationsProvider.overrideWithValue(
        List<LocalFlutterApplication>.generate(_appCount, _app),
      ),
      shellSettingsProvider.overrideWith(_ShelfSettingsController.new),
      homeGridControllerProvider.overrideWith(_EmptyHomeGridController.new),
      applicationRecentsStoreProvider.overrideWithValue(_EmptyRecentsStore()),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        backgroundColor: const Color(0xff121212),
        body: Center(
          child: SizedBox(
            width: surfaceWidth,
            height: 560,
            child: ShellTheme(
              data: const ShellThemeData(),
              child: DesktopApplicationLauncher(
                searchFocusNode: searchFocusNode,
                onEnter: () {},
                onExit: () {},
                onDismiss: () {},
                onLaunch: (_) {},
                onLaunchLocal: onLaunchLocal,
                visible: true,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _ShelfSettingsController extends ShellSettingsController {
  @override
  ShellSettings build() {
    return const ShellSettings(
      layout: ShellLayoutSettings(useChromeOsShelf: true),
    );
  }
}

/// Keeps the catalog deterministic: no desktop entries from the host file
/// system and no persisted recents, so the launcher lists only the local test
/// applications in id order.
class _EmptyHomeGridController extends HomeGridController {
  @override
  Future<HomeGridState> build() async {
    return HomeGridState(slots: const <HomeGridItem?>[]);
  }
}

class _EmptyRecentsStore implements ApplicationRecentsStore {
  @override
  Future<List<String>> readEntries() async => const <String>[];

  @override
  Future<void> saveEntries(List<String> entries) async {}
}
