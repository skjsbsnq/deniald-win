import 'package:denial_dart_shell/src/settings/widgets/settings_buttons.dart';
import 'package:denial_dart_shell/src/settings/widgets/settings_controls.dart';
import 'package:denial_dart_shell/src/theme/shell_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('SettingsSelect reports the chosen value', (tester) async {
    String? changed;
    await tester.pumpWidget(
      _wrap(
        SettingsSelect<String>(
          label: 'Window layout',
          description: 'How windows are arranged',
          value: 'auto',
          choices: const <SettingsChoice<String>>[
            SettingsChoice<String>('auto', 'Automatic'),
            SettingsChoice<String>('float', 'Floating'),
          ],
          onChanged: (value) => changed = value,
        ),
      ),
    );

    await tester.tap(find.byType(SettingsButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Floating').last);
    await tester.pumpAndSettle();

    expect(changed, 'float');
  });

  testWidgets('SettingsSegmentedControl reports the chosen value', (
    tester,
  ) async {
    String? changed;
    await tester.pumpWidget(
      _wrap(
        SettingsSegmentedControl<String>(
          value: 'a',
          choices: const <SettingsChoice<String>>[
            SettingsChoice<String>('a', 'Alpha'),
            SettingsChoice<String>('b', 'Beta'),
          ],
          onChanged: (value) => changed = value,
        ),
      ),
    );

    await tester.tap(find.text('Beta'));
    await tester.pump();

    expect(changed, 'b');
  });

  testWidgets('SettingsSlider reports drag updates', (tester) async {
    double? changed;
    await tester.pumpWidget(
      _wrap(
        SettingsSlider(
          label: 'Cursor size',
          value: 0.5,
          minimum: 0,
          maximum: 1,
          onChanged: (value) => changed = value,
        ),
      ),
    );

    await tester.drag(find.byType(Slider), const Offset(150, 0));
    await tester.pump();

    expect(changed, isNotNull);
    expect(changed, greaterThan(0.5));
  });

  testWidgets('a disabled SettingsSlider ignores drags', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      _wrap(
        SettingsSlider(
          label: 'Cursor size',
          value: 0.5,
          minimum: 0,
          maximum: 1,
          enabled: false,
          onChanged: (_) => calls += 1,
        ),
      ),
    );

    await tester.drag(find.byType(Slider), const Offset(150, 0));
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
