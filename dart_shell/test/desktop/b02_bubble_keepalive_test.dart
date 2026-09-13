import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:denial_dart_shell/l10n/generated/app_localizations.dart';
import 'package:denial_dart_shell/src/desktop/desktop_workspace.dart';
import 'package:denial_dart_shell/src/desktop/shelf/dashboard/dashboard_tab_bar.dart';
import 'package:denial_dart_shell/src/desktop/shelf/dashboard/info/profile_header_card.dart';
import 'package:denial_dart_shell/src/desktop/shelf/dashboard/unified_dashboard_panel.dart';
import 'package:denial_dart_shell/src/desktop/shelf/dashboard/views/weather_view.dart';
import 'package:denial_dart_shell/src/desktop/shelf/unified_tray_bubble.dart';
import 'package:denial_dart_shell/src/services/notification_policy_repository.dart';
import 'package:denial_dart_shell/src/services/system_identity_service.dart';
import 'package:denial_dart_shell/src/services/todo_service.dart';
import 'package:denial_dart_shell/src/state/bluetooth.dart';
import 'package:denial_dart_shell/src/state/desktop_notifications.dart';
import 'package:denial_dart_shell/src/state/network_connectivity.dart';
import 'package:denial_dart_shell/src/state/quick_settings.dart';
import 'package:denial_dart_shell/src/state/shell_controller.dart';
import 'package:denial_dart_shell/src/state/system_identity.dart';
import 'package:denial_dart_shell/src/state/system_status.dart';
import 'package:denial_dart_shell/src/state/timer_state.dart';
import 'package:denial_dart_shell/src/theme/shell_theme.dart';
import 'package:denial_dart_shell/src/wallpaper/state/wallpaper_controller.dart';
import 'package:denial_dart_shell/src/wallpaper/wallpaper.dart';
import 'package:denial_dart_shell/src/widgets/shade/range_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/desktop_notifications_harness.dart';
import '../support/notification_fixture.dart';

void main() {
  testWidgets('dashboard warm-up inflates the content parked and inert', (
    tester,
  ) async {
    await tester.pumpWidget(
      _dashboardScope(
        _wrap(
          const _SurfaceHost(initiallyVisible: false, builder: _panelBuilder),
        ),
      ),
    );
    await tester.pump();

    // Before the warm-up delay the hidden panel is still uninflated.
    expect(find.byType(DashboardTabBar, skipOffstage: false), findsNothing);

    // Past the one-shot delay the subtree exists but stays offstage.
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(DashboardTabBar, skipOffstage: false), findsOneWidget);
    expect(find.byType(DashboardTabBar), findsNothing);

    final offstages = tester.widgetList<Offstage>(
      find.ancestor(
        of: find.byType(DashboardTabBar, skipOffstage: false),
        matching: find.byType(Offstage),
      ),
    );
    expect(offstages.any((widget) => widget.offstage), isTrue);
    final tickerModes = tester.widgetList<TickerMode>(
      find.ancestor(
        of: find.byType(DashboardTabBar, skipOffstage: false),
        matching: find.byType(TickerMode),
      ),
    );
    expect(tickerModes.any((mode) => !mode.enabled), isTrue);

    // The parked panel never claims focus.
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      isNot('unified-dashboard-panel'),
    );
  });

  testWidgets('warm-up does not mount the lazily hosted Weather page', (
    tester,
  ) async {
    await tester.pumpWidget(
      _dashboardScope(
        _wrap(
          const _SurfaceHost(initiallyVisible: false, builder: _panelBuilder),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));

    // The Info page inflated under Offstage; the Weather page keeps its
    // tab-selected lazy mount, so no weather fetch can start while hidden.
    expect(find.byType(WeatherView, skipOffstage: false), findsNothing);
  });

  testWidgets('dashboard keeps its content mounted but offstage after close', (
    tester,
  ) async {
    await tester.pumpWidget(
      _dashboardScope(_wrap(const _SurfaceHost(builder: _panelBuilder))),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DashboardTabBar), findsOneWidget);

    final inflatedElement = tester.element(find.byType(DashboardTabBar));

    final host = tester.state<_SurfaceHostState>(find.byType(_SurfaceHost));
    host.setVisible(false);
    await tester.pumpAndSettle();

    // The subtree survived the close: mounted, offstage, and tickers parked.
    expect(find.byType(DashboardTabBar), findsNothing);
    expect(find.byType(DashboardTabBar, skipOffstage: false), findsOneWidget);
    expect(
      tester
          .widgetList<Offstage>(
            find.ancestor(
              of: find.byType(DashboardTabBar, skipOffstage: false),
              matching: find.byType(Offstage),
            ),
          )
          .any((widget) => widget.offstage),
      isTrue,
    );

    host.setVisible(true);
    await tester.pumpAndSettle();
    expect(find.byType(DashboardTabBar), findsOneWidget);
    // Same element across close and reopen: the content was never unmounted.
    expect(tester.element(find.byType(DashboardTabBar)), same(inflatedElement));
  });

  testWidgets(
    'tray bubble keeps its content mounted but offstage after close',
    (tester) async {
      await tester.pumpWidget(
        _bubbleScope(_wrap(const _SurfaceHost(builder: _bubbleBuilder))),
      );
      await tester.pumpAndSettle();
      expect(find.byType(RangeBar), findsNWidgets(2));

      final host = tester.state<_SurfaceHostState>(find.byType(_SurfaceHost));
      host.setVisible(false);
      await tester.pumpAndSettle();

      expect(find.byType(RangeBar), findsNothing);
      expect(find.byType(RangeBar, skipOffstage: false), findsNWidgets(2));
      expect(
        tester
            .widgetList<Offstage>(
              find.ancestor(
                of: find.byType(RangeBar, skipOffstage: false).first,
                matching: find.byType(Offstage),
              ),
            )
            .any((widget) => widget.offstage),
        isTrue,
      );

      host.setVisible(true);
      await tester.pumpAndSettle();
      expect(find.byType(RangeBar), findsNWidgets(2));
    },
  );

  testWidgets(
    'unread markers survive the parked panel and clear only when visible',
    (tester) async {
      final bridge = TestNotificationBridge();
      addTearDown(bridge.close);
      final container = ProviderContainer.test(
        overrides: [
          denialBridgeProvider.overrideWithValue(bridge),
          notificationPolicyStoreProvider.overrideWithValue(
            _MemoryPolicyStore(),
          ),
          systemIdentityProvider.overrideWith(_FixedIdentityController.new),
          wallpaperControllerProvider.overrideWith(
            _InitialWallpaperController.new,
          ),
          todoStoreProvider.overrideWithValue(_MemoryTodoStore()),
          clockProvider.overrideWith(
            (ref) => Stream<DateTime>.value(DateTime(2026, 9, 9)),
          ),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _wrap(
            const _SurfaceHost(initiallyVisible: false, builder: _panelBuilder),
          ),
        ),
      );
      await tester.pump();
      // Let the warm-up inflate the parked notification list.
      await tester.pump(const Duration(seconds: 2));

      // A notification landing while the list is parked offstage must keep
      // its unread marker: DashboardPanelVisibility reports hidden.
      bridge.add(
        notificationEvent(notificationFixture(id: 7, summary: 'Parked')),
      );
      await tester.pump();
      await tester.pump();
      expect(container.read(desktopNotificationsProvider).unreadCount, 1);

      final host = tester.state<_SurfaceHostState>(find.byType(_SurfaceHost));
      host.setVisible(true);
      await tester.pump();
      await tester.pump();
      expect(container.read(desktopNotificationsProvider).unreadCount, 0);
    },
  );

  testWidgets(
    'timer tool ticker suspends while the panel is parked and resumes on open',
    (tester) async {
      final bridge = TestNotificationBridge();
      addTearDown(bridge.close);
      final container = ProviderContainer.test(
        overrides: [
          denialBridgeProvider.overrideWithValue(bridge),
          notificationPolicyStoreProvider.overrideWithValue(
            _MemoryPolicyStore(),
          ),
          systemIdentityProvider.overrideWith(_FixedIdentityController.new),
          wallpaperControllerProvider.overrideWith(
            _InitialWallpaperController.new,
          ),
          todoStoreProvider.overrideWithValue(_MemoryTodoStore()),
          clockProvider.overrideWith(
            (ref) => Stream<DateTime>.value(DateTime(2026, 9, 9)),
          ),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _wrap(const _SurfaceHost(builder: _panelBuilder)),
        ),
      );
      await tester.pumpAndSettle();

      final controller = container.read(timerToolProvider.notifier);
      controller.start();
      await tester.pump();
      expect(controller.debugTickerActive, isTrue);

      // Closing parks the subtree: the last (paused) listener leaves the
      // provider suspended instead of ticking at 1 Hz while invisible. The
      // first pump rebuilds and starts the close spring; the spring ticks on
      // the following frame, so a second pump carries it to rest.
      final host = tester.state<_SurfaceHostState>(find.byType(_SurfaceHost));
      host.setVisible(false);
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(controller.debugTickerActive, isFalse);
      // The parked ticker cannot tick the pumped fake seconds; elapsed can
      // only drift by real wall-clock time materialized on the next read —
      // milliseconds in a test run, never the three fake seconds a live 1 Hz
      // ticker would add.
      final parkedElapsed = container.read(timerToolProvider).elapsed;
      await tester.pump(const Duration(seconds: 3));
      expect(controller.debugTickerActive, isFalse);
      expect(
        container.read(timerToolProvider).elapsed - parkedElapsed,
        lessThan(const Duration(seconds: 1)),
      );

      host.setVisible(true);
      await tester.pump();
      await tester.pump();
      expect(controller.debugTickerActive, isTrue);
      expect(container.read(timerToolProvider).running, isTrue);
    },
  );

  testWidgets('tray bubble sliders stay disabled until levels load', (
    tester,
  ) async {
    final container = ProviderContainer.test(
      overrides: [
        quickSettingsProvider.overrideWith(_DrivenQuickSettingsController.new),
        networkConnectivityProvider.overrideWith(_FakeNetworkController.new),
        bluetoothProvider.overrideWith(_FakeBluetoothController.new),
        desktopNotificationsProvider.overrideWithBuild(
          (_, _) => const DesktopNotificationsState(),
        ),
        desktopWorkspaceProvider.overrideWith(_FakeWorkspaceController.new),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _wrap(const UnifiedTrayBubble(visible: true, shelfHeight: 56.0)),
      ),
    );
    await tester.pumpAndSettle();

    RangeBar bar(IconData icon) => tester.widget<RangeBar>(
      find.byWidgetPredicate(
        (widget) => widget is RangeBar && widget.icon == icon,
      ),
    );

    // Unloaded levels render as inert controls instead of placeholder thumbs.
    expect(bar(Icons.brightness_6_rounded).enabled, isFalse);
    expect(bar(Icons.volume_up_rounded).enabled, isFalse);

    final controller =
        container.read(quickSettingsProvider.notifier)
            as _DrivenQuickSettingsController;
    controller.emitLoadedLevels(brightness: 0.7, volume: 0.5);
    await tester.pump();
    expect(bar(Icons.brightness_6_rounded).enabled, isTrue);
    expect(bar(Icons.volume_up_rounded).enabled, isTrue);
    expect(bar(Icons.brightness_6_rounded).value, 0.7);
    expect(bar(Icons.volume_up_rounded).value, 0.5);
  });

  testWidgets('warm-up precaches the cover and avatar into the image cache', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final dir = Directory.systemTemp.createTempSync('b02_warmup');
      addTearDown(() => dir.deleteSync(recursive: true));
      final png = await _testPngBytes();
      final coverFile = File('${dir.path}/cover.png')..writeAsBytesSync(png);
      final avatarFile = File('${dir.path}/avatar.png')..writeAsBytesSync(png);

      final container = ProviderContainer.test(
        overrides: [
          denialBridgeProvider.overrideWithValue(TestNotificationBridge()),
          notificationPolicyStoreProvider.overrideWithValue(
            _MemoryPolicyStore(),
          ),
          systemIdentityProvider.overrideWith(
            () => _AvatarIdentityController(avatarFile.path),
          ),
          wallpaperControllerProvider.overrideWith(
            () => _FileWallpaperController(
              WallpaperResource.file(coverFile.path),
            ),
          ),
          todoStoreProvider.overrideWithValue(_MemoryTodoStore()),
          clockProvider.overrideWith(
            (ref) => Stream<DateTime>.value(DateTime(2026, 9, 9)),
          ),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _wrap(
            const UnifiedDashboardPanel(visible: false, shelfHeight: 56.0),
          ),
        ),
      );

      // The warm-up timer is a real timer inside runAsync: wait it out, then
      // pump so the parked subtree inflates and the precache pass runs.
      await Future<void>.delayed(const Duration(milliseconds: 1300));
      await tester.pump();
      await tester.pump();

      final panelContext = tester.element(find.byType(UnifiedDashboardPanel));
      final coverProvider = ProfileHeaderCard.coverImageProvider(
        panelContext,
        WallpaperResource.file(coverFile.path),
      );
      final coverKey = await coverProvider.obtainKey(ImageConfiguration.empty);
      await _expectCached(coverKey);
      await _expectCached(FileImage(avatarFile));
    });
  });
}

Future<void> _expectCached(Object key) async {
  final cache = PaintingBinding.instance.imageCache;
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (cache.containsKey(key)) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail('expected the warm-up to leave $key in the image cache');
}

Future<List<int>> _testPngBytes() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 8, 8), ui.Paint());
  final image = await recorder.endRecording().toImage(8, 8);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}

/// Toggles `visible` on the hosted surface the way the scene's
/// ValueListenableBuilder does, without pulling the whole scene into the
/// test. The visibility lives in the state and feeds a builder so toggling
/// always rebuilds the hosted panel with a fresh `visible` value — a shared
/// child widget instance would be short-circuited by the element tree.
class _SurfaceHost extends StatefulWidget {
  const _SurfaceHost({required this.builder, this.initiallyVisible = true});

  final Widget Function(BuildContext context, bool visible) builder;
  final bool initiallyVisible;

  @override
  State<_SurfaceHost> createState() => _SurfaceHostState();
}

class _SurfaceHostState extends State<_SurfaceHost> {
  late bool _visible = widget.initiallyVisible;

  void setVisible(bool value) {
    setState(() => _visible = value);
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _visible);
  }
}

Widget _panelBuilder(BuildContext context, bool visible) {
  return UnifiedDashboardPanel(
    visible: visible,
    onDismiss: () {},
    shelfHeight: 56.0,
  );
}

Widget _bubbleBuilder(BuildContext context, bool visible) {
  return UnifiedTrayBubble(
    visible: visible,
    onDismiss: () {},
    shelfHeight: 56.0,
  );
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

Widget _dashboardScope(Widget child) {
  final bridge = TestNotificationBridge();
  addTearDown(bridge.close);
  return ProviderScope(
    overrides: [
      denialBridgeProvider.overrideWithValue(bridge),
      notificationPolicyStoreProvider.overrideWithValue(_MemoryPolicyStore()),
      systemIdentityProvider.overrideWith(_FixedIdentityController.new),
      wallpaperControllerProvider.overrideWith(_InitialWallpaperController.new),
      todoStoreProvider.overrideWithValue(_MemoryTodoStore()),
      clockProvider.overrideWith(
        (ref) => Stream<DateTime>.value(DateTime(2026, 9, 9)),
      ),
    ],
    child: child,
  );
}

Widget _bubbleScope(Widget child) {
  return ProviderScope(
    overrides: [
      quickSettingsProvider.overrideWith(_DrivenQuickSettingsController.new),
      networkConnectivityProvider.overrideWith(_FakeNetworkController.new),
      bluetoothProvider.overrideWith(_FakeBluetoothController.new),
      desktopNotificationsProvider.overrideWithBuild(
        (_, _) => const DesktopNotificationsState(),
      ),
      desktopWorkspaceProvider.overrideWith(_FakeWorkspaceController.new),
    ],
    child: child,
  );
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

class _MemoryTodoStore implements TodoStore {
  List<TodoItem> items = <TodoItem>[];

  @override
  Future<List<TodoItem>> read() async => List<TodoItem>.unmodifiable(items);

  @override
  Future<void> write(List<TodoItem> newItems) async {
    items = List<TodoItem>.unmodifiable(newItems);
  }
}

class _FixedIdentityController extends SystemIdentityController {
  @override
  SystemIdentityState build() {
    return const SystemIdentityState(
      uptimeSeconds: 11400,
      distro: DistroInfo(id: 'arch', prettyName: 'Arch Linux'),
    );
  }
}

class _AvatarIdentityController extends SystemIdentityController {
  _AvatarIdentityController(this.avatarPath);

  final String avatarPath;

  @override
  SystemIdentityState build() {
    return SystemIdentityState(avatarPath: avatarPath);
  }
}

class _InitialWallpaperController extends WallpaperController {
  @override
  WallpaperExperienceState build() => WallpaperExperienceState.initial();
}

class _FileWallpaperController extends WallpaperController {
  _FileWallpaperController(this.resource);

  final WallpaperResource resource;

  @override
  WallpaperExperienceState build() {
    return WallpaperExperienceState.initial().copyWith(
      assignment: WallpaperAssignment(all: resource),
    );
  }
}

class _DrivenQuickSettingsController extends QuickSettingsController {
  @override
  QuickSettingsState build() => QuickSettingsState.initial();

  void emitLoadedLevels({required double brightness, required double volume}) {
    state = state.copyWith(
      brightness: brightness,
      brightnessLoaded: true,
      volume: volume,
      volumeLoaded: true,
    );
  }
}

class _FakeNetworkController extends NetworkConnectivityController {
  @override
  NetworkConnectivityState build() =>
      NetworkConnectivityState.initial().copyWith(initializing: false);
}

class _FakeBluetoothController extends BluetoothController {
  @override
  BluetoothState build() =>
      BluetoothState.initial().copyWith(initializing: false);
}

class _FakeWorkspaceController extends DesktopWorkspaceController {
  @override
  DesktopWorkspaceState build() => DesktopWorkspaceState.initial();
}
