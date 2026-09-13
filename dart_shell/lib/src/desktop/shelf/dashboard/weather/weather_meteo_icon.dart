import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:lottie/lottie.dart';

import 'weather_visibility.dart';

/// WMO 4677 code + day/night → meteocons slug. Ported verbatim from
/// `CLAVIS/Widgets/weather/MeteoIcon.qml` `slugForCode` (L29-42): thirteen
/// branches producing 25 slugs plus the `not-available` fallback.
String meteoSlugForCode(int code, {required bool night}) {
  if (code == 0) {
    return night ? 'clear-night' : 'clear-day';
  }
  if (code == 1) {
    return night ? 'mostly-clear-night' : 'mostly-clear-day';
  }
  if (code == 2) {
    return night ? 'partly-cloudy-night' : 'partly-cloudy-day';
  }
  if (code == 3) {
    return 'cloudy';
  }
  if (code == 45 || code == 48) {
    return night ? 'fog-night' : 'fog-day';
  }
  if (code >= 51 && code <= 57) {
    return 'drizzle';
  }
  if (code == 61 || code == 63 || code == 65) {
    return night ? 'overcast-night-rain' : 'overcast-day-rain';
  }
  if (code == 66 || code == 67) {
    return night ? 'overcast-night-sleet' : 'overcast-day-sleet';
  }
  if (code >= 71 && code <= 77) {
    return night ? 'overcast-night-snow' : 'overcast-day-snow';
  }
  if (code >= 80 && code <= 82) {
    return night ? 'partly-cloudy-night-rain' : 'partly-cloudy-day-rain';
  }
  if (code == 85 || code == 86) {
    return night ? 'partly-cloudy-night-snow' : 'partly-cloudy-day-snow';
  }
  if (code == 95) {
    return night ? 'thunderstorms-night' : 'thunderstorms-day';
  }
  if (code == 96 || code == 99) {
    return night ? 'thunderstorms-night-hail' : 'thunderstorms-day-hail';
  }
  return 'not-available';
}

/// Name-based slug fallback for providers that ship an icon name instead of a
/// WMO code. Mirrors `MeteoIcon.qml` `slugFromName` (L45-57).
String meteoSlugFromName(String name, {required bool night}) {
  if (name.isEmpty) {
    return '';
  }
  if (name.contains('clear_night')) {
    return 'clear-night';
  }
  if (name.contains('sun')) {
    return 'clear-day';
  }
  if (name.contains('partly')) {
    return night ? 'partly-cloudy-night' : 'partly-cloudy-day';
  }
  if (name.contains('cloud')) {
    return 'cloudy';
  }
  if (name.contains('fog')) {
    return night ? 'fog-night' : 'fog-day';
  }
  if (name.contains('drizzle')) {
    return 'drizzle';
  }
  if (name.contains('rain')) {
    return night ? 'overcast-night-rain' : 'overcast-day-rain';
  }
  if (name.contains('snow')) {
    return night ? 'overcast-night-snow' : 'overcast-day-snow';
  }
  if (name.contains('thunder')) {
    return night ? 'thunderstorms-night' : 'thunderstorms-day';
  }
  return '';
}

/// The resolved meteocons slug: code mapping first, icon-name fallback
/// second, `not-available` last — the `MeteoIcon.qml` `iconSlug` order.
String meteoSlug({
  required int code,
  String iconName = '',
  required bool night,
}) {
  final byCode = meteoSlugForCode(code, night: night);
  if (byCode != 'not-available') {
    return byCode;
  }
  final byName = meteoSlugFromName(iconName.toLowerCase(), night: night);
  return byName.isNotEmpty ? byName : 'not-available';
}

/// Animated meteocons glyph: the bundled Lottie playback first, the bundled
/// SVG as the fallback (missing asset, decode failure, or reduce-motion) —
/// the dual-channel pattern of `MeteoIcon.qml` L66-113.
class WeatherMeteoIcon extends StatelessWidget {
  const WeatherMeteoIcon({
    super.key,
    required this.weatherCode,
    this.iconName = '',
    required this.night,
    required this.size,
    this.animated = true,
    this.fallbackIcon,
    this.fallbackIconColor,
    this.semanticLabel,
  });

  final int weatherCode;
  final String iconName;
  final bool night;
  final double size;

  /// Master switch for the Lottie channel; reduce-motion pages pass false so
  /// the static SVG is used directly.
  final bool animated;

  /// Last-resort glyph when both bundled asset channels fail to decode or are
  /// absent (e.g. bare widget tests without the asset bundle).
  final IconData? fallbackIcon;
  final Color? fallbackIconColor;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final slug = meteoSlug(code: weatherCode, iconName: iconName, night: night);
    final scope = WeatherPageActivity.maybeOf(context);
    final animationsEnabled =
        scope?.animationsEnabled ?? !MediaQuery.disableAnimationsOf(context);
    final tickerEnabled = TickerMode.valuesOf(context).enabled;

    Widget fallback() => fallbackIcon == null
        ? SizedBox(width: size, height: size)
        : Icon(fallbackIcon, size: size, color: fallbackIconColor);

    Widget svg() => SvgPicture.asset(
      'assets/weather/meteocons/svg/$slug.svg',
      width: size,
      height: size,
      fit: BoxFit.contain,
      placeholderBuilder: fallbackIcon == null
          ? (_) => SizedBox(width: size, height: size)
          : (_) => fallback(),
      errorBuilder: (context, error, stackTrace) => fallback(),
    );

    Widget buildChannel(bool pageActive) {
      // The page-activity flag pauses playback while the Weather tab stays
      // mounted under another dashboard tab (IndexedStack keeps tickers
      // alive); TickerMode covers a parked panel; the page-level animation
      // switch covers reduce-motion.
      final playing =
          animated && animationsEnabled && pageActive && tickerEnabled;
      if (!animationsEnabled || !animated) {
        return svg();
      }
      return Lottie.asset(
        'assets/weather/meteocons/lottie/$slug.json',
        width: size,
        height: size,
        fit: BoxFit.contain,
        animate: playing,
        repeat: true,
        errorBuilder: (context, error, stackTrace) => svg(),
      );
    }

    final active = scope?.active;
    final Widget child = active == null
        ? buildChannel(true)
        : ValueListenableBuilder<bool>(
            valueListenable: active,
            builder: (context, pageActive, _) => buildChannel(pageActive),
          );

    return Semantics(
      image: true,
      label: semanticLabel,
      child: SizedBox(width: size, height: size, child: child),
    );
  }
}
