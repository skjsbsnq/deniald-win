import 'package:denial_dart_shell/src/desktop/desktop_start_menu.dart';
import 'package:denial_dart_shell/src/desktop/desktop_start_menu_app_list.dart';
import 'package:denial_dart_shell/src/launcher/controllers/home_grid_controller.dart';
import 'package:denial_dart_shell/src/launcher/models/desktop_app.dart';
import 'package:denial_dart_shell/src/local_apps/local_flutter_application.dart';
import 'package:denial_dart_shell/src/localization/denial_localizations.dart';
import 'package:denial_dart_shell/src/settings/settings_application.dart';
import 'package:denial_dart_shell/src/wallpaper/state/wallpaper_accent.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// The rect DesktopMetrics.launcherRect resolves the start menu to.
const Size _panelSize = Size(680, 620);

void main() {
  testWidgets('the menu includes and launches registered local applications', (
    tester,
  ) async {
    LocalFlutterApplication? launched;
    await _pumpMenu(
      tester,
      localApps: <LocalFlutterApplication>[denialSettingsApplication],
      onLaunchLocal: (app) => launched = app,
    );

    expect(find.text('Settings'), findsWidgets);
    expect(
      find.byKey(const ValueKey<String>('desktop-app-dev.denial.settings')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('desktop-app-dev.denial.settings')),
    );
    expect(launched, same(denialSettingsApplication));
  });

  testWidgets('installed applications are listed, not just tiled ones', (
    tester,
  ) async {
    await _pumpMenu(
      tester,
      apps: <DesktopApp>[_app('Alacritty'), _app('Chromium')],
    );

    expect(find.text('Alacritty'), findsOneWidget);
    expect(find.text('Chromium'), findsOneWidget);
  });

  testWidgets('searching drops the headings and lists matches only', (
    tester,
  ) async {
    await _pumpMenu(
      tester,
      apps: <DesktopApp>[_app('Alacritty'), _app('Chromium')],
    );
    expect(find.text('A'), findsOneWidget);

    await tester.enterText(find.byType(EditableText), 'chro');
    await tester.pumpAndSettle();

    expect(find.text('Chromium'), findsOneWidget);
    expect(find.text('Alacritty'), findsNothing);
    expect(find.text('A'), findsNothing);
    expect(find.text('C'), findsNothing);
  });

  testWidgets('a query that matches nothing shows the empty state', (
    tester,
  ) async {
    await _pumpMenu(tester, apps: <DesktopApp>[_app('Alacritty')]);

    await tester.enterText(find.byType(EditableText), 'nothing matches this');
    await tester.pumpAndSettle();

    expect(find.text('No applications found'), findsOneWidget);
    expect(find.text('Alacritty'), findsNothing);
  });

  testWidgets('submitting a query launches the first match', (tester) async {
    DesktopApp? launched;
    await _pumpMenu(
      tester,
      apps: <DesktopApp>[_app('Alacritty'), _app('Chromium')],
      onLaunch: (app) => launched = app,
    );

    await tester.enterText(find.byType(EditableText), 'chro');
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.search);

    expect(launched?.name, 'Chromium');
  });

  testWidgets('clearing the query restores the grouped list', (tester) async {
    await _pumpMenu(
      tester,
      apps: <DesktopApp>[_app('Alacritty'), _app('Chromium')],
    );

    await tester.enterText(find.byType(EditableText), 'chro');
    await tester.pumpAndSettle();
    expect(find.text('Alacritty'), findsNothing);

    await tester.enterText(find.byType(EditableText), '');
    await tester.pumpAndSettle();

    expect(find.text('Alacritty'), findsOneWidget);
    expect(find.text('A'), findsOneWidget);
    expect(find.text('C'), findsOneWidget);
  });

  testWidgets('the menu reports loading until applications arrive', (
    tester,
  ) async {
    await _pumpMenu(tester);

    expect(find.text('Loading applications…'), findsOneWidget);
    expect(find.byType(DesktopStartMenuAppList), findsNothing);
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

Future<void> _pumpMenu(
  WidgetTester tester, {
  List<DesktopApp> apps = const <DesktopApp>[],
  List<LocalFlutterApplication> localApps = const <LocalFlutterApplication>[],
  ValueChanged<DesktopApp>? onLaunch,
  ValueChanged<LocalFlutterApplication>? onLaunchLocal,
  VoidCallback? onOpenSettings,
  VoidCallback? onClose,
}) async {
  tester.view.physicalSize = _panelSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final searchFocusNode = FocusNode();
  addTearDown(searchFocusNode.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        homeGridControllerProvider.overrideWith(
          () => _StubHomeGridController(apps),
        ),
        localFlutterApplicationsProvider.overrideWithValue(localApps),
        shellAccentProvider.overrideWithValue(WallpaperAccent.fallback),
      ],
      child: DenialLocalizationScope(
        locale: const Locale('en'),
        child: DesktopStartMenu(
          searchFocusNode: searchFocusNode,
          onEnter: () {},
          onExit: () {},
          onClose: onClose ?? () {},
          onLaunch: onLaunch ?? (_) => fail('launched an external application'),
          onLaunchLocal:
              onLaunchLocal ?? (_) => fail('launched a local application'),
          onOpenSettings: onOpenSettings ?? () {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _StubHomeGridController extends HomeGridController {
  _StubHomeGridController(this.apps);

  final List<DesktopApp> apps;

  @override
  Future<HomeGridState> build() async {
    return HomeGridState(slots: const [], desktopApps: apps);
  }
}
