import 'package:denial_dart_shell/src/desktop/desktop_tile_menu.dart';
import 'package:denial_dart_shell/src/desktop/models/desktop_tile.dart';
import 'package:denial_dart_shell/src/localization/denial_localizations.dart';
import 'package:denial_dart_shell/src/theme/shell_theme.dart';
import 'package:denial_dart_shell/src/widgets/shell_surface_host.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('height', () {
    test('height follows the rows the menu actually has', () {
      final one = DesktopTileMenu.heightFor(<DesktopTileMenuEntry>[
        _item('Pin to Start'),
      ]);
      final many = DesktopTileMenu.heightFor(<DesktopTileMenuEntry>[
        _item('Unpin from Start'),
        const DesktopTileMenuEntry.divider(),
        const DesktopTileMenuEntry.heading('Resize'),
        _item('Small'),
        _item('Medium'),
        _item('Wide'),
        _item('Large'),
      ]);

      // The window menu next door hardcodes 136.0 for its three rows, so a menu
      // with a different count would be placed against the wrong height.
      expect(one, DesktopTileMenu.verticalPadding + DesktopTileMenu.itemExtent);
      expect(
        many,
        DesktopTileMenu.verticalPadding +
            DesktopTileMenu.itemExtent * 5 +
            DesktopTileMenu.dividerExtent +
            DesktopTileMenu.headingExtent,
      );
      expect(many, greaterThan(one));
    });
  });

  group('placement', () {
    testWidgets('a menu near the right edge flips to the left', (tester) async {
      await _pumpMenu(
        tester,
        position: const Offset(1180, 100),
        entries: <DesktopTileMenuEntry>[_item('Unpin from Start')],
      );

      final card = tester.getRect(_cardFinder);
      expect(card.right, lessThanOrEqualTo(1200 - DesktopTileMenu.margin));
      expect(card.left, closeTo(1180 - DesktopTileMenu.menuWidth, 0.5));
    });

    testWidgets('a tall menu near the bottom edge flips upward', (
      tester,
    ) async {
      final entries = <DesktopTileMenuEntry>[
        _item('Unpin from Start'),
        const DesktopTileMenuEntry.divider(),
        const DesktopTileMenuEntry.heading('Resize'),
        _item('Small'),
        _item('Medium'),
        _item('Wide'),
        _item('Large'),
      ];
      await _pumpMenu(
        tester,
        position: const Offset(100, 780),
        entries: entries,
      );

      final card = tester.getRect(_cardFinder);
      expect(card.bottom, lessThanOrEqualTo(800 - DesktopTileMenu.margin));
      expect(card.top, closeTo(780 - DesktopTileMenu.heightFor(entries), 1.0));
    });

    testWidgets('a menu never lands off the top-left corner', (tester) async {
      await _pumpMenu(
        tester,
        position: const Offset(-500, -500),
        entries: <DesktopTileMenuEntry>[_item('Unpin from Start')],
      );

      final card = tester.getRect(_cardFinder);
      expect(card.left, DesktopTileMenu.margin);
      expect(card.top, DesktopTileMenu.margin);
    });
  });

  group('rows', () {
    testWidgets('items, heading and divider all render', (tester) async {
      await _pumpMenu(
        tester,
        position: const Offset(100, 100),
        entries: <DesktopTileMenuEntry>[
          _item('Unpin from Start'),
          const DesktopTileMenuEntry.divider(),
          const DesktopTileMenuEntry.heading('Resize'),
          _item('Small'),
        ],
      );

      expect(find.text('Unpin from Start'), findsOneWidget);
      expect(find.text('Resize'), findsOneWidget);
      expect(find.text('Small'), findsOneWidget);
      expect(find.bySemanticsLabel('Unpin from Start'), findsOneWidget);
      // A heading is not a button, so it must not be reachable as one.
      expect(
        find.descendant(
          of: find.byType(DesktopTileMenu),
          matching: find.byType(GestureDetector),
        ),
        findsNWidgets(2),
      );
    });

    testWidgets('choosing a row runs it and closes the menu', (tester) async {
      var pressed = 0;
      await _pumpMenu(
        tester,
        position: const Offset(100, 100),
        entries: <DesktopTileMenuEntry>[
          _item('Unpin from Start', onPressed: () => pressed += 1),
        ],
      );

      await tester.tap(find.text('Unpin from Start'));
      await tester.pumpAndSettle();

      expect(pressed, 1);
      expect(find.byType(DesktopTileMenu), findsNothing);
    });

    testWidgets('the first row takes focus so Enter works straight away', (
      tester,
    ) async {
      var pressed = 0;
      await _pumpMenu(
        tester,
        position: const Offset(100, 100),
        entries: <DesktopTileMenuEntry>[
          _item('Unpin from Start', onPressed: () => pressed += 1),
          const DesktopTileMenuEntry.divider(),
          _item('Small'),
        ],
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(pressed, 1);
    });

    testWidgets('a size row draws its own footprint instead of a glyph', (
      tester,
    ) async {
      await _pumpMenu(
        tester,
        position: const Offset(100, 100),
        entries: <DesktopTileMenuEntry>[
          DesktopTileMenuEntry.item(
            label: 'Wide',
            icon: null,
            tileSize: DesktopTileSize.wide,
            selected: true,
            onPressed: () {},
          ),
        ],
      );

      final painter = tester
          .widgetList<CustomPaint>(
            find.descendant(
              of: find.byType(DesktopTileMenu),
              matching: find.byType(CustomPaint),
            ),
          )
          .map((paint) => paint.painter)
          .whereType<DesktopTileSizeGlyphPainter>()
          .single;

      expect(painter.size, DesktopTileSize.wide);
      expect(find.bySemanticsLabel('Wide'), findsOneWidget);
    });
  });

  group('dismissal', () {
    testWidgets('tapping outside closes the menu', (tester) async {
      await _pumpMenu(
        tester,
        position: const Offset(600, 400),
        entries: <DesktopTileMenuEntry>[_item('Unpin from Start')],
      );

      await tester.tapAt(const Offset(40, 40));
      await tester.pumpAndSettle();

      expect(find.byType(DesktopTileMenu), findsNothing);
    });

    testWidgets('Escape closes the menu', (tester) async {
      await _pumpMenu(
        tester,
        position: const Offset(600, 400),
        entries: <DesktopTileMenuEntry>[_item('Unpin from Start')],
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byType(DesktopTileMenu), findsNothing);
    });

    testWidgets('a second right-click on the same target does not stack', (
      tester,
    ) async {
      late WidgetRef captured;
      await _pumpHost(tester, onRef: (ref) => captured = ref);

      for (var attempt = 0; attempt < 2; attempt += 1) {
        showDesktopTileMenu(
          ref: captured,
          keySuffix: 'tile-app:alacritty.desktop',
          position: const Offset(100, 100),
          entries: <DesktopTileMenuEntry>[_item('Unpin from Start')],
        );
        await tester.pumpAndSettle();
      }

      expect(find.byType(DesktopTileMenu), findsOneWidget);
    });
  });
}

final Finder _cardFinder = find
    .descendant(
      of: find.byType(DesktopTileMenu),
      matching: find.byType(FocusTraversalGroup),
    )
    .first;

DesktopTileMenuEntry _item(String label, {VoidCallback? onPressed}) {
  return DesktopTileMenuEntry.item(
    label: label,
    icon: Icons.push_pin_outlined,
    onPressed: onPressed ?? () {},
  );
}

Future<void> _pumpHost(
  WidgetTester tester, {
  required ValueChanged<WidgetRef> onRef,
}) async {
  tester.view.physicalSize = const Size(1200, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      child: DenialLocalizationScope(
        locale: const Locale('en'),
        child: ShellTheme(
          data: const ShellThemeData(),
          child: ShellSurfaceHost(
            child: Consumer(
              builder: (context, ref, _) {
                onRef(ref);
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpMenu(
  WidgetTester tester, {
  required Offset position,
  required List<DesktopTileMenuEntry> entries,
}) async {
  late WidgetRef captured;
  await _pumpHost(tester, onRef: (ref) => captured = ref);

  showDesktopTileMenu(
    ref: captured,
    keySuffix: 'test',
    position: position,
    entries: entries,
  );
  await tester.pumpAndSettle();
}
