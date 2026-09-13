import 'dart:async';

import 'package:dbus/dbus.dart';
import 'package:denial_dart_shell/l10n/generated/app_localizations.dart';
import 'package:denial_dart_shell/src/desktop/shelf/shelf_app_button.dart';
import 'package:denial_dart_shell/src/desktop/shelf/shelf_layer.dart';
import 'package:denial_dart_shell/src/desktop/shelf/unified_tray_button.dart';
import 'package:denial_dart_shell/src/launcher/controllers/home_grid_controller.dart';
import 'package:denial_dart_shell/src/launcher/models/home_grid_item.dart';
import 'package:denial_dart_shell/src/local_apps/local_flutter_application.dart';
import 'package:denial_dart_shell/src/models/battery_status.dart';
import 'package:denial_dart_shell/src/models/denial_window.dart';
import 'package:denial_dart_shell/src/models/system_tray_item.dart';
import 'package:denial_dart_shell/src/platform/denial_bridge.dart';
import 'package:denial_dart_shell/src/services/media_player_service.dart';
import 'package:denial_dart_shell/src/settings/settings_controller.dart';
import 'package:denial_dart_shell/src/settings/shell_settings.dart';
import 'package:denial_dart_shell/src/state/bluetooth.dart';
import 'package:denial_dart_shell/src/state/desktop_notifications.dart';
import 'package:denial_dart_shell/src/state/network_connectivity.dart';
import 'package:denial_dart_shell/src/state/pinned_apps.dart';
import 'package:denial_dart_shell/src/state/shell_controller.dart';
import 'package:denial_dart_shell/src/state/shell_state.dart';
import 'package:denial_dart_shell/src/state/system_status.dart';
import 'package:denial_dart_shell/src/state/system_tray.dart';
import 'package:denial_dart_shell/src/theme/shell_theme.dart';
import 'package:denial_dart_shell/src/theme/tokens.dart';
import 'package:denial_dart_shell/src/widgets/shell_backdrop_blur.dart';
import 'package:denial_dart_shell/src/widgets/shell_hover_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('floating shelf geometry', () {
    testWidgets('bar insets inside its track with extraLarge corners', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _shelfHarness(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: ShelfLayer(trayExpanded: ValueNotifier<bool>(false)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The layer still occupies the full 56 dp track: work-area geometry
      // is untouched by the floating treatment.
      final layerRect = tester.getRect(find.byType(ShelfLayer));
      expect(layerRect, const Rect.fromLTRB(0, 800 - 56, 1200, 800));

      // The painted bar floats: 8 dp off the left/right edges and 8 dp off
      // the bottom, leaving a 48 dp tall rounded surface.
      final blur = find.descendant(
        of: find.byType(ShelfLayer),
        matching: find.byType(ShellBackdropBlur),
      );
      final barRect = tester.getRect(blur);
      expect(barRect.left, moreOrLessEquals(8, epsilon: 0.5));
      expect(barRect.right, moreOrLessEquals(1200 - 8, epsilon: 0.5));
      expect(barRect.bottom, moreOrLessEquals(800 - 8, epsilon: 0.5));
      expect(barRect.height, moreOrLessEquals(56 - 8, epsilon: 0.5));

      final clip = tester.widget<ClipRRect>(
        find.descendant(of: blur, matching: find.byType(ClipRRect)).first,
      );
      expect(
        clip.borderRadius,
        const BorderRadius.all(Radius.circular(ShellShapeScale.extraLarge)),
      );
    });
  });

  group('shelf app indicator dots', () {
    Future<void> pumpButton(
      WidgetTester tester, {
      required int windowCount,
      bool isActive = false,
      bool isPinned = false,
    }) {
      return tester.pumpWidget(
        MaterialApp(
          home: ShellTheme(
            data: const ShellThemeData(),
            child: Center(
              child: ShelfAppButton(
                appId: 'org.example.test',
                icon: Icons.apps_rounded,
                windowCount: windowCount,
                isActive: isActive,
                isPinned: isPinned,
              ),
            ),
          ),
        ),
      );
    }

    double indicatorWidth(WidgetTester tester) =>
        tester.getSize(find.byKey(const ValueKey('shelf-app-indicator'))).width;

    testWidgets('pinned without windows shows no dot', (tester) async {
      await pumpButton(tester, windowCount: 0, isPinned: true);
      await tester.pumpAndSettle();
      expect(indicatorWidth(tester), 0);
    });

    testWidgets('running app shows a Ø4 dot', (tester) async {
      await pumpButton(tester, windowCount: 1);
      await tester.pumpAndSettle();
      expect(indicatorWidth(tester), 4);
    });

    testWidgets('active app shows a 16x4 capsule', (tester) async {
      await pumpButton(tester, windowCount: 1, isActive: true);
      await tester.pumpAndSettle();
      expect(indicatorWidth(tester), 16);
    });

    testWidgets('multiple windows show a two-dot lane', (tester) async {
      await pumpButton(tester, windowCount: 2);
      await tester.pumpAndSettle();
      // Two Ø4 dots plus the xs gap between them.
      expect(indicatorWidth(tester), 12);
    });
  });

  group('tray capsule color spring', () {
    testWidgets('status capsule glides to primary when expanded', (
      tester,
    ) async {
      await tester.pumpWidget(
        _trayHarness(
          child: UnifiedTrayButton(expanded: false, onPressed: () {}),
        ),
      );
      await tester.pumpAndSettle();

      final element = tester.element(find.byType(UnifiedTrayButton));
      final theme = element.shellTheme;
      final colors = element.shellColors;

      Color capsuleColor() => tester
          .widget<ShellHoverPill>(find.byType(ShellHoverPill).first)
          .color!;

      expect(capsuleColor(), colors.surfaceContainerHigh);

      await tester.pumpWidget(
        _trayHarness(
          child: UnifiedTrayButton(expanded: true, onPressed: () {}),
        ),
      );
      // One frame in, the effects spring is still mid-glide: the color must
      // not snap between the idle container and the expanded accent.
      await tester.pump(const Duration(milliseconds: 8));
      final mid = capsuleColor();
      expect(mid, isNot(colors.surfaceContainerHigh));
      expect(mid, isNot(theme.accentPalette.primary));

      await tester.pumpAndSettle();
      // The spring stops a hair short of the target, so compare at ARGB
      // precision rather than exact channel equality.
      expect(
        capsuleColor().toARGB32(),
        theme.accentPalette.primary.toARGB32(),
      );
    });
  });

  group('shelf media entry', () {
    testWidgets('hidden while no player is active', (tester) async {
      await tester.pumpWidget(
        _trayHarness(
          child: UnifiedTrayButton(expanded: false, onPressed: () {}),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.graphic_eq_rounded), findsNothing);
      expect(find.byIcon(Icons.music_note_rounded), findsNothing);
    });

    testWidgets('active player exposes the button and hover popup', (
      tester,
    ) async {
      final playback = MprisPlaybackState(
        serviceName: 'org.mpris.MediaPlayer2.test',
        identity: 'Test player',
        title: 'Test song',
        artists: const <String>['Test artist'],
        album: 'Test album',
        artUrl: '',
        length: const Duration(minutes: 3),
        position: const Duration(minutes: 1),
        observedAt: DateTime(2026, 9, 8, 14, 30),
        status: MprisPlaybackStatus.playing,
        canGoNext: true,
        canGoPrevious: true,
        canPlay: true,
        canPause: true,
      );
      await tester.pumpWidget(
        _trayHarness(
          mediaStream: Stream<MprisPlaybackState>.value(playback),
          child: UnifiedTrayButton(expanded: false, onPressed: () {}),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.graphic_eq_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.graphic_eq_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Test song'), findsOneWidget);
      expect(find.text('Test artist'), findsOneWidget);

      // Unmount so the popup's position ticker is cancelled before the
      // pending-timer invariant runs.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });
}

class _ShelfSettingsController extends ShellSettingsController {
  @override
  ShellSettings build() {
    return const ShellSettings(
      layout: ShellLayoutSettings(useChromeOsShelf: true),
    );
  }
}

class _ShelfShellController extends ShellController {
  @override
  ShellState build() {
    return ShellState(
      windows: const <DenialWindow>[],
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

class _ShelfPinnedApps extends PinnedAppsController {
  @override
  List<String> build() => const <String>[];
}

class _ShelfHomeGrid extends HomeGridController {
  @override
  Future<HomeGridState> build() async =>
      HomeGridState(slots: <HomeGridItem?>[]);
}

class _FakeBridge extends DenialBridge {}

class _FakeSystemTray extends SystemTrayController {
  @override
  List<SystemTrayItem> build() => const <SystemTrayItem>[];
}

class _FakeBattery extends BatteryController {
  @override
  BatteryStatus build() =>
      const BatteryStatus(capacity: 87, charging: false, full: true);
}

class _FakeNetwork extends NetworkConnectivityController {
  @override
  NetworkConnectivityState build() =>
      NetworkConnectivityState.initial().copyWith(initializing: false);
}

class _FakeBluetooth extends BluetoothController {
  @override
  BluetoothState build() =>
      BluetoothState.initial().copyWith(initializing: false);
}

class _FakeNotifications extends DesktopNotificationsController {
  @override
  DesktopNotificationsState build() => const DesktopNotificationsState();
}

List<Override> _trayOverrides({Stream<MprisPlaybackState>? mediaStream}) => [
  batteryProvider.overrideWith(_FakeBattery.new),
  clockProvider.overrideWith(
    (ref) => Stream<DateTime>.value(DateTime(2026, 9, 8, 14, 30)),
  ),
  bluetoothProvider.overrideWith(_FakeBluetooth.new),
  networkConnectivityProvider.overrideWith(_FakeNetwork.new),
  desktopNotificationsProvider.overrideWith(_FakeNotifications.new),
  // The media service is backed by an unconnected client so the button's
  // ref.read never spins up a session-bus connection inside fake async.
  mediaPlayerServiceProvider.overrideWith(
    (ref) => MediaPlayerService(
      client: DBusClient(DBusAddress('unix:path=/dev/null/denial-media-test')),
    ),
  ),
  mediaPlaybackProvider.overrideWith(
    (ref) => mediaStream ?? const Stream<MprisPlaybackState>.empty(),
  ),
];

Widget _trayHarness({required Widget child, Stream<MprisPlaybackState>? mediaStream}) {
  return ProviderScope(
    overrides: _trayOverrides(mediaStream: mediaStream),
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: ShellTheme(
        data: const ShellThemeData(),
        child: Center(child: child),
      ),
    ),
  );
}

Widget _shelfHarness({required Widget child}) {
  return ProviderScope(
    overrides: [
      denialBridgeProvider.overrideWithValue(_FakeBridge()),
      shellSettingsProvider.overrideWith(_ShelfSettingsController.new),
      shellControllerProvider.overrideWith(_ShelfShellController.new),
      pinnedAppsProvider.overrideWith(_ShelfPinnedApps.new),
      homeGridControllerProvider.overrideWith(_ShelfHomeGrid.new),
      localFlutterApplicationRegistryProvider.overrideWithValue(
        LocalFlutterApplicationRegistry(const <LocalFlutterApplication>[]),
      ),
      systemTrayProvider.overrideWith(_FakeSystemTray.new),
      ..._trayOverrides(),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: ShellTheme(
        data: const ShellThemeData(),
        child: child,
      ),
    ),
  );
}
