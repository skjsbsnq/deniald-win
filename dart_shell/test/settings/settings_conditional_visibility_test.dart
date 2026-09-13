import 'package:denial_dart_shell/src/models/display_layout.dart';
import 'package:denial_dart_shell/src/settings/settings_controller.dart';
import 'package:denial_dart_shell/src/settings/shell_settings.dart';
import 'package:denial_dart_shell/src/settings/widgets/settings_layout_page.dart';
import 'package:denial_dart_shell/src/settings/widgets/settings_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/settings_harness.dart';

/// A single 1280x720 output, so the layout page renders a real display picker
/// instead of its unavailable fallback.
final DisplayLayout _display = DisplayLayout.fallback(
  const Size(1280, 720),
  1.0,
);

const String _barCloneHint =
    'Each selected display gets its own bar. The bar never spans displays.';
const String _shelfCloneHint = 'Each selected display shows its own shelf.';

ShellSettings _layoutSettings({required bool shelf, double thickness = 32}) {
  return ShellSettings(
    layout: ShellLayoutSettings(
      useChromeOsShelf: shelf,
      systemBarThickness: thickness,
    ),
  );
}

Finder _thicknessSlider() => find.descendant(
  of: find.byKey(settingsBarThicknessSliderKey),
  matching: find.byType(Slider),
);

Finder _displayChoice(int monitorId) =>
    find.byKey(ValueKey<String>('settings-system-bar-display-$monitorId'));

SettingsTestSettingsController _controller(ProviderContainer container) =>
    container.read(shellSettingsProvider.notifier)
        as SettingsTestSettingsController;

void main() {
  testWidgets('layout page always renders the shelf-only form', (
    tester,
  ) async {
    // A persisted useChromeOsShelf=false must not resurrect the classic UI:
    // the shelf is the only desktop bar form.
    await pumpSettingsApp(
      tester,
      initialPage: SettingsPageId.layout,
      initialSettings: _layoutSettings(shelf: false),
      displayLayout: _display,
    );

    // The retired toggle and the classic edge picker are gone.
    expect(find.text('Use ChromeOS shelf'), findsNothing);
    expect(find.text('EDGE'), findsNothing);
    // The still-valid parts stay: card title and per-display selection.
    expect(find.text('ChromeOS shelf'), findsOneWidget);
    expect(find.text('Desktop system bar'), findsOneWidget);
    expect(_displayChoice(0), findsOneWidget);
    expect(find.text(_shelfCloneHint), findsOneWidget);
    expect(find.text(_barCloneHint), findsNothing);
    expect(find.text('Shelf height'), findsOneWidget);
    expect(find.text('Bar thickness'), findsNothing);
  });

  testWidgets('shelf height slider keeps a 48-112 range', (tester) async {
    await pumpSettingsApp(
      tester,
      initialPage: SettingsPageId.layout,
      initialSettings: _layoutSettings(shelf: true, thickness: 32),
      displayLayout: _display,
    );

    final slider = tester.widget<Slider>(_thicknessSlider());
    expect(slider.min, 48);
    expect(slider.max, 112);
    expect(slider.divisions, 64);
    // 32 is below the shelf floor, so the effective 56 is what the UI shows.
    expect(slider.value, 56);
    expect(find.text('56 px'), findsOneWidget);
  });

  testWidgets('a sub-floor thickness clamps up to the effective 48', (
    tester,
  ) async {
    await pumpSettingsApp(
      tester,
      initialPage: SettingsPageId.layout,
      initialSettings: _layoutSettings(shelf: true, thickness: 40),
      displayLayout: _display,
    );

    final slider = tester.widget<Slider>(_thicknessSlider());
    expect(slider.value, 48);
    expect(find.text('48 px'), findsOneWidget);
  });

  testWidgets('an above-floor thickness stays untouched', (tester) async {
    await pumpSettingsApp(
      tester,
      initialPage: SettingsPageId.layout,
      initialSettings: _layoutSettings(shelf: true, thickness: 64),
      displayLayout: _display,
    );

    expect(tester.widget<Slider>(_thicknessSlider()).value, 64);
    expect(find.text('64 px'), findsOneWidget);
  });

  testWidgets('the thickness slider still writes systemBarThickness', (
    tester,
  ) async {
    final container = await pumpSettingsApp(
      tester,
      initialPage: SettingsPageId.layout,
      initialSettings: _layoutSettings(shelf: true, thickness: 32),
      displayLayout: _display,
    );

    tester.widget<Slider>(_thicknessSlider()).onChanged!(80);
    await tester.pump();

    expect(container.read(shellSettingsProvider).layout.systemBarThickness, 80);
  });

  testWidgets('overlays page always renders only notifications and HUD', (
    tester,
  ) async {
    // Persisted useChromeOsShelf=false keeps the same two editors.
    await pumpSettingsApp(
      tester,
      initialPage: SettingsPageId.overlays,
      initialSettings: _layoutSettings(shelf: false),
    );

    expect(find.text('Applications'), findsNothing);
    expect(find.text('Dashboard'), findsNothing);
    // Notifications and the system-level display stay valid (§E3).
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('System level display'), findsOneWidget);
  });

  testWidgets('overlays page ignores persisted shelf flag flips', (
    tester,
  ) async {
    final container = await pumpSettingsApp(
      tester,
      initialPage: SettingsPageId.overlays,
      initialSettings: _layoutSettings(shelf: true),
    );
    expect(find.text('Applications'), findsNothing);

    _controller(container).setUseChromeOsShelf(false);
    await tester.pump();

    expect(find.text('Applications'), findsNothing);
    expect(find.text('Dashboard'), findsNothing);
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('System level display'), findsOneWidget);
  });

  testWidgets('the retired edge picker leaves no semantics nodes', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await pumpSettingsApp(
        tester,
        initialPage: SettingsPageId.layout,
        initialSettings: _layoutSettings(shelf: false),
        displayLayout: _display,
      );
      // Scoped to the picker so the clipboard tray's "Top edge" label cannot
      // be mistaken for an edge choice.
      final pickerSemantics = find.descendant(
        of: find.byKey(
          const ValueKey<String>('settings-system-bar-placement-card'),
        ),
        matching: find.bySemanticsLabel(RegExp('Top')),
      );
      expect(find.bySemanticsLabel('EDGE'), findsNothing);
      expect(pickerSemantics, findsNothing);
    } finally {
      semantics.dispose();
    }
  });
}
