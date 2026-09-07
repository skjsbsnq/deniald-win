import 'package:denial_dart_shell/l10n/generated/app_localizations.dart';
import 'package:denial_dart_shell/src/settings/shell_settings.dart';
import 'package:denial_dart_shell/src/settings/widgets/settings_navigation.dart';
import 'package:denial_dart_shell/src/settings/widgets/settings_weather_page.dart';
import 'package:denial_dart_shell/src/theme/shell_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('weather page renders mode and unit controls', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: _wrap(
          const SettingsWeatherPage(
            settings: ShellWeatherSettings(),
            onLocationModeChanged: _noopMode,
            onManualLocationChanged: _noopLocation,
            onTemperatureUnitChanged: _noopUnit,
            onReset: _noop,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Location'), findsOneWidget);
    expect(find.text('Automatic'), findsOneWidget);
    expect(find.text('Manual city'), findsOneWidget);
    expect(find.text('Temperature unit'), findsOneWidget);
    expect(find.text('°C'), findsOneWidget);
    expect(find.text('°F'), findsOneWidget);
    // Manual search field only appears in manual mode.
    expect(find.byKey(settingsWeatherSearchFieldKey), findsNothing);
  });

  testWidgets('manual mode reveals the pinned city and search field', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: _wrap(
          SettingsWeatherPage(
            settings: const ShellWeatherSettings(
              locationMode: ShellWeatherLocationMode.manual,
              manualLocation: ShellManualLocation(
                latitude: 22.5,
                longitude: 114.06,
                city: 'Shenzhen',
              ),
            ),
            onLocationModeChanged: _noopMode,
            onManualLocationChanged: _noopLocation,
            onTemperatureUnitChanged: _noopUnit,
            onReset: _noop,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(settingsWeatherSearchFieldKey), findsOneWidget);
    expect(find.text('Current city: Shenzhen'), findsOneWidget);
  });

  testWidgets('segmented controls report changes', (tester) async {
    ShellWeatherLocationMode? reportedMode;
    ShellTemperatureUnit? reportedUnit;
    await tester.pumpWidget(
      ProviderScope(
        child: _wrap(
          SettingsWeatherPage(
            settings: const ShellWeatherSettings(),
            onLocationModeChanged: (mode) => reportedMode = mode,
            onManualLocationChanged: _noopLocation,
            onTemperatureUnitChanged: (unit) => reportedUnit = unit,
            onReset: _noop,
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Manual city'));
    await tester.pump();
    expect(reportedMode, ShellWeatherLocationMode.manual);

    await tester.tap(find.text('°F'));
    await tester.pump();
    expect(reportedUnit, ShellTemperatureUnit.fahrenheit);
  });

  test('navigation exposes the weather destination', () {
    expect(SettingsPageId.values, contains(SettingsPageId.weather));
  });
}

void _noop() {}

void _noopMode(ShellWeatherLocationMode mode) {}

void _noopLocation(ShellManualLocation? location) {}

void _noopUnit(ShellTemperatureUnit unit) {}

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
