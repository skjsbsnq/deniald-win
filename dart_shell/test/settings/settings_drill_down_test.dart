import 'package:denial_dart_shell/src/settings/settings_application.dart';
import 'package:denial_dart_shell/src/settings/widgets/settings_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/settings_harness.dart';

const _narrow = Size(839, 1800);
const _wide = Size(840, 1800);

void main() {
  testWidgets('tapping a destination drills in and back returns home', (
    tester,
  ) async {
    await pumpSettingsApp(
      tester,
      initialPage: SettingsPageId.about,
      windowSize: _narrow,
    );
    expect(find.byKey(settingsBackButtonKey), findsNothing);

    await tester.tap(_destination(SettingsPageId.power));
    await tester.pumpAndSettle();

    expect(find.byKey(settingsBackButtonKey), findsOneWidget);
    expect(find.byType(SettingsNavigation), findsNothing);

    await tester.tap(find.byKey(settingsBackButtonKey));
    await tester.pumpAndSettle();

    expect(find.byKey(settingsBackButtonKey), findsNothing);
    expect(find.byType(SettingsNavigation), findsOneWidget);
  });

  testWidgets('Escape returns to the home list', (tester) async {
    await pumpSettingsApp(
      tester,
      initialPage: SettingsPageId.about,
      windowSize: _narrow,
    );
    await tester.tap(_destination(SettingsPageId.power));
    await tester.pumpAndSettle();
    expect(find.byKey(settingsBackButtonKey), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byKey(settingsBackButtonKey), findsNothing);
    expect(find.byType(SettingsNavigation), findsOneWidget);
  });

  testWidgets('the back button exposes the Back semantics label', (
    tester,
  ) async {
    await _withSemantics(tester, () async {
      await pumpSettingsApp(
        tester,
        initialPage: SettingsPageId.about,
        windowSize: _narrow,
      );
      await tester.tap(_destination(SettingsPageId.power));
      await tester.pumpAndSettle();

      final node = tester
          .getSemantics(find.byKey(settingsBackButtonKey))
          .getSemanticsData();
      expect(node.hasAction(SemanticsAction.tap), isTrue);
      expect(node.label, 'Back');
    });
  });

  testWidgets('widening keeps the page and narrowing keeps the detail', (
    tester,
  ) async {
    await _withSemantics(tester, () async {
      await pumpSettingsApp(
        tester,
        initialPage: SettingsPageId.about,
        windowSize: _narrow,
      );
      await tester.tap(_destination(SettingsPageId.power));
      await tester.pumpAndSettle();
      expect(find.byKey(settingsBackButtonKey), findsOneWidget);

      tester.view.physicalSize = _wide;
      await tester.pumpAndSettle();

      expect(find.byType(SettingsNavigation), findsOneWidget);
      expect(
        tester.getSize(find.byType(SettingsNavigation)).width,
        settingsSidebarWidth,
      );
      expect(find.byKey(settingsBackButtonKey), findsNothing);
      expect(
        tester.getSemantics(_destination(SettingsPageId.power)),
        isSemantics(isSelected: true),
      );

      tester.view.physicalSize = _narrow;
      await tester.pumpAndSettle();

      expect(find.byKey(settingsBackButtonKey), findsOneWidget);
      expect(find.byType(SettingsNavigation), findsNothing);
    });
  });

  testWidgets('a page-open request opens the destination in the detail', (
    tester,
  ) async {
    final container = await pumpSettingsApp(
      tester,
      initialPage: SettingsPageId.about,
      windowSize: _narrow,
    );
    expect(find.byKey(settingsBackButtonKey), findsNothing);

    container
        .read(settingsPageOpenRequestProvider.notifier)
        .request(SettingsPageId.language);
    await tester.pumpAndSettle();

    expect(find.byKey(settingsBackButtonKey), findsOneWidget);
    expect(container.read(settingsPageOpenRequestProvider), isNull);
  });
}

Finder _destination(SettingsPageId page) => find.descendant(
  of: find.byKey(settingsNavigationListKey),
  matching: find.byKey(ValueKey<SettingsPageId>(page)),
);

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
