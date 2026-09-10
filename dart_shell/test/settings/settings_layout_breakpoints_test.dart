import 'package:denial_dart_shell/l10n/generated/app_localizations.dart';
import 'package:denial_dart_shell/src/settings/settings_application.dart';
import 'package:denial_dart_shell/src/settings/widgets/settings_navigation.dart';
import 'package:denial_dart_shell/src/settings/widgets/settings_search_bar.dart';
import 'package:denial_dart_shell/src/theme/shell_color_scheme.dart';
import 'package:denial_dart_shell/src/theme/shell_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/settings_harness.dart';

void main() {
  testWidgets('840 and wider pins the navigation rail to 288', (tester) async {
    await pumpSettingsApp(tester, windowSize: const Size(840, 1800));

    expect(
      tester.getSize(find.byType(SettingsNavigation)).width,
      settingsSidebarWidth,
    );
    expect(find.byKey(settingsBackButtonKey), findsNothing);
    expect(find.byKey(settingsContentColumnKey), findsOneWidget);
  });

  testWidgets('the content column is centred and capped at 720', (
    tester,
  ) async {
    await pumpSettingsApp(tester, windowSize: const Size(1280, 1800));

    expect(
      tester.getSize(find.byKey(settingsContentColumnKey)).width,
      settingsContentMaxWidth,
    );
  });

  testWidgets('839 and narrower collapses to the single-column home', (
    tester,
  ) async {
    await pumpSettingsApp(tester, windowSize: const Size(839, 1800));

    final navigation = tester.getSize(find.byType(SettingsNavigation));
    expect(navigation.width, lessThanOrEqualTo(settingsContentMaxWidth));
    expect(navigation.width, greaterThan(settingsSidebarWidth));
    expect(find.byKey(settingsBackButtonKey), findsNothing);
    expect(find.byKey(settingsSearchBarKey), findsOneWidget);
  });

  testWidgets('the search capsule is an inert 56dp placeholder', (
    tester,
  ) async {
    await _withSemantics(tester, () async {
      await pumpSettingsApp(tester, windowSize: const Size(1280, 1800));

      final capsule = find.byKey(settingsSearchBarKey);
      expect(capsule, findsOneWidget);
      expect(tester.getSize(capsule).height, settingsSearchBarHeight);

      // S02 ships the appearance only: no handler, so no focus node, no tap
      // action, and no button semantics (card §3.2, constraint §D8).
      expect(
        find.descendant(
          of: capsule,
          matching: find.byType(FocusableActionDetector),
        ),
        findsNothing,
      );
      final node = tester.getSemantics(capsule).getSemanticsData();
      expect(node.hasAction(SemanticsAction.tap), isFalse);
      expect(node.label, 'Search settings');
    });
  });

  testWidgets('navigation cards use the verified 64dp card geometry', (
    tester,
  ) async {
    await _withSemantics(tester, () async {
      await pumpSettingsApp(
        tester,
        initialPage: SettingsPageId.about,
        windowSize: const Size(1280, 1800),
      );

      final about = _destination(SettingsPageId.about);
      expect(tester.getSize(about).height, settingsNavItemHeight);
      expect(tester.getSemantics(about), isSemantics(isSelected: true));

      final dot = find.descendant(
        of: about,
        matching: find.byType(SettingsNavIconDot),
      );
      expect(tester.getSize(dot), const Size(40, 40));
      expect(
        tester.getSize(find.descendant(of: dot, matching: find.byType(Icon))),
        const Size(20, 20),
      );

      final expectedAccent = const ShellThemeData().accentPalette.container;
      expect(
        _cardFills(tester, about).contains(expectedAccent),
        isTrue,
        reason: 'the selected card must be filled with the accent container',
      );
      expect(_indicatorOpacity(tester, about), 1.0);
    });
  });

  testWidgets('an unselected card keeps the surface fill and hides ▶', (
    tester,
  ) async {
    await pumpSettingsApp(
      tester,
      initialPage: SettingsPageId.about,
      windowSize: const Size(1280, 1800),
    );

    final power = _destination(SettingsPageId.power);
    final expectedAccent = const ShellThemeData().accentPalette.container;
    expect(_cardFills(tester, power).contains(expectedAccent), isFalse);
    expect(_indicatorOpacity(tester, power), 0.0);
  });

  testWidgets('destinations render in the four specified groups in order', (
    tester,
  ) async {
    await pumpSettingsApp(tester, windowSize: const Size(1280, 1800));

    final rendered = tester
        .widgetList<SettingsNavItem>(
          find.descendant(
            of: find.byKey(settingsNavigationListKey),
            matching: find.byType(SettingsNavItem),
          ),
        )
        .map((item) => item.page)
        .toList();
    expect(
      rendered,
      settingsNavigationGroups.values.expand((pages) => pages).toList(),
    );

    for (final heading in const <String>[
      'Connectivity & devices',
      'Personalization',
      'Input',
      'System',
    ]) {
      expect(find.text(heading), findsOneWidget);
    }
  });

  testWidgets('the touchpad condition hides its destination when disabled', (
    tester,
  ) async {
    final touchpad = find.descendant(
      of: find.byKey(settingsNavigationListKey),
      matching: find.byKey(
        const ValueKey<SettingsPageId>(SettingsPageId.touchpad),
      ),
    );

    await _pumpNavigation(tester, showTouchpad: false);
    expect(touchpad, findsNothing);

    await _pumpNavigation(tester, showTouchpad: true);
    expect(touchpad, findsOneWidget);
  });

  testWidgets('the navigation honours roundness and card opacity', (
    tester,
  ) async {
    await _pumpNavigation(
      tester,
      showTouchpad: true,
      theme: const ShellThemeData(
        colors: ShellColorScheme.light,
        cornerRadiusScale: 0,
        cardOpacity: 0.2,
      ),
    );

    final decorations = tester
        .widgetList<DecoratedBox>(
          find.descendant(
            of: _destination(SettingsPageId.power),
            matching: find.byType(DecoratedBox),
          ),
        )
        .map((box) => box.decoration)
        .whereType<BoxDecoration>()
        .where((decoration) => decoration.color != null)
        .toList();

    // cardOpacity drives every card fill (constraint §D4) …
    expect(
      decorations.any((decoration) => (decoration.color!.a - 0.2).abs() < 0.001),
      isTrue,
    );
    // … and cornerRadiusScale drives the card corners.
    expect(
      decorations.every(
        (decoration) => decoration.borderRadius == BorderRadius.zero,
      ),
      isTrue,
    );
  });

  testWidgets('an enabled search capsule is tappable and focusable', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      ShellTheme(
        data: const ShellThemeData(),
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: SettingsSearchBar(onTap: () => taps += 1),
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      find.descendant(
        of: find.byKey(settingsSearchBarKey),
        matching: find.byType(FocusableActionDetector),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(settingsSearchBarKey));
    expect(taps, 1);
  });
}

/// Fill colours applied by the card containers inside [item].
List<Color> _cardFills(WidgetTester tester, Finder item) {
  final colors = <Color>[];
  for (final box in tester.widgetList<DecoratedBox>(
    find.descendant(of: item, matching: find.byType(DecoratedBox)),
  )) {
    final decoration = box.decoration;
    if (decoration is BoxDecoration && decoration.color != null) {
      colors.add(decoration.color!);
    }
  }
  return colors;
}

double _indicatorOpacity(WidgetTester tester, Finder item) {
  return tester
      .widget<Opacity>(find.descendant(of: item, matching: find.byType(Opacity)))
      .opacity;
}

Finder _destination(SettingsPageId page) => find.descendant(
  of: find.byKey(settingsNavigationListKey),
  matching: find.byKey(ValueKey<SettingsPageId>(page)),
);

Future<void> _pumpNavigation(
  WidgetTester tester, {
  required bool showTouchpad,
  ShellThemeData theme = const ShellThemeData(),
}) async {
  tester.view.physicalSize = const Size(400, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ShellTheme(
      data: theme,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 1800,
            child: SettingsNavigation(
              selected: SettingsPageId.about,
              form: SettingsNavigationForm.home,
              showTouchpad: showTouchpad,
              onSelected: (_) {},
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _withSemantics(
  WidgetTester tester,
  Future<void> Function() body,
) async {
  final semantics = tester.ensureSemantics();
  try {
    await body();
  } finally {
    semantics.dispose();
  }
}
