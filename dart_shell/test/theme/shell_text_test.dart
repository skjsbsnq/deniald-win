import 'package:denial_dart_shell/src/theme/tokens.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every shell text token carries the CJK fallback chain', () {
    const styles = <TextStyle>[
      ShellText.base,
      ShellText.statusClock,
      ShellText.systemBarValue,
      ShellText.systemBarCaption,
      ShellText.shadeClock,
      ShellText.shadeDate,
      ShellText.lockClock,
      ShellText.lockDate,
      ShellText.lockStatus,
      ShellText.lockChip,
      ShellText.cardTitle,
    ];

    for (final style in styles) {
      expect(
        style.fontFamilyFallback,
        ShellText.fallbackFontFamilies,
        reason: style.toString(),
      );
    }
  });

  test('every shell text token names its primary family', () {
    // Leaving fontFamily null defers to fontconfig, which answers a CJK
    // request with whichever face it sorts first inside NotoSansCJK's
    // collection. That face already covers every Han glyph, so the fallback
    // chain above never runs and Simplified Chinese renders in Korean forms.
    const styles = <TextStyle>[
      ShellText.base,
      ShellText.statusClock,
      ShellText.systemBarValue,
      ShellText.systemBarCaption,
      ShellText.shadeClock,
      ShellText.shadeDate,
      ShellText.lockClock,
      ShellText.lockDate,
      ShellText.lockStatus,
      ShellText.lockChip,
      ShellText.cardTitle,
    ];

    for (final style in styles) {
      expect(
        style.fontFamily,
        ShellText.uiFontFamily,
        reason: style.toString(),
      );
    }
  });
}
