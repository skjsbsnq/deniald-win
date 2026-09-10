import 'package:denial_dart_shell/src/theme/tokens.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the settings typography roles match the verified spec', () {
    _expectRole(
      ShellText.settingsPageTitle,
      size: 28,
      lineHeight: 36,
      weight: FontWeight.w500,
    );
    _expectRole(
      ShellText.settingsPageTitleCollapsed,
      size: 22,
      lineHeight: 28,
      weight: FontWeight.w500,
    );
    _expectRole(
      ShellText.settingsNavLabel,
      size: 16,
      lineHeight: 24,
      weight: FontWeight.w500,
    );
    _expectRole(
      ShellText.settingsNavSupport,
      size: 14,
      lineHeight: 20,
      weight: FontWeight.w400,
    );
    _expectRole(
      ShellText.settingsRowTitle,
      size: 16,
      lineHeight: 24,
      weight: FontWeight.w500,
    );
    _expectRole(
      ShellText.settingsRowSupport,
      size: 14,
      lineHeight: 20,
      weight: FontWeight.w400,
    );
    _expectRole(
      ShellText.settingsSectionHeader,
      size: 14,
      lineHeight: 20,
      weight: FontWeight.w500,
    );
    _expectRole(
      ShellText.settingsButtonLabel,
      size: 14,
      lineHeight: 20,
      weight: FontWeight.w500,
    );
    _expectRole(
      ShellText.settingsBadgeLabel,
      size: 11,
      lineHeight: 16,
      weight: FontWeight.w500,
    );
    _expectRole(
      ShellText.settingsSearchHint,
      size: 16,
      lineHeight: 24,
      weight: FontWeight.w400,
    );
  });
}

void _expectRole(
  TextStyle style, {
  required double size,
  required double lineHeight,
  required FontWeight weight,
}) {
  expect(style.fontSize, size);
  expect(style.height, isNotNull);
  expect(style.fontSize! * style.height!, closeTo(lineHeight, 0.001));
  expect(style.fontWeight, weight);
  // Fractional tracking smears glyph phase; the spec keeps every role at zero.
  expect(style.letterSpacing, 0);
  expect(style.fontFamilyFallback, ShellText.fallbackFontFamilies);
}
