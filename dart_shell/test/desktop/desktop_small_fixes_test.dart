import 'package:denial_dart_shell/l10n/generated/app_localizations.dart';
import 'package:denial_dart_shell/src/desktop/desktop_audio_device_dropdown.dart';
import 'package:denial_dart_shell/src/desktop/shelf/dashboard/unified_dashboard_panel.dart';
import 'package:denial_dart_shell/src/models/desktop_notification.dart';
import 'package:denial_dart_shell/src/services/audio_service.dart';
import 'package:denial_dart_shell/src/services/notification_policy_repository.dart';
import 'package:denial_dart_shell/src/services/system_identity_service.dart';
import 'package:denial_dart_shell/src/services/todo_service.dart';
import 'package:denial_dart_shell/src/state/audio_devices.dart';
import 'package:denial_dart_shell/src/state/desktop_notifications.dart';
import 'package:denial_dart_shell/src/state/shell_controller.dart';
import 'package:denial_dart_shell/src/state/system_identity.dart';
import 'package:denial_dart_shell/src/state/system_status.dart';
import 'package:denial_dart_shell/src/theme/shell_theme.dart';
import 'package:denial_dart_shell/src/wallpaper/state/wallpaper_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/desktop_notifications_harness.dart';

final DateTime _fixedNow = DateTime(2026, 9, 8, 14, 30);

void main() {
  testWidgets(
    'notifications landing after the panel closes stay unread (COR-9)',
    (tester) async {
      final bridge = TestNotificationBridge();
      addTearDown(bridge.close);
      final container = ProviderContainer(
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
            (ref) => Stream<DateTime>.value(_fixedNow),
          ),
        ],
      );
      addTearDown(container.dispose);

      Widget buildPanel(bool visible) => UncontrolledProviderScope(
        container: container,
        child: _wrap(UnifiedDashboardPanel(visible: visible, onDismiss: () {})),
      );

      await tester.pumpWidget(buildPanel(true));
      await tester.pumpAndSettle();

      // A notification landing while the panel is visible is read on sight.
      bridge.add(
        _addedEvent(_notification(1, 'Alpha', 'While open', 'Body one')),
      );
      await tester.pump();
      await tester.pump();
      expect(container.read(desktopNotificationsProvider).unreadCount, 0);

      // Close the panel. The settle spring keeps the page subtree mounted
      // briefly, which is exactly the window that used to swallow unread
      // state.
      await tester.pumpWidget(buildPanel(false));
      await tester.pump();

      bridge.add(
        _addedEvent(_notification(2, 'Beta', 'While closing', 'Body two')),
      );
      await tester.pump();
      await tester.pump();
      final state = container.read(desktopNotificationsProvider);
      expect(state.unreadCount, 1);
      // History is newest-first, so the record that just landed is at the
      // front and must still carry its unread marker.
      expect(state.history.first.unread, isTrue);

      // Reopening consumes the marker through the normal seen-means-read
      // path.
      await tester.pumpWidget(buildPanel(true));
      await tester.pumpAndSettle();
      expect(container.read(desktopNotificationsProvider).unreadCount, 0);
    },
  );

  testWidgets(
    'audio device dropdown opens on the first click once refresh returns '
    'devices (COR-10)',
    (tester) async {
      final host = _DropdownHostState();
      await tester.pumpWidget(
        _wrap(
          StatefulBuilder(
            builder: (context, setState) {
              host.setOuterState = setState;
              return DashboardAudioDeviceDropdown(
                state: host.state,
                onRefresh: host.refresh,
                onSelected: (_) {},
              );
            },
          ),
        ),
      );
      await tester.pump();

      // Empty list, service idle: the first click refreshes and the arrival
      // of the device list expands the dropdown without a second click.
      await tester.tap(find.byKey(dashboardAudioDeviceDropdownButtonKey));
      await tester.pump();
      expect(host.refreshCount, 1);
      expect(
        find.byKey(dashboardAudioDeviceOptionKey('speakers')),
        findsNothing,
      );

      host.respondWith([
        const AudioOutputDevice(
          name: 'speakers',
          description: 'Speakers',
          active: true,
          available: true,
        ),
      ]);
      await tester.pump();
      expect(
        find.byKey(dashboardAudioDeviceOptionKey('speakers')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'a failed refresh never expands the audio dropdown on its own later',
    (tester) async {
      final host = _DropdownHostState();
      await tester.pumpWidget(
        _wrap(
          StatefulBuilder(
            builder: (context, setState) {
              host.setOuterState = setState;
              return DashboardAudioDeviceDropdown(
                state: host.state,
                onRefresh: host.refresh,
                onSelected: (_) {},
              );
            },
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(dashboardAudioDeviceDropdownButtonKey));
      await tester.pump();
      expect(host.refreshCount, 1);

      // The refresh finishes with no devices: nothing expands.
      host.finishEmpty();
      await tester.pump();
      expect(
        find.byKey(dashboardAudioDeviceOptionKey('speakers')),
        findsNothing,
      );

      // Devices arriving much later (hotplug) must not open the dropdown by
      // themselves; the pending open was consumed by the finished refresh.
      host.respondWith([
        const AudioOutputDevice(
          name: 'speakers',
          description: 'Speakers',
          active: true,
          available: true,
        ),
      ]);
      await tester.pump();
      expect(
        find.byKey(dashboardAudioDeviceOptionKey('speakers')),
        findsNothing,
      );
    },
  );
}

/// Mirrors [AudioDevicesController]'s refresh cycle for widget tests: an
/// empty list arms loading, and the service answer resolves it.
class _DropdownHostState {
  int refreshCount = 0;
  List<AudioOutputDevice> devices = const <AudioOutputDevice>[];
  bool loading = false;
  void Function(void Function()) setOuterState = (_) {};

  AudioDevicesState get state => AudioDevicesState(
    devices: devices,
    loading: loading,
    changing: false,
    error: null,
  );

  void refresh() {
    refreshCount += 1;
    loading = devices.isEmpty;
    setOuterState(() {});
  }

  void respondWith(List<AudioOutputDevice> next) {
    devices = next;
    loading = false;
    setOuterState(() {});
  }

  void finishEmpty() {
    devices = const <AudioOutputDevice>[];
    loading = false;
    setOuterState(() {});
  }
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
