import 'package:denial_dart_shell/l10n/generated/app_localizations.dart';
import 'package:denial_dart_shell/src/launcher/models/home_clock_info.dart';
import 'package:denial_dart_shell/src/launcher/widgets/home_tiles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

HomeClockInfo _clock() => HomeClockInfo(
  now: DateTime(2026, 9, 9, 14, 30),
  locale: 'en',
  power: HomePowerStatus.unknown,
);

Future<Text> _pumpHeadline(WidgetTester tester, Size tile) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Center(
        child: SizedBox.fromSize(
          size: tile,
          child: HomeClockWidget(clock: _clock(), showStatus: false),
        ),
      ),
    ),
  );
  return tester.widget<Text>(find.text('14:30'));
}

void main() {
  testWidgets('headline renders at a ladder size with no scaling wrapper', (
    tester,
  ) async {
    final text = await _pumpHeadline(tester, const Size(280, 240));
    // min(280 * 0.36, 240 * 0.42) = 100.8 snaps down to the 100 tier.
    expect(text.style?.fontSize, 100);
    // The digits must not sit under a FittedBox: scaleDown would resample
    // them at an arbitrary ratio whenever the tile is narrower than the
    // text, placing every glyph under a fractional scale transform.
    expect(
      find.ancestor(of: find.text('14:30'), matching: find.byType(FittedBox)),
      findsNothing,
    );
  });

  testWidgets('crossing a ladder threshold steps the size instead of scaling', (
    tester,
  ) async {
    // 277 wide: nominal min(99.72, 100.8) snaps down to the 96 tier.
    expect(
      (await _pumpHeadline(tester, const Size(277, 240))).style?.fontSize,
      96,
    );
    // 280 wide: nominal 100.8 snaps down to the 100 tier.
    expect(
      (await _pumpHeadline(tester, const Size(280, 240))).style?.fontSize,
      100,
    );
  });

  testWidgets('clamps keep the smallest and largest ladder tiers', (
    tester,
  ) async {
    // A tiny tile clamps up to 46; a huge one clamps down to 124.
    expect(
      (await _pumpHeadline(tester, const Size(120, 120))).style?.fontSize,
      46,
    );
    expect(
      (await _pumpHeadline(tester, const Size(500, 500))).style?.fontSize,
      124,
    );
  });
}
