import 'package:denial_dart_shell/src/theme/shell_theme.dart';
import 'package:denial_dart_shell/src/widgets/shell_backdrop_blur.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const theme = ShellThemeData();

  testWidgets('barely non-zero strength enables the filter at a visible step', (
    tester,
  ) async {
    await tester.pumpWidget(_host(theme, strength: 0.01));
    final backdrop = tester.widget<BackdropFilter>(find.byType(BackdropFilter));
    expect(backdrop.enabled, isTrue);
    // The ramp lifts any non-zero strength to at least half of the quantizer
    // range, so the first visible frame already carries a perceptible sigma
    // instead of the near-invisible first step.
    expect(
      backdrop.filterConfig,
      equals(theme.backdropBlurFilterConfigAt(0.5)),
    );
    expect(
      backdrop.filterConfig,
      isNot(equals(theme.backdropBlurFilterConfigAt(0.01))),
    );
  });

  testWidgets('zero strength keeps the filter disabled and unmapped', (
    tester,
  ) async {
    await tester.pumpWidget(_host(theme, strength: 0));
    final backdrop = tester.widget<BackdropFilter>(find.byType(BackdropFilter));
    expect(backdrop.enabled, isFalse);
    expect(backdrop.filterConfig, equals(theme.backdropBlurFilterConfigAt(0)));
  });

  testWidgets('full strength still resolves to the unquantized config', (
    tester,
  ) async {
    await tester.pumpWidget(_host(theme, strength: 1));
    final backdrop = tester.widget<BackdropFilter>(find.byType(BackdropFilter));
    expect(backdrop.enabled, isTrue);
    expect(backdrop.filterConfig, same(theme.backdropBlurFilterConfig));
  });

  testWidgets('omitted strength behaves exactly like full strength', (
    tester,
  ) async {
    await tester.pumpWidget(_host(theme));
    final backdrop = tester.widget<BackdropFilter>(find.byType(BackdropFilter));
    expect(backdrop.enabled, isTrue);
    expect(backdrop.filterConfig, same(theme.backdropBlurFilterConfig));
  });

  testWidgets('the ramp saturates before mid-animation', (tester) async {
    await tester.pumpWidget(_host(theme, strength: 0.4));
    final backdrop = tester.widget<BackdropFilter>(find.byType(BackdropFilter));
    expect(backdrop.enabled, isTrue);
    expect(backdrop.filterConfig, same(theme.backdropBlurFilterConfig));
  });
}

Widget _host(ShellThemeData theme, {double? strength}) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: ShellTheme(
      data: theme,
      child: Center(
        child: SizedBox(
          width: 100,
          height: 100,
          child: strength == null
              ? const ShellBackdropBlur(child: SizedBox.expand())
              : ShellBackdropBlur(
                  strength: strength,
                  child: const SizedBox.expand(),
                ),
        ),
      ),
    ),
  );
}
