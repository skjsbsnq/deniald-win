import 'package:denial_dart_shell/src/settings/widgets/settings_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/settings_harness.dart';

void main() {
  testWidgets('renders every destination and migrates selection on tap', (
    tester,
  ) async {
    await _withSemantics(tester, () async {
      await pumpSettingsApp(tester);

      for (final page in SettingsPageId.values) {
        expect(
          _destination(page),
          findsOneWidget,
          reason: '${page.name} destination is missing',
        );
      }
      expect(find.byKey(settingsNavigationListKey), findsOneWidget);
      expect(
        tester.getSemantics(_destination(SettingsPageId.about)),
        isSemantics(isSelected: true),
      );

      await tester.tap(_destination(SettingsPageId.power));
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(_destination(SettingsPageId.power)),
        isSemantics(isSelected: true),
      );
      expect(
        tester.getSemantics(_destination(SettingsPageId.about)),
        isSemantics(isSelected: false),
      );
    });
  });

  testWidgets('every destination card is a two-line row', (tester) async {
    await pumpSettingsApp(tester);
    final context = tester.element(
      find.byKey(settingsNavigationListKey),
    );

    for (final page in SettingsPageId.values) {
      final item = _destination(page);
      expect(
        tester.getSize(item).height,
        settingsNavItemHeight,
        reason: '${page.name} card height is not the 72dp row',
      );
      // Two painted lines: the destination label plus its supporting
      // summary (§4 reference layout).
      final label = find.descendant(of: item, matching: find.byType(Text));
      expect(
        label,
        findsNWidgets(2),
        reason: '${page.name} must paint the title and supporting line',
      );
      expect(
        find.descendant(
          of: item,
          matching: find.text(page.supportLabel(context)),
        ),
        findsOneWidget,
        reason: '${page.name} supporting line is missing or not localized',
      );
      // The icon and the two-line text block stay vertically centred in the
      // 72dp card: the icon dot centres on the card, and the two lines
      // straddle the centre (title above, support below).
      final center = tester.getRect(item).center.dy;
      final icon = find.descendant(
        of: item,
        matching: find.byType(SettingsNavIconDot),
      );
      expect(
        tester.getRect(icon).center.dy,
        closeTo(center, 0.01),
        reason: '${page.name} icon is not vertically centred',
      );
      final title = find.descendant(
        of: item,
        matching: find.text(page.label(context)),
      );
      final support = find.descendant(
        of: item,
        matching: find.text(page.supportLabel(context)),
      );
      expect(
        tester.getRect(title).center.dy,
        lessThan(center),
        reason: '${page.name} title is not above the card centre',
      );
      expect(
        tester.getRect(support).center.dy,
        greaterThan(center),
        reason: '${page.name} support line is not below the card centre',
      );
    }
  });

  testWidgets('the accessibility label announces title and support', (
    tester,
  ) async {
    await _withSemantics(tester, () async {
      await pumpSettingsApp(tester);
      final context = tester.element(
        find.byKey(settingsNavigationListKey),
      );

      for (final page in SettingsPageId.values) {
        final semantics = tester.getSemantics(_destination(page));
        expect(
          semantics.label,
          contains(page.label(context)),
          reason: '${page.name} label is missing the title',
        );
        expect(
          semantics.label,
          contains(page.supportLabel(context)),
          reason: '${page.name} label is missing the supporting line',
        );
      }
    });
  });

  testWidgets('Tab focuses a destination and Enter activates it', (
    tester,
  ) async {
    await _withSemantics(tester, () async {
      await pumpSettingsApp(tester);

      SettingsPageId? focused;
      for (var attempt = 0; attempt < 60 && focused != SettingsPageId.power; attempt += 1) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        focused = _focusedDestination();
      }
      expect(
        focused,
        SettingsPageId.power,
        reason: 'Tab never reached the power destination',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        tester.getSemantics(_destination(SettingsPageId.power)),
        isSemantics(isSelected: true),
      );
    });
  });
}

/// Enables semantics for the duration of [body].
///
/// [WidgetTester.ensureSemantics] handles are verified at the end of the test
/// body, before `addTearDown` callbacks run, so they must be disposed here.
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

/// Finds one navigation destination inside the navigation list.
///
/// The page body reuses the same [ValueKey] on its `AnimatedSwitcher` child,
/// so an unscoped `find.byKey` would match two elements.
Finder _destination(SettingsPageId page) => find.descendant(
  of: find.byKey(settingsNavigationListKey),
  matching: find.byKey(ValueKey<SettingsPageId>(page)),
);

SettingsPageId? _focusedDestination() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) {
    return null;
  }
  SettingsPageId? page;
  var withinNavigation = false;
  context.visitAncestorElements((element) {
    final key = element.widget.key;
    if (key is ValueKey<SettingsPageId> && page == null) {
      page = key.value;
    } else if (key == settingsNavigationListKey) {
      withinNavigation = true;
    }
    return true;
  });
  return withinNavigation ? page : null;
}
