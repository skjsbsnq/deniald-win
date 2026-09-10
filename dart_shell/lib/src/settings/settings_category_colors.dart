import 'package:flutter/material.dart';

import '../theme/shell_theme.dart';
import 'widgets/settings_navigation.dart';

/// The container/foreground pair for one Settings category icon.
typedef SettingsCategoryHue = ({Color container, Color onContainer});

/// Per-page category hues for Settings iconography.
///
/// The seed table mirrors `02-VISUAL-SPEC.md` §4.3 and is the single source of
/// truth for category color (constraint §D7). Each seed is expanded through
/// `ColorScheme.fromSeed(..., dynamicSchemeVariant: expressive)` so the icon
/// container/foreground pair stays tonally consistent with the active
/// brightness; derivations are cached per `(seed, brightness)` because
/// `fromSeed` is far too expensive to run from `build`.
abstract final class SettingsCategoryColors {
  /// Seed color per page. `about` is deliberately absent: it stays neutral and
  /// borrows the surface roles instead of claiming a hue (§4.3).
  static const Map<SettingsPageId, Color> seeds = <SettingsPageId, Color>{
    SettingsPageId.network: Color(0xff0097a7),
    SettingsPageId.bluetooth: Color(0xff2563eb),
    SettingsPageId.displays: Color(0xff4f46e5),
    SettingsPageId.audio: Color(0xff7c3aed),
    SettingsPageId.appearance: Color(0xffdb2777),
    SettingsPageId.animations: Color(0xffe11d48),
    SettingsPageId.lockScreen: Color(0xffdc2626),
    SettingsPageId.layout: Color(0xff1d4ed8),
    SettingsPageId.overlays: Color(0xff0284c7),
    SettingsPageId.weather: Color(0xffea580c),
    SettingsPageId.power: Color(0xffd97706),
    SettingsPageId.keyboard: Color(0xff16a34a),
    SettingsPageId.touchpad: Color(0xff0d9488),
    SettingsPageId.shortcuts: Color(0xff059669),
    SettingsPageId.language: Color(0xffb45309),
    SettingsPageId.environment: Color(0xff475569),
    SettingsPageId.developer: Color(0xff0f766e),
  };

  /// Derived hue pairs keyed by seed and brightness. One entry per pair, shared
  /// across every rebuild; identity is stable for a given key.
  static final Map<(Color, Brightness), SettingsCategoryHue> _cache =
      <(Color, Brightness), SettingsCategoryHue>{};

  /// Resolves the icon hue pair for [page] under the active shell theme.
  static SettingsCategoryHue of(BuildContext context, SettingsPageId page) {
    final seed = seeds[page];
    if (seed == null) {
      return (
        container: context.shellColors.surfaceContainerHigh,
        onContainer: context.shellColors.textSecondary,
      );
    }
    final brightness = context.shellTheme.brightness;
    return _cache.putIfAbsent(
      (seed, brightness),
      () => _derive(seed, brightness),
    );
  }

  /// Container fill for [page]'s icon circle.
  static Color containerOf(BuildContext context, SettingsPageId page) =>
      of(context, page).container;

  /// Foreground glyph color for [page]'s icon circle.
  static Color onContainerOf(BuildContext context, SettingsPageId page) =>
      of(context, page).onContainer;

  static SettingsCategoryHue _derive(Color seed, Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.expressive,
    );
    return (
      container: scheme.primaryContainer,
      onContainer: scheme.onPrimaryContainer,
    );
  }
}
