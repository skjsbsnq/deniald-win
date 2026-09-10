import 'package:denial_dart_shell/l10n/generated/app_localizations.dart';
import 'package:denial_dart_shell/src/desktop/desktop_shell.dart';
import 'package:denial_dart_shell/src/desktop/desktop_workspace.dart';
import 'package:denial_dart_shell/src/desktop/shelf/shelf_workspace_button.dart';
import 'package:denial_dart_shell/src/platform/denial_bridge.dart';
import 'package:denial_dart_shell/src/settings/settings_controller.dart';
import 'package:denial_dart_shell/src/settings/shell_settings.dart';
import 'package:denial_dart_shell/src/state/shell_controller.dart';
import 'package:denial_dart_shell/src/widgets/desktop_window_reveal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records the workspace switches the Desk button requests.
class _RecordingBridge extends DenialBridge {
  final List<({int monitorId, int workspaceId})> switches =
      <({int monitorId, int workspaceId})>[];

  @override
  void switchWorkspace({required int monitorId, required int workspaceId}) {
    switches.add((monitorId: monitorId, workspaceId: workspaceId));
  }
}

class _WorkspaceSettingsController extends ShellSettingsController {
  _WorkspaceSettingsController({required this.enabled});

  final bool enabled;

  @override
  ShellSettings build() {
    return ShellSettings(
      layout: ShellLayoutSettings(
        workspacesEnabled: enabled,
        workspaceCount: 4,
      ),
    );
  }
}

void main() {
  const placement = DesktopWindowPlacement(
    objectId: 1,
    frame: Rect.fromLTWH(0, 0, 320, 240),
    z: 1,
    monitorId: 7,
    workspaceId: 1,
  );
  const transition = DesktopWorkspaceTransition(
    monitorId: 7,
    fromWorkspace: 1,
    toWorkspace: 2,
    serial: 1,
  );

  testWidgets('workspace motion does not remount its window subtree', (
    tester,
  ) async {
    var mounts = 0;

    Widget build(DesktopWorkspaceTransition? activeTransition) {
      return Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 1920,
          height: 1080,
          child: DesktopWorkspaceWindowTransition(
            placement: placement,
            transition: activeTransition,
            outputRect: const Rect.fromLTWH(0, 0, 1920, 1080),
            duration: Duration.zero,
            child: _MountProbe(onMount: () => mounts++),
          ),
        ),
      );
    }

    await tester.pumpWidget(build(null));
    await tester.pumpWidget(build(transition));
    await tester.pumpWidget(build(null));

    expect(mounts, 1);
  });

  testWidgets('workspace-remounted window never replays its entrance', (
    tester,
  ) async {
    Widget build({required bool suppressInitialAnimation}) {
      return Directionality(
        textDirection: TextDirection.ltr,
        child: DesktopWindowReveal(
          enabled: true,
          suppressInitialAnimation: suppressInitialAnimation,
          child: const SizedBox(width: 320, height: 240),
        ),
      );
    }

    await tester.pumpWidget(build(suppressInitialAnimation: true));
    expect(tester.widget<ClipPath>(find.byType(ClipPath)).clipper, isNull);

    await tester.pumpWidget(build(suppressInitialAnimation: false));
    await tester.pump();

    expect(tester.widget<ClipPath>(find.byType(ClipPath)).clipper, isNull);
  });

  testWidgets('incoming and outgoing workspaces slide across the output', (
    tester,
  ) async {
    Widget build(DesktopWindowPlacement windowPlacement) {
      return Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 800,
            height: 600,
            child: DesktopWorkspaceWindowTransition(
              placement: windowPlacement,
              transition: transition,
              outputRect: const Rect.fromLTWH(0, 0, 800, 600),
              duration: const Duration(milliseconds: 320),
              child: const SizedBox(width: 320, height: 240),
            ),
          ),
        ),
      );
    }

    double offsetX() => tester
        .widget<Transform>(find.byType(Transform))
        .transform
        .getTranslation()
        .x;

    // The incoming workspace starts one output width to the right and settles
    // at its resting position.
    await tester.pumpWidget(build(placement.copyWith(workspaceId: 2)));
    final enteringStart = offsetX();
    expect(enteringStart, moreOrLessEquals(800.0, epsilon: 0.5));
    await tester.pump(const Duration(milliseconds: 320));
    expect(offsetX(), moreOrLessEquals(0.0, epsilon: 0.5));

    // The outgoing workspace leaves to the left.
    await tester.pumpWidget(build(placement.copyWith(workspaceId: 1)));
    await tester.pump(const Duration(milliseconds: 320));
    expect(offsetX(), moreOrLessEquals(-800.0, epsilon: 0.5));

    // Windows of an uninvolved workspace never participate.
    await tester.pumpWidget(build(placement.copyWith(workspaceId: 3)));
    await tester.pump(const Duration(milliseconds: 320));
    expect(offsetX(), moreOrLessEquals(0.0, epsilon: 0.5));
  });

  testWidgets('the Desk button stays hidden until workspaces are enabled', (
    tester,
  ) async {
    final bridge = _RecordingBridge();
    final container = ProviderContainer(
      overrides: [
        denialBridgeProvider.overrideWithValue(bridge),
        shellSettingsProvider.overrideWith(
          () => _WorkspaceSettingsController(enabled: false),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: const Scaffold(body: ShelfWorkspaceButton(monitorId: 7)),
        ),
      ),
    );

    expect(find.text('Desk 1'), findsNothing);
    expect(bridge.switches, isEmpty);
  });

  testWidgets('the Desk button requests the monitor\'s next workspace', (
    tester,
  ) async {
    final bridge = _RecordingBridge();
    final container = ProviderContainer(
      overrides: [
        denialBridgeProvider.overrideWithValue(bridge),
        shellSettingsProvider.overrideWith(
          () => _WorkspaceSettingsController(enabled: true),
        ),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(desktopWorkspaceProvider.notifier);
    controller.syncWorkspaceConfiguration(
      enabled: true,
      count: 4,
      monitorIds: const [7],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: const Scaffold(body: ShelfWorkspaceButton(monitorId: 7)),
        ),
      ),
    );

    expect(find.text('Desk 1'), findsOneWidget);

    await tester.tap(find.byType(ShelfWorkspaceButton));
    await tester.pump();

    expect(bridge.switches, <({int monitorId, int workspaceId})>[
      (monitorId: 7, workspaceId: 2),
    ]);
  });

  group('workspace presentation', () {
    DesktopWorkspaceState stateWith({
      bool enabled = true,
      int count = 4,
      Map<int, DesktopWindowPlacement> placements = const {},
      Map<int, int> active = const {7: 1},
      Map<int, DesktopWorkspaceTransition> transitions = const {},
    }) {
      return DesktopWorkspaceState(
        placements: placements,
        nextZ: 2,
        viewSize: const Size(1920, 1080),
        workspacesEnabled: enabled,
        workspaceCount: count,
        activeWorkspaces: active,
        workspaceTransitions: transitions,
      );
    }

    test('disabled workspaces present every window on workspace one', () {
      final hidden = placement.copyWith(workspaceId: 3);
      final state = stateWith(enabled: false, placements: {1: hidden});

      expect(state.activeWorkspaceFor(7), 1);
      expect(state.isPlacementOnActiveWorkspace(hidden), isTrue);
      expect(state.isPlacementPresented(hidden), isTrue);
    });

    test('only the active workspace is presented without a transition', () {
      final activeWindow = placement.copyWith(workspaceId: 1);
      final otherWindow = placement.copyWith(workspaceId: 2);
      final state = stateWith();

      expect(state.isPlacementPresented(activeWindow), isTrue);
      expect(state.isPlacementPresented(otherWindow), isFalse);
    });

    test('an animating monitor presents both sides of its transition', () {
      final outgoing = placement.copyWith(workspaceId: 1);
      final incoming = placement.copyWith(workspaceId: 2);
      final unrelated = placement.copyWith(workspaceId: 3);
      final state = stateWith(transitions: {7: transition});

      expect(state.isPlacementPresented(outgoing), isTrue);
      expect(state.isPlacementPresented(incoming), isTrue);
      expect(state.isPlacementPresented(unrelated), isFalse);
    });

    test('minimized windows are workspace-less and always presentable', () {
      final minimized = placement.copyWith(workspaceId: -1, minimized: true);
      final state = stateWith();

      expect(state.isPlacementOnActiveWorkspace(minimized), isTrue);
      expect(state.isPlacementPresented(minimized), isTrue);
    });
  });
}

class _MountProbe extends StatefulWidget {
  const _MountProbe({required this.onMount});

  final VoidCallback onMount;

  @override
  State<_MountProbe> createState() => _MountProbeState();
}

class _MountProbeState extends State<_MountProbe> {
  @override
  void initState() {
    super.initState();
    widget.onMount();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
