import 'dart:ui' show PointerDeviceKind, Tristate;

import 'package:denial_dart_shell/l10n/generated/app_localizations.dart';
import 'package:denial_dart_shell/src/desktop/desktop_workspace.dart';
import 'package:denial_dart_shell/src/desktop/shelf/shelf_workspace_button.dart';
import 'package:denial_dart_shell/src/desktop/shelf/shelf_workspace_dots.dart';
import 'package:denial_dart_shell/src/platform/denial_bridge.dart';
import 'package:denial_dart_shell/src/settings/settings_controller.dart';
import 'package:denial_dart_shell/src/settings/shell_settings.dart';
import 'package:denial_dart_shell/src/state/shell_controller.dart';
import 'package:denial_dart_shell/src/theme/shell_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records the workspace switches the dots request.
class _RecordingBridge extends DenialBridge {
  final List<({int monitorId, int workspaceId})> switches =
      <({int monitorId, int workspaceId})>[];

  @override
  void switchWorkspace({required int monitorId, required int workspaceId}) {
    switches.add((monitorId: monitorId, workspaceId: workspaceId));
  }
}

class _WorkspaceSettingsController extends ShellSettingsController {
  _WorkspaceSettingsController({required this.enabled, this.count = 4});

  final bool enabled;
  final int count;

  @override
  ShellSettings build() {
    return ShellSettings(
      layout: ShellLayoutSettings(
        workspacesEnabled: enabled,
        workspaceCount: count,
      ),
    );
  }
}

Finder _dot(int workspaceId) =>
    find.byKey(ValueKey<String>('shelf-workspace-dot-$workspaceId'));

Finder _dotChild(int workspaceId, {required bool colorLayer}) {
  // The dot nests two AnimatedContainers: the outer carries tight size
  // constraints (the 12→32 geometry layer), the inner carries the fill
  // decoration (the color layer). Match on what each animates rather than
  // on child order so the test survives another layer being added.
  return find.descendant(
    of: _dot(workspaceId),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is AnimatedContainer &&
          (colorLayer ? widget.decoration != null : widget.constraints != null),
      description: colorLayer ? 'dot color layer' : 'dot size layer',
    ),
  );
}

Future<ProviderContainer> _pumpButton(
  WidgetTester tester, {
  required _RecordingBridge bridge,
  int? monitorId = 7,
  bool enabled = true,
  int count = 4,
}) async {
  final container = ProviderContainer(
    overrides: [
      denialBridgeProvider.overrideWithValue(bridge),
      shellSettingsProvider.overrideWith(
        () => _WorkspaceSettingsController(enabled: enabled, count: count),
      ),
    ],
  );
  addTearDown(container.dispose);
  container
      .read(desktopWorkspaceProvider.notifier)
      .syncWorkspaceConfiguration(
        enabled: enabled,
        count: count,
        monitorIds: const [7],
      );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: Center(child: ShelfWorkspaceButton(monitorId: monitorId)),
        ),
      ),
    ),
  );
  return container;
}

void main() {
  testWidgets('renders one dot per configured workspace', (tester) async {
    await _pumpButton(tester, bridge: _RecordingBridge(), count: 4);

    for (var id = 1; id <= 4; id++) {
      expect(_dot(id), findsOneWidget);
    }
    expect(_dot(5), findsNothing);
  });

  testWidgets('the active dot is elongated and marked selected', (
    tester,
  ) async {
    final container = await _pumpButton(tester, bridge: _RecordingBridge());
    await tester.pumpAndSettle();

    // Dot 1 is active on a fresh sync: clavis 12→32 elongation.
    expect(
      tester.getSize(_dotChild(1, colorLayer: false)),
      const Size(ShelfWorkspaceDots.activeDotWidth, ShelfWorkspaceDots.dotSize),
    );
    expect(
      tester.getSize(_dotChild(2, colorLayer: false)),
      const Size(ShelfWorkspaceDots.dotSize, ShelfWorkspaceDots.dotSize),
    );
    final selectedNode = tester.getSemantics(
      find.bySemanticsLabel('Workspace 1'),
    );
    expect(
      selectedNode.getSemanticsData().flagsCollection.isSelected,
      Tristate.isTrue,
    );

    // The compositor echo moves the elongation to workspace 3.
    container
        .read(desktopWorkspaceProvider.notifier)
        .applyWorkspaceChanged(7, 3);
    await tester.pumpAndSettle();

    expect(
      tester.getSize(_dotChild(3, colorLayer: false)),
      const Size(ShelfWorkspaceDots.activeDotWidth, ShelfWorkspaceDots.dotSize),
    );
    expect(
      tester.getSize(_dotChild(1, colorLayer: false)),
      const Size(ShelfWorkspaceDots.dotSize, ShelfWorkspaceDots.dotSize),
    );
    final movedNode = tester.getSemantics(find.bySemanticsLabel('Workspace 3'));
    expect(
      movedNode.getSemanticsData().flagsCollection.isSelected,
      Tristate.isTrue,
    );
  });

  testWidgets('tapping a dot requests that exact workspace', (tester) async {
    final bridge = _RecordingBridge();
    await _pumpButton(tester, bridge: bridge);

    await tester.tap(_dot(3));
    await tester.pump();

    expect(bridge.switches, <({int monitorId, int workspaceId})>[
      (monitorId: 7, workspaceId: 3),
    ]);
  });

  testWidgets('an occupied workspace dot paints on-surface', (tester) async {
    const theme = ShellThemeData();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: ShellTheme(
          data: theme,
          child: Scaffold(
            body: Center(
              child: ShelfWorkspaceDots(
                workspaceCount: 4,
                activeWorkspace: 1,
                windowCounts: const [0, 2, 0, 0],
                onSelect: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Color dotColor(int id) {
      final container = tester.widget<AnimatedContainer>(
        _dotChild(id, colorLayer: true),
      );
      return (container.decoration! as BoxDecoration).color!;
    }

    expect(dotColor(1), theme.accentPalette.primary);
    expect(dotColor(2), theme.colors.textPrimary);
    expect(dotColor(3), theme.colors.surfaceContainerHighest);
  });

  testWidgets('hover recolors only empty dots', (tester) async {
    const theme = ShellThemeData();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: ShellTheme(
          data: theme,
          child: Scaffold(
            body: Center(
              child: ShelfWorkspaceDots(
                workspaceCount: 4,
                activeWorkspace: 1,
                windowCounts: const [0, 2, 0, 0],
                onSelect: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Color dotColor(int id) {
      final container = tester.widget<AnimatedContainer>(
        _dotChild(id, colorLayer: true),
      );
      return (container.decoration! as BoxDecoration).color!;
    }

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);

    // Hovering the empty dot 3 swaps it to the hover variant.
    await gesture.addPointer(location: tester.getCenter(_dot(3)));
    await gesture.moveTo(tester.getCenter(_dot(3)));
    await tester.pumpAndSettle();
    expect(
      dotColor(3),
      Color.alphaBlend(
        theme.colors.panelHighlight,
        theme.colors.surfaceContainerHighest,
      ),
    );

    // Hovering the occupied dot 2 keeps its on-surface fill (clavis:
    // `hasWindows ? onSurface : (hovered ? hover : empty)`).
    await gesture.moveTo(tester.getCenter(_dot(2)));
    await tester.pumpAndSettle();
    expect(dotColor(2), theme.colors.textPrimary);
    expect(dotColor(3), theme.colors.surfaceContainerHighest);
  });

  testWidgets('dots snap instantly while animations are disabled', (
    tester,
  ) async {
    Widget build(int activeWorkspace) {
      return MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: ShellTheme(
            data: const ShellThemeData(),
            child: Scaffold(
              body: Center(
                child: ShelfWorkspaceDots(
                  workspaceCount: 4,
                  activeWorkspace: activeWorkspace,
                  windowCounts: const [0, 0, 0, 0],
                  onSelect: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(build(1));
    await tester.pumpWidget(build(3));
    // A single pump lands the new active dot at full width instead of
    // interpolating across the 300ms geometry window.
    await tester.pump();

    expect(
      tester.getSize(_dotChild(3, colorLayer: false)),
      const Size(ShelfWorkspaceDots.activeDotWidth, ShelfWorkspaceDots.dotSize),
    );
  });

  testWidgets('stays hidden without a monitor or while disabled', (
    tester,
  ) async {
    await _pumpButton(tester, bridge: _RecordingBridge(), monitorId: null);
    expect(find.byType(ShelfWorkspaceDots), findsNothing);

    await _pumpButton(tester, bridge: _RecordingBridge(), enabled: false);
    expect(find.byType(ShelfWorkspaceDots), findsNothing);
  });

  group('workspaceWindowCounts', () {
    DesktopWindowPlacement placement(
      int objectId,
      int monitorId,
      int workspaceId, {
      bool minimized = false,
    }) {
      return DesktopWindowPlacement(
        objectId: objectId,
        frame: const Rect.fromLTWH(0, 0, 320, 240),
        z: objectId,
        monitorId: monitorId,
        workspaceId: workspaceId,
        minimized: minimized,
      );
    }

    test('counts only visible windows of the requested monitor', () {
      final counts = workspaceWindowCounts(
        [
          placement(1, 7, 1),
          placement(2, 7, 2),
          placement(3, 7, 2),
          placement(4, 7, 4),
        ],
        7,
        4,
      );

      expect(counts, <int>[1, 2, 0, 1]);
    });

    test('ignores minimized windows and other monitors', () {
      final counts = workspaceWindowCounts(
        [
          placement(1, 7, 2, minimized: true),
          placement(2, 8, 2),
          placement(3, 7, 2),
        ],
        7,
        4,
      );

      expect(counts, <int>[0, 1, 0, 0]);
    });

    test('drops windows outside the configured workspace range', () {
      final counts = workspaceWindowCounts(
        [placement(1, 7, 5), placement(2, 7, -1)],
        7,
        4,
      );

      expect(counts, <int>[0, 0, 0, 0]);
    });
  });
}
