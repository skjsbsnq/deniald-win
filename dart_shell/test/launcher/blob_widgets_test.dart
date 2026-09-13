import 'dart:io';

import 'package:denial_dart_shell/l10n/generated/app_localizations.dart';
import 'package:denial_dart_shell/src/launcher/controllers/home_grid_layout.dart';
import 'package:denial_dart_shell/src/launcher/controllers/home_grid_controller.dart';
import 'package:denial_dart_shell/src/launcher/models/home_clock_info.dart';
import 'package:denial_dart_shell/src/launcher/models/home_grid_item.dart';
import 'package:denial_dart_shell/src/launcher/repositories/home_layout_repository.dart';
import 'package:denial_dart_shell/src/launcher/runtime_paths.dart';
import 'package:denial_dart_shell/src/launcher/widgets/home_tiles.dart';
import 'package:denial_dart_shell/src/models/battery_status.dart';
import 'package:denial_dart_shell/src/services/weather_service.dart';
import 'package:denial_dart_shell/src/settings/settings_controller.dart';
import 'package:denial_dart_shell/src/settings/shell_settings.dart';
import 'package:denial_dart_shell/src/state/desktop_notifications.dart';
import 'package:denial_dart_shell/src/state/system_status.dart';
import 'package:denial_dart_shell/src/state/weather_state.dart';
import 'package:denial_dart_shell/src/theme/shell_theme.dart';
import 'package:denial_dart_shell/src/widgets/desktop_widgets/desktop_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

HomeClockInfo _clock() => HomeClockInfo(
  now: DateTime(2026, 9, 9, 14, 30),
  locale: 'en',
  power: HomePowerStatus.unknown,
);

Widget _wrap(Widget child, {List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: ShellTheme(
          data: const ShellThemeData(),
          child: Center(
            child: SizedBox(width: 320, height: 180, child: child),
          ),
        ),
      ),
    ),
  );
}

class _FixedBattery extends BatteryController {
  @override
  BatteryStatus build() =>
      const BatteryStatus(capacity: 84, charging: true, acOnline: true);
}

class _FixedWeather extends WeatherController {
  @override
  WeatherState build() {
    return WeatherState(
      status: WeatherStatus.ready,
      snapshot: WeatherSnapshot(
        location: const GeoLocation(
          latitude: 39.9,
          longitude: 116.4,
          city: 'Beijing',
        ),
        current: WeatherCurrent(
          temperatureC: 26.4,
          apparentTemperatureC: 28.1,
          weatherCode: 0,
          humidityPercent: 40,
          windSpeedMs: 3,
          windDirectionDeg: 90,
          uvIndex: 2,
          pressureHpa: 1013,
          visibilityM: 10000,
        ),
        hours: const [],
        days: const [],
        airQuality: null,
        fetchedAt: DateTime(2026, 9, 9, 14, 0),
      ),
    );
  }

  @override
  Future<void> refresh() async {}
}

class _FixedSettings extends ShellSettingsController {
  @override
  ShellSettings build() => const ShellSettings();
}

class _FakeNotifications extends DesktopNotificationsController {
  @override
  DesktopNotificationsState build() => const DesktopNotificationsState();
}

void main() {
  group('BlobClockWidget', () {
    testWidgets('renders the analog dial and day/month badges', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(BlobClockWidget(clock: _clock(), showStatus: false)),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CustomPaint), findsWidgets);
      // Day badge `9`, month badge `09` (2026-09-09).
      expect(find.text('9'), findsOneWidget);
      expect(find.text('09'), findsOneWidget);
    });
  });

  group('HomeGridItemCard dispatch (shared by home grid and desktop canvas)', () {
    testWidgets('clock item mounts the blob clock', (tester) async {
      await tester.pumpWidget(
        _wrap(
          HomeGridItemCard(item: HomeGridItem.clock(), onLaunch: (_) {}),
          overrides: [homeClockProvider.overrideWithValue(_clock())],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(BlobClockWidget), findsOneWidget);
      expect(find.byType(HomeClockWidget), findsNothing);
    });

    testWidgets('weather item mounts the weather blob', (tester) async {
      await tester.pumpWidget(
        _wrap(
          HomeGridItemCard(item: HomeGridItem.weather(), onLaunch: (_) {}),
          overrides: [
            weatherProvider.overrideWith(_FixedWeather.new),
            shellSettingsProvider.overrideWith(_FixedSettings.new),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(BlobWeatherWidget), findsOneWidget);
      expect(find.text('26°'), findsOneWidget);
      expect(find.text('Beijing'), findsOneWidget);
    });

    testWidgets('battery item mounts the battery blob', (tester) async {
      await tester.pumpWidget(
        _wrap(
          HomeGridItemCard(item: HomeGridItem.battery(), onLaunch: (_) {}),
          overrides: [batteryProvider.overrideWith(_FixedBattery.new)],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(BlobBatteryWidget), findsOneWidget);
      expect(find.text('84%'), findsOneWidget);
    });

    testWidgets('quick-actions item mounts the pill row', (tester) async {
      await tester.pumpWidget(
        _wrap(
          HomeGridItemCard(
            item: HomeGridItem.quickActions(),
            onLaunch: (_) {},
          ),
          overrides: [
            desktopNotificationsProvider.overrideWith(_FakeNotifications.new),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(QuickActionPillRow), findsOneWidget);
      expect(find.byIcon(Icons.screenshot_monitor_rounded), findsOneWidget);
      expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
      expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
      expect(find.byIcon(Icons.power_settings_new_rounded), findsOneWidget);
    });

    testWidgets('widgets render under a shared BackdropGroup (desktop path)', (
      tester,
    ) async {
      // _DesktopWidgetCanvas wraps every widget in BackdropGroup so sibling
      // blurs share one engine backdrop; this pins that contract.
      await tester.pumpWidget(
        _wrap(
          BackdropGroup(
            child: Column(
              children: [
                Expanded(
                  child: HomeGridItemCard(
                    item: HomeGridItem.clock(),
                    onLaunch: (_) {},
                  ),
                ),
                Expanded(
                  child: HomeGridItemCard(
                    item: HomeGridItem.battery(),
                    onLaunch: (_) {},
                  ),
                ),
              ],
            ),
          ),
          overrides: [
            homeClockProvider.overrideWithValue(_clock()),
            batteryProvider.overrideWith(_FixedBattery.new),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(BlobClockWidget), findsOneWidget);
      expect(find.byType(BlobBatteryWidget), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('HomeGridItem widget types', () {
    test('new factories clamp spans and stay resizable', () {
      final weather = HomeGridItem.weather(colSpan: 99, rowSpan: 0);
      expect(weather.type, HomeGridItemType.weather);
      expect(weather.id, 'widget:weather');
      expect(weather.colSpan, HomeGridItem.weatherMaxColSpan);
      expect(weather.rowSpan, HomeGridItem.weatherMinRowSpan);
      expect(weather.resizable, isTrue);

      final battery = HomeGridItem.battery(colSpan: 1, rowSpan: 2);
      expect(battery.id, 'widget:battery');
      expect(battery.colSpan, 1);
      expect(battery.rowSpan, 2);

      final actions = HomeGridItem.quickActions(colSpan: 4, rowSpan: 9);
      expect(actions.id, 'widget:quick-actions');
      expect(actions.rowSpan, HomeGridItem.quickActionsMaxRowSpan);
    });

    test('resize round-trips through the new types', () {
      final resized = HomeGridItem.weather().resize(colSpan: 3, rowSpan: 2);
      expect(resized.type, HomeGridItemType.weather);
      expect(resized.colSpan, 3);
      expect(resized.rowSpan, 2);
    });
  });

  group('legacy layout persistence', () {
    test('old layout json with only legacy ids still parses', () async {
      final temp = await Directory.systemTemp.createTemp('blob-widget-test');
      addTearDown(() => temp.delete(recursive: true));
      final paths = RuntimePaths(
        environment: <String, String>{
          'HOME': temp.path,
          'XDG_CONFIG_HOME': '${temp.path}/config',
        },
      );
      final layoutDir = Directory('${temp.path}/config/denia-home');
      await layoutDir.create(recursive: true);
      await File(
        '${layoutDir.path}/layout.json',
      ).writeAsString(
        '{"version":2,"slots":["widget:clock",'
        '{"id":"widget:battery-discharge","colSpan":3,"rowSpan":2},'
        'null,"app:demo.app"]}\n',
      );

      final slots = await HomeLayoutRepository(
        paths: paths,
      ).readSavedLayout();
      expect(slots, isNotNull);
      expect(slots!.length, 4);
      expect(slots[0]?.id, 'widget:clock');
      expect(slots[1]?.id, 'widget:battery-discharge');
      expect(slots[1]?.colSpan, 3);
      expect(slots[2], isNull);
      expect(slots[3]?.id, 'app:demo.app');
    });

    test('legacy saved layout still resolves widget items', () {
      final slots = HomeGridLayout.initialSlotsForApps(
        const [],
        const [],
        const [
          HomeLayoutSlot(id: 'widget:clock'),
          HomeLayoutSlot(id: 'widget:battery-discharge', colSpan: 3),
        ],
      );
      final items = slots.whereType<HomeGridItem>().toList();
      expect(
        items.map((item) => item.id),
        containsAll(<String>['widget:clock', 'widget:battery-discharge']),
      );
    });
  });
}
