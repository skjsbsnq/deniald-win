import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../models/tray_item.dart';

/// Defensive limits for untrusted pixmap data received over the session bus.
const int maxSniPixmapDimension = 4096;
const int maxSniPixmapBytes = 16 * 1024 * 1024;

/// Returns the required RGBA byte count, or `null` for invalid/oversized data.
int? sniPixmapByteCount(int width, int height) {
  if (width <= 0 ||
      height <= 0 ||
      width > maxSniPixmapDimension ||
      height > maxSniPixmapDimension) {
    return null;
  }
  final pixels = width * height;
  if (pixels > maxSniPixmapBytes ~/ 4) return null;
  return pixels * 4;
}

/// Converts network-byte-order (Big-Endian) ARGB32 bytes into [ui.PixelFormat.rgba8888] bytes.
///
/// In the StatusNotifierItem D-Bus specification, pixmaps are passed in network order ARGB32:
/// - Byte 0: Alpha (A)
/// - Byte 1: Red (R)
/// - Byte 2: Green (G)
/// - Byte 3: Blue (B)
///
/// Flutter's [ui.PixelFormat.rgba8888] expects byte order:
/// - Byte 0: Red (R)
/// - Byte 1: Green (G)
/// - Byte 2: Blue (B)
/// - Byte 3: Alpha (A)
Uint8List argbToRgba(Uint8List argb, int width, int height) {
  final byteCount = sniPixmapByteCount(width, height);
  if (byteCount == null) {
    throw ArgumentError(
      'Invalid or oversized pixmap dimensions: ${width}x$height',
    );
  }
  if (argb.length < byteCount) {
    throw ArgumentError(
      'ARGB buffer length (${argb.length}) is smaller than required $byteCount for ${width}x$height',
    );
  }

  final Uint8List rgba = Uint8List(byteCount);
  for (int i = 0; i < byteCount; i += 4) {
    rgba[i] = argb[i + 1]; // R
    rgba[i + 1] = argb[i + 2]; // G
    rgba[i + 2] = argb[i + 3]; // B
    rgba[i + 3] = argb[i]; // A
  }
  return rgba;
}

/// Selects the best matching [TrayPixmap] from a list for the given [targetSize].
///
/// Selection strategy:
/// 1. Filters out pixmaps with invalid dimensions or truncated byte arrays.
/// 2. Exact match (width == targetSize) is preferred.
/// 3. If no exact match, prefers the smallest pixmap with width >= targetSize (downscaling looks crisper than upscaling).
/// 4. If all pixmaps are smaller than targetSize, selects the largest available pixmap.
TrayPixmap? selectBestPixmap(List<TrayPixmap> pixmaps, int targetSize) {
  if (pixmaps.isEmpty) return null;

  final valid = pixmaps.where((p) {
    final minBytes = sniPixmapByteCount(p.width, p.height);
    return minBytes != null && p.bytes.length >= minBytes;
  }).toList();

  if (valid.isEmpty) return null;
  if (valid.length == 1) return valid.first;

  valid.sort((a, b) {
    // 1. Exact match
    if (a.width == targetSize && b.width != targetSize) return -1;
    if (b.width == targetSize && a.width != targetSize) return 1;

    final bool aGte = a.width >= targetSize;
    final bool bGte = b.width >= targetSize;

    if (aGte && !bGte) return -1;
    if (!aGte && bGte) return 1;

    if (aGte && bGte) {
      // Both larger: pick closest to targetSize (ascending order)
      return a.width.compareTo(b.width);
    } else {
      // Both smaller: pick largest (descending order)
      return b.width.compareTo(a.width);
    }
  });

  return valid.first;
}

/// Asynchronous decoder and cache for SNI ARGB32 pixmaps.
///
/// Ensures pixel decoding never blocks the main isolate and cached [ui.Image]s
/// are reused across frame builds and disposed upon eviction.
class SniPixmapDecoder {
  SniPixmapDecoder();

  static const int _maxCacheEntries = 128;

  final Map<String, ui.Image> _cache = <String, ui.Image>{};
  final Map<String, Future<ui.Image?>> _inFlight =
      <String, Future<ui.Image?>>{};

  int get cachedEntriesCount => _cache.length;

  /// Decodes a [TrayPixmap] asynchronously into a [ui.Image].
  ///
  /// Returns `null` if the pixmap contains invalid data or decoding fails.
  Future<ui.Image?> decode(TrayPixmap pixmap, {String? customKey}) async {
    final requiredBytes = sniPixmapByteCount(pixmap.width, pixmap.height);
    if (requiredBytes == null || pixmap.bytes.length < requiredBytes) {
      return null;
    }

    final String key = customKey ?? _computeKey(pixmap);

    if (_cache.containsKey(key)) {
      return _cache[key]?.clone();
    }

    if (_inFlight.containsKey(key)) {
      final img = await _inFlight[key];
      return img?.clone();
    }

    final future = _decodeInternal(pixmap, key);
    _inFlight[key] = future;
    try {
      final img = await future;
      return img?.clone();
    } finally {
      _inFlight.remove(key);
    }
  }

  Future<ui.Image?> _decodeInternal(TrayPixmap pixmap, String key) async {
    try {
      final rgba = argbToRgba(pixmap.bytes, pixmap.width, pixmap.height);
      final completer = Completer<ui.Image>();

      ui.decodeImageFromPixels(
        rgba,
        pixmap.width,
        pixmap.height,
        ui.PixelFormat.rgba8888,
        (ui.Image img) {
          completer.complete(img);
        },
      );

      final image = await completer.future;
      _storeInCache(key, image);
      return image;
    } catch (_) {
      return null;
    }
  }

  void _storeInCache(String key, ui.Image image) {
    if (_cache.containsKey(key)) {
      final old = _cache.remove(key);
      old?.dispose();
    }
    _cache[key] = image;
    while (_cache.length > _maxCacheEntries) {
      final oldestKey = _cache.keys.first;
      final oldest = _cache.remove(oldestKey);
      oldest?.dispose();
    }
  }

  String _computeKey(TrayPixmap pixmap) {
    // 64-bit FNV-1a hash over sampled bytes for robust collision resistance
    var hash = 0xcbf29ce484222325;
    final bytes = pixmap.bytes;
    final step = (bytes.length / 128).ceil().clamp(1, 1024);
    for (int i = 0; i < bytes.length; i += step) {
      hash ^= bytes[i];
      hash = (hash * 0x100000001b3) & 0x7FFFFFFFFFFFFFFF;
    }
    return '${pixmap.width}x${pixmap.height}_${bytes.length}_$hash';
  }

  /// Evicts all cached images whose key begins with [keyPrefix].
  void evict(String keyPrefix) {
    final matching = _cache.keys.where((k) => k.startsWith(keyPrefix)).toList();
    for (final k in matching) {
      final img = _cache.remove(k);
      img?.dispose();
    }
  }

  /// Clears the entire cache and disposes all native image resources.
  void clear() {
    for (final img in _cache.values) {
      img.dispose();
    }
    _cache.clear();
  }
}

/// Global shared instance for pixmap decoding.
final SniPixmapDecoder defaultSniPixmapDecoder = SniPixmapDecoder();
