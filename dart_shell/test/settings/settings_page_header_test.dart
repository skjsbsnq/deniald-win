import 'package:denial_dart_shell/l10n/generated/app_localizations.dart';
import 'package:denial_dart_shell/src/settings/settings_category_colors.dart';
import 'package:denial_dart_shell/src/settings/widgets/settings_controls.dart';
import 'package:denial_dart_shell/src/settings/widgets/settings_navigation.dart';
import 'package:denial_dart_shell/src/settings/widgets/settings_page_header.dart';
import 'package:denial_dart_shell/src/theme/shell_theme.dart';
import 'package:denial_dart_shell/src/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the header expands to 120 and pins at 64 when scrolled', (
    tester,
  ) async {
    await _pumpLayout(tester);
    final header = find.byType(SettingsPageHeader);

    expect(
      tester.getSize(header).height,
      settingsPageHeaderExpandedHeight,
    );

    await _scrollTo(tester, 200);

    expect(
      tester.getSize(header).height,
      settingsPageHeaderCollapsedHeight,
    );
  });

  testWidgets('the title cross-fades between the 28 and 22 roles', (
    tester,
  ) async {
    await _pumpLayout(tester);

    final styles = tester
        .widgetList<Text>(find.text('Appearance'))
        .map((text) => text.style)
        .toList();
    expect(
      styles.any(
        (style) =>
            style?.fontSize == 28 && style?.fontWeight == FontWeight.w500,
      ),
      isTrue,
      reason: 'the expanded title is 28/36 w500 (§6)',
    );
    expect(
      styles.any(
        (style) =>
            style?.fontSize == 22 && style?.fontWeight == FontWeight.w500,
      ),
      isTrue,
      reason: 'the collapsed title is 22/28 w500 (§6)',
    );
  });

  testWidgets('the cross-fade interpolates while scrolling', (tester) async {
    await _pumpLayout(tester);
    expect(_titleOpacities(tester).toSet(), <double>{1.0, 0.0});

    await _scrollTo(tester, 20);

    final opacities = _titleOpacities(tester);
    expect(opacities.every((value) => value > 0 && value < 1), isTrue);
  });

  testWidgets('reduced motion snaps the title instead of interpolating', (
    tester,
  ) async {
    await _pumpLayout(tester, disableAnimations: true);
    await _scrollTo(tester, 20);

    expect(_titleOpacities(tester).toSet(), <double>{1.0, 0.0});
  });

  testWidgets('the header shows a 32dp category hue circle with an 18dp glyph', (
    tester,
  ) async {
    await _pumpLayout(tester);
    final context = tester.element(find.byType(SettingsPageHeader));
    final icon = find.descendant(
      of: find.byType(SettingsPageHeader),
      matching: find.byIcon(Icons.palette_outlined),
    );
    expect(tester.getSize(icon), const Size(18, 18));

    final circle = find
        .ancestor(of: icon, matching: find.byType(DecoratedBox))
        .first;
    expect(
      tester.getSize(circle),
      const Size(
        settingsPageHeaderIconDiameter,
        settingsPageHeaderIconDiameter,
      ),
    );
    final decoration =
        tester.widget<DecoratedBox>(circle).decoration as BoxDecoration;
    expect(
      decoration.color,
      SettingsCategoryColors.containerOf(context, SettingsPageId.appearance),
    );
  });

  testWidgets('group containers use the 28 radius, no border, hairline rows', (
    tester,
  ) async {
    await _pumpLayout(tester);
    final group = find.byType(SettingsCardGroup);
    final decoration =
        tester
                .widget<DecoratedBox>(
                  find
                      .descendant(of: group, matching: find.byType(DecoratedBox))
                      .first,
                )
                .decoration
            as BoxDecoration;
    expect(
      decoration.borderRadius,
      const ShellThemeData().borderRadius(ShellShapeScale.extraLarge),
    );
    expect(decoration.border, isNull);

    final divider = tester.widget<Divider>(
      find.descendant(of: group, matching: find.byType(Divider)).first,
    );
    expect(divider.color, const ShellThemeData().colors.hairlineSoft);
  });

  testWidgets('section titles use the restrained section header role', (
    tester,
  ) async {
    await _pumpLayout(tester);

    final style = tester.widget<Text>(find.text('Section One')).style;
    expect(style?.fontSize, 14);
    expect(style?.fontWeight, FontWeight.w500);
  });

  testWidgets('the live-changes badge is a 24dp capsule in the badge role', (
    tester,
  ) async {
    await _pumpLayout(tester);
    final badge = find.byType(SettingsSavedBadge);

    expect(tester.getSize(badge).height, SettingsSavedBadge.height);

    final decoration =
        tester
                .widget<DecoratedBox>(
                  find
                      .descendant(
                        of: badge,
                        matching: find.byType(DecoratedBox),
                      )
                      .first,
                )
                .decoration
            as BoxDecoration;
    expect(
      decoration.color,
      const ShellThemeData().colors.surfaceContainerHigh,
    );

    final label = tester.widget<Text>(
      find.descendant(of: badge, matching: find.byType(Text)),
    );
    expect(label.style?.fontSize, 11);
    expect(label.style?.fontWeight, FontWeight.w500);
  });
  testWidgets('a page without reset renders no badge or trailing action', (
    tester,
  ) async {
    await _pumpLayout(tester, onReset: null);

    expect(find.byType(SettingsSavedBadge), findsNothing);
    expect(find.text('Reset page'), findsNothing);
  });
}

/// The opacity values of the expanded/collapsed title cross-fade.
List<double> _titleOpacities(WidgetTester tester) => tester
    .widgetList<Opacity>(
      find.descendant(
        of: find.byType(SettingsPageHeader),
        matching: find.byType(Opacity),
      ),
    )
    .map((opacity) => opacity.opacity)
    .toList();

Future<void> _scrollTo(WidgetTester tester, double offset) async {
  tester.state<ScrollableState>(find.byType(Scrollable).first).position.jumpTo(
    offset,
  );
  await tester.pump();
}

Future<void> _pumpLayout(
  WidgetTester tester, {
  double width = 720,
  bool disableAnimations = false,
  VoidCallback? onReset = _noop,
}) async {
  await tester.pumpWidget(
    ShellTheme(
      data: const ShellThemeData(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: disableAnimations),
          child: Scaffold(
            body: SizedBox(
              width: width,
              height: 600,
              child: SettingsPageLayout(
                icon: Icons.palette_outlined,
                eyebrow: 'Appearance',
                title: 'Appearance',
                onReset: onReset,
                children: <Widget>[
                  SettingsCardGroup(
                    children: <Widget>[
                      const SettingsSection(
                        title: 'Section One',
                        child: SizedBox(height: 40),
                      ),
                      const SettingsSection(
                        title: 'Section Two',
                        child: SizedBox(height: 40),
                      ),
                    ],
                  ),
                  const SizedBox(height: 1200),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void _noop() {}
