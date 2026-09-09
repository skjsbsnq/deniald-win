import 'package:denial_dart_shell/src/models/display_layout.dart';
import 'package:denial_dart_shell/src/models/shell_popup_placement.dart';
import 'package:denial_dart_shell/src/models/suspend_mode.dart';
import 'package:denial_dart_shell/src/settings/shell_settings.dart';
import 'package:denial_dart_shell/src/theme/backdrop_blur_level.dart';
import 'package:denial_dart_shell/src/theme/cursor_themes.dart';
import 'package:denial_dart_shell/src/theme/tokens.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'idle policy defaults lock and display off on while suspend stays off',
    () {
      const power = ShellPowerSettings();

      expect(power.idleLockEnabled, isTrue);
      expect(power.idleLockTimeoutMinutes, 5);
      expect(power.idleDpmsEnabled, isTrue);
      expect(power.idleDpmsTimeoutMinutes, 10);
      expect(power.idleSuspendEnabled, isFalse);
      expect(power.idleSuspendTimeoutMinutes, 30);
      expect(power.suspendMode, SuspendMode.systemDefault);
    },
  );

  test('the complete settings document survives a JSON round trip', () {
    const settings = ShellSettings(
      localization: ShellLocalizationSettings(
        locale: ShellLocalePreference.simplifiedChinese,
      ),
      appearance: ShellAppearanceSettings(
        colorSchemePreference: DesktopColorSchemePreference.preferLight,
        accentSource: ShellAccentSource.custom,
        customAccentColor: Color(0xffc062ff),
        cornerRadiusScale: 1.35,
        panelOpacity: 0.78,
        backdropBlurEnabled: false,
        backdropBlurLevel: ShellBackdropBlurLevel.best,
        backdropBlurOpacityThreshold: 0.18,
        focusedWindowBorderEnabled: false,
        focusedWindowOpacity: 0.96,
        unfocusedWindowOpacity: 0.72,
        cursorSize: 44,
        cursorThemeId: 'imported-theme-sha256',
        allowClientCursorSurfaces: false,
      ),
      layout: ShellLayoutSettings(
        windowLayout: DesktopWindowLayout.dwindle,
        systemBarSide: SystemBarSide.right,
        systemBarOutputNames: <String>['DP-1', 'HDMI-A-1'],
        systemBarThickness: 46,
        maximizePadding: 18,
        minimizedWindowPlacement: MinimizedWindowPlacement.offscreen,
        clipboardTrayEdge: ClipboardTrayEdge.bottom,
        clipboardTrayExtent: 288,
      ),
      overlays: ShellOverlaySettings(
        launcher: ShellPopupPlacement(
          anchor: ShellPopupAnchor.topRight,
          width: 720,
          height: 650,
          margin: 20,
          hoverTriggerEnabled: false,
        ),
      ),
      animations: ShellAnimationSettings(
        durationScale: 0.75,
        panelTravel: 24,
        animateLockScreen: false,
      ),
      lockScreen: ShellLockScreenSettings(
        dimAmount: 0.42,
        blurRadius: 14,
        clockScale: 1.15,
        showSystemStatus: false,
      ),
      power: ShellPowerSettings(
        idleLockEnabled: false,
        idleLockTimeoutMinutes: 13,
        idleDpmsEnabled: false,
        idleDpmsTimeoutMinutes: 47,
        idleSuspendEnabled: true,
        idleSuspendTimeoutMinutes: 72,
        suspendMode: SuspendMode.deep,
      ),
      weather: ShellWeatherSettings(
        locationMode: ShellWeatherLocationMode.manual,
        manualLocation: ShellManualLocation(
          latitude: 22.5,
          longitude: 114.06,
          city: 'Shenzhen',
        ),
        temperatureUnit: ShellTemperatureUnit.fahrenheit,
      ),
      applicationEnvironment: ShellApplicationEnvironmentSettings(
        variables: <String, String?>{
          'DISPLAY': null,
          'MOZ_ENABLE_WAYLAND': '1',
        },
        applications: <String, Map<String, String?>>{
          'org.mozilla.firefox.desktop': <String, String?>{
            'MOZ_ENABLE_WAYLAND': '0',
          },
        },
      ),
    );

    expect(ShellSettings.fromJson(settings.toJson()), settings);
    expect(settings.toJson()['version'], ShellSettings.schemaVersion);
  });

  test('suspend mode persists and produces a typed patch', () {
    const previous = ShellSettings();
    final next = previous.copyWith(
      power: previous.power.copyWith(suspendMode: SuspendMode.s2idle),
    );

    expect(
      ShellSettings.fromJson(next.toJson()).power.suspendMode,
      SuspendMode.s2idle,
    );
    expect(next.differenceFrom(previous), <String, Object?>{
      'power': <String, Object?>{'suspendMode': 's2idle'},
    });
  });

  test('window layout persists and produces a typed patch', () {
    const previous = ShellSettings();
    final next = previous.copyWith(
      layout: previous.layout.copyWith(
        windowLayout: DesktopWindowLayout.dwindle,
      ),
    );

    expect(
      ShellSettings.fromJson(next.toJson()).layout.windowLayout,
      DesktopWindowLayout.dwindle,
    );
    expect(next.differenceFrom(previous), <String, Object?>{
      'layout': <String, Object?>{'windowLayout': 'dwindle'},
    });
  });

  test('minimized window placement persists and produces a typed patch', () {
    const previous = ShellSettings();
    final next = previous.copyWith(
      layout: previous.layout.copyWith(
        minimizedWindowPlacement: MinimizedWindowPlacement.offscreen,
      ),
    );

    expect(
      ShellSettings.fromJson(next.toJson()).layout.minimizedWindowPlacement,
      MinimizedWindowPlacement.offscreen,
    );
    expect(next.differenceFrom(previous), <String, Object?>{
      'layout': <String, Object?>{'minimizedWindowPlacement': 'offscreen'},
    });
  });

  test('typed settings patches preserve cursor authority changes', () {
    const previous = ShellSettings();
    final next = previous.copyWith(
      appearance: previous.appearance.copyWith(
        cursorSize: 48,
        cursorThemeId: 'imported-theme-sha256',
        allowClientCursorSurfaces: false,
      ),
    );

    expect(next.differenceFrom(previous), <String, Object?>{
      'appearance': <String, Object?>{
        'cursorSize': 48.0,
        'cursorThemeId': 'imported-theme-sha256',
        'allowClientCursorSurfaces': false,
      },
    });
  });

  test('malformed settings fail safe and bounded values are clamped', () {
    final settings = ShellSettings.fromJson(<String, dynamic>{
      'version': 999,
      'localization': <String, dynamic>{'locale': 'future-locale'},
      'appearance': <String, dynamic>{
        'accentSource': 'future-source',
        'windowRadius': 400,
        'panelOpacity': 0.01,
        'cursorSize': 400,
        'cursorThemeId': '\u0000invalid',
        'allowClientCursorSurfaces': 'sometimes',
      },
      'layout': <String, dynamic>{
        'windowLayout': 'future-layout',
        'systemBarSide': 'diagonal',
        'systemBarOutputs': <Object?>[' DP-1 ', 42, ''],
        'systemBarThickness': double.nan,
        'maximizePadding': -20,
        'minimizedWindowPlacement': 'somewhere-else',
        'clipboardTrayExtent': 5000,
      },
      'power': <String, dynamic>{
        'idleLockEnabled': 'sometimes',
        'idleLockTimeoutMinutes': 900,
        'idleDpmsEnabled': 'sometimes',
        'idleDpmsTimeoutMinutes': 900,
        'idleSuspendEnabled': 'sometimes',
        'idleSuspendTimeoutMinutes': 2,
      },
    });

    expect(settings.localization.locale, ShellLocalePreference.system);
    expect(settings.appearance.accentSource, ShellAccentSource.wallpaper);
    expect(settings.appearance.cornerRadiusScale, ShellRoundness.maximum);
    expect(settings.appearance.panelOpacity, ShellOpacity.minimumPanel);
    expect(settings.appearance.cursorSize, shellCursorMaximumSize);
    expect(settings.appearance.cursorThemeId, 'bibata_modern_ice');
    expect(settings.appearance.allowClientCursorSurfaces, isTrue);
    expect(settings.layout.windowLayout, DesktopWindowLayout.stacking);
    expect(settings.layout.systemBarSide, isNull);
    expect(settings.layout.systemBarOutputNames, <String>['DP-1']);
    expect(settings.layout.systemBarThickness, 32);
    expect(settings.layout.maximizePadding, 0);
    expect(
      settings.layout.minimizedWindowPlacement,
      MinimizedWindowPlacement.desktop,
    );
    expect(settings.layout.clipboardTrayExtent, clipboardTrayMaximumExtent);
    expect(settings.power.idleLockEnabled, isTrue);
    expect(settings.power.idleLockTimeoutMinutes, 120);
    expect(settings.power.idleDpmsEnabled, isTrue);
    expect(settings.power.idleDpmsTimeoutMinutes, 120);
    expect(settings.power.idleSuspendEnabled, isFalse);
    expect(settings.power.idleSuspendTimeoutMinutes, 120);
  });

  test('idle timeout ordering is repaired without shortening display off', () {
    final settings = ShellSettings.fromJson(<String, dynamic>{
      'power': <String, dynamic>{
        'idleLockTimeoutMinutes': 90,
        'idleDpmsTimeoutMinutes': 80,
        'idleSuspendTimeoutMinutes': 30,
      },
    });

    expect(settings.power.idleDpmsTimeoutMinutes, 80);
    expect(settings.power.idleSuspendTimeoutMinutes, 80);
    expect(settings.power.idleLockTimeoutMinutes, 80);
  });

  test('legacy panel radius migrates to the global roundness scale', () {
    final settings = ShellSettings.fromJson(<String, dynamic>{
      'appearance': <String, dynamic>{'panelRadius': 42},
    });

    expect(settings.appearance.cornerRadiusScale, 1.5);
    final appearance = settings.toJson()['appearance']! as Map<String, Object>;
    expect(appearance.containsKey('windowRadius'), isFalse);
    expect(appearance.containsKey('panelRadius'), isFalse);
  });

  test('weather settings default to automatic celsius', () {
    const settings = ShellSettings();
    expect(settings.weather.locationMode, ShellWeatherLocationMode.auto);
    expect(settings.weather.manualLocation, isNull);
    expect(settings.weather.temperatureUnit, ShellTemperatureUnit.celsius);
    expect(settings.weather.resolvedLocation, isNull);
  });

  test('weather settings survive a round trip and clear the pinned city', () {
    const weather = ShellWeatherSettings(
      locationMode: ShellWeatherLocationMode.manual,
      manualLocation: ShellManualLocation(
        latitude: 39.9,
        longitude: 116.4,
        city: 'Beijing',
      ),
      temperatureUnit: ShellTemperatureUnit.fahrenheit,
    );
    expect(ShellWeatherSettings.fromJson(weather.toJson()), weather);
    expect(weather.resolvedLocation?.city, 'Beijing');

    final cleared = weather.copyWith(manualLocation: null);
    expect(cleared.manualLocation, isNull);
    // Clearing the city while keeping manual mode stays stable in JSON.
    expect(ShellWeatherSettings.fromJson(cleared.toJson()), cleared);
  });

  test('malformed weather settings fail safe to defaults', () {
    final settings = ShellSettings.fromJson(<String, dynamic>{
      'weather': <String, dynamic>{
        'locationMode': 'orbit',
        'manualLocation': <String, dynamic>{
          'latitude': 'not-a-number',
          'longitude': 116.4,
          'city': 'Beijing',
        },
        'temperatureUnit': 'kelvin',
      },
    });

    expect(settings.weather.locationMode, ShellWeatherLocationMode.auto);
    expect(settings.weather.manualLocation, isNull);
    expect(settings.weather.temperatureUnit, ShellTemperatureUnit.celsius);
  });

  test('weather changes produce a typed patch', () {
    const before = ShellSettings();
    const after = ShellSettings(
      weather: ShellWeatherSettings(
        locationMode: ShellWeatherLocationMode.manual,
        manualLocation: ShellManualLocation(
          latitude: 22.5,
          longitude: 114.06,
          city: 'Shenzhen',
        ),
      ),
    );

    final patch = after.differenceFrom(before);
    final weatherPatch = patch['weather']! as Map<String, Object?>;
    expect(weatherPatch['locationMode'], 'manual');
    final location = weatherPatch['manualLocation']! as Map<String, Object>;
    expect(location['city'], 'Shenzhen');
    expect(weatherPatch.containsKey('temperatureUnit'), isFalse);

    // Resetting back clears the pinned city with an explicit null.
    final resetPatch =
        before.differenceFrom(after)['weather']! as Map<String, Object?>;
    expect(resetPatch['manualLocation'], isNull);
    expect(resetPatch['locationMode'], 'auto');
  });
}
