import 'package:denial_dart_shell/src/settings/settings_application.dart';
import 'package:denial_dart_shell/src/settings/widgets/settings_navigation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/settings_harness.dart';

void main() {
  testWidgets('the initial page follows initialPage', (tester) async {
    await _withSemantics(tester, () async {
      await pumpSettingsApp(tester, initialPage: SettingsPageId.language);

      expect(
        tester.getSemantics(_destination(SettingsPageId.language)),
        isSemantics(isSelected: true),
      );
    });
  });

  testWidgets('a page-open request switches pages and is consumed', (
    tester,
  ) async {
    await _withSemantics(tester, () async {
      final container = await pumpSettingsApp(
        tester,
        initialPage: SettingsPageId.about,
      );
      expect(
        tester.getSemantics(_destination(SettingsPageId.about)),
        isSemantics(isSelected: true),
      );

      container
          .read(settingsPageOpenRequestProvider.notifier)
          .request(SettingsPageId.language);
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(_destination(SettingsPageId.language)),
        isSemantics(isSelected: true),
      );
      expect(container.read(settingsPageOpenRequestProvider), isNull);
    });
  });
}

/// See `settings_navigation_test.dart`: semantics handles are verified before
/// `addTearDown` runs, so they are disposed inside the test body.
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

/// See `settings_navigation_test.dart`: the page body reuses the page key, so
/// destination lookups must be scoped to the navigation list.
Finder _destination(SettingsPageId page) => find.descendant(
  of: find.byKey(settingsNavigationListKey),
  matching: find.byKey(ValueKey<SettingsPageId>(page)),
);
