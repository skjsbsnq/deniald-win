import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:denial_dart_shell/src/desktop/desktop_taskbar.dart';
import 'package:denial_dart_shell/src/desktop/desktop_taskbar_button.dart';
import 'package:denial_dart_shell/src/desktop/desktop_taskbar_preview.dart';
import 'package:denial_dart_shell/src/desktop/desktop_workspace.dart';
import 'package:denial_dart_shell/src/localization/denial_localizations.dart';
import 'package:denial_dart_shell/src/models/denial_window.dart';
import 'package:denial_dart_shell/src/models/display_layout.dart';
import 'package:denial_dart_shell/src/state/shell_controller.dart';
import 'package:denial_dart_shell/src/state/shell_state.dart';
import 'package:denial_dart_shell/src/wallpaper/state/wallpaper_accent.dart';

DenialWindow _createTestWindow({
  required int objectId,
  required String title,
  required String appId,
  bool isLocalFlutter = false,
  int monitorId = 1,
}) {
  return DenialWindow(
    objectId: objectId,
    objectKind: 'toplevel',
    surfaceId: objectId * 10,
    windowId: objectId * 100,
    textureId: objectId,
    title: title,
    appId: appId,
    width: 800,
    height: 600,
    surfaceX: 0,
    surfaceY: 0,
    surfaceWidth: 800,
    surfaceHeight: 600,
    textureSourceX: 0,
    textureSourceY: 0,
    textureSourceWidth: 800,
    textureSourceHeight: 600,
    geometryX: 100,
    geometryY: 100,
    geometryWidth: 800,
    geometryHeight: 600,
    monitorId: monitorId,
    transform: 0,
    scale120: 120,
    contentKind: isLocalFlutter
        ? DenialWindowContentKind.localFlutter
        : DenialWindowContentKind.surfaceTree,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DesktopTaskbarButton Widget Tests', () {
    testWidgets('renders icon, title, and active indicator for active window', (
      tester,
    ) async {
      var tapped = false;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: DenialLocalizationScope(
              child: Scaffold(
                body: DesktopTaskbarButton(
                  icon: const Icon(Icons.terminal),
                  title: 'Terminal - denial@box',
                  active: true,
                  minimized: false,
                  compact: false,
                  side: SystemBarSide.bottom,
                  accent: const WallpaperAccent(Color(0xff64d8cb)),
                  onTap: () => tapped = true,
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Terminal - denial@box'), findsOneWidget);
      expect(find.byIcon(Icons.terminal), findsOneWidget);

      await tester.tap(find.byType(DesktopTaskbarButton));
      expect(tapped, isTrue);
    });

    testWidgets('compact mode hides title and renders only icon', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: DenialLocalizationScope(
              child: Scaffold(
                body: DesktopTaskbarButton(
                  icon: const Icon(Icons.web),
                  title: 'Web Browser',
                  active: false,
                  minimized: false,
                  compact: true,
                  side: SystemBarSide.bottom,
                  onTap: () {},
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.web), findsOneWidget);
      expect(find.text('Web Browser'), findsNothing);
    });

    testWidgets('minimized window renders dimmed content', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: DenialLocalizationScope(
              child: Scaffold(
                body: DesktopTaskbarButton(
                  icon: const Icon(Icons.folder),
                  title: 'Files',
                  active: false,
                  minimized: true,
                  compact: false,
                  side: SystemBarSide.bottom,
                  onTap: () {},
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Files'), findsOneWidget);
      final opacityFinder = find.descendant(
        of: find.byType(DesktopTaskbarButton),
        matching: find.byType(Opacity),
      );
      expect(opacityFinder, findsWidgets);
      final opacityWidget = tester.widget<Opacity>(opacityFinder.first);
      expect(opacityWidget.opacity, closeTo(0.65, 0.01));
    });

    testWidgets('vertical system bar renders side indicator', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: DenialLocalizationScope(
              child: Scaffold(
                body: DesktopTaskbarButton(
                  icon: const Icon(Icons.settings),
                  title: 'Settings',
                  active: true,
                  minimized: false,
                  compact: true,
                  side: SystemBarSide.left,
                  onTap: () {},
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.settings), findsOneWidget);
    });
  });

  group('DesktopTaskbar Container Integration Tests', () {
    testWidgets('renders empty space when no user windows exist', (
      tester,
    ) async {
      final shellState = ShellState.initial();
      final workspaceState = DesktopWorkspaceState.initial();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            shellControllerProvider.overrideWith(
              () => _MockShellController(shellState),
            ),
            desktopWorkspaceProvider.overrideWith(
              () => _MockDesktopWorkspaceController(workspaceState),
            ),
            wallpaperAccentProvider.overrideWithBuild(
              (ref, controller) => const WallpaperAccent(Color(0xff64d8cb)),
            ),
          ],
          child: const MaterialApp(
            home: DenialLocalizationScope(
              child: Scaffold(body: DesktopTaskbar(side: SystemBarSide.bottom)),
            ),
          ),
        ),
      );

      expect(find.byType(DesktopTaskbarWindowButton), findsNothing);
    });

    testWidgets(
      'renders N buttons for N open user windows and handles activation',
      (tester) async {
        final w1 = _createTestWindow(
          objectId: 1,
          title: 'Foot Terminal',
          appId: 'foot',
        );
        final w2 = _createTestWindow(
          objectId: 2,
          title: 'Nautilus',
          appId: 'org.gnome.Nautilus',
        );
        final w3 = _createTestWindow(
          objectId: 3,
          title: 'Settings',
          appId: 'denial-settings',
          isLocalFlutter: true,
        );

        final shellState = ShellState.initial().copyWith(windows: [w1, w2, w3]);
        final workspaceState = DesktopWorkspaceState(
          placements: {
            1: DesktopWindowPlacement(
              objectId: 1,
              frame: const Rect.fromLTWH(0, 0, 800, 600),
              z: 1,
              monitorId: 1,
            ),
            2: DesktopWindowPlacement(
              objectId: 2,
              frame: const Rect.fromLTWH(50, 50, 800, 600),
              z: 2, // w2 is top active window
              monitorId: 1,
            ),
            3: DesktopWindowPlacement(
              objectId: 3,
              frame: const Rect.fromLTWH(100, 100, 800, 600),
              z: 0,
              minimized: true,
              monitorId: 1,
            ),
          },
          nextZ: 3,
          viewSize: const Size(1920, 1080),
        );

        final mockShell = _MockShellController(shellState);
        final mockWorkspace = _MockDesktopWorkspaceController(workspaceState);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              shellControllerProvider.overrideWith(() => mockShell),
              desktopWorkspaceProvider.overrideWith(() => mockWorkspace),
              wallpaperAccentProvider.overrideWithBuild(
                (ref, controller) => const WallpaperAccent(Color(0xff64d8cb)),
              ),
            ],
            child: const MaterialApp(
              home: DenialLocalizationScope(
                child: Scaffold(
                  body: SizedBox(
                    width: 800,
                    height: 48,
                    child: DesktopTaskbar(side: SystemBarSide.bottom),
                  ),
                ),
              ),
            ),
          ),
        );

        expect(find.byType(DesktopTaskbarWindowButton), findsNWidgets(3));
        expect(find.text('Foot Terminal'), findsOneWidget);
        expect(find.text('Nautilus'), findsOneWidget);
        expect(find.text('Settings'), findsOneWidget);

        // Click Foot Terminal (non-active window with objectId 1)
        await tester.tap(find.text('Foot Terminal'));
        expect(mockWorkspace.activatedId, equals(1));
        expect(mockShell.focusedWindow?.objectId, equals(1));
      },
    );

    testWidgets('filters windows by monitorId when specified', (tester) async {
      final w1 = _createTestWindow(
        objectId: 1,
        title: 'Monitor 1 Window',
        appId: 'app1',
        monitorId: 1,
      );
      final w2 = _createTestWindow(
        objectId: 2,
        title: 'Monitor 2 Window',
        appId: 'app2',
        monitorId: 2,
      );

      final shellState = ShellState.initial().copyWith(windows: [w1, w2]);
      final workspaceState = DesktopWorkspaceState(
        placements: {
          1: DesktopWindowPlacement(
            objectId: 1,
            frame: const Rect.fromLTWH(0, 0, 800, 600),
            z: 1,
            monitorId: 1,
          ),
          2: DesktopWindowPlacement(
            objectId: 2,
            frame: const Rect.fromLTWH(0, 0, 800, 600),
            z: 2,
            monitorId: 2,
          ),
        },
        nextZ: 3,
        viewSize: const Size(1920, 1080),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            shellControllerProvider.overrideWith(
              () => _MockShellController(shellState),
            ),
            desktopWorkspaceProvider.overrideWith(
              () => _MockDesktopWorkspaceController(workspaceState),
            ),
            wallpaperAccentProvider.overrideWithBuild(
              (ref, controller) => const WallpaperAccent(Color(0xff64d8cb)),
            ),
          ],
          child: const MaterialApp(
            home: DenialLocalizationScope(
              child: Scaffold(
                body: DesktopTaskbar(side: SystemBarSide.bottom, monitorId: 1),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Monitor 1 Window'), findsOneWidget);
      expect(find.text('Monitor 2 Window'), findsNothing);
    });

    testWidgets('switches to compact mode when window count exceeds threshold', (
      tester,
    ) async {
      final windows = <DenialWindow>[
        for (int i = 1; i <= 10; i++)
          _createTestWindow(objectId: i, title: 'Window $i', appId: 'app.$i'),
      ];

      final placements = <int, DesktopWindowPlacement>{
        for (int i = 1; i <= 10; i++)
          i: DesktopWindowPlacement(
            objectId: i,
            frame: const Rect.fromLTWH(0, 0, 800, 600),
            z: i,
            monitorId: 1,
          ),
      };

      final shellState = ShellState.initial().copyWith(windows: windows);
      final workspaceState = DesktopWorkspaceState(
        placements: placements,
        nextZ: 11,
        viewSize: const Size(1920, 1080),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            shellControllerProvider.overrideWith(
              () => _MockShellController(shellState),
            ),
            desktopWorkspaceProvider.overrideWith(
              () => _MockDesktopWorkspaceController(workspaceState),
            ),
            wallpaperAccentProvider.overrideWithBuild(
              (ref, controller) => const WallpaperAccent(Color(0xff64d8cb)),
            ),
          ],
          child: const MaterialApp(
            home: DenialLocalizationScope(
              child: Scaffold(
                body: SizedBox(
                  width: 1200,
                  height: 48,
                  child: DesktopTaskbar(
                    side: SystemBarSide.bottom,
                    compactThreshold: 8,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      // In compact mode, all 10 buttons are present but their title texts are omitted
      expect(find.byType(DesktopTaskbarWindowButton), findsNWidgets(10));
      expect(find.text('Window 1'), findsNothing);
    });

    testWidgets(
      'tri-state click: active window minimizes, minimized window activates and focuses',
      (tester) async {
        final w1 = _createTestWindow(
          objectId: 1,
          title: 'Active Window',
          appId: 'app1',
        );
        final w2 = _createTestWindow(
          objectId: 2,
          title: 'Minimized Window',
          appId: 'app2',
        );

        final shellState = ShellState.initial().copyWith(windows: [w1, w2]);
        final workspaceState = DesktopWorkspaceState(
          placements: {
            1: DesktopWindowPlacement(
              objectId: 1,
              frame: const Rect.fromLTWH(0, 0, 800, 600),
              z: 2, // Active window
              minimized: false,
              maximized: true, // Maximized!
              monitorId: 1,
            ),
            2: DesktopWindowPlacement(
              objectId: 2,
              frame: const Rect.fromLTWH(50, 50, 800, 600),
              z: 1,
              minimized: true,
              monitorId: 1,
            ),
          },
          nextZ: 3,
          viewSize: const Size(1920, 1080),
        );

        final mockShell = _MockShellController(shellState);
        final mockWorkspace = _MockDesktopWorkspaceController(workspaceState);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              shellControllerProvider.overrideWith(() => mockShell),
              desktopWorkspaceProvider.overrideWith(() => mockWorkspace),
              wallpaperAccentProvider.overrideWithBuild(
                (ref, controller) => const WallpaperAccent(Color(0xff64d8cb)),
              ),
            ],
            child: const MaterialApp(
              home: DenialLocalizationScope(
                child: Scaffold(
                  body: SizedBox(
                    width: 800,
                    height: 48,
                    child: DesktopTaskbar(side: SystemBarSide.bottom),
                  ),
                ),
              ),
            ),
          ),
        );

        // 1. Click active window button -> triggers minimize
        await tester.tap(find.text('Active Window'));
        expect(mockWorkspace.minimizedId, equals(1));

        // 2. Click minimized window button -> triggers activate and focus
        await tester.tap(find.text('Minimized Window'));
        expect(mockWorkspace.activatedId, equals(2));
        expect(mockShell.focusedWindow?.objectId, equals(2));
      },
    );

    testWidgets('hover triggers preview after delay and cancel on exit', (
      tester,
    ) async {
      final w1 = _createTestWindow(
        objectId: 1,
        title: 'Browser',
        appId: 'browser',
      );

      final shellState = ShellState.initial().copyWith(windows: [w1]);
      final workspaceState = DesktopWorkspaceState(
        placements: {
          1: DesktopWindowPlacement(
            objectId: 1,
            frame: const Rect.fromLTWH(0, 0, 800, 600),
            z: 1,
            monitorId: 1,
          ),
        },
        nextZ: 2,
        viewSize: const Size(1920, 1080),
      );

      final mockShell = _MockShellController(shellState);
      final mockWorkspace = _MockDesktopWorkspaceController(workspaceState);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            shellControllerProvider.overrideWith(() => mockShell),
            desktopWorkspaceProvider.overrideWith(() => mockWorkspace),
            wallpaperAccentProvider.overrideWithBuild(
              (ref, controller) => const WallpaperAccent(Color(0xff64d8cb)),
            ),
          ],
          child: const MaterialApp(
            home: DenialLocalizationScope(
              child: Scaffold(
                body: Stack(
                  children: [
                    SizedBox(
                      width: 800,
                      height: 48,
                      child: DesktopTaskbar(side: SystemBarSide.bottom),
                    ),
                    DesktopTaskbarPreviewLayer(),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      // Initially no preview
      expect(find.byType(DesktopTaskbarPreviewPositionedCard), findsNothing);

      // Mouse enters button
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      await gesture.moveTo(tester.getCenter(find.text('Browser')));
      await tester.pump();

      // Before 350ms: preview not shown yet
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.byType(DesktopTaskbarPreviewPositionedCard), findsNothing);

      // After 350ms: preview appears
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byType(DesktopTaskbarPreviewPositionedCard), findsOneWidget);

      // Mouse leaves button
      await gesture.moveTo(const Offset(500, 500));
      await tester.pump();

      // Before 250ms hide delay: still visible
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(DesktopTaskbarPreviewPositionedCard), findsOneWidget);

      // After 250ms hide delay: preview disappears
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(DesktopTaskbarPreviewPositionedCard), findsNothing);
    });

    testWidgets(
      'clicking preview card restores/activates window and dismisses preview',
      (tester) async {
        final w1 = _createTestWindow(
          objectId: 1,
          title: 'Preview Target',
          appId: 'target',
        );

        final shellState = ShellState.initial().copyWith(windows: [w1]);
        final workspaceState = DesktopWorkspaceState(
          placements: {
            1: DesktopWindowPlacement(
              objectId: 1,
              frame: const Rect.fromLTWH(0, 0, 800, 600),
              z: 1,
              minimized: true,
              monitorId: 1,
            ),
          },
          nextZ: 2,
          viewSize: const Size(1920, 1080),
        );

        final mockShell = _MockShellController(shellState);
        final mockWorkspace = _MockDesktopWorkspaceController(workspaceState);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              shellControllerProvider.overrideWith(() => mockShell),
              desktopWorkspaceProvider.overrideWith(() => mockWorkspace),
              wallpaperAccentProvider.overrideWithBuild(
                (ref, controller) => const WallpaperAccent(Color(0xff64d8cb)),
              ),
            ],
            child: const MaterialApp(
              home: DenialLocalizationScope(
                child: Scaffold(
                  body: Stack(
                    children: [
                      SizedBox(
                        width: 800,
                        height: 48,
                        child: DesktopTaskbar(side: SystemBarSide.bottom),
                      ),
                      DesktopTaskbarPreviewLayer(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );

        // Hover to open preview
        final gesture = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        await gesture.addPointer(location: Offset.zero);
        await gesture.moveTo(tester.getCenter(find.text('Preview Target')));
        await tester.pump(const Duration(milliseconds: 400));
        expect(
          find.byType(DesktopTaskbarPreviewPositionedCard),
          findsOneWidget,
        );

        // Click the preview card
        await tester.tap(find.byType(DesktopTaskbarPreviewPositionedCard));
        await tester.pump();

        expect(mockWorkspace.activatedId, equals(1));
        expect(mockShell.focusedWindow?.objectId, equals(1));
        expect(find.byType(DesktopTaskbarPreviewPositionedCard), findsNothing);
      },
    );

    testWidgets(
      'clicking preview close button closes window and dismisses preview',
      (tester) async {
        final w1 = _createTestWindow(
          objectId: 1,
          title: 'Close Target',
          appId: 'target',
        );

        final shellState = ShellState.initial().copyWith(windows: [w1]);
        final workspaceState = DesktopWorkspaceState(
          placements: {
            1: DesktopWindowPlacement(
              objectId: 1,
              frame: const Rect.fromLTWH(0, 0, 800, 600),
              z: 1,
              monitorId: 1,
            ),
          },
          nextZ: 2,
          viewSize: const Size(1920, 1080),
        );

        final mockShell = _MockShellController(shellState);
        final mockWorkspace = _MockDesktopWorkspaceController(workspaceState);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              shellControllerProvider.overrideWith(() => mockShell),
              desktopWorkspaceProvider.overrideWith(() => mockWorkspace),
              wallpaperAccentProvider.overrideWithBuild(
                (ref, controller) => const WallpaperAccent(Color(0xff64d8cb)),
              ),
            ],
            child: const MaterialApp(
              home: DenialLocalizationScope(
                child: Scaffold(
                  body: Stack(
                    children: [
                      SizedBox(
                        width: 800,
                        height: 48,
                        child: DesktopTaskbar(side: SystemBarSide.bottom),
                      ),
                      DesktopTaskbarPreviewLayer(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );

        // Hover to open preview
        final gesture = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        await gesture.addPointer(location: Offset.zero);
        await gesture.moveTo(tester.getCenter(find.text('Close Target')));
        await tester.pump(const Duration(milliseconds: 400));
        expect(
          find.byType(DesktopTaskbarPreviewPositionedCard),
          findsOneWidget,
        );

        // Click the close button (Icons.close)
        await tester.tap(find.byIcon(Icons.close));
        await tester.pump();

        expect(mockShell.closedWindow?.objectId, equals(1));
        expect(find.byType(DesktopTaskbarPreviewPositionedCard), findsNothing);
      },
    );
  });
}

class _MockShellController extends ShellController {
  _MockShellController(this._initialState);

  final ShellState _initialState;
  DenialWindow? focusedWindow;
  DenialWindow? closedWindow;

  @override
  ShellState build() => _initialState;

  @override
  void focusWindow(DenialWindow window) {
    focusedWindow = window;
  }

  @override
  void closeWindow(DenialWindow window) {
    closedWindow = window;
  }
}

class _MockDesktopWorkspaceController extends DesktopWorkspaceController {
  _MockDesktopWorkspaceController(this._initialState);

  final DesktopWorkspaceState _initialState;
  int? activatedId;
  int? minimizedId;

  @override
  DesktopWorkspaceState build() => _initialState;

  @override
  void activate(int objectId) {
    activatedId = objectId;
  }

  @override
  void minimize(int objectId) {
    minimizedId = objectId;
  }
}
