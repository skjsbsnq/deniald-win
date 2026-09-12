import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

import '../../settings/settings_controller.dart';
import '../../settings/shell_settings.dart';
import '../../state/display_layout.dart';
import '../../state/notifier_lifecycle.dart';
import '../../theme/shell_theme.dart';
import '../../theme/tokens.dart';
import '../wallpaper.dart';
import 'wallpaper_controller.dart';

/// Shell theme colors derived from the current wallpaper.
///
/// [color] is a seed carrying the wallpaper's dominant hue and chroma. The
/// active [ShellThemeData] resolves that seed into brightness-safe roles.
@immutable
class WallpaperAccent {
  const WallpaperAccent(this.color, {this.isResolved = true});

  /// The brand accent used until extraction produces a wallpaper color.
  static const WallpaperAccent fallback = WallpaperAccent(
    ShellBrandColors.defaultAccent,
    isResolved: false,
  );

  /// The same brand color after extraction established that the wallpaper has
  /// no useful chroma. This may be published; the temporary fallback may not.
  static const WallpaperAccent resolvedFallback = WallpaperAccent(
    ShellBrandColors.defaultAccent,
  );

  final Color color;
  final bool isResolved;

  /// Card fill for system bar cards. The shell theme supplies the shared
  /// frosted-surface opacity at the point of use.
  Color cardFill(ShellThemeData theme) => theme.accentPalette.secondaryContainer;

  /// Top stop of the card gradient: [cardFill] nudged further toward the
  /// accent so pills read as softly lit from above.
  Color cardFillTop(ShellThemeData theme) => theme.accentPalette.container;

  /// Secondary text inside system bar cards, re-themed with the wallpaper
  /// through the matching on-container role instead of an alpha blend.
  Color captionColor(ShellThemeData theme) =>
      theme.accentPalette.onSecondaryContainer;

  @override
  bool operator ==(Object other) =>
      other is WallpaperAccent &&
      other.color == color &&
      other.isResolved == isResolved;

  @override
  int get hashCode => Object.hash(color, isResolved);
}

/// The wallpaper resource whose colors theme the shell chrome. The system
/// bar's output is authoritative because that is where the themed chrome
/// lives; without a display layout the shared wallpaper decides.
final _accentSourceWallpaperProvider = Provider<WallpaperResource>((ref) {
  final assignment = ref.watch(
    wallpaperControllerProvider.select((state) => state.assignment),
  );
  final outputName = ref.watch(
    displayLayoutProvider.select((layout) => layout?.systemBarOutput?.name),
  );
  return outputName == null ? assignment.all : assignment.forOutput(outputName);
});

typedef WallpaperAccentExtractor =
    Future<Color?> Function(WallpaperResource resource);

final wallpaperAccentExtractorProvider = Provider<WallpaperAccentExtractor>(
  (ref) => _extractFromResource,
);

final wallpaperAccentProvider =
    NotifierProvider<WallpaperAccentController, WallpaperAccent>(
      WallpaperAccentController.new,
    );

/// Effective shell accent after applying the user's source preference.
///
/// Wallpaper extraction remains independently cached so toggling between a
/// custom color and the wallpaper never decodes the image again.
final shellAccentProvider = Provider<WallpaperAccent>((ref) {
  final appearance = ref.watch(
    shellSettingsProvider.select((settings) => settings.appearance),
  );
  if (appearance.accentSource == ShellAccentSource.custom) {
    return WallpaperAccent(appearance.customAccentColor);
  }
  return ref.watch(wallpaperAccentProvider);
});

class WallpaperAccentController extends Notifier<WallpaperAccent>
    with NotifierLifecycle<WallpaperAccent> {
  @override
  WallpaperAccent build() {
    _extract = ref.watch(wallpaperAccentExtractorProvider);
    _cache.clear();
    _loadGeneration = 0;
    _buildGeneration = beginBuildGeneration();
    final generation = _buildGeneration;
    ref.listen<WallpaperResource>(_accentSourceWallpaperProvider, (
      previous,
      next,
    ) {
      if (isBuildGenerationActive(generation)) {
        unawaited(_load(next, generation));
      }
    }, fireImmediately: true);
    return WallpaperAccent.fallback;
  }

  static const int _maxCacheEntries = 8;

  late WallpaperAccentExtractor _extract;
  final Map<String, WallpaperAccent> _cache = <String, WallpaperAccent>{};
  late int _buildGeneration;
  int _loadGeneration = 0;

  Future<void> load(WallpaperResource resource) =>
      _load(resource, _buildGeneration);

  Future<void> _load(WallpaperResource resource, int buildGeneration) async {
    final key = resource.persistenceValue;
    final cached = _cache[key];
    if (cached != null) {
      state = cached;
      return;
    }
    final generation = ++_loadGeneration;
    Color? color;
    try {
      color = await _extract(resource);
    } on Object {
      color = null;
    }
    if (!isBuildGenerationActive(buildGeneration) ||
        generation != _loadGeneration) {
      return;
    }
    final accent = color == null
        ? WallpaperAccent.resolvedFallback
        : WallpaperAccent(color);
    if (_cache.length >= _maxCacheEntries) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = accent;
    state = accent;
  }
}

Future<Color?> _extractFromResource(WallpaperResource resource) async {
  final Uint8List encoded;
  switch (resource.kind) {
    case WallpaperResourceKind.asset:
      encoded = (await rootBundle.load(resource.path)).buffer.asUint8List();
    case WallpaperResourceKind.file:
      encoded = await File(resource.path).readAsBytes();
  }
  return extractWallpaperAccent(encoded);
}

/// Decodes [encoded] at thumbnail size and returns its dominant vibrant seed,
/// or null for effectively monochrome images.
Future<Color?> extractWallpaperAccent(Uint8List encoded) async {
  final codec = await ui.instantiateImageCodec(
    encoded,
    targetWidth: 64,
    allowUpscaling: false,
  );
  final ui.Image image;
  try {
    image = (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) {
      return null;
    }
    return dominantVibrantColor(data);
  } finally {
    image.dispose();
  }
}

/// Quantizes raw RGBA pixels with `QuantizerCelebi` and picks the seed via
/// `Score.score()` — the same pipeline Android 16 uses for wallpaper Monet.
///
/// Returns null for effectively monochrome images: [Score] emits the
/// sentinel fallback only when every quantized color fails its own
/// chroma/population cutoffs, and the additional HCT chroma check rejects
/// near-gray survivors so a washed-out wallpaper keeps the brand accent.
@visibleForTesting
Future<Color?> dominantVibrantColor(ByteData rgba) async {
  final pixelCount = rgba.lengthInBytes ~/ 4;
  if (pixelCount == 0) {
    return null;
  }
  final pixels = Uint32List(pixelCount);
  for (var index = 0; index < pixelCount; index += 1) {
    final offset = index * 4;
    pixels[index] =
        0xff000000 |
        rgba.getUint8(offset) << 16 |
        rgba.getUint8(offset + 1) << 8 |
        rgba.getUint8(offset + 2);
  }
  final quantized = await QuantizerCelebi().quantize(
    pixels,
    _quantizerMaxColors,
  );
  // A zero argb fallback is unrepresentable for real pixels (they always
  // carry a full alpha channel), so it marks "nothing usable was scored".
  final ranked = Score.score(
    quantized.colorToCount,
    fallbackColorARGB: 0x00000000,
  );
  if (ranked.isEmpty || ranked.first == 0x00000000) {
    return null;
  }
  final seed = Hct.fromInt(ranked.first);
  if (seed.chroma < _minimumSeedChroma) {
    return null;
  }
  return Color(ranked.first);
}

/// Celebi input cluster budget; 128 matches Android's wallpaper pipeline.
const int _quantizerMaxColors = 128;

/// Mirrors `Score`'s internal chroma cutoff so near-gray winners still fall
/// back to the brand accent.
const double _minimumSeedChroma = 5.0;
