import 'package:denial_dart_shell/src/settings/widgets/settings_buttons.dart';
import 'package:denial_dart_shell/src/settings/widgets/settings_menu.dart';
import 'package:denial_dart_shell/src/theme/shell_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _items = <SettingsMenuItem<String>>[
  SettingsMenuItem<String>('a', 'Automatic'),
  SettingsMenuItem<String>('b', 'Floating'),
];

void main() {
  testWidgets('tapping the trigger opens the menu and reports a selection', (
    tester,
  ) async {
    String? changed;
    await tester.pumpWidget(
      _wrap(
        SettingsMenu<String>(
          semanticsLabel: 'Layout',
          value: 'a',
          items: _items,
          onChanged: (value) => changed = value,
        ),
      ),
    );

    expect(find.text('Floating'), findsNothing);
    await tester.tap(find.byType(SettingsButton));
    await tester.pumpAndSettle();
    expect(find.text('Floating'), findsOneWidget);

    await tester.tap(find.text('Floating'));
    await tester.pumpAndSettle();
    expect(changed, 'b');
    expect(find.text('Floating'), findsNothing);
  });

  testWidgets('the trigger exposes the current value as semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        _wrap(
          SettingsMenu<String>(
            semanticsLabel: 'Layout',
            value: 'a',
            items: _items,
            onChanged: (_) {},
          ),
        ),
      );

      final node = tester.getSemantics(
        find.bySemanticsLabel(RegExp('Layout')),
      );
      expect(node.label, contains('Layout'));
      expect(node.value, 'Automatic');
      expect(node.hasFlag(SemanticsFlag.isButton), isTrue);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('keyboard opens, moves the highlight and selects', (
    tester,
  ) async {
    String? changed;
    await tester.pumpWidget(
      _wrap(
        SettingsMenu<String>(
          semanticsLabel: 'Layout',
          value: 'a',
          items: _items,
          onChanged: (value) => changed = value,
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(find.text('Floating'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(changed, 'b');
  });

  testWidgets('escape closes the menu and returns focus to the trigger', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        SettingsMenu<String>(
          semanticsLabel: 'Layout',
          value: 'a',
          items: _items,
          onChanged: (_) {},
        ),
      ),
    );

    await tester.tap(find.byType(SettingsButton));
    await tester.pumpAndSettle();
    expect(find.text('Floating'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Floating'), findsNothing);

    // Focus was returned to the trigger, so Enter reopens the menu.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Floating'), findsOneWidget);
  });
}

Widget _wrap(Widget child) {
  return MaterialApp(
    locale: const Locale('en'),
    home: ShellTheme(
      data: const ShellThemeData(),
      child: Material(
        child: Center(child: SizedBox(width: 260, child: child)),
      ),
    ),
  );
}
