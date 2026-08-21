import 'dart:ui' show Tristate;

import 'package:dbus/dbus.dart';
import 'package:denial_dart_shell/src/desktop/desktop_input_method.dart';
import 'package:denial_dart_shell/src/localization/denial_localizations.dart';
import 'package:denial_dart_shell/src/services/fcitx5_service.dart';
import 'package:denial_dart_shell/src/state/fcitx5.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('snapshot maps English and Chinese input methods to short labels', () {
    expect(
      const Fcitx5Snapshot(
        available: true,
        inputMethod: 'keyboard-us',
        label: 'Keyboard - English (US)',
        languageCode: 'en',
      ).shortLabel,
      'EN',
    );
    expect(
      const Fcitx5Snapshot(
        available: true,
        inputMethod: 'pinyin',
        label: 'Pinyin',
        languageCode: 'zh_CN',
      ).shortLabel,
      '\u4e2d',
    );
  });

  test('Fcitx5 info parser reads top-level D-Bus return values', () {
    final snapshot = buildFcitx5Snapshot('pinyin', const <DBusValue>[
      DBusString('pinyin'),
      DBusString('Pinyin'),
      DBusString(''),
      DBusString('fcitx-pinyin'),
      DBusString('zh_CN'),
      DBusString('zh_CN'),
    ]);

    expect(snapshot.label, 'Pinyin');
    expect(snapshot.languageCode, 'zh_CN');
    expect(snapshot.shortLabel, '\u4e2d');
  });

  testWidgets('unavailable input method disables both options', (tester) async {
    await _pumpInputMethod(tester, const Fcitx5Snapshot.unavailable());

    expect(find.text('--'), findsOneWidget);
    final semantics = tester.getSemantics(find.text('EN'));
    expect(semantics.flagsCollection.isEnabled, Tristate.isFalse);
  });

  testWidgets('English state is selected and can switch to Chinese', (
    tester,
  ) async {
    final controller = _TestFcitx5Controller(
      const Fcitx5Snapshot(
        available: true,
        inputMethod: 'keyboard-us',
        label: 'Keyboard - English (US)',
        languageCode: 'en',
      ),
    );
    await _pumpInputMethod(tester, controller.initial, controller: controller);

    expect(find.text('EN'), findsNWidgets(2));
    await tester.tap(find.text('\u4e2d').last);
    await tester.pump();

    expect(controller.requestedChinese, isTrue);
    expect(find.text('\u4e2d'), findsNWidgets(2));
  });
}

class _TestFcitx5Controller extends Fcitx5Controller {
  _TestFcitx5Controller(this.initial);

  final Fcitx5Snapshot initial;
  bool? requestedChinese;

  @override
  Fcitx5Snapshot build() => initial;

  @override
  Future<void> setChinese(bool chinese) async {
    requestedChinese = chinese;
    state = Fcitx5Snapshot(
      available: true,
      inputMethod: chinese ? 'pinyin' : 'keyboard-us',
      label: chinese ? 'Pinyin' : 'Keyboard - English (US)',
      languageCode: chinese ? 'zh_CN' : 'en',
    );
  }
}

Future<void> _pumpInputMethod(
  WidgetTester tester,
  Fcitx5Snapshot snapshot, {
  _TestFcitx5Controller? controller,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (controller != null)
          fcitx5Provider.overrideWith(() => controller)
        else
          fcitx5Provider.overrideWithBuild((ref, notifier) => snapshot),
      ],
      child: const DenialLocalizationScope(
        locale: Locale('en'),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Material(
            child: SizedBox(
              width: 500,
              height: 200,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [DesktopInputMethodMark(), DesktopInputMethodCard()],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}
