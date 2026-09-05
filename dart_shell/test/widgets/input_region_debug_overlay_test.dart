import 'package:denial_dart_shell/l10n/generated/app_localizations.dart';
import 'package:denial_dart_shell/src/config/startup_environment.dart';
import 'package:denial_dart_shell/src/desktop/desktop_input_layout_publisher.dart';
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
import 'package:denial_dart_shell/src/widgets/input_region_debug_overlay.dart';
import 'package:denial_dart_shell/src/widgets/notification_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderCustomPaint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _debugWindow = DenialWindow(
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

const _debugNotification = DesktopNotification(
  id: 1,
  sender: 'test',
  appName: 'Client',
  appIcon: '',
  summary: 'Debug banner',
  body: 'Mirrors a published input layout snapshot.',
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
  testWidgets('overlay stays dormant without the debug flag', (tester) async {
    final bridge = _NoopBridge();
    addTearDown(bridge.dispose);
    await tester.pumpWidget(_debugScene(bridge, debugFlag: false));
    await tester.pumpAndSettle();
    await tester.pump();

    expect(find.byType(InputRegionDebugOverlay), findsOneWidget);
    expect(_overlayPaintFinder(), findsNothing);
  });

  testWidgets('overlay paints the mirrored input layout', (tester) async {
    final bridge = _NoopBridge();
    addTearDown(bridge.dispose);
    await tester.pumpWidget(_debugScene(bridge, debugFlag: true));
    final controller =
        ProviderScope.containerOf(
              tester.element(find.byType(NotificationBannerLayer)),
            ).read(desktopNotificationsProvider.notifier)
            as _DebugNotificationsController;
    controller.retainOnly(const [_debugNotification]);
    await tester.pumpAndSettle();
    await tester.pump();

    final renderObject = tester.renderObject<RenderCustomPaint>(
      _overlayPaintFinder(),
    );
    expect(renderObject.foregroundPainter, isNotNull);
  });
}

Finder _overlayPaintFinder() {
  return find.descendant(
    of: find.byType(InputRegionDebugOverlay),
    matching: find.byType(CustomPaint),
  );
}

Widget _debugScene(DenialBridge bridge, {required bool debugFlag}) {
  return ProviderScope(
    overrides: [
      denialBridgeProvider.overrideWithValue(bridge),
      startupEnvironmentProvider.overrideWithValue(
        StartupEnvironment(
          debugFlag
              ? <String, String>{'DENIA_DEBUG_INPUT_REGIONS': '1'}
              : <String, String>{},
        ),
      ),
      shellControllerProvider.overrideWith(_DebugShellController.new),
      desktopNotificationsProvider.overrideWith(
        _DebugNotificationsController.new,
      ),
      shellSettingsProvider.overrideWith(_DebugSettingsController.new),
      displayLayoutProvider.overrideWithBuild((ref, controller) => null),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: ShellTheme(
        data: const ShellThemeData(),
        child: DesktopInputLayoutPublisher(
          child: Stack(
            fit: StackFit.expand,
            children: const <Widget>[
              NotificationBannerLayer(),
              InputRegionDebugOverlay(),
            ],
          ),
        ),
      ),
    ),
  );
}

class _NoopBridge extends DenialBridge {}

class _DebugShellController extends ShellController {
  @override
  ShellState build() {
    return ShellState(
      windows: const [_debugWindow],
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

class _DebugSettingsController extends ShellSettingsController {
  @override
  ShellSettings build() => const ShellSettings();
}

class _DebugNotificationsController extends DesktopNotificationsController {
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
