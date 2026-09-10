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

  testWidgets('every destination card is a single-line row', (tester) async {
    await pumpSettingsApp(tester);

    for (final page in SettingsPageId.values) {
      final item = _destination(page);
      expect(
        tester.getSize(item).height,
        settingsNavItemHeight,
        reason: '${page.name} card height is not the 64dp row',
      );
      final label = find.descendant(of: item, matching: find.byType(Text));
      expect(
        label,
        findsOneWidget,
        reason: '${page.name} must not carry a supporting line',
      );
      // Dropping the supporting line must not leave the icon or the label
      // pinned to the top edge: the row centres both in the 64dp card.
      final center = tester.getRect(item).center.dy;
      for (final part in <String, Finder>{
        'icon': find.descendant(
          of: item,
          matching: find.byType(SettingsNavIconDot),
        ),
        'label': label,
      }.entries) {
        expect(
          tester.getRect(part.value).center.dy,
          closeTo(center, 0.01),
          reason: '${page.name} ${part.key} is not vertically centred',
        );
      }
    }
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
