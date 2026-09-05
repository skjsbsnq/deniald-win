import 'package:denial_dart_shell/l10n/generated/app_localizations.dart';
import 'package:denial_dart_shell/src/desktop/desktop_shell.dart';
import 'package:denial_dart_shell/src/desktop/desktop_workspace.dart';
import 'package:denial_dart_shell/src/desktop/shelf/unified_tray_bubble.dart';
import 'package:denial_dart_shell/src/models/battery_status.dart';
import 'package:denial_dart_shell/src/models/desktop_notification.dart';
import 'package:denial_dart_shell/src/models/denial_window.dart';
import 'package:denial_dart_shell/src/settings/settings_controller.dart';
import 'package:denial_dart_shell/src/settings/shell_settings.dart';
import 'package:denial_dart_shell/src/state/bluetooth.dart';
import 'package:denial_dart_shell/src/state/desktop_notifications.dart';
import 'package:denial_dart_shell/src/state/network_connectivity.dart';
import 'package:denial_dart_shell/src/state/quick_settings.dart';
import 'package:denial_dart_shell/src/state/system_status.dart';
import 'package:denial_dart_shell/src/theme/shell_theme.dart';
import 'package:denial_dart_shell/src/widgets/notification_banner.dart';
import 'package:denial_dart_shell/src/widgets/overview/overview_window_card.dart';
import 'package:denial_dart_shell/src/widgets/shade/range_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _testNotification = DesktopNotification(
  id: 1,
  sender: 'test',
  appName: 'Terminal',
  appIcon: 'utilities-terminal',
  summary: 'Build finished',
  body: 'Compilation succeeded with 0 errors.',
  actions: [
    DesktopNotificationAction(key: 'view', label: 'View Output'),
    DesktopNotificationAction(key: 'dismiss', label: 'Dismiss'),
  ],
  urgency: DesktopNotificationUrgency.normal,
  category: 'transfer',
  desktopEntry: 'org.gnome.Terminal',
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
  progress: 60,
  hasProgress: true,
  expireTimeoutMs: 5000,
);

const _testOverviewWindow = DenialWindow(
  objectId: 7,
  objectKind: 'xdg',
  surfaceId: 17,
  windowId: 27,
  textureId: 0,
  title: 'Text Editor',
  appId: 'org.example.editor',
  width: 720,
  height: 480,
  surfaceX: 0,
  surfaceY: 0,
  surfaceWidth: 720,
  surfaceHeight: 480,
  textureSourceX: 0,
  textureSourceY: 0,
  textureSourceWidth: 720,
  textureSourceHeight: 480,
  geometryX: 0,
  geometryY: 0,
  geometryWidth: 720,
  geometryHeight: 480,
  monitorId: 1,
  transform: 0,
  scale120: 120,
  opacityClass: DenialWindowOpacityClass.fullyOpaque,
);

void main() {
  testWidgets('range bar chrome baseline renders', (tester) async {
    await tester.pumpWidget(
      ShellTheme(
        data: const ShellThemeData(),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 320,
              height: 48,
              child: RangeBar(
                icon: Icons.volume_up_rounded,
                value: 0.6,
                activeColor: const Color(0xff80cbc4),
                inactiveColor: const Color(0xff263238),
                onChanged: (_) {},
                onChangeEnd: (_) {},
                height: 38,
              ),
            ),
          ),
        ),
      ),
    );

    await expectLater(
      find.byType(RangeBar),
      matchesGoldenFile('goldens/range_bar.png'),
    );
  });

  testWidgets('notification card renders', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            backgroundColor: const Color(0xff121212),
            body: Center(
              child: SizedBox(
                width: 360,
                child: ShellTheme(
                  data: const ShellThemeData(),
                  child: NotificationCard(
                    notification: _testNotification,
                    onDismiss: () {},
                    onAction: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await expectLater(
      find.byType(NotificationCard),
      matchesGoldenFile('goldens/notification_card.png'),
    );
  });

  testWidgets('desktop application launcher bubble renders', (tester) async {
    final searchFocusNode = FocusNode();
    addTearDown(searchFocusNode.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          shellSettingsProvider.overrideWith(_MockShelfSettingsController.new),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            backgroundColor: const Color(0xff121212),
            body: Center(
              child: SizedBox(
                width: 400,
                height: 560,
                child: ShellTheme(
                  data: const ShellThemeData(),
                  child: DesktopApplicationLauncher(
                    searchFocusNode: searchFocusNode,
                    onEnter: () {},
                    onExit: () {},
                    onDismiss: () {},
                    onLaunch: (_) {},
                    onLaunchLocal: (_) {},
                    visible: true,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    await expectLater(
      find.byType(DesktopApplicationLauncher),
      matchesGoldenFile('goldens/desktop_application_launcher.png'),
    );
  });
  testWidgets('overview window card renders', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            backgroundColor: const Color(0xff121212),
            body: Center(
              child: SizedBox(
                width: 360,
                height: 300,
                child: ShellTheme(
                  data: const ShellThemeData(),
                  child: OverviewWindowCard(
                    window: _testOverviewWindow,
                    index: 0,
                    progress: 1.0,
                    pageOffset: 0.0,
                    cardSize: const Size(280, 180),
                    hidden: false,
                    onDismiss: (_) {},
                    onFocus: (_, _) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    await expectLater(
      find.byType(OverviewWindowCard),
      matchesGoldenFile('goldens/overview_window_card.png'),
    );
  });

  testWidgets('unified tray bubble renders a bounded history window', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          quickSettingsProvider.overrideWith(_FakeQuickSettingsController.new),
          networkConnectivityProvider.overrideWith(_FakeNetworkController.new),
          bluetoothProvider.overrideWith(_FakeBluetoothController.new),
          desktopNotificationsProvider.overrideWith(
            _FakeNotificationsController.new,
          ),
          batteryProvider.overrideWith(_FakeBatteryController.new),
          desktopWorkspaceProvider.overrideWith(_FakeWorkspaceController.new),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            backgroundColor: const Color(0xff121212),
            body: ShellTheme(
              data: const ShellThemeData(),
              child: UnifiedTrayBubble(
                visible: true,
                onDismiss: () {},
                shelfHeight: 56.0,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    await expectLater(
      find.byType(UnifiedTrayBubble),
      matchesGoldenFile('goldens/unified_tray_bubble.png'),
    );

    // The list stays lazy, so prove the cap by scrolling: the 10th record is
    // reachable and the 11th never materializes.
    await tester.dragUntilVisible(
      find.text('History 9'),
      find.byType(ListView),
      const Offset(0, -80),
    );
    await tester.pumpAndSettle();
    expect(find.text('History 10'), findsNothing);
    expect(find.text('History 11'), findsNothing);
  });

  testWidgets('launcher bubble keeps its subtree mounted across close', (
    tester,
  ) async {
    final searchFocusNode = FocusNode();
    addTearDown(searchFocusNode.dispose);

    Widget buildLauncher(bool visible) {
      return ProviderScope(
        overrides: [
          shellSettingsProvider.overrideWith(_MockShelfSettingsController.new),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            backgroundColor: const Color(0xff121212),
            body: Center(
              child: SizedBox(
                width: 400,
                height: 560,
                child: ShellTheme(
                  data: const ShellThemeData(),
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
      );
    }

    await tester.pumpWidget(buildLauncher(true));
    await tester.pumpAndSettle();

    final gridFinder = find.descendant(
      of: find.byType(DesktopApplicationLauncher),
      matching: find.byType(CustomScrollView),
    );
    final gridElement = tester.element(gridFinder);

    await tester.enterText(find.byType(EditableText), 'term');
    await tester.pump();
    searchFocusNode.unfocus();
    await tester.pump();

    await tester.pumpWidget(buildLauncher(false));
    await tester.pumpAndSettle();

    // The collapsed bubble parks the grid behind Offstage instead of
    // unmounting it, so a reopen skips the full first-frame inflate.
    expect(gridFinder, findsNothing);
    expect(
      find.descendant(
        of: find.byType(DesktopApplicationLauncher),
        matching: find.byType(CustomScrollView, skipOffstage: false),
        skipOffstage: false,
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(buildLauncher(true));
    await tester.pumpAndSettle();

    // Same element instance: the subtree was retained, not rebuilt, and the
    // close-settle reset already cleared the search field.
    expect(find.text('term'), findsNothing);
    expect(identical(tester.element(gridFinder), gridElement), isTrue);
  });
}

class _MockShelfSettingsController extends ShellSettingsController {
  @override
  ShellSettings build() {
    return const ShellSettings(
      layout: ShellLayoutSettings(useChromeOsShelf: true),
    );
  }
}

// Fixed-state controllers so the tray bubble golden renders the same chips on
// every machine: no D-Bus, sysfs, or clock reads.
class _FakeQuickSettingsController extends QuickSettingsController {
  @override
  QuickSettingsState build() => QuickSettingsState.initial();
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

class _FakeBatteryController extends BatteryController {
  @override
  BatteryStatus build() =>
      const BatteryStatus(capacity: 87, charging: false, full: true);
}

class _FakeWorkspaceController extends DesktopWorkspaceController {
  @override
  DesktopWorkspaceState build() => DesktopWorkspaceState.initial();
}

class _FakeNotificationsController extends DesktopNotificationsController {
  @override
  DesktopNotificationsState build() {
    return DesktopNotificationsState(
      history: List<DesktopNotificationRecord>.unmodifiable(
        <DesktopNotificationRecord>[
          for (var index = 0; index < 12; index += 1)
            DesktopNotificationRecord(
              notification: _historyNotification(index),
              sequence: index,
              active: false,
              unread: false,
            ),
        ],
      ),
    );
  }
}

DesktopNotification _historyNotification(int index) {
  return DesktopNotification(
    id: index,
    sender: 'test',
    appName: 'Test App',
    appIcon: '',
    summary: 'History $index',
    body: 'Notification body number $index.',
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
