import 'package:denial_dart_shell/l10n/generated/app_localizations.dart';
import 'package:denial_dart_shell/src/desktop/desktop_input_layout_publisher.dart';
import 'package:denial_dart_shell/src/input/input_layout.dart';
import 'package:denial_dart_shell/src/models/desktop_notification.dart';
import 'package:denial_dart_shell/src/models/denial_window.dart';
import 'package:denial_dart_shell/src/platform/denial_bridge.dart';
import 'package:denial_dart_shell/src/settings/settings_controller.dart';
import 'package:denial_dart_shell/src/settings/shell_settings.dart';
import 'package:denial_dart_shell/src/state/desktop_notifications.dart';
import 'package:denial_dart_shell/src/state/display_layout.dart';
import 'package:denial_dart_shell/src/state/shell_controller.dart';
import 'package:denial_dart_shell/src/state/shell_state.dart';
import 'package:denial_dart_shell/src/theme/shell_theme.dart';
import 'package:denial_dart_shell/src/widgets/notification_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// A client window placed under the default top-left banner placement so the
// banner rectangle has to be re-added to the shell regions above the window.
const _windowUnderBanner = DenialWindow(
  objectId: 7,
  objectKind: 'xdg',
  surfaceId: 17,
  windowId: 27,
  textureId: 37,
  title: 'Client',
  appId: 'org.example.client',
  width: 700,
  height: 560,
  surfaceX: 0,
  surfaceY: 0,
  surfaceWidth: 700,
  surfaceHeight: 560,
  textureSourceX: 0,
  textureSourceY: 0,
  textureSourceWidth: 700,
  textureSourceHeight: 560,
  geometryX: 10,
  geometryY: 16,
  geometryWidth: 700,
  geometryHeight: 560,
  monitorId: 1,
  transform: 0,
  scale120: 120,
);

const _firstNotification = DesktopNotification(
  id: 1,
  sender: 'test',
  appName: 'Client',
  appIcon: '',
  summary: 'First banner',
  body: 'The first stacked banner card.',
  actions: <DesktopNotificationAction>[],
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
  expireTimeoutMs: 0,
);

const _secondNotification = DesktopNotification(
  id: 2,
  sender: 'test',
  appName: 'Client',
  appIcon: '',
  summary: 'Second banner',
  body: 'The second stacked banner card.',
  actions: <DesktopNotificationAction>[],
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
  expireTimeoutMs: 0,
);

void main() {
  testWidgets('banner input region settles above a client window', (
    tester,
  ) async {
    final bridge = _InputLayoutRecordingBridge();
    addTearDown(bridge.dispose);
    await tester.pumpWidget(_bannerScene(bridge));
    final controller = _notificationsControllerOf(tester);
    controller.retainOnly(const [_firstNotification]);
    await tester.pumpAndSettle();
    await tester.pump();

    final cardRect = tester.getRect(find.byType(NotificationCard));
    expect(cardRect.isEmpty, isFalse);

    final snapshot = bridge.snapshots.last;
    expect(snapshot.windows, hasLength(1));
    final windowRect = snapshot.windows.single.rect;
    expect(cardRect.overlaps(windowRect), isTrue);

    final bannerRegion = _regionMatching(snapshot, cardRect);
    expect(bannerRegion, isNotNull);
    expect(bannerRegion!.overlaps(windowRect), isTrue);
  });

  testWidgets('stacked banners re-report regions when a sibling exits', (
    tester,
  ) async {
    final bridge = _InputLayoutRecordingBridge();
    addTearDown(bridge.dispose);
    await tester.pumpWidget(_bannerScene(bridge));
    final controller = _notificationsControllerOf(tester);
    controller.retainOnly(const [_firstNotification, _secondNotification]);
    await tester.pumpAndSettle();
    await tester.pump();

    final secondCardBefore = tester.getRect(_secondCardFinder());
    expect(
      _regionMatching(bridge.snapshots.last, secondCardBefore),
      isNotNull,
    );

    controller.retainOnly(const [_secondNotification]);
    await tester.pumpAndSettle();
    await tester.pump();

    final secondCardAfter = tester.getRect(_secondCardFinder());
    expect(secondCardAfter.top, lessThan(secondCardBefore.top));
    expect(
      _regionMatching(bridge.snapshots.last, secondCardAfter),
      isNotNull,
    );
  });
}

Widget _bannerScene(_InputLayoutRecordingBridge bridge) {
  return ProviderScope(
    overrides: [
      denialBridgeProvider.overrideWithValue(bridge),
      shellControllerProvider.overrideWith(_ShellControllerWithWindow.new),
      desktopNotificationsProvider.overrideWith(
        _BannerNotificationsController.new,
      ),
      shellSettingsProvider.overrideWith(_DefaultShellSettingsController.new),
      displayLayoutProvider.overrideWithBuild((ref, controller) => null),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: ShellTheme(
        data: const ShellThemeData(),
        child: DesktopInputLayoutPublisher(
          child: const NotificationBannerLayer(),
        ),
      ),
    ),
  );
}

Finder _secondCardFinder() {
  return find.descendant(
    of: find.byKey(const ValueKey<int>(2)),
    matching: find.byType(NotificationCard),
  );
}

_BannerNotificationsController _notificationsControllerOf(WidgetTester tester) {
  final container = ProviderScope.containerOf(
    tester.element(find.byType(NotificationBannerLayer)),
  );
  return container.read(desktopNotificationsProvider.notifier)
      as _BannerNotificationsController;
}

/// Finds the shell region published for a banner card: same top-left corner
/// and width as the rendered card, with the card fully covered. The stacked
/// banner gap adds a little height below the card itself.
Rect? _regionMatching(InputLayoutSnapshot snapshot, Rect cardRect) {
  for (final region in snapshot.shellRegions) {
    final topLeftMatches =
        (region.left - cardRect.left).abs() < 0.5 &&
        (region.top - cardRect.top).abs() < 0.5;
    final sizeMatches =
        (region.width - cardRect.width).abs() < 0.5 &&
        region.height >= cardRect.height - 0.5 &&
        region.height <= cardRect.height + 12.5;
    if (topLeftMatches && sizeMatches) {
      return region;
    }
  }
  return null;
}

class _InputLayoutRecordingBridge extends DenialBridge {
  final List<InputLayoutSnapshot> snapshots = <InputLayoutSnapshot>[];

  @override
  bool publishInputLayout(InputLayoutSnapshot snapshot) {
    snapshots.add(snapshot);
    return true;
  }
}

class _ShellControllerWithWindow extends ShellController {
  @override
  ShellState build() {
    return ShellState(
      windows: const [_windowUnderBanner],
      windowSnapshotSequence: 1,
      overviewVisible: false,
      gestureDrag: Offset.zero,
      quickSettingsVisible: false,
      quickSettingsDrag: Offset.zero,
      quickSettingsDragActive: false,
      edgePanelVisible: false,
      edgePanelDrag: Offset.zero,
      edgePanelDragActive: false,
      edgePanelViewportScroll: 0.0,
      locked: false,
      lockLayerVisible: false,
      foregroundObjectId: null,
      launchingObjectId: null,
      launchRequest: null,
      homeTransitionActive: false,
    );
  }
}

class _DefaultShellSettingsController extends ShellSettingsController {
  @override
  ShellSettings build() => const ShellSettings();
}

class _BannerNotificationsController extends DesktopNotificationsController {
  List<DesktopNotification> _notifications = const <DesktopNotification>[];

  @override
  DesktopNotificationsState build() => _stateFor(_notifications);

  void retainOnly(List<DesktopNotification> next) {
    _notifications = next;
    state = _stateFor(next);
  }
}

DesktopNotificationsState _stateFor(List<DesktopNotification> notifications) {
  return DesktopNotificationsState(
    active: <int, DesktopNotification>{
      for (final notification in notifications) notification.id: notification,
    },
    bannerQueue: <int>[
      for (final notification in notifications) notification.id,
    ],
  );
}
