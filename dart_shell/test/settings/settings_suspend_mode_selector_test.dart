import 'package:denial_dart_shell/src/localization/denial_localizations.dart';
import 'package:denial_dart_shell/src/models/suspend_mode.dart';
import 'package:denial_dart_shell/src/settings/widgets/settings_buttons.dart';
import 'package:denial_dart_shell/src/settings/widgets/settings_suspend_mode_selector.dart';
import 'package:denial_dart_shell/src/theme/shell_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows a disabled select when Linux reports one mode', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        capabilities: SuspendModeCapabilities.parse('[s2idle]\n'),
        onChanged: (_) {},
      ),
    );

    final trigger = tester.widget<SettingsButton>(find.byType(SettingsButton));
    expect(trigger.onPressed, isNull);
    expect(find.text('Suspend to idle (s2idle)'), findsWidgets);
  });

  testWidgets('enables the select when Linux reports multiple modes', (
    tester,
  ) async {
    SuspendMode? changed;
    await tester.pumpWidget(
      _harness(
        capabilities: SuspendModeCapabilities.parse('s2idle [deep]\n'),
        onChanged: (value) => changed = value,
      ),
    );

    final trigger = tester.widget<SettingsButton>(find.byType(SettingsButton));
    expect(trigger.onPressed, isNotNull);

    await tester.tap(find.byType(SettingsButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Suspend to idle (s2idle)'));
    await tester.pumpAndSettle();

    expect(changed, SuspendMode.s2idle);
  });
}

Widget _harness({
  required SuspendModeCapabilities capabilities,
  required ValueChanged<SuspendMode> onChanged,
}) {
  return MaterialApp(
    home: DenialLocalizationScope(
      locale: const Locale('en'),
      child: ShellTheme(
        data: const ShellThemeData(),
        child: Material(
          child: SizedBox(
            width: 800,
            child: SettingsSuspendModeSelector(
              capabilities: capabilities,
              preferredMode: SuspendMode.systemDefault,
              onChanged: onChanged,
            ),
          ),
        ),
      ),
    ),
  );
}
