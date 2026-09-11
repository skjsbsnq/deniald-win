import 'package:denial_dart_shell/l10n/generated/app_localizations.dart';
import 'package:denial_dart_shell/src/settings/widgets/settings_controls.dart';
import 'package:denial_dart_shell/src/theme/shell_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: Scaffold(
      body: ShellTheme(
        data: const ShellThemeData(),
        child: Center(
          child: SizedBox(
            width: 400,
            child: child,
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('SettingsRow geometry and heights', () {
    testWidgets('single line row has 56dp height and 16dp horizontal padding', (tester) async {
      await tester.pumpWidget(
        _wrap(
          SettingsRow.text(
            title: 'Single line title',
            onTap: () {},
          ),
        ),
      );

      final rowFinder = find.byType(SettingsRow);
      expect(rowFinder, findsOneWidget);
      final size = tester.getSize(rowFinder);
      expect(size.height, 56.0);

      // Verify horizontal padding of 16
      final paddingWidget = tester.widget<Padding>(
        find.descendant(
          of: rowFinder,
          matching: find.byWidgetPredicate(
            (w) => w is Padding && w.padding == const EdgeInsets.symmetric(horizontal: 16),
          ),
        ),
      );
      expect(paddingWidget.padding, const EdgeInsets.symmetric(horizontal: 16));
    });

    testWidgets('two line row (with subtitle) has 72dp height', (tester) async {
      await tester.pumpWidget(
        _wrap(
          SettingsRow.text(
            title: 'Two line title',
            subtitle: 'This is a supporting subtitle description',
            onTap: () {},
          ),
        ),
      );

      final rowFinder = find.byType(SettingsRow);
      expect(rowFinder, findsOneWidget);
      final size = tester.getSize(rowFinder);
      expect(size.height, 72.0);
    });

    testWidgets('slider row has 88dp height', (tester) async {
      double value = 0.5;
      await tester.pumpWidget(
        _wrap(
          SettingsRow.slider(
            title: 'Slider title',
            value: value,
            onChanged: (v) => value = v,
          ),
        ),
      );

      final rowFinder = find.byType(SettingsRow);
      expect(rowFinder, findsOneWidget);
      final size = tester.getSize(rowFinder);
      expect(size.height, 88.0);
    });
  });

  group('SettingsRow.toggle interactions', () {
    testWidgets('entire row tap triggers toggle callback', (tester) async {
      bool toggled = false;
      await tester.pumpWidget(
        _wrap(
          StatefulBuilder(
            builder: (context, setState) {
              return SettingsRow.toggle(
                title: 'Bluetooth toggle',
                subtitle: 'Manage wireless connections',
                value: toggled,
                onChanged: (val) => setState(() => toggled = val),
              );
            },
          ),
        ),
      );

      expect(toggled, isFalse);

      // Tap on the text label (left side of the row), not the switch directly
      await tester.tap(find.text('Bluetooth toggle'));
      await tester.pumpAndSettle();

      expect(toggled, isTrue);

      // Tap again to toggle off
      await tester.tap(find.text('Manage wireless connections'));
      await tester.pumpAndSettle();

      expect(toggled, isFalse);
    });

    testWidgets('keyboard space/enter triggers toggle', (tester) async {
      bool toggled = false;
      await tester.pumpWidget(
        _wrap(
          StatefulBuilder(
            builder: (context, setState) {
              return SettingsRow.toggle(
                title: 'Dark mode',
                value: toggled,
                onChanged: (val) => setState(() => toggled = val),
              );
            },
          ),
        ),
      );

      // Focus row via Tab
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();

      // Press Space
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(toggled, isTrue);

      // Press Enter
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(toggled, isFalse);
    });

    testWidgets('disabled toggle row does not fire callbacks', (tester) async {
      bool toggled = false;
      await tester.pumpWidget(
        _wrap(
          SettingsRow.toggle(
            title: 'Disabled option',
            value: false,
            enabled: false,
            onChanged: (val) => toggled = val,
          ),
        ),
      );

      await tester.tap(find.text('Disabled option'));
      await tester.pumpAndSettle();
      expect(toggled, isFalse);
    });
  });

  group('SettingsCardGroup dividers', () {
    testWidgets('indents dividers by 56dp when indentDividers is true', (tester) async {
      await tester.pumpWidget(
        _wrap(
          SettingsCardGroup(
            indentDividers: true,
            children: [
              SettingsRow.text(title: 'Row 1', onTap: () {}),
              SettingsRow.text(title: 'Row 2', onTap: () {}),
            ],
          ),
        ),
      );

      final divider = tester.widget<Divider>(find.byType(Divider));
      expect(divider.indent, 56.0);
    });
  });
}
