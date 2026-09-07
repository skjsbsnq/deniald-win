import 'package:denial_dart_shell/l10n/generated/app_localizations.dart';
import 'package:denial_dart_shell/src/desktop/shelf/dashboard/dashboard_tab_bar.dart';
import 'package:denial_dart_shell/src/desktop/shelf/dashboard/unified_dashboard_panel.dart';
import 'package:denial_dart_shell/src/desktop/shelf/dashboard/views/system_view.dart';
import 'package:denial_dart_shell/src/desktop/shelf/dashboard/views/weather_view.dart';
import 'package:denial_dart_shell/src/services/notification_policy_repository.dart';
import 'package:denial_dart_shell/src/state/desktop_notifications.dart';
import 'package:denial_dart_shell/src/state/shell_controller.dart';
import 'package:denial_dart_shell/src/state/system_status.dart';
import 'package:denial_dart_shell/src/theme/shell_theme.dart';
import 'package:denial_dart_shell/src/wallpaper/state/wallpaper_controller.dart';
import 'package:denial_dart_shell/src/widgets/shell_backdrop_blur.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/desktop_notifications_harness.dart';

void main() {
  testWidgets('tab bar pill springs across entries on tap', (tester) async {
    DashboardTabBarHost.selected = DashboardTab.info;
    addTearDown(() => DashboardTabBarHost.selected = DashboardTab.info);
    await tester.pumpWidget(
      _wrap(
        const SizedBox(height: 52, width: 420, child: DashboardTabBarHost()),
      ),
    );
    await tester.pump();

    expect(find.text('Info'), findsOneWidget);
    expect(find.text('System'), findsOneWidget);
    expect(find.text('Weather'), findsOneWidget);

    await tester.tap(find.text('System'));
    await tester.pump();
    // The unbounded spring keeps moving right after the first tick.
    expect(DashboardTabBarHost.selected, DashboardTab.system);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Weather'));
    await tester.pumpAndSettle();
    expect(DashboardTabBarHost.selected, DashboardTab.weather);
  });

  testWidgets('tab bar wheel advances through the pages', (tester) async {
    DashboardTabBarHost.selected = DashboardTab.info;
    addTearDown(() => DashboardTabBarHost.selected = DashboardTab.info);
    await tester.pumpWidget(
      _wrap(
        const SizedBox(height: 52, width: 420, child: DashboardTabBarHost()),
      ),
    );
    await tester.pump();

    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    final center = tester.getCenter(find.byType(DashboardTabBar));
    await tester.sendEventToBinding(mouse.hover(center));
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, 120)));
    await tester.pump();
    expect(DashboardTabBarHost.selected, DashboardTab.system);

    await tester.sendEventToBinding(mouse.scroll(const Offset(0, 120)));
    await tester.pump();
    expect(DashboardTabBarHost.selected, DashboardTab.weather);

    // Scrolling past the last tab clamps instead of wrapping around.
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, 120)));
    await tester.pump();
    expect(DashboardTabBarHost.selected, DashboardTab.weather);

    await tester.sendEventToBinding(mouse.scroll(const Offset(0, -120)));
    await tester.pump();
    expect(DashboardTabBarHost.selected, DashboardTab.system);

    await tester.sendEventToBinding(mouse.scroll(const Offset(0, -120)));
    await tester.pump();
    expect(DashboardTabBarHost.selected, DashboardTab.info);
  });

  testWidgets('panel mounts Info first and pages stay alive after visit', (
    tester,
  ) async {
    final bridge = TestNotificationBridge();
    addTearDown(bridge.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // The real minute clock parks a timer until the next boundary,
          // which trips the pending-timer invariant at teardown. A finite
          // stream keeps the drawer deterministic as well.
          clockProvider.overrideWith(
            (ref) => Stream<DateTime>.value(DateTime(2026, 9, 7, 14, 30)),
          ),
          denialBridgeProvider.overrideWithValue(bridge),
          notificationPolicyStoreProvider.overrideWithValue(
            _MemoryPolicyStore(),
          ),
          wallpaperControllerProvider.overrideWith(
            _InitialWallpaperController.new,
          ),
        ],
        child: _wrap(
          const UnifiedDashboardPanel(visible: true, shelfHeight: 56.0),
        ),
      ),
    );
    await tester.pump();

    // Info mounts by default: its page subtree is present, and no System or
    // Weather page is built yet.
    expect(
      find.byKey(const ValueKey('dashboard-tab-info'), skipOffstage: false),
      findsOneWidget,
    );
    expect(find.byType(SystemView), findsNothing);
    expect(find.byType(WeatherView), findsNothing);

    // Switch to System: the System page mounts.
    await tester.tap(find.text('System'));
    await tester.pumpAndSettle();
    expect(find.byType(SystemView), findsOneWidget);

    // Switch back to Info: the System page stays mounted (IndexedStack) so
    // its state survives; Info is visible again.
    await tester.tap(find.text('Info'));
    await tester.pumpAndSettle();
    expect(find.byType(SystemView, skipOffstage: false), findsOneWidget);
  });

  testWidgets('panel keeps its full docked height on every tab', (
    tester,
  ) async {
    final bridge = TestNotificationBridge();
    addTearDown(bridge.close);
    // Static host state must not leak into later cases if this one fails
    // midway (same lesson as the tab bar host).
    addTearDown(() => _PanelVisibilityHost.visible = true);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // The real minute clock parks a timer until the next boundary,
          // which trips the pending-timer invariant at teardown. A finite
          // stream keeps the drawer deterministic as well.
          clockProvider.overrideWith(
            (ref) => Stream<DateTime>.value(DateTime(2026, 9, 7, 14, 30)),
          ),
          denialBridgeProvider.overrideWithValue(bridge),
          notificationPolicyStoreProvider.overrideWithValue(
            _MemoryPolicyStore(),
          ),
          wallpaperControllerProvider.overrideWith(
            _InitialWallpaperController.new,
          ),
        ],
        child: _wrap(const _PanelVisibilityHost()),
      ),
    );
    await tester.pumpAndSettle();

    // The 800x600 test surface docks the panel at 600 - 56 - 24 = 520.
    Size panelSize() => tester.getSize(find.byType(ShellBackdropBlur));
    expect(panelSize(), const Size(420, 520));

    // A page whose content is shorter than the panel (System) must not
    // shrink it: every tab opens the same fully expanded panel.
    await tester.tap(find.text('System'));
    await tester.pumpAndSettle();
    expect(panelSize(), const Size(420, 520));

    // Reopening on the remembered tab keeps the full height too. Before the
    // fixed-height fix this reopened as a content-sized stub panel because
    // only the remembered page remounted.
    final host = tester.state<_PanelVisibilityHostState>(
      find.byType(_PanelVisibilityHost),
    );
    host.setVisible(false);
    await tester.pumpAndSettle();
    host.setVisible(true);
    await tester.pumpAndSettle();
    expect(find.byType(SystemView), findsOneWidget);
    expect(panelSize(), const Size(420, 520));
  });

  testWidgets('hidden panel renders nothing until visible flips', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(const UnifiedDashboardPanel(visible: false, shelfHeight: 56.0)),
    );
    await tester.pump();

    expect(find.byType(DashboardTabBar), findsNothing);
  });
}

class _PanelVisibilityHost extends StatefulWidget {
  const _PanelVisibilityHost();

  static bool visible = true;

  @override
  State<_PanelVisibilityHost> createState() => _PanelVisibilityHostState();
}

class _PanelVisibilityHostState extends State<_PanelVisibilityHost> {
  // Public so the test can drive the visibility flip the way the scene
  // does; calling State.setState from outside would be a protected member.
  void setVisible(bool value) {
    setState(() => _PanelVisibilityHost.visible = value);
  }

  @override
  Widget build(BuildContext context) {
    return UnifiedDashboardPanel(
      visible: _PanelVisibilityHost.visible,
      onDismiss: () => setVisible(false),
      shelfHeight: 56.0,
    );
  }
}

class DashboardTabBarHost extends StatefulWidget {
  const DashboardTabBarHost({super.key});

  static DashboardTab selected = DashboardTab.info;

  @override
  State<DashboardTabBarHost> createState() => _DashboardTabBarHostState();
}

class _DashboardTabBarHostState extends State<DashboardTabBarHost> {
  @override
  Widget build(BuildContext context) {
    return DashboardTabBar(
      selected: DashboardTabBarHost.selected,
      onSelected: (tab) => setState(() => DashboardTabBarHost.selected = tab),
    );
  }
}

class _MemoryPolicyStore implements NotificationPolicyStore {
  NotificationPolicy policy = const NotificationPolicy();

  @override
  Future<NotificationPolicy> read() async => policy;

  @override
  Future<void> write(NotificationPolicy newPolicy) async {
    policy = newPolicy;
  }
}

class _InitialWallpaperController extends WallpaperController {
  @override
  WallpaperExperienceState build() => WallpaperExperienceState.initial();
}

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: Scaffold(
      backgroundColor: const Color(0xff121212),
      body: ShellTheme(data: const ShellThemeData(), child: child),
    ),
  );
}
