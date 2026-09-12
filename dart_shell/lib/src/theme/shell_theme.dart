import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:material_color_utilities/material_color_utilities.dart'
    show DynamicScheme, Hct, SchemeExpressive;

import 'backdrop_blur_level.dart';
import 'shell_color_scheme.dart';
import 'shell_text_theme.dart';
import 'tokens.dart';

export 'package:material_color_utilities/material_color_utilities.dart'
    show DynamicScheme;
export 'shell_color_scheme.dart' show shellSchemeColor;

/// Memoized `SchemeExpressive` dynamic schemes keyed by the
/// (seed argb, isDark, contrastLevel) triple.
final Map<(int, bool, double), DynamicScheme> _dynamicSchemes =
    <(int, bool, double), DynamicScheme>{};

/// The single Monet entry point: expands a seed into a `SchemeExpressive`
/// [DynamicScheme] aligned with Android 16. Every accent-driven consumer
/// (shell surfaces, accent palette, Settings category hues, appearance-page
/// swatches) resolves through this helper so the variant can never drift.
///
/// [contrastLevel] follows the MCU convention: 0 is standard, ±1 are the
/// accessibility extremes. Schemes are memoized because construction is far
/// too expensive to run from `build`.
DynamicScheme shellDynamicScheme(
  Color seed, {
  Brightness brightness = Brightness.dark,
  double contrastLevel = 0,
}) {
  final key = (
    seed.withValues(alpha: 1).toARGB32(),
    brightness == Brightness.dark,
    contrastLevel.clamp(-1.0, 1.0).toDouble(),
  );
  return _dynamicSchemes.putIfAbsent(
    key,
    () => SchemeExpressive(
      sourceColorHct: Hct.fromInt(key.$1),
      isDark: key.$2,
      contrastLevel: key.$3,
    ),
  );
}

@immutable
class ShellAccentPalette {
  const ShellAccentPalette._({
    required this.primary,
    required this.onPrimary,
    required this.container,
    required this.onContainer,
    required this.onContainerSecondary,
    required this.mutedContainer,
    required this.onMutedContainer,
    required this.subtle,
    required this.outline,
    required this.selection,
    required this.secondary,
    required this.onSecondary,
    required this.secondaryContainer,
    required this.onSecondaryContainer,
    required this.tertiary,
    required this.onTertiary,
    required this.tertiaryContainer,
    required this.onTertiaryContainer,
    required this.error,
    required this.onError,
    required this.errorContainer,
    required this.onErrorContainer,
  });

  factory ShellAccentPalette.from(
    Color source, [
    ShellColorScheme colors = ShellColorScheme.dark,
  ]) {
    return ShellAccentPalette._fromScheme(
      shellDynamicScheme(source, brightness: colors.brightness),
      colors,
    );
  }

  factory ShellAccentPalette._fromScheme(
    DynamicScheme scheme,
    ShellColorScheme colors,
  ) {
    final primary = shellSchemeColor(scheme.primary);
    final container = shellSchemeColor(scheme.primaryContainer);
    // M3E derives quiet roles from the same tonal palette instead of alpha
    // blends: tone-based derivation keeps light and dark brightness
    // symmetric, which alpha blending cannot.
    final mutedContainer = _tintedSurface(
      primary,
      colors,
      colors.brightness == Brightness.dark ? 0.22 : 0.12,
    );
    return ShellAccentPalette._(
      primary: primary,
      onPrimary: shellSchemeColor(scheme.onPrimary),
      container: container,
      onContainer: shellSchemeColor(scheme.onPrimaryContainer),
      onContainerSecondary: shellSchemeColor(
        scheme.onPrimaryContainer,
      ).withValues(alpha: 0.78),
      mutedContainer: mutedContainer,
      onMutedContainer: _contrastForeground(mutedContainer),
      subtle: colors.brightness == Brightness.dark
          ? primary.withValues(alpha: 0.10)
          : _tintedSurface(primary, colors, 0.10),
      outline: shellSchemeColor(scheme.outline),
      selection: primary.withValues(alpha: 0.38),
      secondary: shellSchemeColor(scheme.secondary),
      onSecondary: shellSchemeColor(scheme.onSecondary),
      secondaryContainer: shellSchemeColor(scheme.secondaryContainer),
      onSecondaryContainer: shellSchemeColor(scheme.onSecondaryContainer),
      tertiary: shellSchemeColor(scheme.tertiary),
      onTertiary: shellSchemeColor(scheme.onTertiary),
      tertiaryContainer: shellSchemeColor(scheme.tertiaryContainer),
      onTertiaryContainer: shellSchemeColor(scheme.onTertiaryContainer),
      // The error palette is seed-independent inside DynamicScheme
      // (TonalPalette.of(25, 84)), so these roles are static by construction.
      error: shellSchemeColor(scheme.error),
      onError: shellSchemeColor(scheme.onError),
      errorContainer: shellSchemeColor(scheme.errorContainer),
      onErrorContainer: shellSchemeColor(scheme.onErrorContainer),
    );
  }

  final Color primary;
  final Color onPrimary;
  final Color container;
  final Color onContainer;
  final Color onContainerSecondary;
  final Color mutedContainer;
  final Color onMutedContainer;
  final Color subtle;
  final Color outline;
  final Color selection;

  /// Secondary family: lower-emphasis accent used for secondary activation.
  final Color secondary;
  final Color onSecondary;
  final Color secondaryContainer;
  final Color onSecondaryContainer;

  /// Tertiary family: rotated-hue accents for emphasis and ratings.
  final Color tertiary;
  final Color onTertiary;
  final Color tertiaryContainer;
  final Color onTertiaryContainer;

  /// Error family: static and seed-independent.
  final Color error;
  final Color onError;
  final Color errorContainer;
  final Color onErrorContainer;

  static ShellAccentPalette lerp(
    ShellAccentPalette first,
    ShellAccentPalette second,
    double t,
  ) {
    Color blend(Color a, Color b) => Color.lerp(a, b, t)!;
    return ShellAccentPalette._(
      primary: blend(first.primary, second.primary),
      onPrimary: blend(first.onPrimary, second.onPrimary),
      container: blend(first.container, second.container),
      onContainer: blend(first.onContainer, second.onContainer),
      onContainerSecondary: blend(
        first.onContainerSecondary,
        second.onContainerSecondary,
      ),
      mutedContainer: blend(first.mutedContainer, second.mutedContainer),
      onMutedContainer: blend(first.onMutedContainer, second.onMutedContainer),
      subtle: blend(first.subtle, second.subtle),
      outline: blend(first.outline, second.outline),
      selection: blend(first.selection, second.selection),
      secondary: blend(first.secondary, second.secondary),
      onSecondary: blend(first.onSecondary, second.onSecondary),
      secondaryContainer: blend(
        first.secondaryContainer,
        second.secondaryContainer,
      ),
      onSecondaryContainer: blend(
        first.onSecondaryContainer,
        second.onSecondaryContainer,
      ),
      tertiary: blend(first.tertiary, second.tertiary),
      onTertiary: blend(first.onTertiary, second.onTertiary),
      tertiaryContainer: blend(
        first.tertiaryContainer,
        second.tertiaryContainer,
      ),
      onTertiaryContainer: blend(
        first.onTertiaryContainer,
        second.onTertiaryContainer,
      ),
      error: blend(first.error, second.error),
      onError: blend(first.onError, second.onError),
      errorContainer: blend(first.errorContainer, second.errorContainer),
      onErrorContainer: blend(first.onErrorContainer, second.onErrorContainer),
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ShellAccentPalette &&
            other.primary == primary &&
            other.onPrimary == onPrimary &&
            other.container == container &&
            other.onContainer == onContainer &&
            other.onContainerSecondary == onContainerSecondary &&
            other.mutedContainer == mutedContainer &&
            other.onMutedContainer == onMutedContainer &&
            other.subtle == subtle &&
            other.outline == outline &&
            other.selection == selection &&
            other.secondary == secondary &&
            other.onSecondary == onSecondary &&
            other.secondaryContainer == secondaryContainer &&
            other.onSecondaryContainer == onSecondaryContainer &&
            other.tertiary == tertiary &&
            other.onTertiary == onTertiary &&
            other.tertiaryContainer == tertiaryContainer &&
            other.onTertiaryContainer == onTertiaryContainer &&
            other.error == error &&
            other.onError == onError &&
            other.errorContainer == errorContainer &&
            other.onErrorContainer == onErrorContainer;
  }

  @override
  int get hashCode => Object.hashAll(<Object>[
    primary,
    onPrimary,
    container,
    onContainer,
    onContainerSecondary,
    mutedContainer,
    onMutedContainer,
    subtle,
    outline,
    selection,
    secondary,
    onSecondary,
    secondaryContainer,
    onSecondaryContainer,
    tertiary,
    onTertiary,
    tertiaryContainer,
    onTertiaryContainer,
    error,
    onError,
    errorContainer,
    onErrorContainer,
  ]);
}

@immutable
class ShellThemeData {
  const ShellThemeData({
    ShellColorScheme colors = ShellColorScheme.dark,
    Color accent = ShellBrandColors.defaultAccent,
    this.contrastLevel = 0,
    this.cornerRadiusScale = ShellRoundness.normal,
    this.panelOpacity = ShellOpacity.panel,
    this.cardOpacity = ShellOpacity.card,
    this.backdropBlurEnabled = true,
    this.backdropBlurLevel = ShellBackdropBlurLevel.fast,
    this.backdropBlurOpacityThreshold = 0.2,
    this.focusedWindowBorderEnabled = true,
    this.focusedWindowOpacity = 1,
    this.unfocusedWindowOpacity = 1,
    this.fontFamily,
    this._resolvedColorScheme,
    this._resolvedTextTheme,
    this._resolvedAccentPalette,
    this._resolvedGeneratedColorScheme,
    this._resolvedBackdropBlurFilterConfig,
  }) : _baseColors = colors,
       accentSeed = accent;

  /// The neutral base scheme supplied at construction. Only its brightness
  /// still participates in derivation; every semantic role is expanded from
  /// the wallpaper seed through [ShellColorScheme.fromDynamicScheme].
  final ShellColorScheme _baseColors;

  /// Precomputed interpolated scheme produced by [ShellThemeData.lerp]; when
  /// set, [colors] returns it verbatim instead of re-deriving from the seed.
  final ShellColorScheme? _resolvedColorScheme;
  final Color accentSeed;

  /// MCU contrast level for the generated dynamic scheme: 0 is standard,
  /// -1 reduces and +1 raises contrast. Persisted in appearance settings.
  final double contrastLevel;
  final ShellTextTheme? _resolvedTextTheme;
  final ShellAccentPalette? _resolvedAccentPalette;
  final ColorScheme? _resolvedGeneratedColorScheme;
  final ImageFilterConfig? _resolvedBackdropBlurFilterConfig;
  final double cornerRadiusScale;
  final double panelOpacity;
  final double cardOpacity;
  final bool backdropBlurEnabled;
  final ShellBackdropBlurLevel backdropBlurLevel;
  final double backdropBlurOpacityThreshold;
  final bool focusedWindowBorderEnabled;
  final double focusedWindowOpacity;
  final double unfocusedWindowOpacity;

  /// Non-null replaces every shell text role's family. Constant within one
  /// session (settings take effect after a shell restart), so lerping
  /// snapshots the nearest end instead of blending family names.
  final String? fontFamily;

  static final Expando<_ShellThemeResolution> _resolutionCache =
      Expando<_ShellThemeResolution>('ShellThemeData resolution');

  _ShellThemeResolution get _resolution =>
      _resolutionCache[this] ??= _ShellThemeResolution(this);

  double get backdropBlurSigma => backdropBlurLevel.sigma;

  double get backdropBlurDownsampleScale => backdropBlurLevel.downsampleScale;

  /// Immutable blur blueprint shared by every surface using this theme.
  ImageFilterConfig get backdropBlurFilterConfig =>
      _resolution.backdropBlurFilterConfig;

  /// Quantized blur used while a panel and its backdrop retire together.
  ImageFilterConfig backdropBlurFilterConfigAt(double strength) =>
      _resolution.backdropBlurFilterConfigAt(strength);

  /// Native per-pixel window blur using the configured final-alpha threshold.
  ImageFilterConfig get windowBackdropBlurFilterConfig =>
      _resolution.windowBackdropBlurFilterConfig;

  /// One-pass variant for a window proven to contain one external surface.
  ImageFilterConfig get singleSurfaceWindowBackdropBlurFilterConfig =>
      _resolution.singleSurfaceWindowBackdropBlurFilterConfig;

  Brightness get brightness => _baseColors.brightness;

  /// The effective semantic color stack: derived once from
  /// ([accentSeed], brightness, [contrastLevel]) through `SchemeExpressive`,
  /// or the interpolated scheme while [AnimatedShellTheme] is lerping.
  ShellColorScheme get colors => _resolution.colorScheme;

  /// Semantic text roles resolved once for this immutable theme value.
  ShellTextTheme get text => _resolution.text;

  /// Seed-derived accent roles resolved once for this immutable theme value.
  ShellAccentPalette get accentPalette => _resolution.accentPalette;

  /// The normalized primary role. [accentSeed] is the persisted source color.
  Color get accent => accentPalette.primary;

  /// Scales a component's base radius by the single user-selected roundness.
  double scaledRadius(double radius) => radius * cornerRadiusScale;

  Radius radius(double baseRadius) => _resolution.radius(baseRadius);

  BorderRadius borderRadius(double baseRadius) =>
      _resolution.borderRadius(baseRadius);

  double get windowRadius => scaledRadius(ShellRadii.window);

  double get notificationRadius => scaledRadius(ShellRadii.notification);

  double get tileRadius => scaledRadius(ShellRadii.tile);

  double get tileWideRadius => scaledRadius(ShellRadii.tileWide);

  double get panelRadius => scaledRadius(ShellRadii.panel);

  double get chipRadius => scaledRadius(ShellRadii.chip);

  double get roundButtonRadius => scaledRadius(ShellRadii.roundButton);

  /// The normalized backing opacity shared by panels, notifications, and HUDs.
  double get effectivePanelOpacity =>
      panelOpacity.clamp(ShellOpacity.minimumPanel, 1.0).toDouble();

  double get effectiveCardOpacity =>
      cardOpacity.clamp(ShellOpacity.minimumCard, 1.0).toDouble();

  Color panelColor(Color color) => _resolution.panelColor(color);

  LinearGradient panelGradient(Color top, Color bottom) =>
      _resolution.panelGradient(top, bottom);

  Color cardColor(Color color) => _resolution.cardColor(color);

  LinearGradient cardGradient(Color top, Color bottom) =>
      _resolution.cardGradient(top, bottom);

  /// Material compatibility theme resolved once for this immutable value.
  ThemeData toMaterialTheme() => _resolution.materialTheme;

  ShellThemeData copyWith({
    ShellColorScheme? colors,
    Color? accent,
    double? contrastLevel,
    double? cornerRadiusScale,
    double? panelOpacity,
    double? cardOpacity,
    bool? backdropBlurEnabled,
    ShellBackdropBlurLevel? backdropBlurLevel,
    double? backdropBlurOpacityThreshold,
    bool? focusedWindowBorderEnabled,
    double? focusedWindowOpacity,
    double? unfocusedWindowOpacity,
    String? fontFamily,
  }) {
    return ShellThemeData(
      colors: colors ?? _baseColors,
      accent: accent ?? accentSeed,
      contrastLevel: contrastLevel ?? this.contrastLevel,
      cornerRadiusScale: cornerRadiusScale ?? this.cornerRadiusScale,
      panelOpacity: panelOpacity ?? this.panelOpacity,
      cardOpacity: cardOpacity ?? this.cardOpacity,
      backdropBlurEnabled: backdropBlurEnabled ?? this.backdropBlurEnabled,
      backdropBlurLevel: backdropBlurLevel ?? this.backdropBlurLevel,
      backdropBlurOpacityThreshold:
          backdropBlurOpacityThreshold ?? this.backdropBlurOpacityThreshold,
      focusedWindowBorderEnabled:
          focusedWindowBorderEnabled ?? this.focusedWindowBorderEnabled,
      focusedWindowOpacity: focusedWindowOpacity ?? this.focusedWindowOpacity,
      unfocusedWindowOpacity:
          unfocusedWindowOpacity ?? this.unfocusedWindowOpacity,
      fontFamily: fontFamily ?? this.fontFamily,
    );
  }

  static ShellThemeData lerp(
    ShellThemeData first,
    ShellThemeData second,
    double t,
  ) {
    if (t <= 0) {
      return first;
    }
    if (t >= 1) {
      return second;
    }
    final colorsMatch = first.colors == second.colors;
    final accentsMatch = first.accentSeed == second.accentSeed;
    final colorInputsMatch =
        colorsMatch && accentsMatch && first.contrastLevel == second.contrastLevel;
    double blend(double a, double b) => a + (b - a) * t;
    return ShellThemeData(
      colors: t < 0.5 ? first._baseColors : second._baseColors,
      accent: accentsMatch
          ? first.accentSeed
          : Color.lerp(first.accentSeed, second.accentSeed, t)!,
      contrastLevel: blend(first.contrastLevel, second.contrastLevel),
      resolvedColorScheme: colorsMatch
          ? first.colors
          : ShellColorScheme.lerp(first.colors, second.colors, t),
      resolvedTextTheme: colorsMatch
          ? first.text
          : ShellTextTheme.lerp(first.text, second.text, t),
      resolvedAccentPalette: colorInputsMatch
          ? first.accentPalette
          : ShellAccentPalette.lerp(
              first.accentPalette,
              second.accentPalette,
              t,
            ),
      resolvedGeneratedColorScheme: colorInputsMatch
          ? first._resolution.generatedColorScheme
          : ColorScheme.lerp(
              first._resolution.generatedColorScheme,
              second._resolution.generatedColorScheme,
              t,
            ),
      resolvedBackdropBlurFilterConfig:
          first.backdropBlurLevel == second.backdropBlurLevel
          ? first.backdropBlurFilterConfig
          : t < 0.5
          ? first.backdropBlurFilterConfig
          : second.backdropBlurFilterConfig,
      cornerRadiusScale: blend(
        first.cornerRadiusScale,
        second.cornerRadiusScale,
      ),
      panelOpacity: blend(first.panelOpacity, second.panelOpacity),
      cardOpacity: blend(first.cardOpacity, second.cardOpacity),
      backdropBlurEnabled: t < 0.5
          ? first.backdropBlurEnabled
          : second.backdropBlurEnabled,
      backdropBlurLevel: t < 0.5
          ? first.backdropBlurLevel
          : second.backdropBlurLevel,
      backdropBlurOpacityThreshold: blend(
        first.backdropBlurOpacityThreshold,
        second.backdropBlurOpacityThreshold,
      ),
      focusedWindowBorderEnabled: t < 0.5
          ? first.focusedWindowBorderEnabled
          : second.focusedWindowBorderEnabled,
      focusedWindowOpacity: blend(
        first.focusedWindowOpacity,
        second.focusedWindowOpacity,
      ),
      unfocusedWindowOpacity: blend(
        first.unfocusedWindowOpacity,
        second.unfocusedWindowOpacity,
      ),
      fontFamily: t < 0.5 ? first.fontFamily : second.fontFamily,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ShellThemeData &&
        other.colors == colors &&
        other.accentSeed == accentSeed &&
        other.contrastLevel == contrastLevel &&
        other.cornerRadiusScale == cornerRadiusScale &&
        other.panelOpacity == panelOpacity &&
        other.cardOpacity == cardOpacity &&
        other.backdropBlurEnabled == backdropBlurEnabled &&
        other.backdropBlurLevel == backdropBlurLevel &&
        other.backdropBlurOpacityThreshold == backdropBlurOpacityThreshold &&
        other.focusedWindowBorderEnabled == focusedWindowBorderEnabled &&
        other.focusedWindowOpacity == focusedWindowOpacity &&
        other.unfocusedWindowOpacity == unfocusedWindowOpacity &&
        other.fontFamily == fontFamily;
  }

  @override
  int get hashCode => Object.hash(
    colors,
    accentSeed,
    contrastLevel,
    cornerRadiusScale,
    panelOpacity,
    cardOpacity,
    backdropBlurEnabled,
    backdropBlurLevel,
    backdropBlurOpacityThreshold,
    focusedWindowBorderEnabled,
    focusedWindowOpacity,
    unfocusedWindowOpacity,
    fontFamily,
  );
}

/// Lazily memoizes derived objects by [ShellThemeData] identity.
///
/// Keeping the cache outside the immutable value preserves const construction.
/// Interpolated animation values also benefit: every widget in one transition
/// frame shares the same derived text and accent objects, while an accent-only
/// shell frame never pays to construct a complete Material [ThemeData].
class _ShellThemeResolution {
  _ShellThemeResolution(this.theme);

  final ShellThemeData theme;
  final Map<double, Radius> _radii = <double, Radius>{};
  final Map<double, BorderRadius> _borderRadii = <double, BorderRadius>{};
  final Map<Color, Color> _panelColors = <Color, Color>{};
  final Map<Color, Color> _cardColors = <Color, Color>{};
  final Map<({Color top, Color bottom}), LinearGradient> _panelGradients =
      <({Color top, Color bottom}), LinearGradient>{};
  final Map<({Color top, Color bottom}), LinearGradient> _cardGradients =
      <({Color top, Color bottom}), LinearGradient>{};

  Radius radius(double baseRadius) => _radii.putIfAbsent(
    baseRadius,
    () => Radius.circular(theme.scaledRadius(baseRadius)),
  );

  BorderRadius borderRadius(double baseRadius) => _borderRadii.putIfAbsent(
    baseRadius,
    () => BorderRadius.circular(theme.scaledRadius(baseRadius)),
  );

  Color panelColor(Color color) => _panelColors.putIfAbsent(
    color,
    () => color.withValues(alpha: theme.effectivePanelOpacity),
  );

  LinearGradient panelGradient(Color top, Color bottom) =>
      _panelGradients.putIfAbsent(
        (top: top, bottom: bottom),
        () => LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[panelColor(top), panelColor(bottom)],
        ),
      );

  Color cardColor(Color color) => _cardColors.putIfAbsent(
    color,
    () => color.withValues(alpha: theme.effectiveCardOpacity),
  );

  LinearGradient cardGradient(Color top, Color bottom) =>
      _cardGradients.putIfAbsent(
        (top: top, bottom: bottom),
        () => LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[cardColor(top), cardColor(bottom)],
        ),
      );

  /// The shared `SchemeExpressive` dynamic scheme backing every color role
  /// of this theme value: surfaces, accent palette, and Material theme all
  /// derive from this one instance.
  late final DynamicScheme dynamicScheme = shellDynamicScheme(
    theme.accentSeed,
    brightness: theme._baseColors.brightness,
    contrastLevel: theme.contrastLevel,
  );

  late final ShellColorScheme colorScheme =
      theme._resolvedColorScheme ??
      ShellColorScheme.fromDynamicScheme(dynamicScheme);

  late final ShellTextTheme text =
      theme._resolvedTextTheme ??
      ShellTextTheme.from(colorScheme, fontFamily: theme.fontFamily);

  late final ColorScheme generatedColorScheme =
      theme._resolvedGeneratedColorScheme ??
      _materialColorScheme(dynamicScheme);

  late final ShellAccentPalette accentPalette =
      theme._resolvedAccentPalette ??
      ShellAccentPalette._fromScheme(dynamicScheme, colorScheme);

  late final ImageFilterConfig backdropBlurFilterConfig =
      theme._resolvedBackdropBlurFilterConfig ??
      ImageFilterConfig.blur(
        sigmaX: theme.backdropBlurSigma,
        sigmaY: theme.backdropBlurSigma,
        tileMode: ui.TileMode.clamp,
        downsampleScale: theme.backdropBlurDownsampleScale,
      );

  static const int _blurStrengthSteps = 32;
  final List<ImageFilterConfig?> _animatedBackdropBlurFilters =
      List<ImageFilterConfig?>.filled(_blurStrengthSteps, null);

  ImageFilterConfig backdropBlurFilterConfigAt(double strength) {
    final step = (strength.clamp(0.0, 1.0) * _blurStrengthSteps)
        .round()
        .clamp(1, _blurStrengthSteps)
        .toInt();
    if (step == _blurStrengthSteps) {
      return backdropBlurFilterConfig;
    }
    return _animatedBackdropBlurFilters[step - 1] ??= ImageFilterConfig.blur(
      sigmaX: theme.backdropBlurSigma * step / _blurStrengthSteps,
      sigmaY: theme.backdropBlurSigma * step / _blurStrengthSteps,
      tileMode: ui.TileMode.clamp,
      downsampleScale: theme.backdropBlurDownsampleScale,
    );
  }

  late final ImageFilterConfig windowBackdropBlurFilterConfig =
      ImageFilterConfig.blur(
        sigmaX: theme.backdropBlurSigma,
        sigmaY: theme.backdropBlurSigma,
        tileMode: ui.TileMode.clamp,
        downsampleScale: theme.backdropBlurDownsampleScale,
        backdropAlphaThreshold: theme.backdropBlurOpacityThreshold
            .clamp(0.0, 1.0)
            .toDouble(),
      );

  late final ImageFilterConfig singleSurfaceWindowBackdropBlurFilterConfig =
      ImageFilterConfig.blur(
        sigmaX: theme.backdropBlurSigma,
        sigmaY: theme.backdropBlurSigma,
        tileMode: ui.TileMode.clamp,
        downsampleScale: theme.backdropBlurDownsampleScale,
        backdropAlphaThreshold: theme.backdropBlurOpacityThreshold
            .clamp(0.0, 1.0)
            .toDouble(),
        backdropAlphaThresholdIsSingleSurface: true,
      );

  late final ThemeData materialTheme = ThemeData(
    brightness: theme.brightness,
    useMaterial3: true,
    fontFamily: theme.fontFamily,
    scaffoldBackgroundColor: ShellMediaColors.transparentDark,
    colorScheme: generatedColorScheme.copyWith(
      surface: theme.colors.background,
      onSurface: theme.colors.textPrimary,
      onSurfaceVariant: theme.colors.textSecondary,
      outline: theme.colors.outline,
      outlineVariant: theme.colors.outlineVariant,
      surfaceContainerLowest: theme.colors.surfaceContainerLowest,
      surfaceContainerLow: theme.colors.surfaceContainerLow,
      surfaceContainer: theme.colors.surfaceContainer,
      surfaceContainerHigh: theme.colors.surfaceContainerHigh,
      surfaceContainerHighest: theme.colors.surfaceContainerHighest,
      surfaceDim: theme.colors.panelBackground,
      surfaceBright: theme.colors.background,
      shadow: theme.colors.shadow,
    ),
    cardTheme: CardThemeData(
      color: cardColor(theme.colors.surfaceContainerLow),
      shape: RoundedRectangleBorder(
        borderRadius: theme.borderRadius(ShellRadii.tile),
      ),
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: theme.borderRadius(ShellRadii.panel),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: theme.borderRadius(ShellRadii.chip),
      ),
    ),
    inputDecorationTheme: InputDecorationThemeData(
      border: OutlineInputBorder(
        borderRadius: theme.borderRadius(ShellRadii.chip),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll<OutlinedBorder>(
          RoundedRectangleBorder(
            borderRadius: theme.borderRadius(ShellRadii.chip),
          ),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll<OutlinedBorder>(
          RoundedRectangleBorder(
            borderRadius: theme.borderRadius(ShellRadii.chip),
          ),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll<OutlinedBorder>(
          RoundedRectangleBorder(
            borderRadius: theme.borderRadius(ShellRadii.chip),
          ),
        ),
      ),
    ),
    sliderTheme: SliderThemeData(
      // RoundedRectSliderTrackShape already rounds the track ends to
      // half its height, which reads as a full pill at M3 track heights.
      trackShape: const RoundedRectSliderTrackShape(),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll<OutlinedBorder>(
          RoundedRectangleBorder(
            borderRadius: theme.borderRadius(ShellShapeScale.full),
          ),
        ),
      ),
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: theme.borderRadius(ShellShapeScale.medium),
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: theme.borderRadius(ShellShapeScale.extraSmall),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: theme.borderRadius(ShellShapeScale.small),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        borderRadius: theme.borderRadius(ShellShapeScale.small),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: theme.colors.hairlineSoft,
      thickness: 1,
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll<OutlinedBorder>(
          RoundedRectangleBorder(
            borderRadius: theme.borderRadius(ShellShapeScale.full),
          ),
        ),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: theme.accent),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        shape: WidgetStatePropertyAll<OutlinedBorder>(
          RoundedRectangleBorder(
            borderRadius: theme.borderRadius(ShellShapeScale.medium),
          ),
        ),
      ),
    ),
  );
}

class ShellTheme extends InheritedWidget {
  const ShellTheme({required this.data, required super.child, super.key});

  final ShellThemeData data;

  static ShellThemeData of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ShellTheme>()?.data ??
        const ShellThemeData();
  }

  static ShellColorScheme colorsOf(BuildContext context) => of(context).colors;

  @override
  bool updateShouldNotify(covariant ShellTheme oldWidget) {
    return oldWidget.data != data;
  }
}

class AnimatedShellTheme extends ImplicitlyAnimatedWidget {
  const AnimatedShellTheme({
    required this.data,
    required this.child,
    required super.duration,
    super.curve = Curves.easeInOut,
    super.key,
  });

  final ShellThemeData data;
  final Widget child;

  @override
  AnimatedWidgetBaseState<AnimatedShellTheme> createState() =>
      _AnimatedShellThemeState();
}

/// Installs the interpolated semantic base style below [AnimatedShellTheme].
class ShellDefaultTextStyle extends StatelessWidget {
  const ShellDefaultTextStyle({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle(style: context.shellTheme.text.base, child: child);
  }
}

class _AnimatedShellThemeState
    extends AnimatedWidgetBaseState<AnimatedShellTheme> {
  _ShellThemeDataTween? _theme;

  @override
  void forEachTween(TweenVisitor<dynamic> visitor) {
    _theme =
        visitor(
              _theme,
              widget.data,
              (dynamic value) =>
                  _ShellThemeDataTween(begin: value as ShellThemeData),
            )
            as _ShellThemeDataTween?;
  }

  @override
  Widget build(BuildContext context) {
    return ShellTheme(data: _theme!.evaluate(animation), child: widget.child);
  }
}

class _ShellThemeDataTween extends Tween<ShellThemeData> {
  _ShellThemeDataTween({super.begin});

  @override
  ShellThemeData lerp(double t) => ShellThemeData.lerp(begin!, end!, t);
}

extension ShellThemeBuildContext on BuildContext {
  ShellThemeData get shellTheme => ShellTheme.of(this);

  ShellColorScheme get shellColors => ShellTheme.colorsOf(this);
}

Color _tintedSurface(Color accent, ShellColorScheme colors, double amount) {
  // The shell surface family carries a deliberate alpha channel for its
  // translucent panels, so tinting blends over the flattened backing color
  // and re-applies the original alpha to stay in the same family.
  final backing = colors.surfaceContainerHigh.withValues(alpha: 1);
  final tinted = Color.alphaBlend(accent.withValues(alpha: amount), backing);
  return tinted.withValues(alpha: colors.surfaceContainerHigh.a);
}

/// Expands a [DynamicScheme] into a full Material [ColorScheme], mapping
/// every tonal role — including the five surface-container tiers, the
/// inverse family, and the fixed palettes — so `materialTheme` reflects real
/// M3E layering instead of a partial seed expansion.
ColorScheme _materialColorScheme(DynamicScheme scheme) {
  Color role(int argb) => shellSchemeColor(argb);
  return ColorScheme(
    brightness: scheme.isDark ? Brightness.dark : Brightness.light,
    primary: role(scheme.primary),
    onPrimary: role(scheme.onPrimary),
    primaryContainer: role(scheme.primaryContainer),
    onPrimaryContainer: role(scheme.onPrimaryContainer),
    primaryFixed: role(scheme.primaryFixed),
    primaryFixedDim: role(scheme.primaryFixedDim),
    onPrimaryFixed: role(scheme.onPrimaryFixed),
    onPrimaryFixedVariant: role(scheme.onPrimaryFixedVariant),
    secondary: role(scheme.secondary),
    onSecondary: role(scheme.onSecondary),
    secondaryContainer: role(scheme.secondaryContainer),
    onSecondaryContainer: role(scheme.onSecondaryContainer),
    secondaryFixed: role(scheme.secondaryFixed),
    secondaryFixedDim: role(scheme.secondaryFixedDim),
    onSecondaryFixed: role(scheme.onSecondaryFixed),
    onSecondaryFixedVariant: role(scheme.onSecondaryFixedVariant),
    tertiary: role(scheme.tertiary),
    onTertiary: role(scheme.onTertiary),
    tertiaryContainer: role(scheme.tertiaryContainer),
    onTertiaryContainer: role(scheme.onTertiaryContainer),
    tertiaryFixed: role(scheme.tertiaryFixed),
    tertiaryFixedDim: role(scheme.tertiaryFixedDim),
    onTertiaryFixed: role(scheme.onTertiaryFixed),
    onTertiaryFixedVariant: role(scheme.onTertiaryFixedVariant),
    error: role(scheme.error),
    onError: role(scheme.onError),
    errorContainer: role(scheme.errorContainer),
    onErrorContainer: role(scheme.onErrorContainer),
    surface: role(scheme.surface),
    onSurface: role(scheme.onSurface),
    surfaceDim: role(scheme.surfaceDim),
    surfaceBright: role(scheme.surfaceBright),
    surfaceContainerLowest: role(scheme.surfaceContainerLowest),
    surfaceContainerLow: role(scheme.surfaceContainerLow),
    surfaceContainer: role(scheme.surfaceContainer),
    surfaceContainerHigh: role(scheme.surfaceContainerHigh),
    surfaceContainerHighest: role(scheme.surfaceContainerHighest),
    onSurfaceVariant: role(scheme.onSurfaceVariant),
    outline: role(scheme.outline),
    outlineVariant: role(scheme.outlineVariant),
    shadow: role(scheme.shadow),
    scrim: role(scheme.scrim),
    inverseSurface: role(scheme.inverseSurface),
    onInverseSurface: role(scheme.inverseOnSurface),
    inversePrimary: role(scheme.inversePrimary),
    surfaceTint: role(scheme.surfaceTint),
  );
}

Color _contrastForeground(Color background) {
  const dark = ShellMediaColors.darkness;
  const light = ShellMediaColors.contrastLight;
  final backgroundLuminance = background.computeLuminance();
  const darkLuminance = 0.0;
  const lightLuminance = 1.0;
  final darkContrast = _contrastRatio(backgroundLuminance, darkLuminance);
  final lightContrast = _contrastRatio(backgroundLuminance, lightLuminance);
  return darkContrast >= lightContrast ? dark : light;
}

double _contrastRatio(double first, double second) {
  final lighter = first > second ? first : second;
  final darker = first > second ? second : first;
  return (lighter + 0.05) / (darker + 0.05);
}
