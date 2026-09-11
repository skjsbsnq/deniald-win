import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:denial_dart_shell/src/wallpaper/wallpaper.dart';
import 'package:denial_dart_shell/src/wallpaper/widgets/wallpaper_image.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const resource = WallpaperResource.asset('assets/wallpapers/test.png');

  // WallpaperExperienceState.initial() reports Size.zero before the first
  // layout; decoding the raw source there would rasterize 8K or panoramic
  // wallpapers at native resolution.
  test('invalid target sizes return a provider with a decode size cap', () {
    for (final size in <Size>[
      Size.zero,
      Size.infinite,
      const Size(-4, 200),
      const Size(200, double.nan),
      const Size(double.infinity, 200),
    ]) {
      final provider = wallpaperImageProvider(resource, targetPixelSize: size);
      expect(
        provider,
        isA<ResizeImage>(),
        reason: 'targetPixelSize $size must not decode the raw image',
      );
      final resized = provider as ResizeImage;
      expect(resized.width, lessThanOrEqualTo(2560));
      expect(resized.height, lessThanOrEqualTo(2560));
      expect(resized.policy, ResizeImagePolicy.fit);
      expect(resized.allowUpscaling, isFalse);
      expect(resized.imageProvider, isA<AssetImage>());
    }
  });

  test('a file resource invalid target is capped the same way', () {
    final provider = wallpaperImageProvider(
      const WallpaperResource.file('/tmp/wallpaper.png'),
      targetPixelSize: Size.zero,
    );
    expect(provider, isA<ResizeImage>());
    expect((provider as ResizeImage).imageProvider, isA<FileImage>());
  });

  test('valid target sizes keep the cover-fit provider unchanged', () {
    const target = Size(1920, 1080);
    final provider = wallpaperImageProvider(resource, targetPixelSize: target);
    expect(provider, isNot(isA<ResizeImage>()));
    expect(provider, isNot(isA<AssetImage>()));
    // Equal providers share one cache entry for identical targets.
    expect(provider, wallpaperImageProvider(resource, targetPixelSize: target));
  });

  // The decode callback is never reached with real codec work here: the test
  // intercepts getTargetSize and aborts, so a few arbitrary bytes suffice.
  testWidgets('cover resize caps the longest decoded edge of extreme sources', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final dir = Directory.systemTemp.createTempSync('wallpaper_image_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/source.bin')
        ..writeAsBytesSync(<int>[0, 1, 2, 3]);

      final provider = wallpaperImageProvider(
        WallpaperResource.file(file.path),
        targetPixelSize: const Size(1920, 1080),
      );
      final key = await provider.obtainKey(ImageConfiguration.empty);

      Future<ui.TargetImageSize> decodeTargetFor(
        int intrinsicWidth,
        int intrinsicHeight,
      ) {
        final done = Completer<void>();
        ui.TargetImageSize? captured;
        final completer = provider.loadImage(key, (
          ui.ImmutableBuffer buffer, {
          ui.TargetImageSizeCallback? getTargetSize,
        }) {
          captured = getTargetSize!(intrinsicWidth, intrinsicHeight);
          return Future<ui.Codec>.error(
            StateError('interrupted after capturing target size'),
          );
        });
        completer.addListener(
          ImageStreamListener(
            (image, synchronousCall) => done.complete(),
            onError: (exception, stackTrace) => done.complete(),
          ),
        );
        return done.future.then((_) => captured!);
      }

      // Pure cover-fit would decode the 8000px edge at 4320px; the cap must
      // pull it back inside the 2560px bound, on either axis.
      final wide = await decodeTargetFor(8000, 2000);
      expect(wide.width, lessThanOrEqualTo(2560));
      expect(wide.height, lessThanOrEqualTo(2560));
      expect(wide.height, lessThan(1080));

      final tall = await decodeTargetFor(2000, 8000);
      expect(tall.width, lessThanOrEqualTo(2560));
      expect(tall.height, lessThanOrEqualTo(2560));
      expect(tall.width, lessThan(1920));

      // A source already inside the bound still decodes at its cover-fit
      // size, large enough to cover the 1920x1080 target on both axes.
      final normal = await decodeTargetFor(4000, 3000);
      expect(normal.width, greaterThanOrEqualTo(1920));
      expect(normal.height, greaterThanOrEqualTo(1080));
      expect(normal.width, lessThanOrEqualTo(2560));
      expect(normal.height, lessThanOrEqualTo(2560));
    });
  });
}
