import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'weather_visibility.dart';

// ---------------------------------------------------------------------------
// Scene classification & palettes — parameter tables ported verbatim from
// CLAVIS/Widgets/weather/WeatherBackground.qml. Per constraint D2 the clavis
// hex palette converges here as file-top consts; the weather/ tree is the
// registered exemption area for these ported palettes.
// ---------------------------------------------------------------------------

/// The six ambient scenes of `WeatherBackground.qml`
/// (`classifyWeatherType`).
enum WeatherSceneType { clear, partly, overcast, rain, snow, storm }

/// One scene palette: vertical gradient (top/mid/bottom), sun glow, three
/// cloud-band tones and the star/snow particle color.
class WeatherScenePalette {
  const WeatherScenePalette({
    required this.top,
    required this.mid,
    required this.bottom,
    required this.glow,
    required this.cloud1,
    required this.cloud2,
    required this.cloud3,
    required this.particle,
  });

  final Color top;
  final Color mid;
  final Color bottom;
  final Color glow;
  final Color cloud1;
  final Color cloud2;
  final Color cloud3;
  final Color particle;

  Color cloudTone(int index) =>
      index == 0 ? cloud1 : (index == 1 ? cloud2 : cloud3);
}

const Map<String, WeatherScenePalette> _palettes =
    <String, WeatherScenePalette>{
      'clear_day': WeatherScenePalette(
        top: Color(0xFF7FC5E5),
        mid: Color(0xFFDDE7EC),
        bottom: Color(0xFFF7FBFD),
        glow: Color(0xFFFFF6CD),
        cloud1: Color(0xFFF0EFED),
        cloud2: Color(0xFFE0DFDD),
        cloud3: Color(0xFFCECDCB),
        particle: Color(0xFFFFF2C0),
      ),
      'clear_night': WeatherScenePalette(
        top: Color(0xFF45578F),
        mid: Color(0xFF8CA0D8),
        bottom: Color(0xFFC0CBEF),
        glow: Color(0xFFE8EDFF),
        cloud1: Color(0xFFEEF2FB),
        cloud2: Color(0xFFD7DCE8),
        cloud3: Color(0xFFC4CAD8),
        particle: Color(0xFFEEF2FF),
      ),
      'partly_day': WeatherScenePalette(
        top: Color(0xFF7FC5E5),
        mid: Color(0xFFDDE7EC),
        bottom: Color(0xFFF7FBFD),
        glow: Color(0xFFFFF6CD),
        cloud1: Color(0xFFF0EFED),
        cloud2: Color(0xFFE0DFDD),
        cloud3: Color(0xFFCECDCB),
        particle: Color(0xFFFFF2C0),
      ),
      'partly_night': WeatherScenePalette(
        top: Color(0xFF45578F),
        mid: Color(0xFF8CA0D8),
        bottom: Color(0xFFC0CBEF),
        glow: Color(0xFFE8EDFF),
        cloud1: Color(0xFFEEF2FB),
        cloud2: Color(0xFFD7DCE8),
        cloud3: Color(0xFFC4CAD8),
        particle: Color(0xFFEEF2FF),
      ),
      'overcast_day': WeatherScenePalette(
        top: Color(0xFF9AADB9),
        mid: Color(0xFFC8D2D8),
        bottom: Color(0xFFEEF3F5),
        glow: Color(0xFFF7FAFB),
        cloud1: Color(0xFFECEBEA),
        cloud2: Color(0xFFDDdcd9),
        cloud3: Color(0xFFCBC9C6),
        particle: Color(0xFFEAF0F5),
      ),
      'overcast_night': WeatherScenePalette(
        top: Color(0xFF53657A),
        mid: Color(0xFF8A9BAD),
        bottom: Color(0xFFC1CCD4),
        glow: Color(0xFFE7EDF1),
        cloud1: Color(0xFFDDE2EB),
        cloud2: Color(0xFFC3C8D2),
        cloud3: Color(0xFFAEB4C0),
        particle: Color(0xFFDAE6F4),
      ),
      'rain_day': WeatherScenePalette(
        top: Color(0xFFA5B7D2),
        mid: Color(0xFFCED8E4),
        bottom: Color(0xFFEDF2F7),
        glow: Color(0xFFF6F9FD),
        cloud1: Color(0xFFECEBEA),
        cloud2: Color(0xFFDDdcd9),
        cloud3: Color(0xFFCBC9C6),
        particle: Color(0xFFD8ECFF),
      ),
      'rain_night': WeatherScenePalette(
        top: Color(0xFF4A617D),
        mid: Color(0xFF879CB7),
        bottom: Color(0xFFBCC9D9),
        glow: Color(0xFFE3EBF4),
        cloud1: Color(0xFFDDE2EB),
        cloud2: Color(0xFFC3C8D2),
        cloud3: Color(0xFFAEB4C0),
        particle: Color(0xFFCEE5FF),
      ),
      'snow_day': WeatherScenePalette(
        top: Color(0xFFA5BDD5),
        mid: Color(0xFFD1DFE9),
        bottom: Color(0xFFF7FBFD),
        glow: Color(0xFFFFFFFF),
        cloud1: Color(0xFFF2F2F1),
        cloud2: Color(0xFFE4E3E1),
        cloud3: Color(0xFFD3D2D0),
        particle: Color(0xFFFFFFFF),
      ),
      'snow_night': WeatherScenePalette(
        top: Color(0xFF566D91),
        mid: Color(0xFF9AB0CB),
        bottom: Color(0xFFD1DCE8),
        glow: Color(0xFFF0F5FA),
        cloud1: Color(0xFFEDF1F8),
        cloud2: Color(0xFFD5DAE4),
        cloud3: Color(0xFFC4CCD8),
        particle: Color(0xFFFFFFFF),
      ),
      'storm_day': WeatherScenePalette(
        top: Color(0xFF78879A),
        mid: Color(0xFFADB8C9),
        bottom: Color(0xFFDBE1EA),
        glow: Color(0xFFF5F7FC),
        cloud1: Color(0xFF9FA4AD),
        cloud2: Color(0xFF8B8E98),
        cloud3: Color(0xFF7B7988),
        particle: Color(0xFFD7E8FF),
      ),
      'storm_night': WeatherScenePalette(
        top: Color(0xFF49516F),
        mid: Color(0xFF8790B0),
        bottom: Color(0xFFC0C6DA),
        glow: Color(0xFFE9ECF8),
        cloud1: Color(0xFF8F949D),
        cloud2: Color(0xFF7D8089),
        cloud3: Color(0xFF6D6C79),
        particle: Color(0xFFD3DFFF),
      ),
    };

const WeatherScenePalette _defaultPalette = WeatherScenePalette(
  top: Color(0xFF86A0B5),
  mid: Color(0xFFBCCAD5),
  bottom: Color(0xFFE4EBF1),
  glow: Color(0xFFF6F9FB),
  cloud1: Color(0xFFF0EFED),
  cloud2: Color(0xFFE0DFDD),
  cloud3: Color(0xFFCECDCB),
  particle: Color(0xFFEEF3F8),
);

// Particle constants (clavis literals).
const Color _rainStroke = Color(0xFF0000FF);
const Color _rainStrokeStorm = Color(0xFFD7DEEC);
const Color _cloudMask = Color(0xFF6A7078);
const double _cloudMaskOpacity = 0.18;
const Color _meteorHead = Color(0xFFFFFFFF);
const Color _flashFill = Color(0xFFFFFFFF);
const Color _nightShade = Color(0xFF0D1220);
const List<Color> _meteorColors = <Color>[
  Color(0xFFD2F7FF),
  Color(0xFFD0E9FF),
  Color(0xFFAFD0EC),
  Color(0xFFA4C2DC),
  Color(0xFFECEAD5),
  Color(0xFFF0DC97),
];
const List<Color> _leafColors = <Color>[
  Color(0xFF76993E),
  Color(0xFF4A5E23),
  Color(0xFF6D632F),
];

/// WMO 4677 code (+ optional provider icon name) → ambient scene. Direct port
/// of `classifyWeatherType`.
WeatherSceneType classifyWeatherScene(int weatherCode, [String iconName = '']) {
  final name = iconName.toLowerCase();
  if (weatherCode >= 95 || name.contains('thunder')) {
    return WeatherSceneType.storm;
  }
  if ((weatherCode >= 71 && weatherCode <= 77) ||
      weatherCode == 85 ||
      weatherCode == 86 ||
      name.contains('snow')) {
    return WeatherSceneType.snow;
  }
  if ((weatherCode >= 51 && weatherCode <= 67) ||
      (weatherCode >= 80 && weatherCode <= 82) ||
      name.contains('rain') ||
      name.contains('drizzle') ||
      name.contains('shower') ||
      name.contains('sleet')) {
    return WeatherSceneType.rain;
  }
  if (weatherCode == 0 ||
      name.contains('clear') ||
      name.contains('sunny') ||
      name.contains('sun')) {
    return WeatherSceneType.clear;
  }
  if (weatherCode == 1 ||
      weatherCode == 2 ||
      name.contains('partly') ||
      name.contains('mostly')) {
    return WeatherSceneType.partly;
  }
  return WeatherSceneType.overcast;
}

/// `classifyWindy`: max(sustained, gusts) ≥ 8 m/s on a cloud-family scene
/// forces the windy variant (overcast cloud floor + leaf particles).
bool classifyWindy(
  WeatherSceneType type,
  double windSpeedMs,
  double windGustsMs,
) {
  final sustained = windSpeedMs.isNaN ? 0.0 : windSpeedMs;
  final gusts = windGustsMs.isNaN ? 0.0 : windGustsMs;
  final strength = math.max(sustained, gusts);
  return strength >= 8.0 &&
      (type == WeatherSceneType.clear ||
          type == WeatherSceneType.partly ||
          type == WeatherSceneType.overcast);
}

/// `visualWeatherType`: windy cloud-family scenes render as overcast.
WeatherSceneType visualWeatherScene(WeatherSceneType type, bool windy) {
  if (windy &&
      (type == WeatherSceneType.clear ||
          type == WeatherSceneType.partly ||
          type == WeatherSceneType.overcast)) {
    return WeatherSceneType.overcast;
  }
  return type;
}

/// Palette for a scene + day/night; falls back to the clavis default palette.
WeatherScenePalette weatherScenePalette(
  WeatherSceneType type,
  bool windy,
  bool night,
) {
  final visual = visualWeatherScene(type, windy);
  final key = '${visual.name}_${night ? 'night' : 'day'}';
  return _palettes[key] ?? _defaultPalette;
}

int weatherCloudBandCount(WeatherSceneType type, bool windy) {
  final visual = visualWeatherScene(type, windy);
  if (visual == WeatherSceneType.clear) {
    return 0;
  }
  if (visual == WeatherSceneType.partly) {
    return 2;
  }
  return 3;
}

bool weatherSceneIsRain(WeatherSceneType type) =>
    type == WeatherSceneType.rain || type == WeatherSceneType.storm;

/// `hasCanvasScene`: a clear day is the only scene with nothing to animate —
/// keeping a transparent painter alive would repaint an empty frame.
bool weatherSceneHasCanvas(WeatherSceneType type, bool windy, bool night) {
  return night ||
      weatherCloudBandCount(type, windy) > 0 ||
      weatherSceneIsRain(type) ||
      type == WeatherSceneType.snow;
}

// ---------------------------------------------------------------------------
// Simulation state
// ---------------------------------------------------------------------------

class _CloudBand {
  _CloudBand({
    required this.offset,
    required this.height,
    required this.arch,
    required this.speed,
    required this.toneIndex,
  });

  double offset;
  final double height;
  final double arch;
  final double speed;
  final int toneIndex;
}

class _RainDrop {
  _RainDrop({
    required this.x,
    required this.width,
    required this.len,
    required this.delay,
  });

  final double x;
  final double width;
  final double len;
  final double delay;
  double age = 0;
  final double duration = 1;
}

class _Splash {
  _Splash({
    required this.x,
    required this.y,
    required this.segmentLength,
    required this.duration,
    required this.color,
    required this.samples,
    required this.lengths,
    required this.totalLength,
  });

  final double x;
  final double y;
  final double segmentLength;
  final double duration;
  final Color color;
  final List<Offset> samples;
  final List<double> lengths;
  final double totalLength;
  double age = 0;
}

List<double> _cumulativeLengths(List<Offset> samples) {
  final lengths = <double>[0];
  var total = 0.0;
  for (var i = 1; i < samples.length; i++) {
    total += (samples[i] - samples[i - 1]).distance;
    lengths.add(total);
  }
  return lengths;
}

class _LightningStrike {
  _LightningStrike({required this.points, required this.strokeWidth});

  final List<Offset> points;
  final double strokeWidth;
  double age = 0;
  final double duration = 1.0;
}

class _Meteor {
  _Meteor({
    required this.delay,
    required this.startX,
    required this.startY,
    required this.dx,
    required this.dy,
    required this.travel,
    required this.len,
    required this.strokeWidth,
    required this.color,
  });

  bool active = false;
  double delay;
  double progress = 0;
  final double startX;
  final double startY;
  final double dx;
  final double dy;
  final double travel;
  final double len;
  final double strokeWidth;
  final Color color;
}

class _Snowflake {
  double age = 0;
  double x = 0;
  double y = 0;
  double endY = 0;
  double swayTarget = 0;
  double swayFactor = math.pi / 3.0;
  double fallDuration = 1;
  double fallInverse = 1;
  double radiusBase = 0;
  double alphaBase = 0;
}

class _Leaf {
  _Leaf({
    required this.id,
    required this.scale,
    required this.color,
    required this.startRotation,
    required this.endRotation,
    required this.x0,
    required this.y0,
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
  });

  final int id;
  final double scale;
  final Color color;
  final double startRotation;
  final double endRotation;
  final double x0;
  final double y0;
  final double x1;
  final double y1;
  final double x2;
  final double y2;
  double progress = 0;
  static const double duration = 2.0;
}

// ---------------------------------------------------------------------------
// Widget
// ---------------------------------------------------------------------------

/// Scene-driven ambient backdrop of the Weather page — the
/// `Widgets/weather/WeatherBackground.qml` port: vertical gradient + glow +
/// cloud bands + rain/splash/lightning/snow/stars/meteors/leaves particles,
/// throttled to 30 fps on fast scenes (rain/storm/snow/windy) and 15 fps on
/// quiet ones, with a single ticker driving both simulation and the page's
/// activity publication. Scenes with no canvas (clear day) stop the ticker
/// entirely and mount no painter; a 4 Hz probe keeps the activity flag
/// alive there instead.
class WeatherBackground extends StatefulWidget {
  const WeatherBackground({
    super.key,
    required this.weatherCode,
    this.iconName = '',
    required this.night,
    required this.windSpeedMs,
    this.windGustsMs = 0,
    required this.scrollProgress,
    required this.rainBounceY,
    required this.animationsEnabled,
    this.motionScale = 1.0,
    this.activitySink,
  });

  final int weatherCode;
  final String iconName;
  final bool night;
  final double windSpeedMs;
  final double windGustsMs;

  /// 0 → 1 as the page scrolls; drives the opacity ramps of every layer.
  final ValueListenable<double> scrollProgress;

  /// Y (in widget coordinates) where rain splashes and snow settles — the
  /// top edge of the first forecast card, like `rainBounceY` in clavis.
  final ValueListenable<double> rainBounceY;

  /// `!MediaQuery.disableAnimationsOf` at the page: false collapses the
  /// widget to the static gradient layers and never starts the ticker.
  final bool animationsEnabled;

  /// Ambient speed multiplier — `1 / animations.durationScale` so a slower
  /// motion preference also calms the particles.
  final double motionScale;

  /// Page-activity publication: the ticker writes whether the Weather page
  /// is the painted tab, letting sibling animations (icons, reveals, rolling
  /// values) pause while covered.
  final ValueNotifier<bool>? activitySink;

  @override
  State<WeatherBackground> createState() => _WeatherBackgroundState();
}

class _WeatherBackgroundState extends State<WeatherBackground>
    with SingleTickerProviderStateMixin {
  static const double _frameBaseDt = 33 / 1000;

  final math.Random _random = math.Random();
  final ValueNotifier<int> _repaint = ValueNotifier<int>(0);

  late final Ticker _ticker;
  late final _WeatherParticlePainter _particlePainter = _WeatherParticlePainter(
    scene: _scene,
    repaint: _repaint,
    onPainted: _onPainted,
    onSize: _onCanvasSize,
  );

  /// Coverage probe for scenes with no canvas (clear day): the ticker is
  /// fully stopped there, so a slow timer keeps publishing the page-activity
  /// flag that gates the sibling animations. Clavis pushes `animate` from
  /// the parent instead; inside this widget the IndexedStack coverage can
  /// only be observed, not subscribed to.
  Timer? _activityProbe;
  static const Duration _probeInterval = Duration(milliseconds: 250);

  final _SceneState _scene = _SceneState();

  Duration _lastTick = Duration.zero;
  bool _hasTickBaseline = false;
  double _accumulator = 0;
  Size _size = Size.zero;

  /// Simulation steps actually run — exposed so tests can prove the ticker
  /// does (not) advance under TickerMode/visibility gating.
  @visibleForTesting
  int debugSimFrames = 0;

  @visibleForTesting
  bool get debugTickerActive => _ticker.isActive;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _resetVisualScenes();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _syncTicker();
      }
    });
  }

  @override
  void didUpdateWidget(covariant WeatherBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.weatherCode != widget.weatherCode ||
        oldWidget.iconName != widget.iconName ||
        oldWidget.windSpeedMs != widget.windSpeedMs ||
        oldWidget.windGustsMs != widget.windGustsMs ||
        oldWidget.night != widget.night) {
      _resetVisualScenes();
    }
    _syncTicker();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncTicker();
  }

  @override
  void dispose() {
    _cancelActivityProbe();
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  WeatherSceneType get _type =>
      classifyWeatherScene(widget.weatherCode, widget.iconName);

  bool get _windy =>
      classifyWindy(_type, widget.windSpeedMs, widget.windGustsMs);

  bool get _isRainScene => weatherSceneIsRain(_type);

  bool get _isSnowScene => _type == WeatherSceneType.snow;

  bool get _hasLeafScene =>
      _windy &&
      (_type == WeatherSceneType.clear ||
          _type == WeatherSceneType.partly ||
          _type == WeatherSceneType.overcast);

  bool get _hasMeteorScene =>
      widget.night &&
      visualWeatherScene(_type, _windy) == WeatherSceneType.clear;

  int get _cloudBandCount => weatherCloudBandCount(_type, _windy);

  bool get _hasCanvasScene =>
      weatherSceneHasCanvas(_type, _windy, widget.night);

  bool get _fastScene => _isRainScene || _isSnowScene || _windy;

  bool _isPageActive() {
    return widget.animationsEnabled && dashboardPageSelected(context);
  }

  void _publish(bool active) {
    final sink = widget.activitySink;
    if (sink != null && sink.value != active) {
      sink.value = active;
    }
  }

  void _syncTicker() {
    if (!mounted) {
      return;
    }
    // `sceneTimer.running = animate && hasCanvasScene` in the reference: with
    // nothing to draw the ticker is not merely throttled, it is stopped.
    // `_ticker.muted` mirrors the TickerMode the provider applies — reading it
    // avoids registering an inherited dependency from the paint callback.
    final tickerEnabled = !_ticker.muted;
    final shouldTick = _hasCanvasScene && _isPageActive() && tickerEnabled;
    if (shouldTick && !_ticker.isActive) {
      _lastTick = Duration.zero;
      _hasTickBaseline = false;
      _ticker.start();
    } else if (!shouldTick) {
      if (_ticker.isActive) {
        _ticker.stop();
      }
      _publish(false);
    }
    // Scene-less pages mount no painter at all, so the paint→resume path
    // cannot fire; the periodic probe below takes over the activity
    // publication instead (cancelled as soon as a scene reappears).
    if (!_hasCanvasScene && widget.animationsEnabled && tickerEnabled) {
      _armActivityProbe();
      _publish(_isPageActive());
    } else {
      _cancelActivityProbe();
    }
  }

  void _armActivityProbe() {
    _activityProbe ??= Timer.periodic(_probeInterval, (_) => _probeActivity());
  }

  void _cancelActivityProbe() {
    _activityProbe?.cancel();
    _activityProbe = null;
  }

  /// Publishes tab coverage while no canvas scene exists. Fires at 4 Hz —
  /// far cheaper than the vsync ticker it replaces — and only while the
  /// panel is unparked; `TickerMode` parking cancels it until
  /// `didChangeDependencies` re-arms it through [_syncTicker].
  void _probeActivity() {
    if (!mounted) {
      _cancelActivityProbe();
      return;
    }
    if (_hasCanvasScene || !widget.animationsEnabled || _ticker.muted) {
      _cancelActivityProbe();
      _syncTicker();
      return;
    }
    _publish(_isPageActive());
  }

  /// Resume hook: the particle painter only gets painted when the
  /// dashboard's IndexedStack selects this page again, which is exactly when
  /// a stopped ticker must come back.
  void _onPainted() {
    _syncTicker();
  }

  void _onCanvasSize(Size size) {
    if (size != _size) {
      _size = size;
      _resetVisualScenes();
    }
  }

  void _onTick(Duration elapsed) {
    final dt = !_hasTickBaseline
        ? _frameBaseDt
        : math.min(0.05, (elapsed - _lastTick).inMicroseconds / 1000000.0);
    _lastTick = elapsed;
    _hasTickBaseline = true;

    if (!_isPageActive()) {
      // Covered by another dashboard tab: publish the idle state and stop.
      // The next paint of this page (re-selection) restarts the ticker via
      // the painter's `_onPainted` hook.
      _publish(false);
      _ticker.stop();
      return;
    }
    _publish(true);

    _accumulator += dt;
    final interval = _fastScene ? _frameBaseDt : 66 / 1000;
    if (_accumulator < interval) {
      return;
    }
    final step = _accumulator;
    _accumulator = 0;
    if (!_hasCanvasScene) {
      return;
    }
    _simulate(step * widget.motionScale, step / _frameBaseDt);
    debugSimFrames++;
    _repaint.value++;
  }

  void _simulate(double dt, double stepScale) {
    final width = _size.width;
    final driftBase = _cloudBandCount > 0 ? (_windy ? 3.05 : 1.05) : 0.0;
    for (final band in _scene.cloudBands) {
      if (driftBase > 0 && width > 0) {
        band.offset += driftBase * band.speed * stepScale;
        if (band.offset > width) {
          band.offset -= width;
        }
      }
    }
    if (_isRainScene) {
      _updateRain(dt);
      _updateSplashes(dt);
    } else {
      if (_scene.rainLayers.any((layer) => layer.isNotEmpty)) {
        _scene.rainLayers = <List<_RainDrop>>[
          <_RainDrop>[],
          <_RainDrop>[],
          <_RainDrop>[],
        ];
      }
      _scene.splashes.clear();
    }
    _updateSnow(dt);
    _updateLightning(dt);
    _updateMeteors(dt);
    _updateLeaves(dt);
    _scene.phase += 0.04 * stepScale;
  }

  // ---- scene (re)population ---------------------------------------------

  void _resetVisualScenes() {
    _initCloudBands();
    _scene.rainLayers = <List<_RainDrop>>[
      <_RainDrop>[],
      <_RainDrop>[],
      <_RainDrop>[],
    ];
    _scene.splashes.clear();
    _scene.lightning.clear();
    _scene.lightningCooldown = _randomLightningDelay();
    _resetMeteors();
    _resetSnow();
    _scene.leaves.clear();
    _scene.leafSpawnCooldown = _hasLeafScene ? 0 : -1;
  }

  void _initCloudBands() {
    final count = _cloudBandCount;
    final bands = <_CloudBand>[];
    final wide = math.max(_size.width, 1.0);
    for (var i = 0; i < count; i++) {
      final sourceIndex =
          visualWeatherScene(_type, _windy) == WeatherSceneType.clear
          ? i + 1
          : i;
      const heights = <double>[0.255, 0.335, 0.405];
      const speeds = <double>[1.0, 0.72, 0.48];
      final profile = math.min(sourceIndex, heights.length - 1);
      final height = wide * heights[profile];
      bands.add(
        _CloudBand(
          offset: _random.nextDouble() * wide,
          height: height,
          arch: height + wide * 0.124 + _random.nextDouble() * wide * 0.124,
          speed: speeds[profile],
          toneIndex: sourceIndex,
        ),
      );
    }
    _scene.cloudBands = bands;
  }

  double _randomLightningDelay() => math.max(0.08, _random.nextDouble() * 6.0);

  int get _rainTargetCount => _type == WeatherSceneType.storm ? 60 : 20;

  Color get _rainStrokeColor =>
      _type == WeatherSceneType.storm ? _rainStrokeStorm : _rainStroke;

  void _makeRainDrop() {
    final width = _size.width;
    if (width <= 40) {
      return;
    }
    final lineWidth = _random.nextDouble() * 3;
    final lineLength = _type == WeatherSceneType.storm ? 35.0 : 14.0;
    final layerIndex = (2 - lineWidth.floor()).clamp(0, 2).toInt();
    _scene.rainLayers[layerIndex].add(
      _RainDrop(
        x: 20 + _random.nextDouble() * (width - 40),
        width: lineWidth,
        len: lineLength,
        delay: _random.nextDouble(),
      ),
    );
  }

  void _updateRain(double dt) {
    for (final layer in _scene.rainLayers) {
      for (var i = layer.length - 1; i >= 0; i--) {
        final drop = layer[i];
        drop.age += dt;
        if (drop.age >= drop.delay + drop.duration) {
          if (drop.width > 2) {
            _makeSplash(drop.x, _rainStrokeColor);
          }
          layer.removeAt(i);
        }
      }
    }
    var dropCount = 0;
    for (final layer in _scene.rainLayers) {
      dropCount += layer.length;
    }
    while (dropCount < _rainTargetCount) {
      _makeRainDrop();
      dropCount++;
    }
  }

  /// Splash/settle line: the measured first-card top edge, falling back to
  /// the clavis default (56 % of the height) before any card reports.
  double get _bounceY {
    final measured = widget.rainBounceY.value;
    final value = measured > 0 ? measured : _size.height * 0.56;
    return value.clamp(0.0, _size.height).toDouble();
  }

  void _makeSplash(double x, Color stroke) {
    final splashLength = _type == WeatherSceneType.storm ? 30.0 : 20.0;
    final splashBounce = _type == WeatherSceneType.storm ? 120.0 : 100.0;
    const splashDistance = 80.0;
    final randomX = _random.nextDouble() * splashDistance - splashDistance / 2;
    final samples = _quadraticSamples(
      Offset.zero,
      Offset(randomX, -_random.nextDouble() * splashBounce),
      Offset(randomX * 2, splashDistance),
    );
    final lengths = _cumulativeLengths(samples);
    _scene.splashes.add(
      _Splash(
        x: x,
        y: _bounceY,
        segmentLength: splashLength,
        duration: _type == WeatherSceneType.storm ? 0.7 : 0.5,
        color: stroke,
        samples: samples,
        lengths: lengths,
        totalLength: lengths.last,
      ),
    );
  }

  void _updateSplashes(double dt) {
    for (var i = _scene.splashes.length - 1; i >= 0; i--) {
      final splash = _scene.splashes[i];
      splash.age += dt;
      if (splash.age >= splash.duration) {
        _scene.splashes.removeAt(i);
      }
    }
  }

  List<Offset> _quadraticSamples(Offset start, Offset control, Offset end) {
    const steps = 20;
    final points = <Offset>[start];
    for (var i = 1; i <= steps; i++) {
      final t = i / steps;
      final inverse = 1 - t;
      points.add(
        Offset(
          inverse * inverse * start.dx +
              2 * inverse * t * control.dx +
              t * t * end.dx,
          inverse * inverse * start.dy +
              2 * inverse * t * control.dy +
              t * t * end.dy,
        ),
      );
    }
    return points;
  }

  void _makeLightningStrike() {
    final width = _size.width;
    final height = _size.height;
    if (width <= 0 || height <= 0) {
      return;
    }
    const steps = 20;
    final horizontalMargin = math.min(
      width * 0.25,
      math.max(24.0, width * 0.10),
    );
    final horizontalJitter = math.max(20.0, width * 0.07);
    final pathX =
        horizontalMargin +
        _random.nextDouble() *
            (width - horizontalMargin * 2).clamp(1.0, double.infinity);
    final points = <Offset>[Offset(pathX, 0)];
    for (var i = 0; i < steps; i++) {
      points.add(
        Offset(
          pathX +
              _random.nextDouble() * horizontalJitter -
              horizontalJitter * 0.5,
          height / steps * (i + 1),
        ),
      );
    }
    _scene.lightning.add(
      _LightningStrike(
        points: points,
        strokeWidth: 2.8 + _random.nextDouble() * 1.2,
      ),
    );
  }

  void _updateLightning(double dt) {
    if (_type != WeatherSceneType.storm) {
      _scene.lightning.clear();
      return;
    }
    for (var i = _scene.lightning.length - 1; i >= 0; i--) {
      final strike = _scene.lightning[i];
      strike.age += dt;
      if (strike.age >= strike.duration) {
        _scene.lightning.removeAt(i);
      }
    }
    _scene.lightningCooldown -= dt;
    while (_scene.lightningCooldown <= 0) {
      _makeLightningStrike();
      _scene.lightningCooldown += _randomLightningDelay();
    }
  }

  _Meteor _makeMeteor(double delaySeconds) {
    final scale = 0.45 + _random.nextDouble() * 0.55;
    final size = math.max(1.0, math.min(_size.width, _size.height));
    final angle = (108 + _random.nextDouble() * 18) * math.pi / 180;
    return _Meteor(
      delay: delaySeconds,
      startX: _size.width * (0.22 + _random.nextDouble() * 0.96),
      startY: _size.height * (-0.30 + _random.nextDouble() * 0.42),
      dx: math.cos(angle),
      dy: math.sin(angle),
      travel: size * (0.50 + _random.nextDouble() * 0.26),
      len: size * (0.24 + _random.nextDouble() * 0.14) * scale,
      strokeWidth: 1.5 + scale * 1.5,
      color: _meteorColors[_random.nextInt(_meteorColors.length)],
    );
  }

  double _meteorRespawnDelay(bool firstSpawn) =>
      (firstSpawn ? 1.0 : 5.0) +
      _random.nextDouble() * (firstSpawn ? 6.0 : 12.0);

  void _resetMeteors() {
    _scene.meteors = _hasMeteorScene
        ? <_Meteor>[
            for (var i = 0; i < 3; i++) _makeMeteor(_meteorRespawnDelay(true)),
          ]
        : <_Meteor>[];
  }

  void _updateMeteors(double dt) {
    if (!_hasMeteorScene) {
      _scene.meteors.clear();
      return;
    }
    final next = _scene.meteors.take(3).toList();
    while (next.length < 3) {
      next.add(_makeMeteor(_meteorRespawnDelay(true)));
    }
    for (var i = 0; i < next.length; i++) {
      final meteor = next[i];
      if (!meteor.active) {
        meteor.delay -= dt;
        if (meteor.delay <= 0) {
          meteor.active = true;
          meteor.progress = 0;
        }
        continue;
      }
      meteor.progress += dt * meteor.travel * 1.85;
      if (meteor.progress >= meteor.travel) {
        next[i] = _makeMeteor(_meteorRespawnDelay(false));
      }
    }
    _scene.meteors = next;
  }

  void _configureSnowflake(_Snowflake flake, [double? ageOverride]) {
    final scale = 0.5 + _random.nextDouble() * 0.5;
    final radiusBase = 5 * scale;
    flake
      ..age = ageOverride ?? 0
      ..x = 20 + _random.nextDouble() * math.max(0.0, _size.width - 40)
      ..y = -10
      ..endY = math.max(
        radiusBase,
        math.min(_size.height, _bounceY - radiusBase),
      )
      ..swayTarget = _random.nextDouble() * 150 - 75
      ..swayFactor = math.pi / 3.0
      ..fallDuration = 3.0 + _random.nextDouble() * 5.0
      ..radiusBase = radiusBase
      ..alphaBase = 0.34 + scale * 0.42;
    flake.fallInverse = 1.0 / flake.fallDuration;
  }

  void _resetSnow() {
    _scene.snowflakes = <_Snowflake>[];
    if (!_isSnowScene || _size.width <= 40 || _size.height <= 0) {
      return;
    }
    for (var i = 0; i < 24; i++) {
      final flake = _Snowflake();
      _configureSnowflake(flake);
      flake.age = _random.nextDouble() * flake.fallDuration;
      _scene.snowflakes.add(flake);
    }
  }

  void _updateSnow(double dt) {
    if (!_isSnowScene) {
      _scene.snowflakes.clear();
      return;
    }
    for (final flake in _scene.snowflakes) {
      flake.age += dt;
      if (flake.age >= flake.fallDuration) {
        _configureSnowflake(flake, 0);
      }
    }
    while (_scene.snowflakes.length < 24) {
      final flake = _Snowflake();
      _configureSnowflake(flake);
      _scene.snowflakes.add(flake);
    }
    while (_scene.snowflakes.length > 24) {
      _scene.snowflakes.removeLast();
    }
  }

  void _updateLeaves(double dt) {
    if (!_hasLeafScene) {
      _scene.leaves.clear();
      return;
    }
    for (var i = _scene.leaves.length - 1; i >= 0; i--) {
      final leaf = _scene.leaves[i];
      leaf.progress += dt / _Leaf.duration;
      if (leaf.progress >= 1) {
        _scene.leaves.removeAt(i);
        if (_scene.leafSpawnCooldown < 0) {
          _scene.leafSpawnCooldown = _nextLeafSpawnInterval();
        }
      }
    }
    if (_scene.leaves.length < 3) {
      _scene.leafSpawnCooldown -= dt;
      while (_scene.leafSpawnCooldown <= 0 && _scene.leaves.length < 3) {
        _spawnLeaf();
        _scene.leafSpawnCooldown += _nextLeafSpawnInterval();
      }
    }
  }

  double _nextLeafSpawnInterval() => (260 + _random.nextDouble() * 420) / 1000;

  double get _leafLayerHeight => math.max(
    150.0,
    math.min(
      _size.height * 0.56,
      _bounceY > 0 ? _bounceY - 18 : _size.height * 0.56,
    ),
  );

  void _spawnLeaf() {
    final boundsBottom = math.max(120.0, _leafLayerHeight);
    final span = math.max(48.0, boundsBottom);
    final areaY = span / 2;
    final startY = areaY + _random.nextDouble() * areaY;
    final endY = startY - (_random.nextDouble() * areaY * 2 - areaY);
    final controlY = _random.nextDouble() * endY + endY / 3;
    _scene.leaves.add(
      _Leaf(
        id: _scene.nextLeafId++,
        scale: 0.5 + _random.nextDouble() * 0.5,
        color: _leafColors[_random.nextInt(_leafColors.length)],
        startRotation: _random.nextDouble() * 180,
        endRotation: _random.nextDouble() * 360,
        x0: -100,
        y0: startY,
        x1: _size.width / 2,
        y1: controlY,
        x2: _size.width + 50,
        y2: endY,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = weatherScenePalette(_type, _windy, widget.night);
    return ValueListenableBuilder<double>(
      valueListenable: widget.scrollProgress,
      builder: (context, progress, _) {
        final baseOpacity = math.max(0.46, 0.96 - progress * 0.28);
        final glowOpacity = math.max(0.0, 0.20 - progress * 0.08);
        final canvasOpacity = math.max(0.0, 0.92 - progress * 0.34);
        final shadeOpacity = math.max(0.0, 0.18 - progress * 0.08);
        if (widget.animationsEnabled && _hasCanvasScene) {
          _particlePainter
            ..palette = palette
            ..night = widget.night
            ..type = _type
            // The reference fades the particle layer both globally and per
            // particle; folding both factors here keeps the same combined
            // curve without an extra compositing layer.
            ..fade = canvasOpacity * math.max(0.0, 1 - progress)
            // The leaf layer is a sibling of the canvas in the reference,
            // with its own opacity ramp — `max(0, 0.90 - 0.34p)` — and no
            // `(1 - p)` factor.
            ..leafFade = math.max(0.0, 0.90 - progress * 0.34)
            ..bounceY = _bounceY
            ..leafTop = _leafLayerHeight;
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    palette.top.withValues(alpha: baseOpacity),
                    palette.mid.withValues(alpha: baseOpacity),
                    palette.bottom.withValues(alpha: baseOpacity),
                  ],
                  stops: const <double>[0, 0.54, 1],
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    palette.glow.withValues(alpha: 0.18 * glowOpacity),
                    palette.glow.withValues(alpha: 0.04 * glowOpacity),
                    palette.glow.withValues(alpha: 0),
                  ],
                  stops: const <double>[0, 0.44, 1],
                ),
              ),
            ),
            // No canvas scene → no painter at all (`visible:
            // root.hasCanvasScene` on the reference Canvas).
            if (widget.animationsEnabled && _hasCanvasScene)
              CustomPaint(painter: _particlePainter),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    _nightShade.withValues(alpha: 0),
                    _nightShade.withValues(alpha: 0),
                    _nightShade.withValues(
                      alpha: (widget.night ? 0.12 : 0.09) * shadeOpacity,
                    ),
                  ],
                  stops: const <double>[0, 0.62, 1],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SceneState {
  List<_CloudBand> cloudBands = <_CloudBand>[];
  List<List<_RainDrop>> rainLayers = <List<_RainDrop>>[
    <_RainDrop>[],
    <_RainDrop>[],
    <_RainDrop>[],
  ];
  List<_Splash> splashes = <_Splash>[];
  List<_LightningStrike> lightning = <_LightningStrike>[];
  double lightningCooldown = 0;
  List<_Meteor> meteors = <_Meteor>[];
  List<_Snowflake> snowflakes = <_Snowflake>[];
  List<_Leaf> leaves = <_Leaf>[];
  double leafSpawnCooldown = -1;
  int nextLeafId = 0;
  double phase = 0;
}

class _WeatherParticlePainter extends CustomPainter {
  _WeatherParticlePainter({
    required this.scene,
    required this.onPainted,
    required this.onSize,
    super.repaint,
  });

  final _SceneState scene;
  final VoidCallback onPainted;
  final ValueChanged<Size> onSize;

  WeatherScenePalette palette = _defaultPalette;
  bool night = false;
  WeatherSceneType type = WeatherSceneType.clear;
  double fade = 1;

  /// Opacity ramp of the leaf layer — `max(0, 0.90 - 0.34p)`, independent
  /// of [fade] (QML `leafLayer.opacity`).
  double leafFade = 1;
  double bounceY = 0;
  double leafTop = 150;

  Color _a(Color color, double alpha) =>
      color.withValues(alpha: alpha.clamp(0.0, 1.0));

  @override
  void paint(Canvas canvas, Size size) {
    onPainted();
    onSize(size);
    if (size.isEmpty) {
      return;
    }

    if (night) {
      _drawStars(canvas, size);
    }
    _drawMeteors(canvas, size);
    for (var i = scene.cloudBands.length - 1; i >= 0; i--) {
      if (type == WeatherSceneType.rain || type == WeatherSceneType.storm) {
        _drawRainLayer(canvas, size, i);
      }
      if (type == WeatherSceneType.storm && i == 0) {
        _drawLightning(canvas, size);
      }
      final band = scene.cloudBands[i];
      _drawCloudBand(canvas, size, band);
    }
    if (type == WeatherSceneType.rain || type == WeatherSceneType.storm) {
      _drawSplashes(canvas, size);
    }
    if (type == WeatherSceneType.snow) {
      _drawSnow(canvas, size);
    }
    _drawLeaves(canvas, size);
  }

  void _drawStars(Canvas canvas, Size size) {
    for (var i = 0; i < 34; i++) {
      final twinkle =
          0.4 +
          0.6 *
              (0.5 +
                  0.5 *
                      math.sin(scene.phase * (0.5 + (i % 4) * 0.09) + i * 1.3));
      final x = ((i * 43 + (i % 3) * 29) % math.max(size.width, 1.0))
          .toDouble();
      final y = ((i * 27 + (i % 6) * 15) % math.max(80.0, size.height * 0.48))
          .toDouble();
      final r = 0.9 + (i % 3) * 0.35;
      canvas.drawCircle(
        Offset(x, y),
        r,
        Paint()..color = _a(palette.particle, twinkle * 0.56 * fade),
      );
    }
  }

  void _drawMeteors(Canvas canvas, Size size) {
    for (final meteor in scene.meteors) {
      if (!meteor.active) {
        continue;
      }
      final progress = (meteor.progress / meteor.travel).clamp(0.0, 1.0);
      final opacity = math.sin(progress * math.pi) * 0.92 * fade;
      if (opacity <= 0.02) {
        continue;
      }
      final head = Offset(
        meteor.startX + meteor.dx * meteor.progress,
        meteor.startY + meteor.dy * meteor.progress,
      );
      final tail = Offset(
        head.dx - meteor.dx * meteor.len,
        head.dy - meteor.dy * meteor.len,
      );
      canvas.drawLine(
        tail,
        head,
        Paint()
          ..color = _a(meteor.color, opacity * 0.16)
          ..strokeWidth = meteor.strokeWidth * 2.4
          ..strokeCap = StrokeCap.round,
      );
      const segments = 7;
      for (var s = 0; s < segments; s++) {
        final startRatio = s / segments;
        final endRatio = (s + 1) / segments;
        final segmentStart = Offset(
          tail.dx + (head.dx - tail.dx) * startRatio,
          tail.dy + (head.dy - tail.dy) * startRatio,
        );
        final segmentEnd = Offset(
          tail.dx + (head.dx - tail.dx) * endRatio,
          tail.dy + (head.dy - tail.dy) * endRatio,
        );
        canvas.drawLine(
          segmentStart,
          segmentEnd,
          Paint()
            ..color = _a(
              meteor.color,
              opacity * (0.10 + 0.90 * math.pow(endRatio, 1.7).toDouble()),
            )
            ..strokeWidth = meteor.strokeWidth * (0.30 + 0.70 * endRatio)
            ..strokeCap = StrokeCap.round,
        );
      }
      canvas.drawCircle(
        head,
        meteor.strokeWidth * 0.45,
        Paint()..color = _a(_meteorHead, math.min(1, opacity * 0.95)),
      );
    }
  }

  Path _cloudBandPath(
    Size size,
    double offset,
    double bandHeight,
    double arch,
  ) {
    final w = math.max(size.width, 1.0);
    final startX = -w + offset;
    return Path()
      ..moveTo(startX, 0)
      ..lineTo(startX + w * 2.0, 0)
      ..quadraticBezierTo(
        startX + w * 3.0,
        bandHeight * 0.5,
        startX + w * 2.0,
        bandHeight,
      )
      ..quadraticBezierTo(startX + w * 1.5, arch, startX + w, bandHeight)
      ..quadraticBezierTo(startX + w * 0.5, arch, startX, bandHeight)
      ..quadraticBezierTo(startX - w, bandHeight * 0.5, startX - w, 0)
      ..close();
  }

  void _drawCloudBand(Canvas canvas, Size size, _CloudBand band) {
    final path = _cloudBandPath(size, band.offset, band.height, band.arch);
    canvas.drawPath(path, Paint()..color = palette.cloudTone(band.toneIndex));
    canvas.drawPath(
      path,
      Paint()..color = _cloudMask.withValues(alpha: _cloudMaskOpacity),
    );
  }

  double _rainDropTop(_RainDrop drop, double bounce) {
    if (drop.age <= drop.delay) {
      return -drop.len;
    }
    final progress = math.min(1.0, (drop.age - drop.delay) / drop.duration);
    return -drop.len + (bounce + drop.len) * progress * progress;
  }

  void _drawRainLayer(Canvas canvas, Size size, int layerIndex) {
    if (layerIndex >= scene.rainLayers.length) {
      return;
    }
    final bounce = bounceY.clamp(0.0, size.height).toDouble();
    final color = type == WeatherSceneType.storm
        ? _rainStrokeStorm
        : _rainStroke;
    final paint = Paint()
      ..color = _a(color, fade)
      ..strokeCap = StrokeCap.butt;
    for (final drop in scene.rainLayers[layerIndex]) {
      if (drop.age < drop.delay) {
        continue;
      }
      final top = _rainDropTop(drop, bounce);
      paint.strokeWidth = drop.width;
      canvas.drawLine(
        Offset(drop.x, top),
        Offset(drop.x, top + drop.len),
        paint,
      );
    }
  }

  void _drawSplashes(Canvas canvas, Size size) {
    for (final splash in scene.splashes) {
      final progress = splash.age / splash.duration;
      final strokeWidth = 2 * (1 - progress);
      final startLength = progress * splash.totalLength;
      final endLength = math.min(
        splash.totalLength,
        startLength + splash.segmentLength,
      );
      if (strokeWidth <= 0.02 || endLength <= startLength) {
        continue;
      }
      final paint = Paint()
        ..color = _a(splash.color, fade)
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt
        ..style = PaintingStyle.stroke;
      final startPoint = _splashPointAt(splash, startLength);
      final endPoint = _splashPointAt(splash, endLength);
      final path = Path()
        ..moveTo(splash.x + startPoint.dx, splash.y + startPoint.dy);
      for (var i = 1; i < splash.samples.length - 1; i++) {
        final len = splash.lengths[i];
        if (len <= startLength || len >= endLength) {
          continue;
        }
        path.lineTo(
          splash.x + splash.samples[i].dx,
          splash.y + splash.samples[i].dy,
        );
      }
      path.lineTo(splash.x + endPoint.dx, splash.y + endPoint.dy);
      canvas.drawPath(path, paint);
    }
  }

  Offset _splashPointAt(_Splash splash, double targetLength) {
    if (targetLength <= 0) {
      return splash.samples.first;
    }
    if (targetLength >= splash.totalLength) {
      return splash.samples.last;
    }
    for (var i = 1; i < splash.samples.length; i++) {
      final len = splash.lengths[i];
      if (targetLength <= len) {
        final span = math.max(0.0001, len - splash.lengths[i - 1]);
        final ratio = (targetLength - splash.lengths[i - 1]) / span;
        final a = splash.samples[i - 1];
        final b = splash.samples[i];
        return a + (b - a) * ratio;
      }
    }
    return splash.samples.last;
  }

  void _drawSnow(Canvas canvas, Size size) {
    if (fade <= 0 || scene.snowflakes.isEmpty) {
      return;
    }
    final paint = Paint()..color = palette.particle;
    for (final flake in scene.snowflakes) {
      final fallProgress = (flake.age * flake.fallInverse)
          .clamp(0.0, 1.0)
          .toDouble();
      final growProgress = flake.age.clamp(0.0, 1.0).toDouble();
      final growEase = 0.5 - 0.5 * math.cos(growProgress * math.pi);
      final sway =
          flake.swayTarget * 0.5 * (1 - math.cos(flake.age * flake.swayFactor));
      final x = flake.x + sway;
      final y = flake.y + (flake.endY - flake.y) * fallProgress;
      final radius = flake.radiusBase * growEase;
      if (radius <= 0.05) {
        continue;
      }
      paint.color = palette.particle.withValues(alpha: flake.alphaBase * fade);
      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  void _drawLightning(Canvas canvas, Size size) {
    var flashOpacity = 0.0;
    for (final strike in scene.lightning) {
      final progress = (strike.age / strike.duration).clamp(0.0, 1.0);
      flashOpacity = math.max(
        flashOpacity,
        (math.pow(1 - progress, 10) * 0.22 * fade).toDouble(),
      );
    }
    if (flashOpacity > 0.01) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = _flashFill.withValues(alpha: flashOpacity),
      );
    }
    for (final strike in scene.lightning) {
      final progress = (strike.age / strike.duration).clamp(0.0, 1.0);
      final opacity = (math.pow(1 - progress, 4) * fade).toDouble();
      if (opacity <= 0.01 || strike.points.isEmpty) {
        continue;
      }
      final path = Path()
        ..moveTo(strike.points.first.dx, strike.points.first.dy);
      for (var i = 1; i < strike.points.length; i++) {
        path.lineTo(strike.points[i].dx, strike.points[i].dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = _flashFill.withValues(alpha: opacity.clamp(0.0, 1.0))
          ..style = PaintingStyle.stroke
          ..strokeWidth = strike.strokeWidth
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  void _drawLeaves(Canvas canvas, Size size) {
    if (scene.leaves.isEmpty) {
      return;
    }
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, leafTop));
    for (final leaf in scene.leaves) {
      final t = leaf.progress.clamp(0.0, 1.0).toDouble();
      final inverse = 1 - t;
      final x =
          inverse * inverse * leaf.x0 +
          2 * inverse * t * leaf.x1 +
          t * t * leaf.x2;
      final y =
          inverse * inverse * leaf.y0 +
          2 * inverse * t * leaf.y1 +
          t * t * leaf.y2;
      final rotation =
          leaf.startRotation + (leaf.endRotation - leaf.startRotation) * t;
      canvas.save();
      canvas
        ..translate(x, y)
        ..rotate(rotation * math.pi / 180)
        ..scale(leaf.scale);
      final paint = Paint()
        ..color = leaf.color.withValues(alpha: 0.88 * leafFade);
      final leafPath = Path()
        ..moveTo(0, 0)
        ..quadraticBezierTo(14, -16, 34, -10)
        ..quadraticBezierTo(46, -4, 34, 4)
        ..quadraticBezierTo(14, 12, 0, 0)
        ..close();
      canvas.drawPath(leafPath, paint);
      canvas.drawLine(
        const Offset(0, 0),
        const Offset(30, -4),
        Paint()
          ..color = leaf.color.withValues(alpha: 0.55 * leafFade)
          ..strokeWidth = 1.4
          ..strokeCap = StrokeCap.round,
      );
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WeatherParticlePainter oldDelegate) => true;
}
