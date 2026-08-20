import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:denial_dart_shell/src/desktop/desktop_window_menu.dart';
import 'package:denial_dart_shell/src/desktop/desktop_window_titlebar.dart';
import 'package:denial_dart_shell/src/desktop/desktop_workspace.dart';
import 'package:denial_dart_shell/src/input/shell_interaction_registry.dart';
import 'package:denial_dart_shell/src/localization/denial_localizations.dart';
import 'package:denial_dart_shell/src/models/denial_window.dart';
import 'package:denial_dart_shell/src/theme/shell_theme.dart';
import 'package:denial_dart_shell/src/theme/tokens.dart';
import 'package:denial_dart_shell/src/wallpaper/state/wallpaper_accent.dart';
import 'package:denial_dart_shell/src/widgets/shell_surface_host.dart';

DenialWindow _testWindow({
  int objectId = 1,
  String title = 'Test Application',
  String appId = 'test.app',
  bool serverSideDecorated = true,
  DenialWindowContentKind contentKind = DenialWindowContentKind.surfaceTree,
}) {
  return DenialWindow(
    objectId: objectId,
    objectKind: 'toplevel',
    surfaceId: 10,
    windowId: 100,
    textureId: 1,
    title: title,
    appId: appId,
    width: 640,
    height: 480,
    surfaceX: 0,
    surfaceY: 0,
    surfaceWidth: 640,
    surfaceHeight: 480,
    textureSourceX: 0,
    textureSourceY: 0,
    textureSourceWidth: 640,
    textureSourceHeight: 480,
    geometryX: 100,
    geometryY: 100,
    geometryWidth: 640,
    geometryHeight: 480,
    monitorId: 1,
    transform: 0,
    scale120: 120,
    serverSideDecorated: serverSideDecorated,
    contentKind: contentKind,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DesktopTitlebarMetrics and Geometry Insets', () {
    test('contentRect and initial frame expansion are strictly inverse', () {
      const originalFrame = Rect.fromLTWH(150, 120, 800, 600);
      const placement = DesktopWindowPlacement(
        objectId: 1,
        z: 0,
        monitorId: 1,
        frame: originalFrame,
        serverSideDecorated: true,
      );

      expect(placement.decorated, isTrue);
      expect(placement.frameBorder, DesktopMetrics.frameBorder);
      expect(placement.titlebarHeight, DesktopTitlebarMetrics.height);
      expect(
        placement.frameInsets,
        const EdgeInsets.fromLTRB(
          DesktopMetrics.frameBorder,
          DesktopMetrics.frameBorder + DesktopTitlebarMetrics.height,
          DesktopMetrics.frameBorder,
          DesktopMetrics.frameBorder,
        ),
      );

      final content = placement.contentRect;
      expect(content.left, originalFrame.left + DesktopMetrics.frameBorder);
      expect(
        content.top,
        originalFrame.top +
            DesktopMetrics.frameBorder +
            DesktopTitlebarMetrics.height,
      );
      expect(content.right, originalFrame.right - DesktopMetrics.frameBorder);
      expect(content.bottom, originalFrame.bottom - DesktopMetrics.frameBorder);
      expect(
        content.width,
        originalFrame.width - (DesktopMetrics.frameBorder * 2),
      );
      expect(
        content.height,
        originalFrame.height -
            (DesktopMetrics.frameBorder * 2 + DesktopTitlebarMetrics.height),
      );

      final reconstructedFrame = Rect.fromLTRB(
        content.left - DesktopMetrics.frameBorder,
        content.top -
            DesktopMetrics.frameBorder -
            DesktopTitlebarMetrics.height,
        content.right + DesktopMetrics.frameBorder,
        content.bottom + DesktopMetrics.frameBorder,
      );

      expect(reconstructedFrame.left, originalFrame.left);
      expect(reconstructedFrame.top, originalFrame.top);
      expect(reconstructedFrame.width, originalFrame.width);
      expect(reconstructedFrame.height, originalFrame.height);
      expect(reconstructedFrame, originalFrame);
    });

    test(
      'fullscreen window has zero titlebar height, zero insets and matches contentRect',
      () {
        const frame = Rect.fromLTWH(0, 0, 1920, 1080);
        const placement = DesktopWindowPlacement(
          objectId: 1,
          z: 0,
          monitorId: 1,
          frame: frame,
          serverSideDecorated: true,
          fullscreen: true,
        );

        expect(placement.decorated, isFalse);
        expect(placement.titlebarHeight, 0.0);
        expect(placement.frameBorder, 0.0);
        expect(placement.frameInsets, EdgeInsets.zero);
        expect(placement.contentRect, frame);
      },
    );

    test(
      'undecorated window has zero titlebar height and symmetric frameBorder insets',
      () {
        const frame = Rect.fromLTWH(50, 50, 400, 300);
        const placement = DesktopWindowPlacement(
          objectId: 1,
          z: 0,
          monitorId: 1,
          frame: frame,
          serverSideDecorated: false,
        );

        expect(placement.decorated, isFalse);
        expect(placement.titlebarHeight, 0.0);
        expect(placement.frameBorder, 0.0);
        expect(placement.frameInsets, EdgeInsets.zero);
        expect(placement.contentRect, frame);
      },
    );
  });

  group('DesktopWindowTitlebar Widget', () {
    testWidgets('renders window title and publishes no ShellInputRegion', (
      tester,
    ) async {
      final window = _testWindow(title: 'Terminal - bash');

      await tester.pumpWidget(
        ProviderScope(
          child: DenialLocalizationScope(
            locale: const Locale('en'),
            child: ShellTheme(
              data: const ShellThemeData(),
              child: SizedBox(
                width: 500,
                height: DesktopTitlebarMetrics.height,
                child: DesktopWindowTitlebar(
                  window: window,
                  active: true,
                  maximized: false,
                  onActivate: () {},
                  onBeginMove: () {},
                  onMoveBy: (_) {},
                  onEndMove: () {},
                  onBeginMaximizedDrag:
                      ({
                        required pointerFractionX,
                        required pointerOffsetY,
                        required pointerPosition,
                      }) {},
                  onMinimize: () {},
                  onToggleMaximize: () {},
                  onClose: () {},
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Terminal - bash'), findsOneWidget);
      // A ShellInputRegion measures itself from paint. Moving a window only
      // re-offsets its cached repaint-boundary layer, so the region would keep
      // publishing the window's previous position and swallow clicks there.
      // The titlebar's hit region comes from the placement geometry instead;
      // see DesktopInputLayoutPublisher.
      expect(find.byType(ShellInputRegion), findsNothing);
    });

    testWidgets('renders three titlebar buttons and invokes callbacks on tap', (
      tester,
    ) async {
      final window = _testWindow(title: 'App');
      int minimizeCount = 0;
      int toggleMaximizeCount = 0;
      int closeCount = 0;

      await tester.pumpWidget(
        ProviderScope(
          child: DenialLocalizationScope(
            locale: const Locale('en'),
            child: ShellTheme(
              data: const ShellThemeData(),
              child: SizedBox(
                width: 500,
                height: DesktopTitlebarMetrics.height,
                child: DesktopWindowTitlebar(
                  window: window,
                  active: true,
                  maximized: false,
                  onActivate: () {},
                  onBeginMove: () {},
                  onMoveBy: (_) {},
                  onEndMove: () {},
                  onBeginMaximizedDrag:
                      ({
                        required pointerFractionX,
                        required pointerOffsetY,
                        required pointerPosition,
                      }) {},
                  onMinimize: () => minimizeCount++,
                  onToggleMaximize: () => toggleMaximizeCount++,
                  onClose: () => closeCount++,
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.bySemanticsLabel('Minimize'), findsOneWidget);
      expect(find.bySemanticsLabel('Maximize'), findsOneWidget);
      expect(find.bySemanticsLabel('Close'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Minimize'));
      await tester.pump();
      expect(minimizeCount, 1);

      await tester.tap(find.bySemanticsLabel('Maximize'));
      await tester.pump();
      expect(toggleMaximizeCount, 1);

      await tester.tap(find.bySemanticsLabel('Close'));
      await tester.pump();
      expect(closeCount, 1);
    });

    testWidgets('switches maximize button semantic label when maximized', (
      tester,
    ) async {
      final window = _testWindow(title: 'App');

      await tester.pumpWidget(
        ProviderScope(
          child: DenialLocalizationScope(
            locale: const Locale('en'),
            child: ShellTheme(
              data: const ShellThemeData(),
              child: SizedBox(
                width: 500,
                height: DesktopTitlebarMetrics.height,
                child: DesktopWindowTitlebar(
                  window: window,
                  active: true,
                  maximized: true,
                  onActivate: () {},
                  onBeginMove: () {},
                  onMoveBy: (_) {},
                  onEndMove: () {},
                  onBeginMaximizedDrag:
                      ({
                        required pointerFractionX,
                        required pointerOffsetY,
                        required pointerPosition,
                      }) {},
                  onMinimize: () {},
                  onToggleMaximize: () {},
                  onClose: () {},
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.bySemanticsLabel('Restore down'), findsOneWidget);
      expect(find.bySemanticsLabel('Maximize'), findsNothing);
    });

    testWidgets(
      'dragging titlebar triggers activate, beginMove, moveBy, and endMove',
      (tester) async {
        final window = _testWindow(title: 'App');
        int activateCount = 0;
        int beginMoveCount = 0;
        final movedDeltas = <Offset>[];
        int endMoveCount = 0;

        await tester.pumpWidget(
          ProviderScope(
            child: DenialLocalizationScope(
              locale: const Locale('en'),
              child: ShellTheme(
                data: const ShellThemeData(),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 500,
                    height: DesktopTitlebarMetrics.height,
                    child: DesktopWindowTitlebar(
                      window: window,
                      active: false,
                      maximized: false,
                      onActivate: () => activateCount++,
                      onBeginMove: () => beginMoveCount++,
                      onMoveBy: (delta) => movedDeltas.add(delta),
                      onEndMove: () => endMoveCount++,
                      onBeginMaximizedDrag:
                          ({
                            required pointerFractionX,
                            required pointerOffsetY,
                            required pointerPosition,
                          }) {},
                      onMinimize: () {},
                      onToggleMaximize: () {},
                      onClose: () {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        // Drag across title area (from x=100 to x=250)
        final gesture = await tester.startGesture(const Offset(100, 15));
        expect(activateCount, 1);
        expect(beginMoveCount, 0);

        // Small jitter below 3.0 slop threshold should not begin move
        await gesture.moveBy(const Offset(1, 0));
        expect(beginMoveCount, 0);

        // Larger movement triggers beginMove and moveBy
        await gesture.moveBy(const Offset(10, 5));
        expect(beginMoveCount, 1);
        expect(movedDeltas, isNotEmpty);

        await gesture.moveBy(const Offset(20, 10));
        expect(movedDeltas.length, 2);

        await gesture.up();
        expect(endMoveCount, 1);
      },
    );

    testWidgets('pointer cancel triggers endMove cleanly', (tester) async {
      final window = _testWindow(title: 'App');
      int endMoveCount = 0;

      await tester.pumpWidget(
        ProviderScope(
          child: DenialLocalizationScope(
            locale: const Locale('en'),
            child: ShellTheme(
              data: const ShellThemeData(),
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 500,
                  height: DesktopTitlebarMetrics.height,
                  child: DesktopWindowTitlebar(
                    window: window,
                    active: true,
                    maximized: false,
                    onActivate: () {},
                    onBeginMove: () {},
                    onMoveBy: (_) {},
                    onEndMove: () => endMoveCount++,
                    onBeginMaximizedDrag:
                        ({
                          required pointerFractionX,
                          required pointerOffsetY,
                          required pointerPosition,
                        }) {},
                    onMinimize: () {},
                    onToggleMaximize: () {},
                    onClose: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      final gesture = await tester.startGesture(const Offset(100, 15));
      await gesture.moveBy(const Offset(15, 10));
      await gesture.cancel();
      expect(endMoveCount, 1);
    });

    testWidgets('dragging on buttons does NOT trigger window move', (
      tester,
    ) async {
      final window = _testWindow(title: 'App');
      int beginMoveCount = 0;
      int moveByCount = 0;
      int endMoveCount = 0;

      await tester.pumpWidget(
        ProviderScope(
          child: DenialLocalizationScope(
            locale: const Locale('en'),
            child: ShellTheme(
              data: const ShellThemeData(),
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 500,
                  height: DesktopTitlebarMetrics.height,
                  child: DesktopWindowTitlebar(
                    window: window,
                    active: true,
                    maximized: false,
                    onActivate: () {},
                    onBeginMove: () => beginMoveCount++,
                    onMoveBy: (_) => moveByCount++,
                    onEndMove: () => endMoveCount++,
                    onBeginMaximizedDrag:
                        ({
                          required pointerFractionX,
                          required pointerOffsetY,
                          required pointerPosition,
                        }) {},
                    onMinimize: () {},
                    onToggleMaximize: () {},
                    onClose: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      // Close button is located on the right edge (x ~ 475, y ~ 17)
      final closeButtonFinder = find.bySemanticsLabel('Close');
      final closeCenter = tester.getCenter(closeButtonFinder);

      final gesture = await tester.startGesture(closeCenter);
      await gesture.moveBy(const Offset(10, 5));
      await gesture.up();

      expect(beginMoveCount, 0);
      expect(moveByCount, 0);
      expect(endMoveCount, 0);
    });

    testWidgets('double-clicking titlebar triggers onToggleMaximize', (
      tester,
    ) async {
      final window = _testWindow(title: 'App');
      int toggleMaximizeCount = 0;

      await tester.pumpWidget(
        ProviderScope(
          child: DenialLocalizationScope(
            locale: const Locale('en'),
            child: ShellTheme(
              data: const ShellThemeData(),
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 500,
                  height: DesktopTitlebarMetrics.height,
                  child: DesktopWindowTitlebar(
                    window: window,
                    active: true,
                    maximized: false,
                    onActivate: () {},
                    onBeginMove: () {},
                    onMoveBy: (_) {},
                    onEndMove: () {},
                    onBeginMaximizedDrag:
                        ({
                          required pointerFractionX,
                          required pointerOffsetY,
                          required pointerPosition,
                        }) {},
                    onMinimize: () {},
                    onToggleMaximize: () => toggleMaximizeCount++,
                    onClose: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tapAt(const Offset(100, 15));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(const Offset(100, 15));
      await tester.pumpAndSettle();

      expect(toggleMaximizeCount, 1);
    });

    testWidgets('dragging maximized window triggers onBeginMaximizedDrag', (
      tester,
    ) async {
      final window = _testWindow(title: 'App');
      bool dragMaximizedCalled = false;
      double? capturedFractionX;

      await tester.pumpWidget(
        ProviderScope(
          child: DenialLocalizationScope(
            locale: const Locale('en'),
            child: ShellTheme(
              data: const ShellThemeData(),
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 500,
                  height: DesktopTitlebarMetrics.height,
                  child: DesktopWindowTitlebar(
                    window: window,
                    active: true,
                    maximized: true,
                    onActivate: () {},
                    onBeginMove: () {},
                    onMoveBy: (_) {},
                    onEndMove: () {},
                    onBeginMaximizedDrag:
                        ({
                          required pointerFractionX,
                          required pointerOffsetY,
                          required pointerPosition,
                        }) {
                          dragMaximizedCalled = true;
                          capturedFractionX = pointerFractionX;
                        },
                    onMinimize: () {},
                    onToggleMaximize: () {},
                    onClose: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      final gesture = await tester.startGesture(const Offset(250, 15));
      await gesture.moveBy(const Offset(10, 10));
      await gesture.up();

      expect(dragMaximizedCalled, isTrue);
      expect(capturedFractionX, isNotNull);
      expect(capturedFractionX!, closeTo(0.5, 0.2));
    });

    testWidgets('right-clicking titlebar opens window context menu', (
      tester,
    ) async {
      final window = _testWindow(title: 'App');
      int minimizeCount = 0;
      int toggleMaximizeCount = 0;
      int closeCount = 0;

      await tester.pumpWidget(
        ProviderScope(
          child: DenialLocalizationScope(
            locale: const Locale('en'),
            child: ShellTheme(
              data: const ShellThemeData(),
              child: ShellSurfaceHost(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 500,
                    height: DesktopTitlebarMetrics.height,
                    child: DesktopWindowTitlebar(
                      window: window,
                      active: true,
                      maximized: false,
                      onActivate: () {},
                      onBeginMove: () {},
                      onMoveBy: (_) {},
                      onEndMove: () {},
                      onBeginMaximizedDrag:
                          ({
                            required pointerFractionX,
                            required pointerOffsetY,
                            required pointerPosition,
                          }) {},
                      onMinimize: () => minimizeCount++,
                      onToggleMaximize: () => toggleMaximizeCount++,
                      onClose: () => closeCount++,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      // Secondary click on titlebar
      final gesture = await tester.startGesture(
        const Offset(120, 15),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.byType(DesktopWindowMenu), findsOneWidget);
      expect(find.text('Minimize'), findsOneWidget);
      expect(find.text('Maximize'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);

      // Tap Close item in menu
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(closeCount, 1);
      expect(find.byType(DesktopWindowMenu), findsNothing);
    });

    testWidgets('DesktopWindowMenu respects disabled conditions', (
      tester,
    ) async {
      final window = _testWindow(title: 'App');
      int minimizeCount = 0;
      int toggleMaximizeCount = 0;

      await tester.pumpWidget(
        ProviderScope(
          child: DenialLocalizationScope(
            locale: const Locale('en'),
            child: ShellTheme(
              data: const ShellThemeData(),
              child: ShellSurfaceHost(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 500,
                    height: DesktopTitlebarMetrics.height,
                    child: DesktopWindowTitlebar(
                      window: window,
                      active: true,
                      maximized: false,
                      fullscreen: true, // disables maximize
                      overviewActive: true, // disables minimize
                      onActivate: () {},
                      onBeginMove: () {},
                      onMoveBy: (_) {},
                      onEndMove: () {},
                      onBeginMaximizedDrag:
                          ({
                            required pointerFractionX,
                            required pointerOffsetY,
                            required pointerPosition,
                          }) {},
                      onMinimize: () => minimizeCount++,
                      onToggleMaximize: () => toggleMaximizeCount++,
                      onClose: () {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      final gesture = await tester.startGesture(
        const Offset(120, 15),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.byType(DesktopWindowMenu), findsOneWidget);

      // Tapping disabled Minimize should NOT invoke callback
      await tester.tap(find.text('Minimize'));
      await tester.pump();
      expect(minimizeCount, 0);

      // Tapping disabled Maximize should NOT invoke callback
      await tester.tap(find.text('Maximize'));
      await tester.pump();
      expect(toggleMaximizeCount, 0);
    });

    testWidgets('DesktopWindowMenu keyboard navigation activates items', (
      tester,
    ) async {
      final window = _testWindow(title: 'App');
      int minimizeCount = 0;

      await tester.pumpWidget(
        ProviderScope(
          child: DenialLocalizationScope(
            locale: const Locale('en'),
            child: ShellTheme(
              data: const ShellThemeData(),
              child: ShellSurfaceHost(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 500,
                    height: DesktopTitlebarMetrics.height,
                    child: DesktopWindowTitlebar(
                      window: window,
                      active: true,
                      maximized: false,
                      onActivate: () {},
                      onBeginMove: () {},
                      onMoveBy: (_) {},
                      onEndMove: () {},
                      onBeginMaximizedDrag:
                          ({
                            required pointerFractionX,
                            required pointerOffsetY,
                            required pointerPosition,
                          }) {},
                      onMinimize: () => minimizeCount++,
                      onToggleMaximize: () {},
                      onClose: () {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      final gesture = await tester.startGesture(
        const Offset(120, 15),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.byType(DesktopWindowMenu), findsOneWidget);

      // Press Enter on the first autofocused item (Minimize)
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(minimizeCount, 1);
      expect(find.byType(DesktopWindowMenu), findsNothing);
    });

    testWidgets('distinguishes active and inactive visual appearance', (
      tester,
    ) async {
      final window = _testWindow(title: 'Editor');

      await tester.pumpWidget(
        ProviderScope(
          child: DenialLocalizationScope(
            locale: const Locale('en'),
            child: ShellTheme(
              data: const ShellThemeData(),
              child: SizedBox(
                width: 500,
                height: DesktopTitlebarMetrics.height,
                child: DesktopWindowTitlebar(
                  window: window,
                  active: false,
                  maximized: false,
                  onActivate: () {},
                  onBeginMove: () {},
                  onMoveBy: (_) {},
                  onEndMove: () {},
                  onBeginMaximizedDrag:
                      ({
                        required pointerFractionX,
                        required pointerOffsetY,
                        required pointerPosition,
                      }) {},
                  onMinimize: () {},
                  onToggleMaximize: () {},
                  onClose: () {},
                ),
              ),
            ),
          ),
        ),
      );

      final inactiveText = tester.widget<Text>(find.text('Editor'));
      expect(inactiveText.style?.color, ShellColors.textTertiary);

      await tester.pumpWidget(
        ProviderScope(
          child: DenialLocalizationScope(
            locale: const Locale('en'),
            child: ShellTheme(
              data: const ShellThemeData(),
              child: SizedBox(
                width: 500,
                height: DesktopTitlebarMetrics.height,
                child: DesktopWindowTitlebar(
                  window: window,
                  active: true,
                  maximized: false,
                  onActivate: () {},
                  onBeginMove: () {},
                  onMoveBy: (_) {},
                  onEndMove: () {},
                  onBeginMaximizedDrag:
                      ({
                        required pointerFractionX,
                        required pointerOffsetY,
                        required pointerPosition,
                      }) {},
                  onMinimize: () {},
                  onToggleMaximize: () {},
                  onClose: () {},
                ),
              ),
            ),
          ),
        ),
      );

      final activeText = tester.widget<Text>(find.text('Editor'));
      expect(activeText.style?.color, ShellColors.textPrimary);
    });

    testWidgets('renders active titlebar with wallpaper accent background', (
      tester,
    ) async {
      final window = _testWindow(title: 'Wallpaper Themed App');
      const testAccentColor = Color(0xFF00E5FF);
      final customAccent = const WallpaperAccent(testAccentColor);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [shellAccentProvider.overrideWithValue(customAccent)],
          child: DenialLocalizationScope(
            locale: const Locale('en'),
            child: ShellTheme(
              data: const ShellThemeData(),
              child: SizedBox(
                width: 500,
                height: DesktopTitlebarMetrics.height,
                child: DesktopWindowTitlebar(
                  window: window,
                  active: true,
                  maximized: false,
                  onActivate: () {},
                  onBeginMove: () {},
                  onMoveBy: (_) {},
                  onEndMove: () {},
                  onBeginMaximizedDrag:
                      ({
                        required pointerFractionX,
                        required pointerOffsetY,
                        required pointerPosition,
                      }) {},
                  onMinimize: () {},
                  onToggleMaximize: () {},
                  onClose: () {},
                ),
              ),
            ),
          ),
        ),
      );

      final decoratedBoxFinder = find.descendant(
        of: find.byType(DesktopWindowTitlebar),
        matching: find.byType(DecoratedBox),
      );
      final topDecoratedBox = tester.widget<DecoratedBox>(
        decoratedBoxFinder.first,
      );
      final boxDecoration = topDecoratedBox.decoration as BoxDecoration;
      expect(boxDecoration.color, customAccent.cardFill);
    });

    testWidgets('renders titlebar buttons inside isolated RepaintBoundary', (
      tester,
    ) async {
      final window = _testWindow(title: 'Repaint Isolation App');

      await tester.pumpWidget(
        ProviderScope(
          child: DenialLocalizationScope(
            locale: const Locale('en'),
            child: ShellTheme(
              data: const ShellThemeData(),
              child: SizedBox(
                width: 500,
                height: DesktopTitlebarMetrics.height,
                child: DesktopWindowTitlebar(
                  window: window,
                  active: true,
                  maximized: false,
                  onActivate: () {},
                  onBeginMove: () {},
                  onMoveBy: (_) {},
                  onEndMove: () {},
                  onBeginMaximizedDrag:
                      ({
                        required pointerFractionX,
                        required pointerOffsetY,
                        required pointerPosition,
                      }) {},
                  onMinimize: () {},
                  onToggleMaximize: () {},
                  onClose: () {},
                ),
              ),
            ),
          ),
        ),
      );

      // All three buttons must be inside RepaintBoundary widgets
      for (final buttonLabel in ['Minimize', 'Maximize', 'Close']) {
        final btn = find.bySemanticsLabel(buttonLabel);
        expect(btn, findsOneWidget);
        final parentBoundary = find.ancestor(
          of: btn,
          matching: find.byType(RepaintBoundary),
        );
        expect(parentBoundary, findsAtLeastNWidgets(1));
      }
    });

    testWidgets('inactive window dims titlebar icon opacity', (tester) async {
      final window = _testWindow(title: 'App With Inactive Icon');

      await tester.pumpWidget(
        ProviderScope(
          child: DenialLocalizationScope(
            locale: const Locale('en'),
            child: ShellTheme(
              data: const ShellThemeData(),
              child: SizedBox(
                width: 500,
                height: DesktopTitlebarMetrics.height,
                child: DesktopWindowTitlebar(
                  window: window,
                  active: false,
                  maximized: false,
                  onActivate: () {},
                  onBeginMove: () {},
                  onMoveBy: (_) {},
                  onEndMove: () {},
                  onBeginMaximizedDrag:
                      ({
                        required pointerFractionX,
                        required pointerOffsetY,
                        required pointerPosition,
                      }) {},
                  onMinimize: () {},
                  onToggleMaximize: () {},
                  onClose: () {},
                ),
              ),
            ),
          ),
        ),
      );

      final opacityFinder = find.descendant(
        of: find.byType(DesktopWindowTitlebar),
        matching: find.byType(Opacity),
      );
      expect(opacityFinder, findsOneWidget);
      final opacityWidget = tester.widget<Opacity>(opacityFinder);
      expect(opacityWidget.opacity, 0.65);
    });

    test('TitlebarGlyphPainter shouldRepaint and custom paint logic', () {
      const painter1 = TitlebarGlyphPainter(
        type: TitlebarButtonType.minimize,
        maximized: false,
        color: Color(0xFFFFFFFF),
      );
      const painterSame = TitlebarGlyphPainter(
        type: TitlebarButtonType.minimize,
        maximized: false,
        color: Color(0xFFFFFFFF),
      );
      const painterDiffType = TitlebarGlyphPainter(
        type: TitlebarButtonType.maximize,
        maximized: false,
        color: Color(0xFFFFFFFF),
      );
      const painterDiffMax = TitlebarGlyphPainter(
        type: TitlebarButtonType.maximize,
        maximized: true,
        color: Color(0xFFFFFFFF),
      );
      const painterDiffColor = TitlebarGlyphPainter(
        type: TitlebarButtonType.minimize,
        maximized: false,
        color: Color(0xFFC42B1C),
      );

      expect(painter1.shouldRepaint(painterSame), isFalse);
      expect(painter1.shouldRepaint(painterDiffType), isTrue);
      expect(painterDiffType.shouldRepaint(painterDiffMax), isTrue);
      expect(painter1.shouldRepaint(painterDiffColor), isTrue);
    });
  });
}
