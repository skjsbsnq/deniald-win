import 'package:denial_dart_shell/src/models/display_layout.dart';
import 'package:denial_dart_shell/src/settings/settings_controller.dart';
import 'package:denial_dart_shell/src/settings/shell_settings.dart';
import 'package:denial_dart_shell/src/settings/widgets/settings_layout_page.dart';
import 'package:denial_dart_shell/src/settings/widgets/settings_navigation.dart';
import 'package:denial_dart_shell/src/settings/widgets/system_bar_placement_card.dart';
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
  testWidgets('shelf on hides the edge picker and keeps the display picker', (
    tester,
  ) async {
    await pumpSettingsApp(
      tester,
      initialPage: SettingsPageId.layout,
      initialSettings: _layoutSettings(shelf: true),
      displayLayout: _display,
    );

    expect(find.byKey(settingsSystemBarEdgeSelectorKey), findsNothing);
    expect(find.text('EDGE'), findsNothing);
    // The still-valid parts stay: card title and per-display selection.
    expect(find.text('Desktop system bar'), findsOneWidget);
    expect(_displayChoice(0), findsOneWidget);
    expect(find.text(_shelfCloneHint), findsOneWidget);
    expect(find.text(_barCloneHint), findsNothing);
  });

  testWidgets('shelf off shows the edge picker and the classic bar hint', (
    tester,
  ) async {
    await pumpSettingsApp(
      tester,
      initialPage: SettingsPageId.layout,
      initialSettings: _layoutSettings(shelf: false),
      displayLayout: _display,
    );

    expect(find.byKey(settingsSystemBarEdgeSelectorKey), findsOneWidget);
    expect(find.text('EDGE'), findsOneWidget);
    expect(_displayChoice(0), findsOneWidget);
    expect(find.text(_barCloneHint), findsOneWidget);
    expect(find.text(_shelfCloneHint), findsNothing);
  });

  testWidgets('shelf on relabels thickness as shelf height with a 48 floor', (
    tester,
  ) async {
    await pumpSettingsApp(
      tester,
      initialPage: SettingsPageId.layout,
      initialSettings: _layoutSettings(shelf: true, thickness: 32),
      displayLayout: _display,
    );

    expect(find.text('Shelf height'), findsOneWidget);
    expect(find.text('Bar thickness'), findsNothing);

    final slider = tester.widget<Slider>(_thicknessSlider());
    expect(slider.min, 48);
    expect(slider.max, 112);
    expect(slider.divisions, 64);
    // 32 is below the shelf floor, so the effective 56 is what the UI shows.
    expect(slider.value, 56);
    expect(find.text('56 px'), findsOneWidget);
  });

  testWidgets('shelf on clamps a sub-floor thickness up to the effective 48', (
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

  testWidgets('shelf on leaves an above-floor thickness untouched', (
    tester,
  ) async {
    await pumpSettingsApp(
      tester,
      initialPage: SettingsPageId.layout,
      initialSettings: _layoutSettings(shelf: true, thickness: 64),
      displayLayout: _display,
    );

    expect(tester.widget<Slider>(_thicknessSlider()).value, 64);
    expect(find.text('64 px'), findsOneWidget);
  });

  testWidgets('shelf off keeps the classic 24-112 bar thickness range', (
    tester,
  ) async {
    await pumpSettingsApp(
      tester,
      initialPage: SettingsPageId.layout,
      initialSettings: _layoutSettings(shelf: false, thickness: 32),
      displayLayout: _display,
    );

    expect(find.text('Bar thickness'), findsOneWidget);
    expect(find.text('Shelf height'), findsNothing);

    final slider = tester.widget<Slider>(_thicknessSlider());
    expect(slider.min, 24);
    expect(slider.max, 112);
    expect(slider.divisions, 88);
    expect(slider.value, 32);
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

  testWidgets('shelf on hides the launcher and dashboard editors', (
    tester,
  ) async {
    await pumpSettingsApp(
      tester,
      initialPage: SettingsPageId.overlays,
      initialSettings: _layoutSettings(shelf: true),
    );

    expect(find.text('Applications'), findsNothing);
    expect(find.text('Dashboard'), findsNothing);
    // Notifications and the system-level display stay valid (§E3).
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('System level display'), findsOneWidget);
  });

  testWidgets('shelf off renders all four overlay editors', (tester) async {
    await pumpSettingsApp(
      tester,
      initialPage: SettingsPageId.overlays,
      initialSettings: _layoutSettings(shelf: false),
    );

    expect(find.text('Applications'), findsOneWidget);
    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('System level display'), findsOneWidget);
  });

  testWidgets('toggling shelf updates the layout page without a rebuild', (
    tester,
  ) async {
    final container = await pumpSettingsApp(
      tester,
      initialPage: SettingsPageId.layout,
      initialSettings: _layoutSettings(shelf: false),
      displayLayout: _display,
    );
    expect(find.byKey(settingsSystemBarEdgeSelectorKey), findsOneWidget);
    expect(find.text('Bar thickness'), findsOneWidget);

    _controller(container).setUseChromeOsShelf(true);
    await tester.pump();

    expect(find.byKey(settingsSystemBarEdgeSelectorKey), findsNothing);
    expect(find.text('Shelf height'), findsOneWidget);
    expect(_displayChoice(0), findsOneWidget);

    _controller(container).setUseChromeOsShelf(false);
    await tester.pump();

    expect(find.byKey(settingsSystemBarEdgeSelectorKey), findsOneWidget);
    expect(find.text('Bar thickness'), findsOneWidget);
  });

  testWidgets('toggling shelf updates the overlays page without a rebuild', (
    tester,
  ) async {
    final container = await pumpSettingsApp(
      tester,
      initialPage: SettingsPageId.overlays,
      initialSettings: _layoutSettings(shelf: false),
    );
    expect(find.text('Applications'), findsOneWidget);

    _controller(container).setUseChromeOsShelf(true);
    await tester.pump();

    expect(find.text('Applications'), findsNothing);
    expect(find.text('Dashboard'), findsNothing);
    expect(find.text('Notifications'), findsOneWidget);
  });

  testWidgets('hiding the edge picker removes its semantics nodes too', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      final container = await pumpSettingsApp(
        tester,
        initialPage: SettingsPageId.layout,
        initialSettings: _layoutSettings(shelf: false),
        displayLayout: _display,
      );
      // Scoped to the picker so the clipboard tray's "Top edge" label cannot
      // be mistaken for an edge choice.
      final pickerSemantics = find.descendant(
        of: find.byKey(settingsSystemBarEdgeSelectorKey),
        matching: find.bySemanticsLabel(RegExp('Top')),
      );
      expect(find.bySemanticsLabel('EDGE'), findsOneWidget);
      expect(pickerSemantics, findsWidgets);

      _controller(container).setUseChromeOsShelf(true);
      await tester.pump();

      expect(find.byKey(settingsSystemBarEdgeSelectorKey), findsNothing);
      expect(find.bySemanticsLabel('EDGE'), findsNothing);
      expect(pickerSemantics, findsNothing);
    } finally {
      semantics.dispose();
    }
  });
}
