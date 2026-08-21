import 'dart:ui' show PointerDeviceKind;

import 'package:denial_dart_shell/src/desktop/desktop_status_cluster.dart';
import 'package:denial_dart_shell/src/desktop/desktop_input_method.dart';
import 'package:denial_dart_shell/src/desktop/desktop_workspace.dart';
import 'package:denial_dart_shell/src/input/shell_interaction_registry.dart';
import 'package:denial_dart_shell/src/localization/denial_localizations.dart';
import 'package:denial_dart_shell/src/models/battery_status.dart';
import 'package:denial_dart_shell/src/services/network_manager_service.dart';
import 'package:denial_dart_shell/src/services/fcitx5_service.dart';
import 'package:denial_dart_shell/src/state/fcitx5.dart';
import 'package:denial_dart_shell/src/state/network_connectivity.dart';
import 'package:denial_dart_shell/src/state/quick_settings.dart';
import 'package:denial_dart_shell/src/state/system_status.dart';
import 'package:denial_dart_shell/src/wallpaper/state/wallpaper_accent.dart';
import 'package:denial_dart_shell/src/widgets/shade/status_glyphs.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DesktopStatusCluster', () {
    testWidgets(
      'renders network, volume, and battery when battery data is present',
      (tester) async {
        await _pumpCluster(
          tester,
          battery: const BatteryStatus(capacity: 85, charging: false),
          volume: 0.65,
          networkSnapshot: NetworkManagerSnapshot(
            serviceAvailable: true,
            wifiDeviceAvailable: true,
            wirelessHardwareEnabled: true,
            wirelessEnabled: true,
            status: NetworkConnectivityStatus.online,
            networks: [
              WifiNetwork(
                ssid: 'Denial-5G',
                ssidBytes: [68, 101, 110, 105, 97, 108, 45, 53, 71],
                security: WifiSecurity.wpaPersonal,
                strength: 85,
                frequency: 5180,
                devicePath: '/device/0',
                accessPointPath: '/ap/0',
                savedConnectionPath: '/saved/0',
                connected: true,
                available: true,
              ),
            ],
            activeConnectionPath: '/active/0',
            devicePath: '/device/0',
            lastScan: 100,
            radioPermission: NetworkPermission.allowed,
            controlPermission: NetworkPermission.allowed,
            modifyPermission: NetworkPermission.allowed,
          ),
        );

        expect(find.byType(DesktopStatusCluster), findsOneWidget);
        expect(find.text('EN'), findsOneWidget);
        expect(find.byIcon(Icons.translate_rounded), findsOneWidget);
        expect(find.byIcon(Icons.wifi_rounded), findsOneWidget);
        expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);
        expect(find.byType(BatteryIconMark), findsOneWidget);
        expect(find.byIcon(Icons.tune_rounded), findsOneWidget);

        // Verify accessibility semantics
        expect(
          find.bySemanticsLabel(RegExp(r'Denial-5G.*85%')),
          findsOneWidget,
        );
        expect(find.bySemanticsLabel(RegExp(r'65%')), findsOneWidget);
        expect(find.bySemanticsLabel(RegExp(r'85%')), findsOneWidget);
      },
    );

    testWidgets('places the live input method mark before Wi-Fi', (
      tester,
    ) async {
      await _pumpCluster(
        tester,
        inputMethod: const Fcitx5Snapshot(
          available: true,
          inputMethod: 'pinyin',
          label: 'Pinyin',
          languageCode: 'zh_CN',
        ),
      );

      final inputX = tester.getTopLeft(find.byType(DesktopInputMethodMark)).dx;
      final inputIconX = tester
          .getTopLeft(find.byIcon(Icons.translate_rounded))
          .dx;
      final wifiX = tester.getTopLeft(find.byIcon(Icons.wifi_rounded)).dx;
      expect(find.text('\u4e2d'), findsOneWidget);
      expect(inputIconX, lessThan(wifiX));
      expect(inputX, lessThan(wifiX));
    });

    testWidgets('omits battery icon when device has no battery data', (
      tester,
    ) async {
      await _pumpCluster(tester, battery: BatteryStatus.unknown, volume: 0.5);

      expect(find.byType(BatteryIconMark), findsNothing);
      expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);
    });

    testWidgets('shows charging battery semantics when charging', (
      tester,
    ) async {
      await _pumpCluster(
        tester,
        battery: const BatteryStatus(capacity: 92, charging: true),
        volume: 0.5,
      );

      expect(find.byType(BatteryIconMark), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp(r'92%.*(charging|正在充电)')),
        findsOneWidget,
      );
    });

    testWidgets('reflects volume mute and percentage states', (tester) async {
      // Muted
      await _pumpCluster(tester, volume: 0.0);
      expect(find.byIcon(Icons.volume_off_rounded), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp(r'(muted|静音)', caseSensitive: false)),
        findsOneWidget,
      );

      // Mid volume
      await _pumpCluster(tester, volume: 0.35);
      expect(find.byIcon(Icons.volume_down_rounded), findsOneWidget);

      // High volume
      await _pumpCluster(tester, volume: 0.80);
      expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);
    });

    testWidgets('reflects WiFi signal strength levels', (tester) async {
      // 0% / minimum signal
      await _pumpCluster(
        tester,
        networkSnapshot: _makeSnapshot(
          status: NetworkConnectivityStatus.online,
          strength: 0,
        ),
      );
      expect(find.byIcon(Icons.network_wifi_1_bar_rounded), findsOneWidget);

      // Weak signal (20%)
      await _pumpCluster(
        tester,
        networkSnapshot: _makeSnapshot(
          status: NetworkConnectivityStatus.online,
          strength: 20,
        ),
      );
      expect(find.byIcon(Icons.network_wifi_1_bar_rounded), findsOneWidget);

      // Medium signal (50%)
      await _pumpCluster(
        tester,
        networkSnapshot: _makeSnapshot(
          status: NetworkConnectivityStatus.online,
          strength: 50,
        ),
      );
      expect(find.byIcon(Icons.network_wifi_2_bar_rounded), findsOneWidget);

      // Strong signal (90%)
      await _pumpCluster(
        tester,
        networkSnapshot: _makeSnapshot(
          status: NetworkConnectivityStatus.online,
          strength: 90,
        ),
      );
      expect(find.byIcon(Icons.wifi_rounded), findsOneWidget);
    });

    testWidgets('reflects network disconnected and disabled states', (
      tester,
    ) async {
      // Disconnected
      await _pumpCluster(
        tester,
        networkSnapshot: _makeSnapshot(
          status: NetworkConnectivityStatus.disconnected,
        ),
      );
      expect(find.byIcon(Icons.signal_wifi_off_rounded), findsOneWidget);

      // Disabled / Wi-Fi off
      await _pumpCluster(
        tester,
        networkSnapshot: _makeSnapshot(
          status: NetworkConnectivityStatus.disabled,
          wirelessEnabled: false,
        ),
      );
      expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);

      // Service unavailable
      await _pumpCluster(
        tester,
        networkSnapshot: const NetworkManagerSnapshot.unavailable(),
      );
      expect(find.byIcon(Icons.signal_wifi_off_rounded), findsOneWidget);
    });

    testWidgets('publishes input region with debug label', (tester) async {
      await _pumpCluster(tester);
      final region = tester.widget<ShellInputRegion>(
        find.descendant(
          of: find.byType(DesktopStatusCluster),
          matching: find.byType(ShellInputRegion),
        ),
      );
      expect(region.debugLabel, 'Desktop status cluster');
    });

    testWidgets('triggers onTap callback when tapped', (tester) async {
      var tapped = 0;
      await _pumpCluster(tester, onTap: () => tapped++);

      expect(tapped, 0);
      await tester.tap(find.byType(DesktopStatusCluster));
      expect(tapped, 1);
    });

    testWidgets(
      'semantics label switches based on dashboardOpen state in en & zh',
      (tester) async {
        // English closed
        await _pumpCluster(tester, panel: DesktopPanel.none);
        expect(
          find.bySemanticsLabel(RegExp(r'Open control center')),
          findsOneWidget,
        );

        // English open
        await _pumpCluster(tester, panel: DesktopPanel.dashboard);
        expect(
          find.bySemanticsLabel(RegExp(r'Close control center')),
          findsOneWidget,
        );

        // Chinese closed
        await _pumpCluster(
          tester,
          panel: DesktopPanel.none,
          locale: const Locale('zh'),
        );
        expect(find.bySemanticsLabel(RegExp(r'打开控制中心')), findsOneWidget);

        // Chinese open
        await _pumpCluster(
          tester,
          panel: DesktopPanel.dashboard,
          locale: const Locale('zh'),
        );
        expect(find.bySemanticsLabel(RegExp(r'关闭控制中心')), findsOneWidget);
      },
    );

    testWidgets('supports keyboard activation via Enter and Space keys', (
      tester,
    ) async {
      var activated = 0;
      await _pumpCluster(tester, onTap: () => activated++);

      // Focus the widget
      final mouseRegionFinder = find.descendant(
        of: find.byType(DesktopStatusCluster),
        matching: find.byType(MouseRegion),
      );
      expect(mouseRegionFinder, findsWidgets);
      Focus.of(tester.element(mouseRegionFinder.first)).requestFocus();
      await tester.pumpAndSettle();

      // Send Enter key
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(activated, 1);

      // Send Space key
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(activated, 2);
    });

    testWidgets('animates background pill color on hover and press', (
      tester,
    ) async {
      await _pumpCluster(tester);

      final containerFinder = find.descendant(
        of: find.byType(DesktopStatusCluster),
        matching: find.byType(AnimatedContainer),
      );
      expect(containerFinder, findsOneWidget);

      // Initial state: transparent background
      var container = tester.widget<AnimatedContainer>(containerFinder);
      var decoration = container.decoration! as BoxDecoration;
      expect(decoration.color, const Color(0x00000000));

      // Pointer enter (hover)
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      await gesture.moveTo(tester.getCenter(find.byType(DesktopStatusCluster)));
      await tester.pumpAndSettle();

      container = tester.widget<AnimatedContainer>(containerFinder);
      decoration = container.decoration! as BoxDecoration;
      expect((decoration.color!).a, greaterThan(0));

      // Pointer exit
      await gesture.moveTo(const Offset(999, 999));
      await tester.pumpAndSettle();
      container = tester.widget<AnimatedContainer>(containerFinder);
      decoration = container.decoration! as BoxDecoration;
      expect(decoration.color, const Color(0x00000000));

      await gesture.removePointer();
    });
  });
}

NetworkManagerSnapshot _makeSnapshot({
  required NetworkConnectivityStatus status,
  int strength = 80,
  bool wirelessEnabled = true,
}) {
  return NetworkManagerSnapshot(
    serviceAvailable: true,
    wifiDeviceAvailable: true,
    wirelessHardwareEnabled: true,
    wirelessEnabled: wirelessEnabled,
    status: status,
    networks: [
      WifiNetwork(
        ssid: 'Home-WiFi',
        ssidBytes: [72, 111, 109, 101],
        security: WifiSecurity.wpaPersonal,
        strength: strength,
        frequency: 2412,
        devicePath: '/dev/0',
        accessPointPath: '/ap/0',
        savedConnectionPath: '/saved/0',
        connected: status == NetworkConnectivityStatus.online,
        available: true,
      ),
    ],
    activeConnectionPath: status == NetworkConnectivityStatus.online
        ? '/active/0'
        : null,
    devicePath: '/dev/0',
    lastScan: 1,
    radioPermission: NetworkPermission.allowed,
    controlPermission: NetworkPermission.allowed,
    modifyPermission: NetworkPermission.allowed,
  );
}

Future<void> _pumpCluster(
  WidgetTester tester, {
  BatteryStatus battery = const BatteryStatus(capacity: 80, charging: false),
  double volume = 0.5,
  NetworkManagerSnapshot? networkSnapshot,
  bool horizontal = true,
  VoidCallback? onTap,
  DesktopPanel panel = DesktopPanel.none,
  Locale locale = const Locale('en'),
  Fcitx5Snapshot inputMethod = const Fcitx5Snapshot(
    available: true,
    inputMethod: 'keyboard-us',
    label: 'Keyboard - English (US)',
    languageCode: 'en',
  ),
}) async {
  final networkState = NetworkConnectivityState(
    snapshot:
        networkSnapshot ??
        _makeSnapshot(status: NetworkConnectivityStatus.online),
    initializing: false,
    scanning: false,
    radioChanging: false,
    busyNetworks: const <String>{},
  );

  final workspaceState = DesktopWorkspaceState.initial().copyWith(panel: panel);

  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        wallpaperAccentProvider.overrideWithBuild(
          (ref, controller) => const WallpaperAccent(Color(0xff64d8cb)),
        ),
        desktopWorkspaceProvider.overrideWithBuild(
          (ref, controller) => workspaceState,
        ),
        batteryProvider.overrideWithBuild((ref, controller) => battery),
        quickSettingsProvider.overrideWithBuild(
          (ref, controller) => QuickSettingsState(
            brightness: 0.8,
            volume: volume,
            rotationLock: false,
            profile: 'balanced',
            screenshotRunning: false,
          ),
        ),
        networkConnectivityProvider.overrideWithBuild(
          (ref, controller) => networkState,
        ),
        fcitx5Provider.overrideWithBuild((ref, controller) => inputMethod),
      ],
      child: MaterialApp(
        home: DenialLocalizationScope(
          locale: locale,
          child: Scaffold(
            body: DesktopStatusCluster(horizontal: horizontal, onTap: onTap),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
