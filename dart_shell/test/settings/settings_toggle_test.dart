import 'package:denial_dart_shell/src/settings/widgets/settings_controls.dart';
import 'package:denial_dart_shell/src/theme/shell_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('tapping reports the negated value', (tester) async {
    bool? changed;
    await tester.pumpWidget(
      _wrap(
        SettingsToggle(
          label: 'Dark mode',
          description: 'Preview dark surfaces',
          value: false,
          onChanged: (value) => changed = value,
        ),
      ),
    );

    await tester.tap(find.byType(SettingsToggle));
    await tester.pump();

    expect(changed, isTrue);
  });

  testWidgets('an enabled toggle reports a flip back to false', (tester) async {
    bool? changed;
    await tester.pumpWidget(
      _wrap(
        SettingsToggle(
          label: 'Dark mode',
          description: 'Preview dark surfaces',
          value: true,
          onChanged: (value) => changed = value,
        ),
      ),
    );

    await tester.tap(find.byType(SettingsToggle));
    await tester.pump();

    expect(changed, isFalse);
  });

  testWidgets('semantics expose the toggled state', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        _wrap(
          SettingsToggle(
            label: 'Dark mode',
            description: 'Preview dark surfaces',
            value: true,
            onChanged: (_) {},
          ),
        ),
      );

      expect(
        tester.getSemantics(find.byType(SettingsToggle)),
        isSemantics(isToggled: true, isButton: true),
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('a disabled toggle ignores input', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      _wrap(
        SettingsToggle(
          label: 'Dark mode',
          description: 'Preview dark surfaces',
          value: false,
          enabled: false,
          onChanged: (_) => calls += 1,
        ),
      ),
    );

    await tester.tap(find.byType(SettingsToggle));
    await tester.pump();

    expect(calls, 0);
  });
}

Widget _wrap(Widget child) {
  return MaterialApp(
    locale: const Locale('en'),
    home: ShellTheme(
      data: const ShellThemeData(),
      child: Material(child: Center(child: SizedBox(width: 800, child: child))),
    ),
  );
}
