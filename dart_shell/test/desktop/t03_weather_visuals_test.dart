import 'package:denial_dart_shell/l10n/generated/app_localizations.dart';
import 'package:denial_dart_shell/src/desktop/shelf/dashboard/weather/weather_animated_value.dart';
import 'package:denial_dart_shell/src/desktop/shelf/dashboard/weather/weather_arc_gauge.dart';
import 'package:denial_dart_shell/src/desktop/shelf/dashboard/weather/weather_background.dart';
import 'package:denial_dart_shell/src/desktop/shelf/dashboard/weather/weather_metrics_grid.dart';
import 'package:denial_dart_shell/src/desktop/shelf/dashboard/weather/weather_meteo_icon.dart';
import 'package:denial_dart_shell/src/desktop/shelf/dashboard/weather/weather_reveal.dart';
import 'package:denial_dart_shell/src/desktop/shelf/dashboard/weather/weather_trend_chart.dart';
import 'package:denial_dart_shell/src/desktop/shelf/dashboard/weather/weather_visibility.dart';
import 'package:denial_dart_shell/src/services/weather_service.dart';
import 'package:denial_dart_shell/src/theme/shell_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: ShellTheme(data: const ShellThemeData(), child: child),
  );
}

Widget _activityScope(
  Widget child, {
  ValueNotifier<bool>? active,
  bool animationsEnabled = true,
  double durationScale = 1,
}) {
  return WeatherPageActivity(
    active: active ?? ValueNotifier<bool>(true),
    durationScale: durationScale,
    animationsEnabled: animationsEnabled,
    child: child,
  );
}

void main() {
  group('scene classification', () {
    test('WMO codes map to the six clavis scenes', () {
      expect(classifyWeatherScene(95), WeatherSceneType.storm);
      expect(classifyWeatherScene(99), WeatherSceneType.storm);
      expect(classifyWeatherScene(71), WeatherSceneType.snow);
      expect(classifyWeatherScene(77), WeatherSceneType.snow);
      expect(classifyWeatherScene(85), WeatherSceneType.snow);
      expect(classifyWeatherScene(51), WeatherSceneType.rain);
      expect(classifyWeatherScene(65), WeatherSceneType.rain);
      expect(classifyWeatherScene(80), WeatherSceneType.rain);
      expect(classifyWeatherScene(82), WeatherSceneType.rain);
      expect(classifyWeatherScene(0), WeatherSceneType.clear);
      expect(classifyWeatherScene(1), WeatherSceneType.partly);
      expect(classifyWeatherScene(2), WeatherSceneType.partly);
      expect(classifyWeatherScene(3), WeatherSceneType.overcast);
      expect(classifyWeatherScene(45), WeatherSceneType.overcast);
      expect(classifyWeatherScene(48), WeatherSceneType.overcast);
      expect(classifyWeatherScene(90), WeatherSceneType.overcast);
    });

    test('icon-name keywords classify when the code does not', () {
      expect(classifyWeatherScene(-1, 'thunderstorm'), WeatherSceneType.storm);
      expect(classifyWeatherScene(-1, 'snow showers'), WeatherSceneType.snow);
      expect(classifyWeatherScene(-1, 'rain'), WeatherSceneType.rain);
      expect(classifyWeatherScene(-1, 'drizzle'), WeatherSceneType.rain);
      expect(classifyWeatherScene(-1, 'sleet'), WeatherSceneType.rain);
      expect(classifyWeatherScene(-1, 'clear'), WeatherSceneType.clear);
      expect(classifyWeatherScene(-1, 'sunny'), WeatherSceneType.clear);
      expect(
        classifyWeatherScene(-1, 'partly cloudy'),
        WeatherSceneType.partly,
      );
      expect(
        classifyWeatherScene(-1, 'mostly cloudy'),
        WeatherSceneType.partly,
      );
      expect(classifyWeatherScene(-1, 'unknown'), WeatherSceneType.overcast);
    });

    test('windy variant needs ≥8 m/s on a cloud-family scene', () {
      expect(classifyWindy(WeatherSceneType.clear, 8.0, 0), isTrue);
      expect(classifyWindy(WeatherSceneType.clear, 7.9, 0), isFalse);
      // Gusts count the same as sustained speed.
      expect(classifyWindy(WeatherSceneType.partly, 2.0, 8.5), isTrue);
      expect(classifyWindy(WeatherSceneType.overcast, 12, 0), isTrue);
      // Precipitation scenes never flip to the windy variant.
      expect(classifyWindy(WeatherSceneType.rain, 20, 0), isFalse);
      expect(classifyWindy(WeatherSceneType.snow, 20, 0), isFalse);
      expect(classifyWindy(WeatherSceneType.storm, 20, 0), isFalse);
      // NaN readings degrade to calm rather than crash.
      expect(
        classifyWindy(WeatherSceneType.clear, double.nan, double.nan),
        isFalse,
      );
    });

    test('windy renders with the overcast visual scene', () {
      expect(
        visualWeatherScene(WeatherSceneType.clear, true),
        WeatherSceneType.overcast,
      );
      expect(
        visualWeatherScene(WeatherSceneType.partly, true),
        WeatherSceneType.overcast,
      );
      expect(
        visualWeatherScene(WeatherSceneType.rain, false),
        WeatherSceneType.rain,
      );
      expect(
        visualWeatherScene(WeatherSceneType.storm, true),
        WeatherSceneType.storm,
      );
    });
  });

  group('palette table', () {
    test('all twelve day/night palettes resolve', () {
      for (final type in WeatherSceneType.values) {
        for (final night in <bool>[false, true]) {
          final palette = weatherScenePalette(type, false, night);
          expect(palette.top.a, greaterThan(0));
          expect(palette.particle.a, greaterThan(0));
          expect(palette.cloudTone(0), isNotNull);
        }
      }
    });

    test('windy cloud scenes reuse the overcast palette', () {
      expect(
        weatherScenePalette(WeatherSceneType.clear, true, false).top,
        weatherScenePalette(WeatherSceneType.overcast, false, false).top,
      );
      expect(
        weatherScenePalette(WeatherSceneType.partly, true, true).mid,
        weatherScenePalette(WeatherSceneType.overcast, false, true).mid,
      );
    });

    test('canvas eligibility follows hasCanvasScene', () {
      // The one scene with nothing to animate: clear daytime without clouds.
      expect(
        weatherSceneHasCanvas(WeatherSceneType.clear, false, false),
        isFalse,
      );
      // Night always paints (stars).
      expect(
        weatherSceneHasCanvas(WeatherSceneType.clear, false, true),
        isTrue,
      );
      expect(
        weatherSceneHasCanvas(WeatherSceneType.rain, false, false),
        isTrue,
      );
      expect(
        weatherSceneHasCanvas(WeatherSceneType.snow, false, false),
        isTrue,
      );
      // Windy clear gains overcast cloud bands → a scene exists.
      expect(
        weatherSceneHasCanvas(WeatherSceneType.clear, true, false),
        isTrue,
      );
    });

    test('cloud band counts match the reference tiers', () {
      expect(weatherCloudBandCount(WeatherSceneType.clear, false), 0);
      expect(weatherCloudBandCount(WeatherSceneType.partly, false), 2);
      expect(weatherCloudBandCount(WeatherSceneType.overcast, false), 3);
      expect(weatherCloudBandCount(WeatherSceneType.clear, true), 3);
    });
  });

  group('clavis AQI/UV banding', () {
    test('aqiLevelIndex follows the clavis thresholds', () {
      expect(aqiLevelIndex(0), 0);
      expect(aqiLevelIndex(19.9), 0);
      expect(aqiLevelIndex(20), 1);
      expect(aqiLevelIndex(49.9), 1);
      expect(aqiLevelIndex(50), 2);
      expect(aqiLevelIndex(100), 3);
      expect(aqiLevelIndex(150), 4);
      expect(aqiLevelIndex(250), 5);
      expect(aqiLevelIndex(999), 5);
      expect(aqiLevelIndex(double.nan), -1);
    });

    test('uvIndexBucket follows the WeatherBlob five buckets', () {
      expect(uvIndexBucket(2.9), 0);
      expect(uvIndexBucket(3), 1);
      expect(uvIndexBucket(6.5), 2);
      expect(uvIndexBucket(8), 3);
      expect(uvIndexBucket(11), 4);
      expect(uvIndexBucket(double.nan), -1);
    });

    test('airQualityIndex interpolates on the clavis 0-250 scale', () {
      // pm2.5 10 → band [5,15] → [20,50] → 35; pm10 20 → 25; worst = 35.
      expect(airQualityIndex(const AirQuality(pm10: 20, pm2_5: 10)), 35);
      // pm10 160 → band [160,400] → [150,250] → 150.
      expect(airQualityIndex(const AirQuality(pm10: 160, pm2_5: 5)), 150);
    });
  });

  group('meteocons slug mapping', () {
    test('WMO + day/night produces the reference slugs', () {
      expect(meteoSlugForCode(0, night: false), 'clear-day');
      expect(meteoSlugForCode(0, night: true), 'clear-night');
      expect(meteoSlugForCode(1, night: false), 'mostly-clear-day');
      expect(meteoSlugForCode(2, night: true), 'partly-cloudy-night');
      expect(meteoSlugForCode(3, night: false), 'cloudy');
      expect(meteoSlugForCode(45, night: false), 'fog-day');
      expect(meteoSlugForCode(48, night: true), 'fog-night');
      expect(meteoSlugForCode(55, night: false), 'drizzle');
      expect(meteoSlugForCode(61, night: true), 'overcast-night-rain');
      expect(meteoSlugForCode(66, night: false), 'overcast-day-sleet');
      expect(meteoSlugForCode(73, night: true), 'overcast-night-snow');
      expect(meteoSlugForCode(81, night: false), 'partly-cloudy-day-rain');
      expect(meteoSlugForCode(86, night: true), 'partly-cloudy-night-snow');
      expect(meteoSlugForCode(95, night: false), 'thunderstorms-day');
      expect(meteoSlugForCode(99, night: true), 'thunderstorms-night-hail');
      expect(meteoSlugForCode(999, night: false), 'not-available');
    });

    test('name fallback engages only for unmapped codes', () {
      expect(
        meteoSlug(code: -1, iconName: 'rain showers', night: false),
        'overcast-day-rain',
      );
      expect(meteoSlug(code: -1, iconName: 'sun', night: true), 'clear-day');
      expect(meteoSlug(code: -1, iconName: '', night: false), 'not-available');
      // A mapped code wins over any icon name.
      expect(meteoSlug(code: 0, iconName: 'rain', night: false), 'clear-day');
    });
  });

  group('WeatherArcGauge', () {
    testWidgets('renders the ring and centers its child', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const Center(
            child: SizedBox(
              width: 100,
              height: 100,
              child: WeatherArcGauge(
                value: 42,
                maximum: 100,
                progressColor: Color(0xFF3366CC),
                child: Text('42'),
              ),
            ),
          ),
        ),
      );
      expect(find.byType(WeatherArcGauge), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
      expect(find.text('42'), findsOneWidget);
    });

    test('exposes the reference geometry', () {
      expect(WeatherArcGauge.startAngleDegrees, 135);
      expect(WeatherArcGauge.sweepAngleDegrees, 270);
      const gauge = WeatherArcGauge(
        value: 1,
        maximum: 10,
        progressColor: Color(0xFF3366CC),
      );
      expect(gauge.thickness, 10);
    });
  });

  group('WeatherReveal', () {
    testWidgets('reveals once the page is active', (tester) async {
      final active = ValueNotifier<bool>(true);
      await tester.pumpWidget(
        _wrap(
          _activityScope(
            const WeatherReveal(staggerIndex: 0, child: Text('card')),
            active: active,
          ),
        ),
      );
      await tester.pump();
      // Entrance in flight or done — the child is mounted either way.
      expect(find.text('card'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      final opacity = tester.widget<Opacity>(
        find.descendant(
          of: find.byType(WeatherReveal),
          matching: find.byType(Opacity),
        ),
      );
      expect(opacity.opacity, 1.0);
    });

    testWidgets('stays hidden while the page is covered, then replays', (
      tester,
    ) async {
      final active = ValueNotifier<bool>(false);
      await tester.pumpWidget(
        _wrap(
          _activityScope(
            const WeatherReveal(staggerIndex: 0, child: Text('card')),
            active: active,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      var opacity = tester.widget<Opacity>(
        find.descendant(
          of: find.byType(WeatherReveal),
          matching: find.byType(Opacity),
        ),
      );
      expect(opacity.opacity, 0.0);

      active.value = true;
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      opacity = tester.widget<Opacity>(
        find.descendant(
          of: find.byType(WeatherReveal),
          matching: find.byType(Opacity),
        ),
      );
      expect(opacity.opacity, 1.0);
    });

    testWidgets('settles immediately under reduce-motion', (tester) async {
      await tester.pumpWidget(
        _wrap(
          _activityScope(
            const WeatherReveal(staggerIndex: 3, child: Text('card')),
            animationsEnabled: false,
          ),
        ),
      );
      await tester.pump();
      final opacity = tester.widget<Opacity>(
        find.descendant(
          of: find.byType(WeatherReveal),
          matching: find.byType(Opacity),
        ),
      );
      expect(opacity.opacity, 1.0);
    });
  });

  group('WeatherAnimatedValue', () {
    testWidgets('rolls up on the first active bind, then updates faster', (
      tester,
    ) async {
      final active = ValueNotifier<bool>(true);
      var value = 42.0;
      Widget build() => _wrap(
        _activityScope(
          WeatherAnimatedValue(
            value: value,
            builder: (context, v) => Text('${v?.round()}'),
          ),
          active: active,
        ),
      );

      await tester.pumpWidget(build());
      await tester.pump();
      // The initial 1000 ms roll starts at 0.
      await tester.pump(const Duration(milliseconds: 100));
      var text = tester.widget<Text>(find.byType(Text));
      expect(num.parse(text.data!), lessThan(42));

      await tester.pump(const Duration(seconds: 2));
      expect(find.text('42'), findsOneWidget);

      // A later change uses the 500 ms update glide.
      value = 84;
      await tester.pumpWidget(build());
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('84'), findsOneWidget);
    });

    testWidgets('snaps instantly while the page is inactive', (tester) async {
      final active = ValueNotifier<bool>(false);
      await tester.pumpWidget(
        _wrap(
          _activityScope(
            WeatherAnimatedValue(
              value: 42,
              builder: (context, v) => Text('${v?.round()}'),
            ),
            active: active,
          ),
        ),
      );
      await tester.pump();
      // Settled at the target — a covered page never half-animates.
      expect(find.text('42'), findsOneWidget);
    });

    testWidgets('snaps instantly under reduce-motion', (tester) async {
      await tester.pumpWidget(
        _wrap(
          _activityScope(
            WeatherAnimatedValue(
              value: 42,
              builder: (context, v) => Text('${v?.round()}'),
            ),
            animationsEnabled: false,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('42'), findsOneWidget);
    });
  });

  group('WeatherBackground lifecycle', () {
    WeatherBackground buildBackground({
      bool animationsEnabled = true,
      ValueNotifier<bool>? activitySink,
      int weatherCode = 61,
      bool night = false,
      double windSpeedMs = 2,
    }) {
      return WeatherBackground(
        weatherCode: weatherCode,
        night: night,
        windSpeedMs: windSpeedMs,
        scrollProgress: ValueNotifier<double>(0),
        rainBounceY: ValueNotifier<double>(300),
        animationsEnabled: animationsEnabled,
        activitySink: activitySink,
      );
    }

    testWidgets('ticks and publishes page activity while visible', (
      tester,
    ) async {
      final sink = ValueNotifier<bool>(false);
      await tester.pumpWidget(
        _wrap(
          SizedBox(
            width: 400,
            height: 600,
            child: buildBackground(activitySink: sink),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(sink.value, isTrue);
      final state = tester.state(find.byType(WeatherBackground)) as dynamic;
      expect(state.debugSimFrames, greaterThan(0));
    });

    testWidgets('does not tick under reduce-motion and mounts no painter', (
      tester,
    ) async {
      final sink = ValueNotifier<bool>(false);
      await tester.pumpWidget(
        _wrap(
          SizedBox(
            width: 400,
            height: 600,
            child: buildBackground(
              animationsEnabled: false,
              activitySink: sink,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(sink.value, isFalse);
      final state = tester.state(find.byType(WeatherBackground)) as dynamic;
      expect(state.debugTickerActive, isFalse);
      expect(state.debugSimFrames, 0);
      // Static gradient only: no particle canvas inside the background.
      expect(
        find.descendant(
          of: find.byType(WeatherBackground),
          matching: find.byType(CustomPaint),
        ),
        findsNothing,
      );
    });

    testWidgets('stops ticking while covered by another IndexedStack child', (
      tester,
    ) async {
      final sink = ValueNotifier<bool>(false);
      await tester.pumpWidget(
        _wrap(
          SizedBox(
            width: 400,
            height: 600,
            child: IndexedStack(
              index: 0,
              children: [
                const SizedBox.expand(),
                buildBackground(activitySink: sink),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final state =
          tester.state(find.byType(WeatherBackground, skipOffstage: false))
              as dynamic;
      // Covered from the start: the ticker publishes inactive and idles.
      expect(sink.value, isFalse);
      expect(state.debugSimFrames, 0);
    });

    testWidgets('ticker stops while TickerMode is off and resumes after', (
      tester,
    ) async {
      var enabled = true;
      Widget build() => _wrap(
        TickerMode(
          enabled: enabled,
          child: SizedBox(width: 400, height: 600, child: buildBackground()),
        ),
      );
      await tester.pumpWidget(build());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final state = tester.state(find.byType(WeatherBackground)) as dynamic;
      expect(state.debugTickerActive, isTrue);

      enabled = false;
      await tester.pumpWidget(build());
      await tester.pump(const Duration(milliseconds: 100));
      expect(state.debugTickerActive, isFalse);
      final framesWhileMuted = state.debugSimFrames as int;
      await tester.pump(const Duration(milliseconds: 200));
      expect(state.debugSimFrames, framesWhileMuted);

      enabled = true;
      await tester.pumpWidget(build());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(state.debugTickerActive, isTrue);

      // Unmount so no live ticker or probe timer outlives the test.
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('clear day mounts no painter and never starts the ticker', (
      tester,
    ) async {
      final sink = ValueNotifier<bool>(false);
      await tester.pumpWidget(
        _wrap(
          SizedBox(
            width: 400,
            height: 600,
            child: buildBackground(weatherCode: 0, activitySink: sink),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final state = tester.state(find.byType(WeatherBackground)) as dynamic;
      expect(state.debugTickerActive, isFalse);
      expect(state.debugSimFrames, 0);
      // The slow probe still publishes page activity for siblings.
      expect(sink.value, isTrue);
      // `hasCanvasScene` is false: no painter is mounted at all.
      expect(
        find.descendant(
          of: find.byType(WeatherBackground),
          matching: find.byType(CustomPaint),
        ),
        findsNothing,
      );

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a data-driven scene reappearing restarts the ticker', (
      tester,
    ) async {
      var weatherCode = 0;
      Widget build() => _wrap(
        SizedBox(
          width: 400,
          height: 600,
          child: buildBackground(weatherCode: weatherCode),
        ),
      );
      await tester.pumpWidget(build());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final state = tester.state(find.byType(WeatherBackground)) as dynamic;
      expect(state.debugTickerActive, isFalse);

      weatherCode = 61;
      await tester.pumpWidget(build());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(state.debugTickerActive, isTrue);
      expect(state.debugSimFrames, greaterThan(0));

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('scene-less probe still publishes tab coverage', (
      tester,
    ) async {
      var index = 0;
      final sink = ValueNotifier<bool>(false);
      Widget build() => _wrap(
        SizedBox(
          width: 400,
          height: 600,
          child: IndexedStack(
            index: index,
            children: [
              const SizedBox.expand(),
              buildBackground(weatherCode: 0, activitySink: sink),
            ],
          ),
        ),
      );
      await tester.pumpWidget(build());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(sink.value, isFalse);

      index = 1;
      await tester.pumpWidget(build());
      // The 250 ms probe — not a paint callback — detects re-selection.
      await tester.pump(const Duration(milliseconds: 300));
      expect(sink.value, isTrue);

      await tester.pumpWidget(const SizedBox());
    });
  });

  group('WeatherTrendChart', () {
    testWidgets('renders hourly and dual-line variants without error', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const Column(
            children: [
              SizedBox(
                width: 360,
                height: 100,
                child: WeatherTrendChart(
                  values: <double>[20, 22, 21, 24, 25, 23],
                  precipitationProbabilities: <int>[0, 20, 40, 10, 0, 60],
                ),
              ),
              SizedBox(
                width: 360,
                height: 120,
                child: WeatherTrendChart(
                  values: <double>[28, 30, 29, 31, 32, 33, 30],
                  lowValues: <double>[18, 17, 16, 18, 19, 20, 17],
                  precipitationProbabilities: <int>[10, 20, 30, 40, 50, 60, 70],
                  fadeFirstBar: true,
                ),
              ),
            ],
          ),
        ),
      );
      expect(find.byType(WeatherTrendChart), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('degenerate inputs draw nothing and do not throw', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const SizedBox(
            width: 360,
            height: 100,
            child: WeatherTrendChart(
              values: <double>[22],
              lowValues: <double>[18],
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
