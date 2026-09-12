import 'package:flutter/widgets.dart';

/// Product colors whose identity is independent of surface brightness.
abstract final class ShellBrandColors {
  static const Color defaultAccent = Color(0xffd0bcff);
  static const Color fallbackAppIcon = Color(0xff147cdc);

  /// Source foreground embedded in the Denial SVG wordmark. The SVG loader
  /// replaces this sentinel with the active semantic text foreground.
  static const Color wordmarkAssetForeground = Color(0xfff0eef5);
}

/// Colors for shell content deliberately composited over imagery.
///
/// These roles do not follow desktop brightness: their callers provide a dark
/// glass or scrim so clocks, launcher labels, and media annotations retain a
/// stable foreground over arbitrary wallpaper and application content.
abstract final class ShellMediaColors {
  static const Color lightForeground = Color(0xfff7f7f8);
  static const Color contrastLight = Color(0xffffffff);
  static const Color lightForegroundSecondary = Color(0xffc7c9d1);
  static const Color lightForegroundTertiary = Color(0xff8f96a3);
  static const Color darkSurface = Color(0xff070910);
  static const Color glassSurface = Color(0x28070910);
  static const Color glassSurfaceStrong = Color(0xdd070910);
  static const Color lightOutline = Color(0x26ffffff);
  static const Color lightGrid = Color(0x24ffffff);
  static const Color wallpaperScrim = Color(0x14000000);
  static const Color darkness = Color(0xff000000);
  static const Color shadow = Color(0x80000000);
  static const Color transparentDark = Color(0x00000000);
  static const Color transparentLight = Color(0x00ffffff);
}

/// Invariant telemetry colors whose hue communicates a native device state.
abstract final class ShellTelemetryColors {
  static const Color chargingVooc = Color(0xff5ff38a);
  static const Color chargingPps = Color(0xffbd8cff);
  static const Color chargingPd = Color(0xff7aa8ff);
  static const Color charging = Color(0xff78dce8);
  static const Color warning = Color(0xffffd166);
  static const Color danger = Color(0xffff6b6b);
  static const Color discharge = Color(0xffffa657);
  static const Color warm = Color(0xffffb86b);
  static const Color nominal = Color(0xff8ee6c1);
}

/// Default opacity for the shell's frosted surfaces.
abstract final class ShellOpacity {
  static const double panel = 0.75;
  static const double card = 0.95;
  static const double minimumPanel = 0.05;
  static const double minimumCard = 0;
}

/// Global scale applied to every semantic shell corner radius.
///
/// A scale keeps the visual hierarchy between windows, panels, cards, chips,
/// and controls while giving users one coherent roundness control. A value of
/// zero makes every themed corner square.
abstract final class ShellRoundness {
  static const double normal = 1.0;
  static const double minimum = 0.0;
  static const double maximum = 2.0;
}

/// Base corner radii used throughout the shell at normal roundness.
abstract final class ShellRadii {
  /// Windows and panels are peer top-level surfaces and must share one shape.
  static const double panel = 28.0;
  static const double window = panel;
  static const double notification = 18.0;
  static const double tile = 24.0;
  static const double tileWide = 24.0;
  static const double chip = 21.0;
  static const double roundButton = 21.0;
}

/// Material 3 Expressive corner scale.
///
/// [ShellRadii] keeps its established component values; this scale gives new
/// surfaces a shared vocabulary instead of ad-hoc numbers.
abstract final class ShellShapeScale {
  static const double none = 0.0;
  static const double extraSmall = 4.0;
  static const double small = 8.0;
  static const double medium = 12.0;
  static const double large = 16.0;
  static const double largeIncreased = 20.0;
  static const double extraLarge = 28.0;
  static const double extraLargeIncreased = 32.0;
  static const double extraExtraLarge = 48.0;
  static const double full = 999.0;
}

/// Material 3 Expressive spacing ramp (02-VISUAL-SPEC.md §4).
///
/// Every padding, gap, and margin introduced by the expressive refactor snaps
/// to these steps instead of inventing ad-hoc offsets.
abstract final class ShellSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Material 3 Expressive elevation levels (02-VISUAL-SPEC.md §1.2).
///
/// Hierarchy is tonal, not shadow-based: each level resolves to a
/// `surfaceContainer*` tier of the active `ShellColorScheme`, so frosted
/// surfaces keep their blur and panels never paint cast shadows.
abstract final class ShellElevation {
  /// Flat content painted directly on the surrounding surface.
  static const int level0 = 0;

  /// Raised floor for panels and bubbles — `surfaceContainerLow`.
  static const int level1 = 1;

  /// Cards and grouped content resting on a level-1 surface —
  /// `surfaceContainer`.
  static const int level2 = 2;

  /// Nested cards, indicator wells, and other highest-order content —
  /// `surfaceContainerHigh`/`surfaceContainerHighest`.
  static const int level3 = 3;
}

/// Brightness-independent text metrics.
///
/// [ShellTextTheme] applies semantic foreground colors. Keeping these
/// prototypes colorless lets text inherit the active shell foreground when a
/// specialized resolved style is unnecessary.
abstract final class ShellText {
  /// Monospace family bundled for the system bar so ticking values keep a
  /// fixed advance; the rest of the shell stays on the default family.
  static const String systemBarFontFamily = 'JetBrainsMono';
  static const List<String> fallbackFontFamilies = <String>[
    'Source Han Sans CN',
    'Noto Sans CJK SC',
  ];

  static const TextStyle base = TextStyle(
    fontFamilyFallback: fallbackFontFamilies,
    fontSize: 14,
    decoration: TextDecoration.none,
  );

  static const TextStyle statusClock = TextStyle(
    fontFamilyFallback: fallbackFontFamilies,
    fontSize: 18,
    height: 1,
    fontWeight: FontWeight.w800,
    decoration: TextDecoration.none,
  );

  /// System bar card text, sized for the thin pill cards floating inside the
  /// reserved bar strip.
  static const TextStyle systemBarValue = TextStyle(
    fontFamily: systemBarFontFamily,
    fontFamilyFallback: fallbackFontFamilies,
    fontSize: 13,
    height: 1,
    leadingDistribution: TextLeadingDistribution.even,
    fontWeight: FontWeight.w700,
    // Letter spacing stays zero: fractional tracking smears glyph phase at
    // 150% scale and is a direct source of blurry text.
    letterSpacing: 0,
    decoration: TextDecoration.none,
  );

  /// Secondary system bar text (the date caption beside the clock). Callers
  /// tint the color toward the wallpaper accent.
  static const TextStyle systemBarCaption = TextStyle(
    fontFamily: systemBarFontFamily,
    fontFamilyFallback: fallbackFontFamilies,
    fontSize: 11,
    height: 1,
    leadingDistribution: TextLeadingDistribution.even,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
    decoration: TextDecoration.none,
  );

  static const TextStyle shadeClock = TextStyle(
    fontFamilyFallback: fallbackFontFamilies,
    fontSize: 42,
    height: 1,
    fontWeight: FontWeight.w800,
    letterSpacing: 0,
    decoration: TextDecoration.none,
  );

  static const TextStyle shadeDate = TextStyle(
    fontFamilyFallback: fallbackFontFamilies,
    fontSize: 16,
    height: 1,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
    decoration: TextDecoration.none,
  );

  static const TextStyle lockClock = TextStyle(
    fontFamilyFallback: fallbackFontFamilies,
    fontSize: 124,
    height: 0.95,
    fontWeight: FontWeight.w300,
    letterSpacing: 0,
    decoration: TextDecoration.none,
  );

  static const TextStyle lockDate = TextStyle(
    fontFamilyFallback: fallbackFontFamilies,
    fontSize: 24,
    height: 1.15,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    decoration: TextDecoration.none,
  );

  static const TextStyle lockStatus = TextStyle(
    fontFamilyFallback: fallbackFontFamilies,
    fontSize: 18,
    height: 1.1,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
    decoration: TextDecoration.none,
  );

  static const TextStyle lockChip = TextStyle(
    fontFamilyFallback: fallbackFontFamilies,
    fontSize: 12,
    height: 1,
    fontWeight: FontWeight.w800,
    letterSpacing: 0,
    decoration: TextDecoration.none,
  );

  static const TextStyle cardTitle = TextStyle(
    fontFamilyFallback: fallbackFontFamilies,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    decoration: TextDecoration.none,
  );

  static const TextStyle shelfTooltip = TextStyle(
    fontFamilyFallback: fallbackFontFamilies,
    fontSize: 12,
    height: 1,
    fontWeight: FontWeight.w500,
    decoration: TextDecoration.none,
  );

  static const TextStyle trayClock = TextStyle(
    fontFamilyFallback: fallbackFontFamilies,
    fontSize: 13,
    height: 1,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    decoration: TextDecoration.none,
  );

  static const TextStyle podLabel = TextStyle(
    fontFamilyFallback: fallbackFontFamilies,
    fontSize: 11,
    height: 1.2,
    fontWeight: FontWeight.w500,
    decoration: TextDecoration.none,
  );

  // Settings typography roles (02-VISUAL-SPEC.md §6).
  //
  // The explicit `height` values are the spec's line-height / font-size
  // ratios; every role keeps `letterSpacing` at zero so glyph phase stays on
  // the physical pixel grid (constraint §D5).

  /// Page headline, expanded state (M3E emphasized HeadlineMedium).
  static const TextStyle settingsPageTitle = TextStyle(
    fontFamilyFallback: fallbackFontFamilies,
    fontSize: 28,
    height: 36 / 28,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
    decoration: TextDecoration.none,
  );

  /// Page headline, collapsed-and-pinned state (M3E emphasized TitleLarge).
  static const TextStyle settingsPageTitleCollapsed = TextStyle(
    fontFamilyFallback: fallbackFontFamilies,
    fontSize: 22,
    height: 28 / 22,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
    decoration: TextDecoration.none,
  );

  /// Navigation destination title (M3 TitleMedium).
  static const TextStyle settingsNavLabel = TextStyle(
    fontFamilyFallback: fallbackFontFamilies,
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
    decoration: TextDecoration.none,
  );

  /// Navigation destination supporting line (M3 BodyMedium).
  static const TextStyle settingsNavSupport = TextStyle(
    fontFamilyFallback: fallbackFontFamilies,
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    decoration: TextDecoration.none,
  );

  /// Content row title (M3 TitleMedium).
  static const TextStyle settingsRowTitle = TextStyle(
    fontFamilyFallback: fallbackFontFamilies,
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
    decoration: TextDecoration.none,
  );

  /// Content row supporting line (M3 BodyMedium).
  static const TextStyle settingsRowSupport = TextStyle(
    fontFamilyFallback: fallbackFontFamilies,
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    decoration: TextDecoration.none,
  );

  /// Group or section title (M3 TitleSmall, deliberately restrained).
  static const TextStyle settingsSectionHeader = TextStyle(
    fontFamilyFallback: fallbackFontFamilies,
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
    decoration: TextDecoration.none,
  );

  /// Button label (M3 LabelLarge).
  static const TextStyle settingsButtonLabel = TextStyle(
    fontFamilyFallback: fallbackFontFamilies,
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
    decoration: TextDecoration.none,
  );

  /// "Live changes" badge label (M3 LabelSmall).
  static const TextStyle settingsBadgeLabel = TextStyle(
    fontFamilyFallback: fallbackFontFamilies,
    fontSize: 11,
    height: 16 / 11,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
    decoration: TextDecoration.none,
  );

  /// Search field hint (M3 BodyLarge).
  static const TextStyle settingsSearchHint = TextStyle(
    fontFamilyFallback: fallbackFontFamilies,
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    decoration: TextDecoration.none,
  );

  // Full M3E typescale (02-VISUAL-SPEC.md §3).
  //
  // Every size is an integer sp value and `letterSpacing` stays zero (§D5).
  // Line heights use the standard M3 line-height / font-size ratios, the same
  // convention as the settings roles above. Baseline weights follow the M3
  // scale; each `*Emphasized` variant carries identical metrics at w600 for
  // hero numerals and other moments the spec calls for emphasized type.
  //
  // Older shell roles remain as semantic aliases of this scale — for example
  // [settingsNavLabel] matches titleMedium and [cardTitle] reads as an
  // emphasized label — and keep their own fields for existing callers.

  /// M3E DisplayLarge (57sp).
  static const TextStyle displayLarge = TextStyle(
    fontFamilyFallback: fallbackFontFamilies,
    fontSize: 57,
    height: 64 / 57,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    decoration: TextDecoration.none,
  );

  /// M3E DisplayMedium (45sp).
  static const TextStyle displayMedium = TextStyle(
    fontFamilyFallback: fallbackFontFamilies,
    fontSize: 45,
    height: 52 / 45,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    decoration: TextDecoration.none,
  );

  /// M3E DisplaySmall (36sp).
  static const TextStyle displaySmall = TextStyle(
    fontFamilyFallback: fallbackFontFamilies,
    fontSize: 36,
    height: 44 / 36,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    decoration: TextDecoration.none,
  );

  /// M3E HeadlineLarge (32sp).
  static const TextStyle headlineLarge = TextStyle(
    fontFamilyFallback: fallbackFontFamilies,
    fontSize: 32,
    height: 40 / 32,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    decoration: TextDecoration.none,
  );

  /// M3E HeadlineMedium (28sp).
  static const TextStyle headlineMedium = TextStyle(
    fontFamilyFallback: fallbackFontFamilies,
    fontSize: 28,
    height: 36 / 28,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    decoration: TextDecoration.none,
  );

  /// M3E HeadlineSmall (24sp).
  static const TextStyle headlineSmall = TextStyle(
    fontFamilyFallback: fallbackFontFamilies,
    fontSize: 24,
    height: 32 / 24,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    decoration: TextDecoration.none,
  );

  /// M3E TitleLarge (22sp).
  static const TextStyle titleLarge = TextStyle(
    fontFamilyFallback: fallbackFontFamilies,
    fontSize: 22,
    height: 28 / 22,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    decoration: TextDecoration.none,
  );

  /// M3E TitleMedium (16sp).
  static const TextStyle titleMedium = TextStyle(
    fontFamilyFallback: fallbackFontFamilies,
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
    decoration: TextDecoration.none,
  );

  /// M3E TitleSmall (14sp).
  static const TextStyle titleSmall = TextStyle(
    fontFamilyFallback: fallbackFontFamilies,
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
    decoration: TextDecoration.none,
  );

  /// M3E BodyLarge (16sp).
  static const TextStyle bodyLarge = TextStyle(
    fontFamilyFallback: fallbackFontFamilies,
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    decoration: TextDecoration.none,
  );

  /// M3E BodyMedium (14sp).
  static const TextStyle bodyMedium = TextStyle(
    fontFamilyFallback: fallbackFontFamilies,
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    decoration: TextDecoration.none,
  );

  /// M3E BodySmall (12sp).
  static const TextStyle bodySmall = TextStyle(
    fontFamilyFallback: fallbackFontFamilies,
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    decoration: TextDecoration.none,
  );

  /// M3E LabelLarge (14sp).
  static const TextStyle labelLarge = TextStyle(
    fontFamilyFallback: fallbackFontFamilies,
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
    decoration: TextDecoration.none,
  );

  /// M3E LabelMedium (12sp).
  static const TextStyle labelMedium = TextStyle(
    fontFamilyFallback: fallbackFontFamilies,
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
    decoration: TextDecoration.none,
  );

  /// M3E LabelSmall (11sp).
  static const TextStyle labelSmall = TextStyle(
    fontFamilyFallback: fallbackFontFamilies,
    fontSize: 11,
    height: 16 / 11,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
    decoration: TextDecoration.none,
  );

  /// Emphasized DisplayLarge: [displayLarge] metrics at w600.
  static const TextStyle displayLargeEmphasized = TextStyle(
    fontFamilyFallback: fallbackFontFamilies,
    fontSize: 57,
    height: 64 / 57,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    decoration: TextDecoration.none,
  );

  /// Emphasized DisplayMedium: [displayMedium] metrics at w600.
  static const TextStyle displayMediumEmphasized = TextStyle(
    fontFamilyFallback: fallbackFontFamilies,
    fontSize: 45,
    height: 52 / 45,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    decoration: TextDecoration.none,
  );

  /// Emphasized DisplaySmall: [displaySmall] metrics at w600.
  static const TextStyle displaySmallEmphasized = TextStyle(
    fontFamilyFallback: fallbackFontFamilies,
    fontSize: 36,
    height: 44 / 36,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    decoration: TextDecoration.none,
  );

  /// Emphasized HeadlineLarge: [headlineLarge] metrics at w600.
  static const TextStyle headlineLargeEmphasized = TextStyle(
    fontFamilyFallback: fallbackFontFamilies,
    fontSize: 32,
    height: 40 / 32,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    decoration: TextDecoration.none,
  );

  /// Emphasized HeadlineMedium: [headlineMedium] metrics at w600.
  static const TextStyle headlineMediumEmphasized = TextStyle(
    fontFamilyFallback: fallbackFontFamilies,
    fontSize: 28,
    height: 36 / 28,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    decoration: TextDecoration.none,
  );

  /// Emphasized HeadlineSmall: [headlineSmall] metrics at w600.
  static const TextStyle headlineSmallEmphasized = TextStyle(
    fontFamilyFallback: fallbackFontFamilies,
    fontSize: 24,
    height: 32 / 24,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    decoration: TextDecoration.none,
  );

  /// Emphasized TitleLarge: [titleLarge] metrics at w600.
  static const TextStyle titleLargeEmphasized = TextStyle(
    fontFamilyFallback: fallbackFontFamilies,
    fontSize: 22,
    height: 28 / 22,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    decoration: TextDecoration.none,
  );

  /// Emphasized TitleMedium: [titleMedium] metrics at w600.
  static const TextStyle titleMediumEmphasized = TextStyle(
    fontFamilyFallback: fallbackFontFamilies,
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    decoration: TextDecoration.none,
  );

  /// Emphasized TitleSmall: [titleSmall] metrics at w600.
  static const TextStyle titleSmallEmphasized = TextStyle(
    fontFamilyFallback: fallbackFontFamilies,
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    decoration: TextDecoration.none,
  );

  /// Emphasized BodyLarge: [bodyLarge] metrics at w600.
  static const TextStyle bodyLargeEmphasized = TextStyle(
    fontFamilyFallback: fallbackFontFamilies,
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    decoration: TextDecoration.none,
  );

  /// Emphasized BodyMedium: [bodyMedium] metrics at w600.
  static const TextStyle bodyMediumEmphasized = TextStyle(
    fontFamilyFallback: fallbackFontFamilies,
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    decoration: TextDecoration.none,
  );

  /// Emphasized BodySmall: [bodySmall] metrics at w600.
  static const TextStyle bodySmallEmphasized = TextStyle(
    fontFamilyFallback: fallbackFontFamilies,
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    decoration: TextDecoration.none,
  );

  /// Emphasized LabelLarge: [labelLarge] metrics at w600.
  static const TextStyle labelLargeEmphasized = TextStyle(
    fontFamilyFallback: fallbackFontFamilies,
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    decoration: TextDecoration.none,
  );

  /// Emphasized LabelMedium: [labelMedium] metrics at w600.
  static const TextStyle labelMediumEmphasized = TextStyle(
    fontFamilyFallback: fallbackFontFamilies,
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    decoration: TextDecoration.none,
  );

  /// Emphasized LabelSmall: [labelSmall] metrics at w600.
  static const TextStyle labelSmallEmphasized = TextStyle(
    fontFamilyFallback: fallbackFontFamilies,
    fontSize: 11,
    height: 16 / 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    decoration: TextDecoration.none,
  );
}
