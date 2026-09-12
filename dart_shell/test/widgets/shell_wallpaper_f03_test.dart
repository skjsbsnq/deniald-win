import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:denial_dart_shell/src/models/display_layout.dart';
import 'package:denial_dart_shell/src/state/display_layout.dart';
import 'package:denial_dart_shell/src/theme/motion.dart';
import 'package:denial_dart_shell/src/theme/shell_theme.dart';
import 'package:denial_dart_shell/src/wallpaper/state/wallpaper_controller.dart';
import 'package:denial_dart_shell/src/wallpaper/wallpaper.dart';
import 'package:denial_dart_shell/src/widgets/shell_wallpaper.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _fixturePath = 'test/widgets/fixtures/clipboard_screenshot.jpg';

void main() {
  test('reveal clip keeps the hole inside the transitioning rect', () {
    final path = wallpaperRevealClipPath(
      size: const Size(400, 600),
      targetRect: const Rect.fromLTWH(0, 0, 400, 600),
      originFraction: const Offset(0.5, 0.5),
      progress: 0.5,
    );
    // The reveal center is inside the growing hole, while a corner still
    // shows the outgoing wallpaper.
    expect(path.contains(const Offset(200, 300)), isFalse);
    expect(path.contains(const Offset(5, 5)), isTrue);
  });

  testWidgets(
    'transition clip subtree is bounded to the transitioning output',
    (tester) async {
      const left = DisplayOutput(
        monitorId: 0,
        name: 'left',
        logicalRect: Rect.fromLTWH(0, 0, 400, 600),
        pixelSize: Size(400, 600),
        scale: 1.0,
        refreshRate: 60.0,
      );
      const right = DisplayOutput(
        monitorId: 1,
        name: 'right',
        logicalRect: Rect.fromLTWH(400, 0, 400, 600),
        pixelSize: Size(400, 600),
        scale: 1.0,
        refreshRate: 60.0,
      );
      final layout = DisplayLayout(
        epoch: 0,
        globalOrigin: Offset.zero,
        logicalSize: const Size(800, 600),
        pixelSize: const Size(800, 600),
        engineScale: 1.0,
        tickerMonitorId: 0,
        systemBarMonitorId: 0,
        systemBarSide: SystemBarSide.top,
        outputs: const [left, right],
      );
      final state = WallpaperExperienceState.initial().copyWith(
        assignment: WallpaperAssignment(
          all: WallpaperResource.file(_fixturePath),
        ),
        outgoingAssignment: WallpaperAssignment(
          all: WallpaperResource.file(_fixturePath),
        ),
        transitionTarget: const WallpaperTarget.output('right'),
        transitionId: 7,
      );
      final container = ProviderContainer(
        overrides: [
          wallpaperControllerProvider.overrideWith(
            () => _FixedWallpaperController(state),
          ),
          displayLayoutProvider.overrideWithBuild((ref, controller) => layout),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MediaQuery(
            data: MediaQueryData(size: Size(800, 600)),
            child: ShellTheme(
              data: ShellThemeData(),
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: ShellWallpaper(),
              ),
            ),
          ),
        ),
      );

      final tweenFinder = find.byType(TweenAnimationBuilder<double>);
      expect(tweenFinder, findsOneWidget);
      final tween = tester.widget<TweenAnimationBuilder<double>>(tweenFinder);
      expect(tween.duration, Motion.wallpaperReveal);
      expect(tween.curve, Motion.md3Emphasized);

      // The clipped subtree spans only the output under transition instead
      // of the whole wallpaper canvas.
      final positioned = tester.widget<Positioned>(
        find.ancestor(of: tweenFinder, matching: find.byType(Positioned)),
      );
      expect(positioned.left, right.logicalRect.left);
      expect(positioned.top, right.logicalRect.top);
      expect(positioned.width, right.logicalRect.width);
      expect(positioned.height, right.logicalRect.height);

      final clip = find.byType(ClipPath);
      expect(clip, findsOneWidget);
      // The static outgoing scene sits behind its own repaint boundary so a
      // reclip does not re-record it.
      expect(
        find.descendant(of: clip, matching: find.byType(RepaintBoundary)),
        findsOneWidget,
      );
      expect(find.byType(WallpaperScene), findsNWidgets(2));

      await tester.pumpAndSettle();
      expect(find.byType(WallpaperScene), findsOneWidget);
      expect(find.byType(ClipPath), findsNothing);
    },
  );

  testWidgets('image transformer wraps the resolved wallpaper provider', (
    tester,
  ) async {
    const output = DisplayOutput(
      monitorId: 1,
      name: 'right',
      logicalRect: Rect.fromLTWH(400, 0, 400, 600),
      pixelSize: Size(400, 600),
      scale: 1.0,
      refreshRate: 60.0,
    );
    Size? seenTarget;
    Size? seenLogical;
    final container = ProviderContainer(
      overrides: [
        wallpaperControllerProvider.overrideWith(
          () => _FixedWallpaperController(
            WallpaperExperienceState.initial().copyWith(
              assignment: WallpaperAssignment(
                all: WallpaperResource.file(_fixturePath),
              ),
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MediaQuery(
          data: const MediaQueryData(size: Size(800, 600)),
          child: ShellTheme(
            data: const ShellThemeData(),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: ShellOutputWallpaper(
                output: output,
                imageTransformer:
                    (
                      provider, {
                      required targetPixelSize,
                      required targetLogicalSize,
                    }) {
                      seenTarget = targetPixelSize;
                      seenLogical = targetLogicalSize;
                      return ResizeImage(provider, width: 16);
                    },
              ),
            ),
          ),
        ),
      ),
    );

    final image = tester.widget<Image>(
      find.descendant(
        of: find.byType(ShellOutputWallpaper),
        matching: find.byType(Image),
      ),
    );
    expect(image.image, isA<ResizeImage>());
    expect(seenTarget, const Size(400, 600));
    expect(seenLogical, const Size(400, 600));
  });

  test('blurred provider passes through at non-positive sigma', () {
    final base = FileImage(File(_fixturePath));
    expect(
      identical(
        blurredWallpaperImageProvider(
          base,
          sigma: 0,
          targetPixelSize: const Size(64, 64),
          targetLogicalSize: const Size(64, 64),
          filterBuilder: _testBlurFilter,
        ),
        base,
      ),
      isTrue,
    );
  });

  test('blurred provider equality keys on sigma and target size', () {
    final base = FileImage(File(_fixturePath));
    final a = blurredWallpaperImageProvider(
      base,
      sigma: 8,
      targetPixelSize: const Size(64, 64),
      targetLogicalSize: const Size(64, 64),
      filterBuilder: _testBlurFilter,
    );
    final b = blurredWallpaperImageProvider(
      base,
      sigma: 8,
      targetPixelSize: const Size(64, 64),
      targetLogicalSize: const Size(64, 64),
      filterBuilder: _testBlurFilter,
    );
    final c = blurredWallpaperImageProvider(
      base,
      sigma: 16,
      targetPixelSize: const Size(64, 64),
      targetLogicalSize: const Size(64, 64),
      filterBuilder: _testBlurFilter,
    );
    expect(a, equals(b));
    expect(a, isNot(equals(c)));
  });

  testWidgets('blurred frames are rasterized small and actually blended', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final source = await _splitFrame();
      final provider = blurredWallpaperImageProvider(
        _SingleFrameProvider(ImageInfo(image: source)),
        sigma: 16,
        targetPixelSize: const Size(64, 64),
        targetLogicalSize: const Size(64, 64),
        filterBuilder: _testBlurFilter,
      );
      final stream = provider.resolve(ImageConfiguration.empty);
      final done = Completer<ImageInfo>();
      stream.addListener(
        ImageStreamListener(
          (info, synchronousCall) => done.complete(info),
          onError: (exception, stackTrace) =>
              done.completeError(exception, stackTrace),
        ),
      );
      final info = await done.future;

      // Sigma 16 downsamples the blur buffer by 4, so the 64x64 source
      // rasterizes at 16x16. scale is image px per logical px, so the
      // emitted frame keeps the source's logical size via division:
      // 1.0 / 4.
      expect(info.image.width, 16);
      expect(info.image.height, 16);
      expect(info.scale, 0.25);

      final data = await info.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      expect(data, isNotNull);
      final center = (8 * 16 + 8) * 4;
      final r = data!.getUint8(center);
      final g = data.getUint8(center + 1);
      final b = data.getUint8(center + 2);
      // The source is half white, half black; at the seam the blur must
      // produce a mid gray rather than either edge color.
      expect(r, greaterThan(40));
      expect(r, lessThan(215));
      expect((r - g).abs(), lessThan(16));
      expect((g - b).abs(), lessThan(16));
    });
  });

  testWidgets('blur kernel converts logical sigma by output pixel ratio', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final source = await _splitFrame();
      double? seenSigma;
      final provider = blurredWallpaperImageProvider(
        _SingleFrameProvider(ImageInfo(image: source)),
        sigma: 16,
        // A 64x64 device target over 32x32 logical px is a 2x output. The
        // old ImageFiltered layer would have rasterized the logical sigma 16
        // as a 32-device-px kernel; the reduced-resolution pass must ask the
        // builder for 16 * 2 / (factor 4 * coverScale 1) = 8.
        targetPixelSize: const Size(64, 64),
        targetLogicalSize: const Size(32, 32),
        filterBuilder: (sigma) {
          seenSigma = sigma;
          return _testBlurFilter(sigma);
        },
      );
      final stream = provider.resolve(ImageConfiguration.empty);
      final done = Completer<ImageInfo>();
      stream.addListener(
        ImageStreamListener(
          (info, synchronousCall) => done.complete(info),
          onError: (exception, stackTrace) =>
              done.completeError(exception, stackTrace),
        ),
      );
      final info = await done.future;
      expect(info.image.width, 16);
      expect(seenSigma, 8.0);
    });
  });

  testWidgets('span fallback keeps the engine pixel scale', (tester) async {
    // The layout's only output sits outside the canvas, so the wallpaper
    // paints through the span fallback sized by the global layout pixels.
    // Its logical target must be derived from the engine scale (2x), not
    // the canvas: 3200/800 would inflate the blur kernel to 4x.
    const output = DisplayOutput(
      monitorId: 0,
      name: 'far',
      logicalRect: Rect.fromLTWH(4000, 0, 400, 600),
      pixelSize: Size(800, 1200),
      scale: 2.0,
      refreshRate: 60.0,
    );
    final layout = DisplayLayout(
      epoch: 0,
      globalOrigin: Offset.zero,
      logicalSize: const Size(1600, 1200),
      pixelSize: const Size(3200, 2400),
      engineScale: 2.0,
      tickerMonitorId: 0,
      systemBarMonitorId: 0,
      systemBarSide: SystemBarSide.top,
      outputs: const [output],
    );
    Size? seenTarget;
    Size? seenLogical;
    final container = ProviderContainer(
      overrides: [
        wallpaperControllerProvider.overrideWith(
          () => _FixedWallpaperController(
            WallpaperExperienceState.initial().copyWith(
              assignment: WallpaperAssignment(
                all: WallpaperResource.file(_fixturePath),
              ),
            ),
          ),
        ),
        displayLayoutProvider.overrideWithBuild((ref, controller) => layout),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MediaQuery(
          data: const MediaQueryData(size: Size(800, 600)),
          child: ShellTheme(
            data: const ShellThemeData(),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: ShellWallpaper(
                imageTransformer:
                    (
                      provider, {
                      required targetPixelSize,
                      required targetLogicalSize,
                    }) {
                      seenTarget = targetPixelSize;
                      seenLogical = targetLogicalSize;
                      return provider;
                    },
              ),
            ),
          ),
        ),
      ),
    );

    expect(seenTarget, const Size(3200, 2400));
    expect(seenLogical, const Size(1600, 1200));
  });

  testWidgets('blurred completer detaches upstream when its listeners leave', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final source = await _splitFrame();
      final base = _RecordingFrameProvider(ImageInfo(image: source));
      final provider = blurredWallpaperImageProvider(
        base,
        sigma: 16,
        targetPixelSize: const Size(64, 64),
        targetLogicalSize: const Size(64, 64),
        filterBuilder: _testBlurFilter,
      );
      final stream = provider.resolve(ImageConfiguration.empty);

      // The image cache keeps both completers alive between listeners, like
      // a lock surface dropping its Image widget while staying cached. Its
      // own bookkeeping listeners also show up in the counters, so the
      // assertions below compare deltas after the first frame settled.
      final emitted = Completer<void>();
      void onImage(ImageInfo info, bool synchronousCall) {
        info.dispose();
        if (!emitted.isCompleted) {
          emitted.complete();
        }
      }

      void onError(Object exception, StackTrace? stackTrace) {}

      final first = ImageStreamListener(onImage, onError: onError);
      stream.addListener(first);
      for (var i = 0; i < 10 && base.lastCompleter == null; i++) {
        await null;
      }
      final upstream = base.lastCompleter;
      expect(upstream, isNotNull);
      // Wait for the blurred frame: emitting retires the cache's pending
      // listener, leaving our listener as the only real one.
      await emitted.future;
      final attach0 = upstream!.attachCount;
      final detach0 = upstream.detachCount;

      stream.removeListener(first);
      expect(upstream.detachCount, detach0 + 1);

      // A later listener reattaches, re-resolving upstream through the
      // shared cache (the same completer while it stays cached, a fresh one
      // after eviction).
      final second = ImageStreamListener(onImage, onError: onError);
      stream.addListener(second);
      expect(upstream.attachCount, attach0 + 1);
      stream.removeListener(second);
      expect(upstream.detachCount, detach0 + 2);
    });
  });
}

ui.ImageFilter _testBlurFilter(double sigma) => ui.ImageFilter.blur(
  sigmaX: sigma,
  sigmaY: sigma,
  tileMode: ui.TileMode.clamp,
);

/// A 64x64 frame, white on the left half and black on the right.
Future<ui.Image> _splitFrame() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 32, 64),
    Paint()..color = const Color(0xFFFFFFFF),
  );
  canvas.drawRect(
    const Rect.fromLTWH(32, 0, 32, 64),
    Paint()..color = const Color(0xFF000000),
  );
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(64, 64);
  } finally {
    picture.dispose();
  }
}

class _FixedWallpaperController extends WallpaperController {
  _FixedWallpaperController(this._state);

  final WallpaperExperienceState _state;

  @override
  WallpaperExperienceState build() => _state;
}

/// An upstream completer that records listener attach/detach so tests can
/// watch the blurred wrapper release it without touching protected members.
/// It emits a single frame on first listen, like a decoded static
/// wallpaper; the emit also retires the image cache's pending listener.
class _CountingCompleter extends ImageStreamCompleter {
  _CountingCompleter(this._info);

  final ImageInfo _info;
  int attachCount = 0;
  int detachCount = 0;
  bool _emitted = false;

  @override
  void addListener(ImageStreamListener listener) {
    attachCount += 1;
    super.addListener(listener);
    if (!_emitted) {
      _emitted = true;
      setImage(_info.clone());
    }
  }

  @override
  void removeListener(ImageStreamListener listener) {
    detachCount += 1;
    super.removeListener(listener);
  }
}

class _RecordingFrameProvider extends ImageProvider<Object> {
  _RecordingFrameProvider(this._info);

  final ImageInfo _info;
  _CountingCompleter? lastCompleter;

  @override
  Future<Object> obtainKey(ImageConfiguration configuration) =>
      Future<Object>.value(this);

  @override
  ImageStreamCompleter loadImage(Object key, ImageDecoderCallback decode) {
    return lastCompleter = _CountingCompleter(_info);
  }
}

class _SingleFrameProvider extends ImageProvider<Object> {
  _SingleFrameProvider(this._info);

  final ImageInfo _info;

  @override
  Future<Object> obtainKey(ImageConfiguration configuration) =>
      Future<Object>.value(this);

  @override
  ImageStreamCompleter loadImage(Object key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(Future<ImageInfo>.value(_info));
}
