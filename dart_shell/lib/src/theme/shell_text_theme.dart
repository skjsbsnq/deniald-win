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
  });

  factory ShellTextTheme.from(ShellColorScheme colors, {String? fontFamily}) {
    // An empty family name falls back to the Flutter default; the inherited
    // fallbackFontFamilies still cover glyphs the family lacks.
    final String? family = fontFamily == null || fontFamily.isEmpty
        ? null
        : fontFamily;
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
    );
  }
}
