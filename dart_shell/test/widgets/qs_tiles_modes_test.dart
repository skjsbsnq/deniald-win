import 'package:denial_dart_shell/l10n/generated/app_localizations.dart';
import 'package:denial_dart_shell/src/services/power_profile_service.dart';
import 'package:denial_dart_shell/src/state/desktop_power_modes.dart';
import 'package:denial_dart_shell/src/theme/shell_theme.dart';
import 'package:denial_dart_shell/src/theme/tokens.dart';
import 'package:denial_dart_shell/src/widgets/shade/quick_settings_tiles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(Widget child, {List<Override> overrides = const []}) {
    return ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: ShellTheme(
            data: const ShellThemeData(),
            child: Center(child: SizedBox(width: 388, child: child)),
          ),
        ),
      ),
    );
  }

  Widget tiles({bool wifiActive = false}) {
    return QuickSettingsTiles(
      wifi: wifiActive,
      wifiSubtitle: 'Connected',
      wifiEnabled: true,
      wifiBusy: false,
      bluetooth: false,
      bluetoothSubtitle: 'Off',
      bluetoothEnabled: true,
      bluetoothBusy: false,
      rotationLock: true,
      darkTheme: true,
      dnd: false,
      dndReady: true,
      profile: PowerProfile.balanced,
      onToggleWifi: () {},
      onOpenWifi: () {},
      onToggleBluetooth: () {},
      onOpenBluetooth: () {},
      onToggleRotation: () {},
      onToggleDarkTheme: () {},
      onToggleDnd: () {},
      onCycleProfile: () {},
      onScreenshot: () {},
    );
  }

  /// The tile surface is the topmost DecoratedBox inside the tile — the one
  /// carrying the lerped border radius.
  BoxDecoration tileDecoration(WidgetTester tester, Finder tile) {
    final box = tester.widget<DecoratedBox>(
      find.descendant(of: tile, matching: find.byType(DecoratedBox)).first,
    );
    return box.decoration as BoxDecoration;
  }

  testWidgets('grid renders seven tiles in segmented rows', (tester) async {
    await tester.pumpWidget(wrap(tiles()));
    await tester.pumpAndSettle();

    expect(find.byType(QuickTile), findsNWidgets(7));
    expect(find.text('Wi-Fi'), findsOneWidget);
    expect(find.text('Dark theme'), findsOneWidget);
    expect(find.text('Rotation'), findsOneWidget);
  });

  testWidgets('segmented corners: outer extraLarge, inner small', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(tiles()));
    await tester.pumpAndSettle();

    final tileWidgets = tester
        .widgetList<QuickTile>(find.byType(QuickTile))
        .toList();
    expect(tileWidgets.map((tile) => tile.segment), [
      QuickTileSegment.leading,
      QuickTileSegment.trailing,
      QuickTileSegment.leading,
      QuickTileSegment.trailing,
      QuickTileSegment.leading,
      QuickTileSegment.middle,
      QuickTileSegment.trailing,
    ]);

    // Row 1 leading tile (Wi-Fi): start edge extraLarge(28), inner edge
    // small(8) under the default cornerRadiusScale of 1.0.
    final leading = tileDecoration(
      tester,
      find.widgetWithText(QuickTile, 'Wi-Fi'),
    ).borderRadius! as BorderRadius;
    expect(leading.topLeft.x, ShellShapeScale.extraLarge);
    expect(leading.bottomLeft.x, ShellShapeScale.extraLarge);
    expect(leading.topRight.x, ShellShapeScale.small);
    expect(leading.bottomRight.x, ShellShapeScale.small);

    // Row 3 middle tile (DND): compact tiles render an icon only, so locate
    // it through its glyph — small on every corner.
    final middle = tileDecoration(
      tester,
      find.ancestor(
        of: find.byIcon(Icons.notifications_off_rounded),
        matching: find.byType(QuickTile),
      ),
    ).borderRadius! as BorderRadius;
    expect(middle.topLeft.x, ShellShapeScale.small);
    expect(middle.topRight.x, ShellShapeScale.small);
    expect(middle.bottomLeft.x, ShellShapeScale.small);
    expect(middle.bottomRight.x, ShellShapeScale.small);
  });

  testWidgets('activation morphs the tile toward full, animated not instant', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(tiles()));
    await tester.pumpAndSettle();

    final wifiTile = find.widgetWithText(QuickTile, 'Wi-Fi');
    final resting = tileDecoration(
      tester,
      wifiTile,
    ).borderRadius! as BorderRadius;
    expect(resting.topRight.x, ShellShapeScale.small);

    // Rebuild with the Wi-Fi tile active: the shape spring runs on
    // expressiveEffectsFast, so one frame in the corners are mid-morph.
    await tester.pumpWidget(wrap(tiles(wifiActive: true)));
    await tester.pump(const Duration(milliseconds: 40));
    final mid = tileDecoration(
      tester,
      wifiTile,
    ).borderRadius! as BorderRadius;
    expect(mid.topRight.x, greaterThan(ShellShapeScale.small));

    await tester.pumpAndSettle();
    final settledDecoration = tileDecoration(tester, wifiTile);
    final settled = settledDecoration.borderRadius! as BorderRadius;
    expect(
      settled.topRight.x,
      moreOrLessEquals(ShellShapeScale.full, epsilon: 2),
    );
    // Active fill lands on the accent primary (within spring settle epsilon).
    expect(
      settledDecoration.color,
      isSameColorAs(const ShellThemeData().accentPalette.primary),
    );
  });

  group('QuickSettingsModesSection', () {
    testWidgets('hides entirely when no system profile is available', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const QuickSettingsModesSection(),
          overrides: [
            desktopPowerModesProvider.overrideWith(
              _UnavailablePowerModes.new,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(QuickSettingsModesRow), findsNothing);
      expect(find.byIcon(Icons.tune_rounded), findsNothing);
    });

    testWidgets('shows the mode buttons and selects a profile', (
      tester,
    ) async {
      String? selected;
      await tester.pumpWidget(
        wrap(
          QuickSettingsModesRow(
            profile: PowerProfile.balanced,
            changing: false,
            onSelect: (profile) => selected = profile,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(QuickSettingsModesRow), findsOneWidget);
      expect(find.text('Power modes'), findsOneWidget);
      expect(find.byIcon(Icons.energy_savings_leaf_rounded), findsOneWidget);
      expect(find.byIcon(Icons.balance_rounded), findsOneWidget);
      expect(find.byIcon(Icons.speed_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.energy_savings_leaf_rounded));
      expect(selected, PowerProfile.powerSave);
    });
  });
}

class _UnavailablePowerModes extends DesktopPowerModesController {
  @override
  DesktopPowerModesState build() => DesktopPowerModesState.initial();
}
