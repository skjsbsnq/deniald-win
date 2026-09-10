import 'package:denial_dart_shell/src/settings/settings_application.dart';
import 'package:denial_dart_shell/src/settings/shell_settings.dart';
import 'package:denial_dart_shell/src/settings/widgets/settings_animations_page.dart';
import 'package:denial_dart_shell/src/settings/widgets/settings_layout_page.dart';
import 'package:denial_dart_shell/src/settings/widgets/settings_navigation.dart';
import 'package:denial_dart_shell/src/settings/widgets/settings_search_bar.dart';
import 'package:denial_dart_shell/src/settings/widgets/settings_search_index.dart';
import 'package:denial_dart_shell/src/settings/widgets/settings_search_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/settings_harness.dart';

const _wide = Size(1280, 1800);
const _narrow = Size(839, 1800);

void main() {
  group('index', () {
    test('covers all eighteen destinations with bilingual keywords', () {
      final data = SettingsSearchIndexData.standard;
      expect(data.keywords.keys.toSet(), SettingsPageId.values.toSet());
      for (final page in SettingsPageId.values) {
        final keywords = data.keywordsFor(page);
        expect(
          keywords.length,
          greaterThanOrEqualTo(4),
          reason: '${page.name} needs at least four keywords',
        );
        expect(
          keywords.where(_hasCjk).length,
          greaterThanOrEqualTo(2),
          reason: '${page.name} needs at least two zh keywords',
        );
        expect(
          keywords.where((keyword) => !_hasCjk(keyword)).length,
          greaterThanOrEqualTo(2),
          reason: '${page.name} needs at least two en keywords',
        );
        expect(data.groupOf(page), isNotNull);
      }
    });

    test('keeps every destination in its navigation group', () {
      final data = SettingsSearchIndexData.standard;
      for (final entry in settingsNavigationGroups.entries) {
        for (final page in entry.value) {
          expect(data.groupOf(page), entry.key, reason: page.name);
        }
      }
    });

    test('an empty query returns no destinations', () {
      final data = SettingsSearchIndexData.standard;
      expect(search('', data, (page) => page.name), isEmpty);
      expect(search('   ', data, (page) => page.name), isEmpty);
    });

    test('ranks title prefix over title contains over keyword', () {
      final data = SettingsSearchIndexData(
        <SettingsPageId, List<String>>{
          SettingsPageId.network: <String>['alpha'],
        },
      );
      // bluetooth/appearance match by title prefix, audio by title contains,
      // network by keyword only. Prefix ties keep navigation order, so
      // bluetooth (connectivity) precedes appearance (personalization).
      expect(
        search('alpha', data, _rankingLabel),
        const <SettingsPageId>[
          SettingsPageId.bluetooth,
          SettingsPageId.appearance,
          SettingsPageId.audio,
          SettingsPageId.network,
        ],
      );
      expect(
        search('ALPHA', data, _rankingLabel),
        search('alpha', data, _rankingLabel),
      );
    });

    test('matches Chinese synonyms by substring', () {
      final data = SettingsSearchIndexData(
        <SettingsPageId, List<String>>{
          SettingsPageId.displays: <String>['显示器', '分辨率'],
        },
      );
      expect(
        search('显示', data, (page) => page.name),
        const <SettingsPageId>[SettingsPageId.displays],
      );
      expect(search('分辨率', data, (page) => page.name), const <SettingsPageId>[
        SettingsPageId.displays,
      ]);
    });

    test('groups results by best rank without reordering inside a group', () {
      final data = SettingsSearchIndexData(
        <SettingsPageId, List<String>>{
          SettingsPageId.network: <String>['alpha'],
        },
      );
      final grouped = groupSearchResults(
        search('alpha', data, _rankingLabel),
        data,
      );
      expect(
        grouped.map((section) => section.group).toList(),
        <SettingsNavGroup>[
          SettingsNavGroup.connectivity,
          SettingsNavGroup.personalization,
        ],
      );
      expect(
        grouped.first.pages,
        const <SettingsPageId>[
          SettingsPageId.bluetooth,
          SettingsPageId.audio,
          SettingsPageId.network,
        ],
      );
      expect(grouped.last.pages, const <SettingsPageId>[
        SettingsPageId.appearance,
      ]);
    });
  });

  group('wide layout', () {
    testWidgets('focusing the capsule opens results and Escape restores the list', (
      tester,
    ) async {
      await pumpSettingsApp(tester, windowSize: _wide);
      expect(find.byKey(settingsNavigationListKey), findsOneWidget);

      await _openSearch(tester);
      expect(find.byKey(settingsSearchResultsKey), findsOneWidget);
      expect(find.byKey(settingsNavigationListKey), findsNothing);
      expect(find.byKey(settingsSearchClearKey), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byKey(settingsSearchResultsKey), findsNothing);
      expect(find.byKey(settingsNavigationListKey), findsOneWidget);
      expect(find.byKey(settingsSearchClearKey), findsNothing);
    });

    testWidgets('typing filters results and shows the group heading', (
      tester,
    ) async {
      await pumpSettingsApp(tester, windowSize: _wide);
      await _openSearch(tester);
      await tester.enterText(_searchField(), 'anim');
      await tester.pumpAndSettle();

      expect(_result(SettingsPageId.animations), findsOneWidget);
      expect(_result(SettingsPageId.audio), findsNothing);
      expect(find.byKey(settingsSearchEmptyKey), findsNothing);
      // The group name appears once, as the section heading: the result card is
      // a single-line 64dp row and carries no supporting line (§3.4).
      expect(
        _sectionHeader('Personalization'),
        findsOneWidget,
        reason: 'results must be grouped under a section heading',
      );
      expect(
        find.descendant(
          of: _result(SettingsPageId.animations),
          matching: find.text('Personalization'),
        ),
        findsNothing,
      );
      expect(
        tester.getSize(_result(SettingsPageId.animations)).height,
        settingsNavItemHeight,
      );
    });

    testWidgets('no match shows the empty state', (tester) async {
      await pumpSettingsApp(tester, windowSize: _wide);
      await _openSearch(tester);
      await tester.enterText(_searchField(), 'zzzz');
      await tester.pumpAndSettle();

      expect(find.byKey(settingsSearchEmptyKey), findsOneWidget);
      expect(find.text('No matching settings'), findsOneWidget);
    });

    testWidgets('tapping a result opens the destination and closes the search', (
      tester,
    ) async {
      await pumpSettingsApp(tester, windowSize: _wide);
      await _openSearch(tester);
      await tester.enterText(_searchField(), 'anim');
      await tester.pumpAndSettle();

      await tester.tap(_result(SettingsPageId.animations));
      await tester.pumpAndSettle();

      expect(find.byType(SettingsAnimationsPage), findsOneWidget);
      expect(find.byKey(settingsSearchResultsKey), findsNothing);
      expect(find.byKey(settingsNavigationListKey), findsOneWidget);
    });

    testWidgets('arrow keys move the highlight and Enter opens it', (
      tester,
    ) async {
      await _withSemantics(tester, () async {
        await pumpSettingsApp(tester, windowSize: _wide);
        await _openSearch(tester);
        await tester.enterText(_searchField(), 'layout');
        await tester.pumpAndSettle();

        // "layout" ranks the layout page (title contains) before keyboard
        // (keyword only).
        expect(_result(SettingsPageId.layout), findsOneWidget);
        expect(_result(SettingsPageId.keyboard), findsOneWidget);
        expect(
          tester.getSemantics(_result(SettingsPageId.layout)),
          isSemantics(isSelected: true),
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        expect(
          tester.getSemantics(_result(SettingsPageId.keyboard)),
          isSemantics(isSelected: true),
        );
        expect(
          tester.getSemantics(_result(SettingsPageId.layout)),
          isSemantics(isSelected: false),
        );

        // Already on the last result: the highlight stays put.
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        expect(
          tester.getSemantics(_result(SettingsPageId.keyboard)),
          isSemantics(isSelected: true),
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pump();
        expect(
          tester.getSemantics(_result(SettingsPageId.layout)),
          isSemantics(isSelected: true),
        );

        // Enter opens the highlighted result, not merely the first one.
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();

        expect(find.byType(SettingsLayoutPage), findsOneWidget);
        expect(find.byKey(settingsSearchResultsKey), findsNothing);
      });
    });

    testWidgets('the clear button empties the query and keeps the search open', (
      tester,
    ) async {
      await pumpSettingsApp(tester, windowSize: _wide);
      await _openSearch(tester);
      await tester.enterText(_searchField(), 'keyboard');
      await tester.pumpAndSettle();
      expect(_result(SettingsPageId.keyboard), findsOneWidget);

      await tester.tap(find.byKey(settingsSearchClearKey));
      await tester.pumpAndSettle();

      expect(tester.widget<TextField>(_searchField()).controller!.text, isEmpty);
      expect(find.byKey(settingsSearchResultsKey), findsOneWidget);
      expect(find.byKey(settingsSearchEmptyKey), findsOneWidget);
    });

    testWidgets('the capsule and clear affordance are announced for a11y', (
      tester,
    ) async {
      await _withSemantics(tester, () async {
        await pumpSettingsApp(tester, windowSize: _wide);
        expect(
          tester.getSemantics(_searchField()),
          isSemantics(isTextField: true, label: 'Search settings'),
        );

        await _openSearch(tester);
        final clearData = tester
            .getSemantics(find.byKey(settingsSearchClearKey))
            .getSemanticsData();
        expect(clearData.label, 'Clear search');
        expect(clearData.hasAction(SemanticsAction.tap), isTrue);

        // Keyboard reachable: Enter/Space activate the clear action.
        final detector = tester.widget<FocusableActionDetector>(
          find.byKey(settingsSearchClearKey),
        );
        expect(
          detector.shortcuts?[const SingleActivator(LogicalKeyboardKey.enter)],
          isA<ActivateIntent>(),
        );
        expect(detector.actions?[ActivateIntent], isNotNull);
      });
    });

    testWidgets('results announce the destination, its group, and the highlight', (
      tester,
    ) async {
      await _withSemantics(tester, () async {
        await pumpSettingsApp(tester, windowSize: _wide);
        await _openSearch(tester);
        await tester.enterText(_searchField(), 'layout');
        await tester.pumpAndSettle();

        final label = tester
            .getSemantics(_result(SettingsPageId.layout))
            .getSemanticsData()
            .label;
        expect(label, contains('Desktop layout'));
        expect(
          label,
          contains('Personalization'),
          reason: 'a result must announce its destination and its group (§3.3)',
        );
        // The group is announced through the label alone: the card keeps the
        // single-line 64dp row and paints no supporting line (§3.4).
        expect(
          find.descendant(
            of: _result(SettingsPageId.layout),
            matching: find.text('Personalization'),
          ),
          findsNothing,
        );
        expect(
          tester.getSize(_result(SettingsPageId.layout)).height,
          settingsNavItemHeight,
        );
        expect(
          tester.getSemantics(_result(SettingsPageId.layout)),
          isSemantics(isSelected: true),
        );
        expect(
          tester.getSemantics(_result(SettingsPageId.keyboard)),
          isSemantics(isSelected: false),
        );
      });
    });

    testWidgets('search still opens pages whose items are conditionally hidden', (
      tester,
    ) async {
      await pumpSettingsApp(
        tester,
        windowSize: _wide,
        initialSettings: const ShellSettings(
          layout: ShellLayoutSettings(useChromeOsShelf: true),
        ),
      );
      await _openSearch(tester);
      await tester.enterText(_searchField(), 'layout');
      await tester.pumpAndSettle();

      expect(_result(SettingsPageId.layout), findsOneWidget);
      await tester.tap(_result(SettingsPageId.layout));
      await tester.pumpAndSettle();

      // The index is static: the shelf-scoped visibility is decided by the
      // page itself (S05), never by the search.
      expect(find.byType(SettingsLayoutPage), findsOneWidget);
    });
  });

  group('narrow layout', () {
    testWidgets('the capsule opens an overlay and a result drills into detail', (
      tester,
    ) async {
      await pumpSettingsApp(tester, initialPage: SettingsPageId.about, windowSize: _narrow);
      expect(find.byKey(settingsNavigationListKey), findsOneWidget);

      await _openSearch(tester);
      expect(find.byKey(settingsSearchResultsKey), findsOneWidget);
      expect(find.byKey(settingsNavigationListKey), findsNothing);

      await tester.enterText(_searchField(), 'anim');
      await tester.pumpAndSettle();
      await tester.tap(_result(SettingsPageId.animations));
      await tester.pumpAndSettle();

      expect(find.byType(SettingsAnimationsPage), findsOneWidget);
      expect(find.byKey(settingsBackButtonKey), findsOneWidget);
      expect(find.byKey(settingsSearchResultsKey), findsNothing);
      expect(find.byType(SettingsNavigation), findsNothing);
    });

    testWidgets('Escape closes the search overlay before any detail exists', (
      tester,
    ) async {
      await pumpSettingsApp(tester, initialPage: SettingsPageId.about, windowSize: _narrow);
      await _openSearch(tester);
      await tester.enterText(_searchField(), 'keyboard');
      await tester.pumpAndSettle();
      expect(find.byKey(settingsSearchResultsKey), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byKey(settingsSearchResultsKey), findsNothing);
      expect(find.byKey(settingsNavigationListKey), findsOneWidget);
      expect(find.byKey(settingsBackButtonKey), findsNothing);
    });

    testWidgets('Escape then exits the detail opened from a result', (
      tester,
    ) async {
      await pumpSettingsApp(tester, initialPage: SettingsPageId.about, windowSize: _narrow);
      await _openSearch(tester);
      await tester.enterText(_searchField(), 'anim');
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byKey(settingsBackButtonKey), findsOneWidget);
      expect(find.byType(SettingsAnimationsPage), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byKey(settingsBackButtonKey), findsNothing);
      expect(find.byType(SettingsNavigation), findsOneWidget);
      expect(find.byKey(settingsSearchResultsKey), findsNothing);
    });
  });
}

String _rankingLabel(SettingsPageId page) => switch (page) {
  SettingsPageId.bluetooth => 'Alpha beta',
  SettingsPageId.appearance => 'Alpha',
  SettingsPageId.audio => 'Beta alpha',
  _ => page.name,
};

bool _hasCjk(String value) => RegExp(r'[\u4e00-\u9fff]').hasMatch(value);

Finder _searchField() => find.descendant(
  of: find.byKey(settingsSearchBarKey),
  matching: find.byType(TextField),
);

Finder _result(SettingsPageId page) => find.descendant(
  of: find.byKey(settingsSearchResultsKey),
  matching: find.byKey(ValueKey<SettingsPageId>(page)),
);

/// Finds the section heading carrying [label].
Finder _sectionHeader(String label) => find.ancestor(
  of: find.descendant(
    of: find.byKey(settingsSearchResultsKey),
    matching: find.text(label),
  ),
  matching: find.byWidgetPredicate(
    (widget) => widget is Semantics && widget.properties.header == true,
  ),
);

Future<void> _openSearch(WidgetTester tester) async {
  await tester.tap(find.byKey(settingsSearchBarKey));
  await tester.pumpAndSettle();
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
