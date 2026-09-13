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
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// B01: the launcher bubble inflates its subtree offstage during shell idle
// instead of inside the first open's animation frames. The parked subtree
// must stay invisible, non-interactive, unfocusable, and out of the
// semantics tree.
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

Finder _tile(int index) => find.byKey(
  ValueKey<String>('desktop-app-local:${_appId(index)}'),
  skipOffstage: false,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('shelf launcher pre-inflate', () {
    testWidgets(
      'inflates the parked subtree while hidden, inert until first open',
      (tester) async {
        tester.view.physicalSize = const Size(500, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final semantics = tester.ensureSemantics();

        final searchFocusNode = FocusNode(debugLabel: 'search');
        addTearDown(searchFocusNode.dispose);
        LocalFlutterApplication? launched;

        await tester.pumpWidget(
          _launcherScene(
            searchFocusNode,
            visible: false,
            onLaunchLocal: (app) => launched = app,
          ),
        );
        await tester.pump();

        // Before the idle prewarm fires the bubble subtree stays unmounted.
        expect(_tile(0), findsNothing);

        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();

        // Inflated but parked: present for finders that include offstage
        // elements, invisible to hit tests and the semantics tree.
        expect(_tile(0), findsOneWidget);
        expect(
          find.byKey(ValueKey<String>('desktop-app-local:${_appId(0)}')),
          findsNothing,
        );
        final offstage = tester.widget<Offstage>(
          find.descendant(
            of: find.byType(DesktopApplicationLauncher),
            matching: find.byType(Offstage),
            skipOffstage: false,
          ),
        );
        expect(offstage.offstage, isTrue);
        final tickerMode = tester.widget<TickerMode>(
          find.descendant(
            of: find.byType(DesktopApplicationLauncher),
            matching: find.byType(TickerMode),
            skipOffstage: false,
          ),
        );
        expect(tickerMode.enabled, isFalse);

        // The parked subtree must not appear in the a11y tree, steal focus,
        // or answer taps.
        expect(find.bySemanticsLabel('Search applications'), findsNothing);
        expect(searchFocusNode.hasFocus, isFalse);
        searchFocusNode.requestFocus();
        await tester.pump();
        expect(searchFocusNode.hasFocus, isFalse);

        await tester.tapAt(tester.getRect(_tile(0)).center);
        await tester.pump();
        expect(launched, isNull);
        semantics.dispose();
      },
    );

    testWidgets('first open after prewarm unfocuses the focus gate', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(500, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final searchFocusNode = FocusNode(debugLabel: 'search');
      addTearDown(searchFocusNode.dispose);
      LocalFlutterApplication? launched;

      await tester.pumpWidget(
        _launcherScene(
          searchFocusNode,
          visible: false,
          onLaunchLocal: (app) => launched = app,
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(_tile(0), findsOneWidget);

      await tester.pumpWidget(
        _launcherScene(
          searchFocusNode,
          visible: true,
          onLaunchLocal: (app) => launched = app,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(ValueKey<String>('desktop-app-local:${_appId(0)}')),
        findsOneWidget,
      );
      // The explicit focus request used by the shell's open path must land
      // once the gate lifts.
      searchFocusNode.requestFocus();
      await tester.pump();
      expect(searchFocusNode.hasFocus, isTrue);

      await tester.tap(
        find.byKey(ValueKey<String>('desktop-app-local:${_appId(0)}')),
      );
      await tester.pump();
      expect(launched?.id, _appId(0));
    });

    testWidgets('opening before the prewarm fires still shows the bubble', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(500, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final searchFocusNode = FocusNode(debugLabel: 'search');
      addTearDown(searchFocusNode.dispose);

      await tester.pumpWidget(
        _launcherScene(searchFocusNode, visible: false, onLaunchLocal: (_) {}),
      );
      await tester.pump(const Duration(milliseconds: 300));

      await tester.pumpWidget(
        _launcherScene(searchFocusNode, visible: true, onLaunchLocal: (_) {}),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(ValueKey<String>('desktop-app-local:${_appId(0)}')),
        findsOneWidget,
      );
      // pumpAndSettle advanced past the prewarm delay; a leaked timer would
      // fail the test at teardown.
    });

    testWidgets('dispose cancels a pending prewarm', (tester) async {
      tester.view.physicalSize = const Size(500, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final searchFocusNode = FocusNode(debugLabel: 'search');
      addTearDown(searchFocusNode.dispose);

      await tester.pumpWidget(
        _launcherScene(searchFocusNode, visible: false, onLaunchLocal: (_) {}),
      );
      await tester.pump(const Duration(milliseconds: 300));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    });
  });
}

Widget _launcherScene(
  FocusNode searchFocusNode, {
  required bool visible,
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
            width: 500,
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
                visible: visible,
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
