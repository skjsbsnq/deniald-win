import 'package:flutter/widgets.dart';

import 'shell_color_scheme.dart';
import 'tokens.dart';

@immutable
class ShellTextTheme {
  const ShellTextTheme({
    required this.base,
    required this.statusClock,
    required this.systemBarValue,
    required this.systemBarCaption,
    required this.shadeClock,
    required this.shadeDate,
    required this.lockClock,
    required this.lockDate,
    required this.lockStatus,
    required this.lockChip,
    required this.cardTitle,
    required this.displayLarge,
    required this.displayMedium,
    required this.displaySmall,
    required this.headlineLarge,
    required this.headlineMedium,
    required this.headlineSmall,
    required this.titleLarge,
    required this.titleMedium,
    required this.titleSmall,
    required this.bodyLarge,
    required this.bodyMedium,
    required this.bodySmall,
    required this.labelLarge,
    required this.labelMedium,
    required this.labelSmall,
    required this.displayLargeEmphasized,
    required this.displayMediumEmphasized,
    required this.displaySmallEmphasized,
    required this.headlineLargeEmphasized,
    required this.headlineMediumEmphasized,
    required this.headlineSmallEmphasized,
    required this.titleLargeEmphasized,
    required this.titleMediumEmphasized,
    required this.titleSmallEmphasized,
    required this.bodyLargeEmphasized,
    required this.bodyMediumEmphasized,
    required this.bodySmallEmphasized,
    required this.labelLargeEmphasized,
    required this.labelMediumEmphasized,
    required this.labelSmallEmphasized,
  });

  factory ShellTextTheme.from(ShellColorScheme colors, {String? fontFamily}) {
    // An empty family name falls back to the Flutter default; the inherited
    // fallbackFontFamilies still cover glyphs the family lacks.
    final String? family = fontFamily == null || fontFamily.isEmpty
        ? null
        : fontFamily;
    // M3E typescale roles resolve to the primary surface foreground; callers
    // tint toward secondary/variant roles at the point of use.
    TextStyle scale(TextStyle prototype) => prototype.copyWith(
          color: colors.textPrimary,
          fontFamily: family,
        );
    return ShellTextTheme(
      base: ShellText.base.copyWith(color: colors.textPrimary),
      statusClock: ShellText.statusClock.copyWith(
        color: colors.textPrimary,
        fontFamily: family,
      ),
      systemBarValue: ShellText.systemBarValue.copyWith(
        color: colors.textPrimary,
        fontFamily: family,
      ),
      systemBarCaption: ShellText.systemBarCaption.copyWith(
        color: colors.textSecondary,
        fontFamily: family,
      ),
      shadeClock: ShellText.shadeClock.copyWith(
        color: colors.panelText,
        fontFamily: family,
      ),
      shadeDate: ShellText.shadeDate.copyWith(
        color: colors.textSecondary,
        fontFamily: family,
      ),
      lockClock: ShellText.lockClock.copyWith(
        color: colors.textPrimary,
        fontFamily: family,
      ),
      lockDate: ShellText.lockDate.copyWith(
        color: colors.textSecondary,
        fontFamily: family,
      ),
      lockStatus: ShellText.lockStatus.copyWith(
        color: colors.textSecondary,
        fontFamily: family,
      ),
      lockChip: ShellText.lockChip.copyWith(
        color: colors.textPrimary,
        fontFamily: family,
      ),
      cardTitle: ShellText.cardTitle.copyWith(
        color: colors.textPrimary,
        fontFamily: family,
      ),
      displayLarge: scale(ShellText.displayLarge),
      displayMedium: scale(ShellText.displayMedium),
      displaySmall: scale(ShellText.displaySmall),
      headlineLarge: scale(ShellText.headlineLarge),
      headlineMedium: scale(ShellText.headlineMedium),
      headlineSmall: scale(ShellText.headlineSmall),
      titleLarge: scale(ShellText.titleLarge),
      titleMedium: scale(ShellText.titleMedium),
      titleSmall: scale(ShellText.titleSmall),
      bodyLarge: scale(ShellText.bodyLarge),
      bodyMedium: scale(ShellText.bodyMedium),
      bodySmall: scale(ShellText.bodySmall),
      labelLarge: scale(ShellText.labelLarge),
      labelMedium: scale(ShellText.labelMedium),
      labelSmall: scale(ShellText.labelSmall),
      displayLargeEmphasized: scale(ShellText.displayLargeEmphasized),
      displayMediumEmphasized: scale(ShellText.displayMediumEmphasized),
      displaySmallEmphasized: scale(ShellText.displaySmallEmphasized),
      headlineLargeEmphasized: scale(ShellText.headlineLargeEmphasized),
      headlineMediumEmphasized: scale(ShellText.headlineMediumEmphasized),
      headlineSmallEmphasized: scale(ShellText.headlineSmallEmphasized),
      titleLargeEmphasized: scale(ShellText.titleLargeEmphasized),
      titleMediumEmphasized: scale(ShellText.titleMediumEmphasized),
      titleSmallEmphasized: scale(ShellText.titleSmallEmphasized),
      bodyLargeEmphasized: scale(ShellText.bodyLargeEmphasized),
      bodyMediumEmphasized: scale(ShellText.bodyMediumEmphasized),
      bodySmallEmphasized: scale(ShellText.bodySmallEmphasized),
      labelLargeEmphasized: scale(ShellText.labelLargeEmphasized),
      labelMediumEmphasized: scale(ShellText.labelMediumEmphasized),
      labelSmallEmphasized: scale(ShellText.labelSmallEmphasized),
    );
  }

  final TextStyle base;
  final TextStyle statusClock;
  final TextStyle systemBarValue;
  final TextStyle systemBarCaption;
  final TextStyle shadeClock;
  final TextStyle shadeDate;
  final TextStyle lockClock;
  final TextStyle lockDate;
  final TextStyle lockStatus;
  final TextStyle lockChip;
  final TextStyle cardTitle;

  // M3E typescale roles (02-VISUAL-SPEC.md §3). Baseline variants map
  // one-to-one onto Material [TextTheme] slots; emphasized variants keep the
  // same metrics at w600 and stay shell-side.

  final TextStyle displayLarge;
  final TextStyle displayMedium;
  final TextStyle displaySmall;
  final TextStyle headlineLarge;
  final TextStyle headlineMedium;
  final TextStyle headlineSmall;
  final TextStyle titleLarge;
  final TextStyle titleMedium;
  final TextStyle titleSmall;
  final TextStyle bodyLarge;
  final TextStyle bodyMedium;
  final TextStyle bodySmall;
  final TextStyle labelLarge;
  final TextStyle labelMedium;
  final TextStyle labelSmall;
  final TextStyle displayLargeEmphasized;
  final TextStyle displayMediumEmphasized;
  final TextStyle displaySmallEmphasized;
  final TextStyle headlineLargeEmphasized;
  final TextStyle headlineMediumEmphasized;
  final TextStyle headlineSmallEmphasized;
  final TextStyle titleLargeEmphasized;
  final TextStyle titleMediumEmphasized;
  final TextStyle titleSmallEmphasized;
  final TextStyle bodyLargeEmphasized;
  final TextStyle bodyMediumEmphasized;
  final TextStyle bodySmallEmphasized;
  final TextStyle labelLargeEmphasized;
  final TextStyle labelMediumEmphasized;
  final TextStyle labelSmallEmphasized;

  static ShellTextTheme lerp(
    ShellTextTheme first,
    ShellTextTheme second,
    double t,
  ) {
    TextStyle blend(TextStyle a, TextStyle b) => TextStyle.lerp(a, b, t)!;
    return ShellTextTheme(
      base: blend(first.base, second.base),
      statusClock: blend(first.statusClock, second.statusClock),
      systemBarValue: blend(first.systemBarValue, second.systemBarValue),
      systemBarCaption: blend(first.systemBarCaption, second.systemBarCaption),
      shadeClock: blend(first.shadeClock, second.shadeClock),
      shadeDate: blend(first.shadeDate, second.shadeDate),
      lockClock: blend(first.lockClock, second.lockClock),
      lockDate: blend(first.lockDate, second.lockDate),
      lockStatus: blend(first.lockStatus, second.lockStatus),
      lockChip: blend(first.lockChip, second.lockChip),
      cardTitle: blend(first.cardTitle, second.cardTitle),
      displayLarge: blend(first.displayLarge, second.displayLarge),
      displayMedium: blend(first.displayMedium, second.displayMedium),
      displaySmall: blend(first.displaySmall, second.displaySmall),
      headlineLarge: blend(first.headlineLarge, second.headlineLarge),
      headlineMedium: blend(first.headlineMedium, second.headlineMedium),
      headlineSmall: blend(first.headlineSmall, second.headlineSmall),
      titleLarge: blend(first.titleLarge, second.titleLarge),
      titleMedium: blend(first.titleMedium, second.titleMedium),
      titleSmall: blend(first.titleSmall, second.titleSmall),
      bodyLarge: blend(first.bodyLarge, second.bodyLarge),
      bodyMedium: blend(first.bodyMedium, second.bodyMedium),
      bodySmall: blend(first.bodySmall, second.bodySmall),
      labelLarge: blend(first.labelLarge, second.labelLarge),
      labelMedium: blend(first.labelMedium, second.labelMedium),
      labelSmall: blend(first.labelSmall, second.labelSmall),
      displayLargeEmphasized: blend(
        first.displayLargeEmphasized,
        second.displayLargeEmphasized,
      ),
      displayMediumEmphasized: blend(
        first.displayMediumEmphasized,
        second.displayMediumEmphasized,
      ),
      displaySmallEmphasized: blend(
        first.displaySmallEmphasized,
        second.displaySmallEmphasized,
      ),
      headlineLargeEmphasized: blend(
        first.headlineLargeEmphasized,
        second.headlineLargeEmphasized,
      ),
      headlineMediumEmphasized: blend(
        first.headlineMediumEmphasized,
        second.headlineMediumEmphasized,
      ),
      headlineSmallEmphasized: blend(
        first.headlineSmallEmphasized,
        second.headlineSmallEmphasized,
      ),
      titleLargeEmphasized: blend(
        first.titleLargeEmphasized,
        second.titleLargeEmphasized,
      ),
      titleMediumEmphasized: blend(
        first.titleMediumEmphasized,
        second.titleMediumEmphasized,
      ),
      titleSmallEmphasized: blend(
        first.titleSmallEmphasized,
        second.titleSmallEmphasized,
      ),
      bodyLargeEmphasized: blend(
        first.bodyLargeEmphasized,
        second.bodyLargeEmphasized,
      ),
      bodyMediumEmphasized: blend(
        first.bodyMediumEmphasized,
        second.bodyMediumEmphasized,
      ),
      bodySmallEmphasized: blend(
        first.bodySmallEmphasized,
        second.bodySmallEmphasized,
      ),
      labelLargeEmphasized: blend(
        first.labelLargeEmphasized,
        second.labelLargeEmphasized,
      ),
      labelMediumEmphasized: blend(
        first.labelMediumEmphasized,
        second.labelMediumEmphasized,
      ),
      labelSmallEmphasized: blend(
        first.labelSmallEmphasized,
        second.labelSmallEmphasized,
      ),
    );
  }
}
