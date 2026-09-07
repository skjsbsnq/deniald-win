import 'package:denial_dart_shell/l10n/generated/app_localizations.dart';
import 'package:denial_dart_shell/src/desktop/shelf/dashboard/info/dashboard_notification_list.dart';
import 'package:denial_dart_shell/src/desktop/shelf/dashboard/info/drawer_timer_widget.dart';
import 'package:denial_dart_shell/src/desktop/shelf/dashboard/info/drawer_todo_widget.dart';
import 'package:denial_dart_shell/src/desktop/shelf/dashboard/info/info_tool_drawer.dart';
import 'package:denial_dart_shell/src/desktop/shelf/dashboard/info/profile_header_card.dart';
import 'package:denial_dart_shell/src/models/desktop_notification.dart';
import 'package:denial_dart_shell/src/services/notification_policy_repository.dart';
import 'package:denial_dart_shell/src/services/system_identity_service.dart';
import 'package:denial_dart_shell/src/services/todo_service.dart';
import 'package:denial_dart_shell/src/state/desktop_notifications.dart';
import 'package:denial_dart_shell/src/state/shell_controller.dart';
import 'package:denial_dart_shell/src/state/system_identity.dart';
import 'package:denial_dart_shell/src/state/system_status.dart';
import 'package:denial_dart_shell/src/state/todo_list.dart';
import 'package:denial_dart_shell/src/theme/shell_theme.dart';
import 'package:denial_dart_shell/src/wallpaper/state/wallpaper_controller.dart';
import 'package:denial_dart_shell/src/widgets/notification_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/desktop_notifications_harness.dart';

final DateTime _fixedNow = DateTime(2026, 9, 7, 14, 30);

void main() {
  testWidgets('notification list groups, expands, and swipes away', (
    tester,
  ) async {
    final bridge = TestNotificationBridge();
    addTearDown(bridge.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          denialBridgeProvider.overrideWithValue(bridge),
          notificationPolicyStoreProvider.overrideWithValue(
            _MemoryPolicyStore(),
          ),
        ],
        child: _wrap(const DashboardNotificationList()),
      ),
    );
    await tester.pump();

    bridge.add(
      _addedEvent(_notification(1, 'Alpha', 'First', 'Alpha body one')),
    );
    bridge.add(
      _addedEvent(_notification(2, 'Alpha', 'Second', 'Alpha body two')),
    );
    bridge.add(_addedEvent(_notification(3, 'Beta', 'Solo', 'Beta body')));
    await tester.pump();

    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    expect(find.text('2 notifications'), findsOneWidget);
    expect(find.text('1 notification'), findsOneWidget);
    expect(find.text('3 notifications'), findsOneWidget);
    expect(find.byType(NotificationCard), findsNothing);

    // Expanding a group reveals its full notification cards.
    await tester.tap(find.text('2 notifications'));
    await tester.pumpAndSettle();
    expect(find.byType(NotificationCard), findsNWidgets(2));
    expect(find.text('First'), findsOneWidget);
    expect(find.text('Second'), findsOneWidget);

    // An elastic horizontal swipe past the threshold removes the whole group.
    await tester.drag(find.text('2 notifications'), const Offset(-240, 0));
    await tester.pumpAndSettle();
    expect(find.text('2 notifications'), findsNothing);
    expect(find.byType(NotificationCard), findsNothing);
    expect(find.text('Beta'), findsOneWidget);
    expect(bridge.dismissed, containsAll(<int>[1, 2]));

    // The do-not-disturb capsule flips the shared policy state.
    await tester.tap(find.text('DND'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.notifications_off_rounded), findsOneWidget);
  });

  testWidgets('todo drawer adds and completes tasks', (tester) async {
    final store = _MemoryTodoStore();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [todoStoreProvider.overrideWithValue(store)],
        child: _wrap(const SizedBox(height: 340, child: DrawerTodoWidget())),
      ),
    );
    await tester.pump();

    expect(find.text('Open 0'), findsOneWidget);
    expect(find.text('Done 0'), findsOneWidget);

    await tester.enterText(find.byType(EditableText), 'Ship task 11.2');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pump();

    expect(find.text('Ship task 11.2'), findsOneWidget);
    expect(find.text('Open 1'), findsOneWidget);

    // Complete the task through the shared controller; the row checkbox
    // invokes the same call.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(DrawerTodoWidget)),
    );
    final id = container.read(todoListProvider).first.id;
    container.read(todoListProvider.notifier).toggle(id);
    await tester.pump();

    expect(find.text('Ship task 11.2'), findsNothing);
    expect(find.text('Done 1'), findsOneWidget);

    await tester.tap(find.text('Done 1'));
    await tester.pumpAndSettle();
    expect(find.text('Ship task 11.2'), findsOneWidget);
    expect(store.items.single.done, isTrue);
  });

  testWidgets('info tool drawer opens expanded and switches tools', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          todoStoreProvider.overrideWithValue(_MemoryTodoStore()),
          // The real minute clock parks a timer until the next boundary,
          // which trips the pending-timer invariant at teardown. A finite
          // stream keeps the drawer deterministic as well.
          clockProvider.overrideWith(
            (ref) => Stream<DateTime>.value(_fixedNow),
          ),
        ],
        child: _wrap(const SizedBox(height: 420, child: InfoToolDrawer())),
      ),
    );
    await tester.pumpAndSettle();

    // The drawer opens expanded so the calendar greets the user directly.
    expect(find.byIcon(Icons.calendar_month_rounded), findsOneWidget);

    // The rail icon is the first match: the timer and checklist glyphs also
    // appear inside their respective tool panes, which stay mounted.
    await tester.tap(find.byIcon(Icons.timer_rounded).first);
    await tester.pumpAndSettle();
    expect(find.text('25:00'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.checklist_rounded).first);
    await tester.pumpAndSettle();
    expect(find.text('Open 0'), findsOneWidget);

    // Collapsing folds the tools back into the compact date capsule.
    await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.keyboard_arrow_up_rounded), findsOneWidget);
    expect(find.textContaining('todos'), findsOneWidget);
  });

  testWidgets('drawer timer counts down and records laps', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: _wrap(const SizedBox(height: 340, child: DrawerTimerWidget())),
      ),
    );
    await tester.pump();

    expect(find.text('25:00'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('24:58'), findsOneWidget);

    // Switching to the stopwatch resets the shared tool state machine.
    await tester.tap(find.byIcon(Icons.timer_rounded));
    await tester.pumpAndSettle();
    expect(find.text('00:00'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.byIcon(Icons.flag_rounded));
    await tester.pump();
    expect(find.text('Lap 1'), findsOneWidget);
    expect(find.text('00:02'), findsNWidgets(2));
  });

  testWidgets('profile header card renders identity and uptime', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          systemIdentityProvider.overrideWith(_FixedIdentityController.new),
          wallpaperControllerProvider.overrideWith(
            _InitialWallpaperController.new,
          ),
        ],
        child: _wrap(const SizedBox(width: 420, child: ProfileHeaderCard())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Arch Linux'), findsOneWidget);
    expect(find.text('Up · 3h 10m'), findsOneWidget);
    expect(find.textContaining('user@'), findsOneWidget);
    expect(find.byIcon(Icons.account_circle_rounded), findsOneWidget);
  });
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

DesktopNotificationEvent _addedEvent(DesktopNotification notification) {
  return DesktopNotificationEvent(
    kind: DesktopNotificationEventKind.added,
    notificationId: notification.id,
    closeReason: 0,
    notification: notification,
  );
}

DesktopNotification _notification(
  int id,
  String appName,
  String summary,
  String body,
) {
  return DesktopNotification(
    id: id,
    sender: 'test',
    appName: appName,
    appIcon: '',
    summary: summary,
    body: body,
    actions: const <DesktopNotificationAction>[],
    urgency: DesktopNotificationUrgency.normal,
    category: '',
    desktopEntry: '',
    imagePath: '',
    imageData: null,
    resident: false,
    transient: false,
    suppressSound: false,
    actionIcons: false,
    soundName: '',
    soundFile: '',
    x: 0,
    y: 0,
    hasPosition: false,
    progress: 0,
    hasProgress: false,
    expireTimeoutMs: 5000,
  );
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

class _MemoryPolicyStore implements NotificationPolicyStore {
  NotificationPolicy policy = const NotificationPolicy();

  @override
  Future<NotificationPolicy> read() async => policy;

  @override
  Future<void> write(NotificationPolicy newPolicy) async {
    policy = newPolicy;
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

class _InitialWallpaperController extends WallpaperController {
  @override
  WallpaperExperienceState build() => WallpaperExperienceState.initial();
}
