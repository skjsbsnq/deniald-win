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
import 'package:denial_dart_shell/src/theme/tokens.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// MD3E bubble contract (T24): tonal tiles, the borderless-until-focused
// search pill, and the bottom-left anchored open/close motion (spring scale
// + <=24dp anchor slide + fade, honoring reduce-motion).
const int _appCount = 20;

const ShellThemeData _theme = ShellThemeData();

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

Finder _tile(String appId) =>
    find.byKey(ValueKey<String>('desktop-app-local:$appId'));

/// The tile's decorated surface; each tile paints exactly one DecoratedBox.
BoxDecoration _tileDecoration(WidgetTester tester, String appId) {
  final box = tester.widget<DecoratedBox>(
    find.descendant(of: _tile(appId), matching: find.byType(DecoratedBox)),
  );
  return box.decoration as BoxDecoration;
}

/// The search pill's focus-ring overlay: the only DecoratedBox inside the
/// launcher whose decoration has a radius but no fill color.
BoxDecoration _searchRingDecoration(WidgetTester tester) {
  final candidates = find.descendant(
    of: find.byType(DesktopApplicationLauncher),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is DecoratedBox &&
          widget.decoration is BoxDecoration &&
          (widget.decoration as BoxDecoration).color == null &&
          (widget.decoration as BoxDecoration).borderRadius != null,
    ),
  );
  expect(candidates, findsOneWidget);
  return tester.widget<DecoratedBox>(candidates).decoration as BoxDecoration;
}

/// The fade wrapper that rides the expand spring; it is an ancestor of the
/// search field rather than a descendant, so EditableText internals cannot
/// shadow it.
Opacity _bubbleOpacity(WidgetTester tester) {
  final candidates = find.ancestor(
    of: find.byType(EditableText, skipOffstage: false),
    matching: find.byType(Opacity, skipOffstage: false),
  );
  expect(candidates, findsOneWidget);
  return tester.widget<Opacity>(candidates);
}

/// The anchor slide transform: a pure translation (unit scale) inside the
/// launcher while the bubble is mid-flight.
Finder _slideTransform() => find.descendant(
  of: find.byType(DesktopApplicationLauncher),
  matching: find.byWidgetPredicate((widget) {
    if (widget is! Transform) {
      return false;
    }
    if (widget.transform.getMaxScaleOnAxis() != 1.0) {
      return false;
    }
    final translation = widget.transform.getTranslation();
    return translation.x != 0.0 || translation.y != 0.0;
  }),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('tiles are tonal extraLarge surfaces with accent.outline '
      'selection and a hover state layer', (tester) async {
    tester.view.physicalSize = const Size(500, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final searchFocusNode = FocusNode(debugLabel: 'search');
    addTearDown(searchFocusNode.dispose);
    await tester.pumpWidget(_launcherScene(searchFocusNode, visible: true));
    await tester.pumpAndSettle();

    final colors = _theme.colors;
    final baseColor = _theme.cardColor(colors.surfaceContainerHigh);
    final layeredColor = Color.alphaBlend(colors.panelHighlight, baseColor);
    final expectedRadius = _theme.borderRadius(ShellShapeScale.extraLarge);

    // The default selection is the first catalog tile: tonal base plus the
    // selection state layer and the accent.outline ring.
    final selected = _tileDecoration(tester, _appId(0));
    expect(selected.color, layeredColor);
    expect(selected.borderRadius, expectedRadius);
    expect(selected.border?.top.color, _theme.accentPalette.outline);

    // An unselected tile carries only the tonal base until hovered.
    expect(_tileDecoration(tester, _appId(1)).border, isNull);
    expect(_tileDecoration(tester, _appId(1)).color, baseColor);

    final hover = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(hover.removePointer);
    await hover.moveTo(tester.getCenter(_tile(_appId(1))));
    await tester.pump();
    expect(_tileDecoration(tester, _appId(1)).color, layeredColor);

    // Pressing the tile runs the 0.94 spatial spring.
    final press = await tester.startGesture(
      tester.getCenter(_tile(_appId(1))),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(
      find.descendant(
        of: _tile(_appId(1)),
        matching: find.byWidgetPredicate(
          // getMaxScaleOnAxis always reads the z axis (1.0) for
          // Transform.scale; the x component carries the press factor.
          (widget) =>
              widget is Transform && widget.transform.entry(0, 0) < 1.0,
        ),
      ),
      findsOneWidget,
    );
    await press.up();
    await tester.pumpAndSettle();
  });

  testWidgets('search pill keeps a 48dp tonal surface, focuses with a 1.5px '
      'primary ring, and the clear button empties the query', (tester) async {
    tester.view.physicalSize = const Size(500, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final searchFocusNode = FocusNode(debugLabel: 'search');
    addTearDown(searchFocusNode.dispose);
    await tester.pumpWidget(_launcherScene(searchFocusNode, visible: true));
    await tester.pumpAndSettle();

    // 48dp tall pill (spec's launcher-bubble row).
    expect(
      find.descendant(
        of: find.byType(DesktopApplicationLauncher),
        matching: find.byWidgetPredicate(
          (widget) => widget is SizedBox && widget.height == 48,
        ),
      ),
      findsWidgets,
    );

    // Autofocus claims the ring: primary at 1.5px, no idle hairline.
    var ring = _searchRingDecoration(tester);
    expect(ring.border?.top.color, _theme.accentPalette.primary);
    expect(ring.border?.top.width, 1.5);

    // Dropping primary focus leaves the pill on its tonal fill alone; the
    // change applies inside the next frame's build, so the ring's
    // ListenableBuilder rebuild lands one frame later.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.pump();
    ring = _searchRingDecoration(tester);
    expect(ring.border, isNull);

    searchFocusNode.requestFocus();
    await tester.pump();
    await tester.pump();
    ring = _searchRingDecoration(tester);
    expect(ring.border?.top.color, _theme.accentPalette.primary);

    // Typing filters the grid; the clear button restores it.
    await tester.enterText(find.byType(EditableText), 'app05');
    await tester.pump();
    expect(_tile(_appId(5)), findsOneWidget);
    expect(_tile(_appId(4)), findsNothing);
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    expect(_tile(_appId(4)), findsOneWidget);
  });

  testWidgets('the bubble opens with an anchor slide + fade and reduce-motion '
      'jumps straight to the end state', (tester) async {
    tester.view.physicalSize = const Size(500, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final searchFocusNode = FocusNode(debugLabel: 'search');
    addTearDown(searchFocusNode.dispose);

    // Parked first: unmounted until the 1s idle warm-up inflates the subtree.
    final editable = find.byType(EditableText, skipOffstage: false);
    await tester.pumpWidget(_launcherScene(searchFocusNode, visible: false));
    await tester.pump();
    expect(editable, findsNothing);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(editable, findsOneWidget);
    expect(_bubbleOpacity(tester).opacity, 0.0);

    // Open: mid-flight the bubble is partially faded and slid toward its
    // bottom-left anchor; settled it is fully opaque and un-offset.
    await tester.pumpWidget(_launcherScene(searchFocusNode, visible: true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    final midFlight = _bubbleOpacity(tester).opacity;
    expect(midFlight, greaterThan(0.0));
    expect(midFlight, lessThan(1.0));

    final sliding = _slideTransform();
    expect(sliding, findsOneWidget);
    final slide = tester
        .widget<Transform>(sliding)
        .transform
        .getTranslation();
    // Anchor direction: left and down, within the 24dp cap.
    expect(slide.x, lessThan(0.0));
    expect(slide.y, greaterThan(0.0));
    expect(slide.length, lessThanOrEqualTo(24.0));

    await tester.pumpAndSettle();
    // Springs settle inside their simulation tolerance, not on the exact
    // terminal value.
    expect(_bubbleOpacity(tester).opacity, closeTo(1.0, 0.001));
    final settledSlide = _slideTransform();
    if (settledSlide.evaluate().isNotEmpty) {
      expect(
        tester.widget<Transform>(settledSlide).transform.getTranslation().length,
        lessThan(0.5),
      );
    }

    // Reduce motion: the same toggle lands directly on the end state.
    await tester.pumpWidget(
      _launcherScene(searchFocusNode, visible: false, disableAnimations: true),
    );
    await tester.pump();
    await tester.pumpWidget(
      _launcherScene(searchFocusNode, visible: true, disableAnimations: true),
    );
    await tester.pump();
    expect(_bubbleOpacity(tester).opacity, 1.0);
    expect(_slideTransform(), findsNothing);
  });
}

Widget _launcherScene(
  FocusNode searchFocusNode, {
  required bool visible,
  bool disableAnimations = false,
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
        body: MediaQuery(
          data: MediaQueryData(disableAnimations: disableAnimations),
          child: Align(
            alignment: Alignment.bottomLeft,
            child: SizedBox(
              width: 500,
              height: 560,
              child: ShellTheme(
                data: _theme,
                child: DesktopApplicationLauncher(
                  searchFocusNode: searchFocusNode,
                  onEnter: () {},
                  onExit: () {},
                  onDismiss: () {},
                  onLaunch: (_) {},
                  onLaunchLocal: (_) {},
                  visible: visible,
                ),
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
