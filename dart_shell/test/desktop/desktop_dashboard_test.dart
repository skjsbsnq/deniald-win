import 'package:denial_dart_shell/src/desktop/desktop_dashboard_wifi_card.dart';
import 'package:denial_dart_shell/src/desktop/desktop_shell.dart';
import 'package:denial_dart_shell/src/desktop/desktop_workspace.dart';
import 'package:denial_dart_shell/src/localization/denial_localizations.dart';
import 'package:denial_dart_shell/src/services/power_profile_service.dart';
import 'package:denial_dart_shell/src/state/bluetooth.dart';
import 'package:denial_dart_shell/src/state/desktop_notifications.dart';
import 'package:denial_dart_shell/src/state/desktop_power_modes.dart';
import 'package:denial_dart_shell/src/state/network_connectivity.dart';
import 'package:denial_dart_shell/src/state/quick_settings.dart';
import 'package:denial_dart_shell/src/theme/tokens.dart';
import 'package:denial_dart_shell/src/widgets/shade/range_bar.dart';
import 'package:flutter/material.dart' show Icons, Material, MaterialType;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// The panel DesktopMetrics.dashboardRect resolves to on the reference output
// (2560x1600 at scale 1.5). The column is a fixed height with two Expanded
// cards at the bottom, so whatever a new fixed card above them costs comes out
// of those two.
const Size _panelSize = Size(470, DesktopMetrics.dashboardHeight);

// Wi-Fi and Bluetooth both fall back to an icon-over-caption empty state that
// measures 82 px, on top of the card's 32 px of padding, a 34 px header row and
// a 12 px gap. Below this the empty state overflows — silently, because a
// release build clips a RenderFlex overflow without a stripe or a log, so this
// number is the only thing standing between a new card and an invisible defect.
const double _flexibleCardFloor = 160.0;

void main() {
  testWidgets('dashboard fits its panel with the brightness bar installed', (
    tester,
  ) async {
    await _pumpDashboard(tester);

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(DesktopDashboard)).height,
      _panelSize.height,
    );
  });

  testWidgets('brightness sits between volume and power modes', (tester) async {
    await _pumpDashboard(tester);

    final bars = _bars(tester);
    final volumeY = tester.getTopLeft(find.byWidget(bars.volume)).dy;
    final brightnessY = tester.getTopLeft(find.byWidget(bars.brightness)).dy;
    final powerModesY = tester.getTopLeft(find.text('Power modes')).dy;

    expect(brightnessY, greaterThan(volumeY));
    expect(brightnessY, lessThan(powerModesY));
  });

  testWidgets('each slider tracks its own quick-settings value', (
    tester,
  ) async {
    await _pumpDashboard(tester, brightness: 0.42, volume: 0.15);

    final bars = _bars(tester);
    expect(bars.brightness.value, 0.42);
    expect(bars.volume.value, 0.15);
  });

  testWidgets('power modes card offers the system profile row only', (
    tester,
  ) async {
    await _pumpDashboard(tester);

    expect(find.text('System profile'), findsOneWidget);
    expect(find.textContaining('PBO'), findsNothing);
    expect(find.textContaining('GPU'), findsNothing);
  });

  testWidgets('brightness is labelled and read out like volume', (
    tester,
  ) async {
    await _pumpDashboard(tester, brightness: 0.8, volume: 0.35);

    final brightnessLabel = find.text('Brightness');
    expect(brightnessLabel, findsOneWidget);
    expect(find.text('80%'), findsOneWidget);
    expect(find.text('35%'), findsOneWidget);

    // The label belongs to the brightness card, not the volume one: it has to
    // sit between the volume slider and the brightness slider it names.
    final bars = _bars(tester);
    expect(
      tester.getTopLeft(brightnessLabel).dy,
      greaterThan(tester.getTopLeft(find.byWidget(bars.volume)).dy),
    );
    expect(
      tester.getTopLeft(brightnessLabel).dy,
      lessThan(tester.getTopLeft(find.byWidget(bars.brightness)).dy),
    );
  });

  testWidgets('the brightness readout follows the slider', (tester) async {
    await _pumpDashboard(tester, brightness: 0.42);

    expect(find.text('42%'), findsOneWidget);
  });

  testWidgets('the flexible cards keep room for their empty state', (
    tester,
  ) async {
    await _pumpDashboard(tester);

    // Wi-Fi and Bluetooth are the column's only flexible children and share the
    // remainder evenly, so measuring one covers both. Asserting the floor and
    // not just the absence of an overflow keeps the next card added above them
    // from landing a pixel short of it.
    expect(
      tester.getSize(find.byType(DesktopDashboardWifiCard)).height,
      greaterThanOrEqualTo(_flexibleCardFloor),
    );
  });

  // The shell ships in Chinese too, and the empty-state captions are the tallest
  // thing in either flexible card. English wraps them to two lines and is the
  // demanding case, but nothing guarantees that stays true, and a release build
  // clips the resulting overflow without a trace.
  testWidgets('the column also fits with Chinese captions', (tester) async {
    await _pumpDashboard(tester, locale: const Locale('zh'));

    expect(tester.takeException(), isNull);
    expect(find.text('亮度'), findsOneWidget);
    expect(
      tester.getSize(find.byType(DesktopDashboardWifiCard)).height,
      greaterThanOrEqualTo(_flexibleCardFloor),
    );
  });
}

({RangeBar brightness, RangeBar volume}) _bars(WidgetTester tester) {
  final bars = tester.widgetList<RangeBar>(find.byType(RangeBar)).toList();
  expect(bars, hasLength(2));
  // Both tracks use the same inactive colour, so the glyph is what tells them
  // apart.
  return (
    brightness: bars.singleWhere(
      (bar) => bar.icon == Icons.brightness_6_rounded,
    ),
    volume: bars.singleWhere((bar) => bar.icon == Icons.volume_up_rounded),
  );
}

Future<void> _pumpDashboard(
  WidgetTester tester, {
  double brightness = 0.8,
  double volume = 0.35,
  Locale? locale,
}) async {
  tester.view.physicalSize = _panelSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        quickSettingsProvider.overrideWithBuild(
          (ref, controller) => QuickSettingsState(
            brightness: brightness,
            volume: volume,
            rotationLock: false,
            profile: 'balanced',
            screenshotRunning: false,
          ),
        ),
        bluetoothProvider.overrideWithBuild(
          (ref, controller) => BluetoothState.initial(),
        ),
        desktopNotificationsProvider.overrideWithBuild(
          (ref, controller) => const DesktopNotificationsState(),
        ),
        desktopPowerModesProvider.overrideWithBuild(
          (ref, controller) => const DesktopPowerModesState(
            systemAvailable: true,
            systemProfile: PowerProfile.balanced,
            pboAvailable: false,
            pboProfile: null,
            gpuAvailable: false,
            gpuPerformancePreset: null,
            refreshing: false,
            systemChanging: false,
            pboChanging: false,
            gpuChanging: false,
          ),
        ),
        networkConnectivityProvider.overrideWithBuild(
          (ref, controller) => NetworkConnectivityState.initial(),
        ),
      ],
      child: DenialLocalizationScope(
        locale: locale,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: DefaultTextStyle(
            style: ShellText.base,
            child: Material(
              type: MaterialType.transparency,
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox.fromSize(
                  size: _panelSize,
                  child: DesktopDashboard(
                    onEnter: () {},
                    onExit: () {},
                    onOpenWallpaper: () {},
                    onOpenAppVolumeManager: () {},
                    onOpenSettings: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}
