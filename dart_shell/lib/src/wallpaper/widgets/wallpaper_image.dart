import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../wallpaper.dart';

/// Longest decoded edge allowed when the caller cannot name a target size.
/// Large enough to cover any single output, small enough to keep 8K or
/// panoramic sources from decoding at native resolution.
const int _maxWallpaperDecodeEdge = 2560;

ImageProvider<Object> wallpaperImageProvider(
  WallpaperResource resource, {
  required Size targetPixelSize,
}) {
  final provider = _rawWallpaperImageProvider(resource);
  if (!targetPixelSize.width.isFinite ||
      !targetPixelSize.height.isFinite ||
      targetPixelSize.width <= 0.0 ||
      targetPixelSize.height <= 0.0) {
    return ResizeImage(
      provider,
      width: _maxWallpaperDecodeEdge,
      height: _maxWallpaperDecodeEdge,
      policy: ResizeImagePolicy.fit,
    );
  }
  return _CoverResizeImage(
    provider,
    width: targetPixelSize.width.ceil(),
    height: targetPixelSize.height.ceil(),
  );
}

ImageProvider<Object> _rawWallpaperImageProvider(WallpaperResource resource) {
  return switch (resource.kind) {
    WallpaperResourceKind.asset => AssetImage(resource.path),
    WallpaperResourceKind.file => FileImage(File(resource.path)),
  };
}

ImageProvider<Object>? wallpaperCandidateImageProvider(
  WallpaperCandidate candidate, {
  int? cacheHeight,
}) {
  ImageProvider<Object>? provider;
  final resource = candidate.resource;
  if (resource != null) {
    provider = _rawWallpaperImageProvider(resource);
  } else {
    final uri = candidate.previewUri;
    if (uri.scheme == 'https') {
      provider = NetworkImage(uri.toString());
    } else if (uri.scheme == 'file') {
      provider = FileImage(File.fromUri(uri));
    } else if (uri.scheme == 'asset' && uri.path.isNotEmpty) {
      provider = AssetImage(uri.path);
    }
  }
  if (provider == null || cacheHeight == null || cacheHeight <= 0) {
    return provider;
  }
  return ResizeImage.resizeIfNeeded(null, cacheHeight, provider);
}

@immutable
class _CoverResizeImageKey {
  const _CoverResizeImageKey(this.providerKey, this.width, this.height);

  final Object providerKey;
  final int width;
  final int height;

  @override
  bool operator ==(Object other) =>
      other is _CoverResizeImageKey &&
      other.providerKey == providerKey &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(providerKey, width, height);
}

/// Decodes an image to the smallest size that can cover the target without
/// changing its aspect ratio. Unlike [ResizeImagePolicy.fit], neither axis can
/// end up smaller than the surface and be upscaled again by [BoxFit.cover],
/// unless the longest-edge cap takes precedence for an extreme source.
@immutable
class _CoverResizeImage extends ImageProvider<_CoverResizeImageKey> {
  const _CoverResizeImage(
    this.imageProvider, {
    required this.width,
    required this.height,
  });

  final ImageProvider<Object> imageProvider;
  final int width;
  final int height;

  @override
  ImageStreamCompleter loadImage(
    _CoverResizeImageKey key,
    ImageDecoderCallback decode,
  ) {
    Future<ui.Codec> decodeCover(
      ui.ImmutableBuffer buffer, {
      ui.TargetImageSizeCallback? getTargetSize,
    }) {
      assert(
        getTargetSize == null,
        '_CoverResizeImage cannot wrap a provider that already resizes.',
      );
      return decode(
        buffer,
        getTargetSize: (intrinsicWidth, intrinsicHeight) {
          var scale = math.min(
            1.0,
            math.max(width / intrinsicWidth, height / intrinsicHeight),
          );
          // A source far longer on one axis than the cover target still
          // decodes that whole edge, so bound the longest decoded edge too.
          final limit = math.max(
            math.max(width, height),
            _maxWallpaperDecodeEdge,
          );
          final decodedLongest =
              math.max(intrinsicWidth, intrinsicHeight) * scale;
          if (decodedLongest > limit) {
            scale *= limit / decodedLongest;
          }
          // Clamp after ceil: floating-point error in scale must not round
          // the longest edge up past the limit.
          return ui.TargetImageSize(
            width: math.min(
              intrinsicWidth,
              math.min(limit, (intrinsicWidth * scale).ceil()),
            ),
            height: math.min(
              intrinsicHeight,
              math.min(limit, (intrinsicHeight * scale).ceil()),
            ),
          );
        },
      );
    }

    final completer = imageProvider.loadImage(key.providerKey, decodeCover);
    if (!kReleaseMode) {
      completer.debugLabel =
          '${completer.debugLabel} - CoverResized(${key.width}×${key.height})';
    }
    completer.addEphemeralErrorListener((exception, stackTrace) {
      scheduleMicrotask(() {
        PaintingBinding.instance.imageCache.evict(key);
      });
    });
    return completer;
  }

  @override
  Future<_CoverResizeImageKey> obtainKey(ImageConfiguration configuration) {
    return imageProvider
        .obtainKey(configuration)
        .then((key) => _CoverResizeImageKey(key, width, height));
  }

  @override
  bool operator ==(Object other) =>
      other is _CoverResizeImage &&
      other.imageProvider == imageProvider &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(imageProvider, width, height);
}

/// Wraps [imageProvider] so each decoded frame is rasterized once through a
/// blur pass at a reduced resolution, then cached as a plain image. The lock
/// screen paints that image directly, which keeps the large gaussian
/// convolution it used to run on the full-screen backdrop out of the lock
/// surface's first frame.
///
/// [sigma] is the desired on-screen sigma in logical pixels;
/// [targetLogicalSize] converts it into the device-pixel radius the kernel
/// needs on this output. [filterBuilder] supplies the filter applied at the
/// reduced resolution so the caller owns the kernel and tile-mode choices.
ImageProvider<Object> blurredWallpaperImageProvider(
  ImageProvider<Object> imageProvider, {
  required double sigma,
  required Size targetPixelSize,
  required Size targetLogicalSize,
  required ui.ImageFilter Function(double sigma) filterBuilder,
}) {
  if (!sigma.isFinite || sigma <= 0.0) {
    return imageProvider;
  }
  return _BlurredWallpaperImage(
    imageProvider,
    sigma: sigma,
    targetPixelSize: targetPixelSize,
    targetLogicalSize: targetLogicalSize,
    filterBuilder: filterBuilder,
  );
}

/// How far below the decoded size a blurred frame is rasterized. Larger
/// sigmas keep a constant, small convolution footprint; the kernel is built
/// at this scale and magnified back when the frame is painted.
double _blurDownsampleFactor(double sigma) => (sigma / 4).clamp(1.0, 4.0);

/// Device pixels per logical pixel on the target surface. Degenerate or
/// unknown geometry falls back to 1x rather than dropping the blur.
double _wallpaperPixelScale(Size targetPixelSize, Size targetLogicalSize) {
  if (!targetPixelSize.width.isFinite ||
      !targetPixelSize.height.isFinite ||
      !targetLogicalSize.width.isFinite ||
      !targetLogicalSize.height.isFinite ||
      targetLogicalSize.width <= 0.0 ||
      targetLogicalSize.height <= 0.0) {
    return 1.0;
  }
  return math.max(
    targetPixelSize.width / targetLogicalSize.width,
    targetPixelSize.height / targetLogicalSize.height,
  );
}

@immutable
class _BlurredWallpaperImageKey {
  const _BlurredWallpaperImageKey(
    this.baseKey,
    this.sigma,
    this.targetPixelSize,
    this.pixelScale,
    this.filterBuilder,
  );

  final Object baseKey;
  final double sigma;
  final Size targetPixelSize;
  final double pixelScale;

  /// Part of the cache identity: top-level tear-offs compare canonical, so
  /// two transformers sharing (baseKey, sigma, targetPixelSize, pixelScale)
  /// cannot collide on a cached frame built with the other filter.
  final ui.ImageFilter Function(double sigma) filterBuilder;

  @override
  bool operator ==(Object other) =>
      other is _BlurredWallpaperImageKey &&
      other.baseKey == baseKey &&
      other.sigma == sigma &&
      other.targetPixelSize == targetPixelSize &&
      other.pixelScale == pixelScale &&
      other.filterBuilder == filterBuilder;

  @override
  int get hashCode =>
      Object.hash(baseKey, sigma, targetPixelSize, pixelScale, filterBuilder);
}

class _BlurredWallpaperImage extends ImageProvider<_BlurredWallpaperImageKey> {
  _BlurredWallpaperImage(
    this.imageProvider, {
    required this.sigma,
    required this.targetPixelSize,
    required Size targetLogicalSize,
    required this.filterBuilder,
  }) : pixelScale = _wallpaperPixelScale(targetPixelSize, targetLogicalSize);

  final ImageProvider<Object> imageProvider;
  final double sigma;
  final Size targetPixelSize;
  final double pixelScale;
  final ui.ImageFilter Function(double sigma) filterBuilder;

  @override
  ImageStreamCompleter loadImage(
    _BlurredWallpaperImageKey key,
    ImageDecoderCallback decode,
  ) {
    final completer = _BlurredWallpaperCompleter(
      key,
      // Resolving through the shared cache lets the lock screen reuse the
      // frame the desktop already decoded instead of decoding a second copy.
      () => PaintingBinding.instance.imageCache.putIfAbsent(
        key.baseKey,
        () => imageProvider.loadImage(key.baseKey, decode),
        onError: (exception, stackTrace) {
          scheduleMicrotask(() {
            PaintingBinding.instance.imageCache.evict(key.baseKey);
          });
        },
      ),
    );
    if (!kReleaseMode) {
      completer.debugLabel = '${key.baseKey} - Blurred(${key.sigma})';
    }
    completer.addEphemeralErrorListener((exception, stackTrace) {
      scheduleMicrotask(() {
        PaintingBinding.instance.imageCache.evict(key);
      });
    });
    return completer;
  }

  @override
  Future<_BlurredWallpaperImageKey> obtainKey(
    ImageConfiguration configuration,
  ) {
    return imageProvider
        .obtainKey(configuration)
        .then(
          (key) => _BlurredWallpaperImageKey(
            key,
            sigma,
            targetPixelSize,
            pixelScale,
            filterBuilder,
          ),
        );
  }

  @override
  bool operator ==(Object other) =>
      other is _BlurredWallpaperImage &&
      other.imageProvider == imageProvider &&
      other.sigma == sigma &&
      other.targetPixelSize == targetPixelSize &&
      other.pixelScale == pixelScale &&
      other.filterBuilder == filterBuilder;

  @override
  int get hashCode => Object.hash(
    imageProvider,
    sigma,
    targetPixelSize,
    pixelScale,
    filterBuilder,
  );
}

/// Rebroadcasts every upstream frame after rasterizing it through the blur
/// pass. The upstream listener is only held while this completer has
/// listeners of its own: a completer kept alive in the image cache with no
/// listeners detaches, so an animated wallpaper stops paying for offscreen
/// convolutions nobody consumes and the shared decode cache keeps evicting
/// normally. Reattaching resolves upstream through the cache again, which
/// reloads it if it was evicted meanwhile.
class _BlurredWallpaperCompleter extends ImageStreamCompleter {
  _BlurredWallpaperCompleter(this._key, this._upstreamLoader);

  final _BlurredWallpaperImageKey _key;

  /// Re-resolves the shared upstream completer on each attach, so a
  /// completer revived after its source was evicted loads a fresh one.
  final ImageStreamCompleter? Function() _upstreamLoader;

  ImageStreamCompleter? _upstream;
  int _frameTicket = 0;
  bool _detached = false;

  late final ImageStreamListener _upstreamListener = ImageStreamListener(
    (info, synchronousCall) {
      final ticket = ++_frameTicket;
      unawaited(_emitBlurred(info, ticket));
    },
    onError: (exception, stackTrace) {
      if (!_detached) {
        reportError(exception: exception, stack: stackTrace);
      }
    },
  );

  @override
  void addListener(ImageStreamListener listener) {
    _attachUpstream();
    super.addListener(listener);
  }

  void _attachUpstream() {
    if (_detached || _upstream != null) {
      return;
    }
    final upstream = _upstreamLoader();
    if (upstream == null) {
      reportError(
        exception: StateError('wallpaper blur source failed to decode'),
      );
      return;
    }
    _upstream = upstream;
    upstream.addListener(_upstreamListener);
    // removeListener clears these callbacks after firing them, so the hook
    // is re-armed on each attach rather than inside the callback.
    addOnLastListenerRemovedCallback(_detachUpstream);
  }

  void _detachUpstream() {
    final upstream = _upstream;
    if (upstream == null) {
      return;
    }
    _upstream = null;
    upstream.removeListener(_upstreamListener);
  }

  Future<void> _emitBlurred(ImageInfo info, int ticket) async {
    final factor = _blurDownsampleFactor(_key.sigma);
    try {
      final blurred = await _blurredFrame(info.image, factor);
      if (_detached || ticket != _frameTicket) {
        blurred.dispose();
        return;
      }
      setImage(
        ImageInfo(
          image: blurred,
          // scale is image px per logical px; the emitted frame is factor
          // times smaller than the source, so dividing keeps the declared
          // logical size equal to what the source reported.
          scale: info.scale / factor,
          debugLabel: info.debugLabel,
        ),
      );
    } catch (exception, stackTrace) {
      if (!_detached) {
        reportError(exception: exception, stack: stackTrace);
      }
    } finally {
      // This listener owns the incoming frame; releasing it in finally keeps
      // it disposed exactly once even when setImage or blurred.dispose
      // throws.
      info.dispose();
    }
  }

  Future<ui.Image> _blurredFrame(ui.Image frame, double factor) {
    final outWidth = math.max(1, (frame.width / factor).round());
    final outHeight = math.max(1, (frame.height / factor).round());
    // The emitted frame is painted with the same cover fit the source would
    // have had, so a kernel built at the reduced resolution lands on screen
    // magnified by exactly factor * coverScale. sigma is logical: pixelScale
    // turns it into the device-pixel radius the blur had as an ImageFiltered
    // layer.
    final coverScale =
        _key.targetPixelSize.width > 0.0 && _key.targetPixelSize.height > 0.0
        ? math.max(
            _key.targetPixelSize.width / frame.width,
            _key.targetPixelSize.height / frame.height,
          )
        : 1.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImageRect(
      frame,
      Offset.zero & Size(frame.width.toDouble(), frame.height.toDouble()),
      Offset.zero & Size(outWidth.toDouble(), outHeight.toDouble()),
      Paint()
        ..filterQuality = FilterQuality.medium
        ..imageFilter = _key.filterBuilder(
          _key.sigma * _key.pixelScale / (factor * coverScale),
        ),
    );
    final picture = recorder.endRecording();
    return picture.toImage(outWidth, outHeight).whenComplete(picture.dispose);
  }

  @override
  void onDisposed() {
    _detached = true;
    _detachUpstream();
    super.onDisposed();
  }
}
