import 'package:denial_dart_shell/src/localization/denial_localizations.dart';
import 'package:denial_dart_shell/src/models/display_layout.dart';
import 'package:denial_dart_shell/src/models/tray_item.dart';
import 'package:denial_dart_shell/src/state/status_notifier.dart';
import 'package:denial_dart_shell/src/theme/shell_theme.dart';
import 'package:denial_dart_shell/src/widgets/shell_surface_host.dart';
import 'package:denial_dart_shell/src/widgets/tray/tray_area.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TrayArea Widget tests', () {
    testWidgets('renders SizedBox.shrink when items list is empty', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            statusNotifierProvider.overrideWith(
              () => _FakeStatusNotifierController(
                StatusNotifierState.initial().copyWith(items: const []),
              ),
            ),
          ],
          child: const MaterialApp(
            home: DenialLocalizationScope(
              child: Scaffold(body: TrayArea(side: SystemBarSide.bottom)),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      final trayAreaFinder = find.byType(TrayArea);
      expect(trayAreaFinder, findsOneWidget);
      expect(find.byType(TrayItemButton), findsNothing);
      final RenderBox box = tester.renderObject(trayAreaFinder);
      expect(box.size, equals(Size.zero));
    });

    testWidgets(
      'renders active items without overflow chevron when no passive items',
      (tester) async {
        final items = [
          const TrayItem(
            service: ':1.201',
            path: '/StatusNotifierItem',
            id: 'nm-applet',
            title: 'Network',
            status: TrayItemStatus.active,
          ),
          const TrayItem(
            service: ':1.202',
            path: '/StatusNotifierItem',
            id: 'discord',
            title: 'Discord',
            status: TrayItemStatus.active,
          ),
        ];

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              statusNotifierProvider.overrideWith(
                () => _FakeStatusNotifierController(
                  StatusNotifierState.initial().copyWith(items: items),
                ),
              ),
            ],
            child: const MaterialApp(
              home: DenialLocalizationScope(
                child: Scaffold(body: TrayArea(side: SystemBarSide.bottom)),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();
        expect(find.byType(TrayItemButton), findsNWidgets(2));
        expect(find.byIcon(Icons.keyboard_arrow_up_rounded), findsNothing);
      },
    );

    testWidgets(
      'folds passive items behind overflow chevron and shows in popup',
      (tester) async {
        final items = [
          const TrayItem(
            service: ':1.301',
            path: '/StatusNotifierItem',
            id: 'active-app',
            title: 'Active App',
            status: TrayItemStatus.active,
          ),
          const TrayItem(
            service: ':1.302',
            path: '/StatusNotifierItem',
            id: 'passive-app',
            title: 'Passive App',
            status: TrayItemStatus.passive,
          ),
        ];

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              statusNotifierProvider.overrideWith(
                () => _FakeStatusNotifierController(
                  StatusNotifierState.initial().copyWith(items: items),
                ),
              ),
            ],
            child: const ShellTheme(
              data: ShellThemeData(),
              child: MaterialApp(
                home: DenialLocalizationScope(
                  child: Scaffold(
                    body: ShellSurfaceHost(
                      child: TrayArea(side: SystemBarSide.bottom),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // In primary tray area: 1 active item and 1 overflow chevron button
        expect(
          find.byKey(const ValueKey('tray-item-:1.301/StatusNotifierItem')),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.keyboard_arrow_up_rounded), findsOneWidget);

        // Tap the overflow chevron to open TrayOverflowPanel
        await tester.tap(find.byIcon(Icons.keyboard_arrow_up_rounded));
        await tester.pumpAndSettle();

        // Passive item should now be visible in the overflow panel
        expect(
          find.byKey(
            const ValueKey('passive-tray-item-:1.302/StatusNotifierItem'),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'unconditionally promotes needsAttention items to primary tray area',
      (tester) async {
        final items = [
          const TrayItem(
            service: ':1.401',
            path: '/StatusNotifierItem',
            id: 'urgent-app',
            title: 'Urgent App',
            status: TrayItemStatus.needsAttention,
          ),
          const TrayItem(
            service: ':1.402',
            path: '/StatusNotifierItem',
            id: 'passive-app',
            title: 'Passive App',
            status: TrayItemStatus.passive,
          ),
        ];

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              statusNotifierProvider.overrideWith(
                () => _FakeStatusNotifierController(
                  StatusNotifierState.initial().copyWith(items: items),
                ),
              ),
            ],
            child: const MaterialApp(
              home: DenialLocalizationScope(
                child: Scaffold(body: TrayArea(side: SystemBarSide.bottom)),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Urgent item is in primary bar alongside the overflow chevron for passive app
        expect(
          find.byKey(const ValueKey('tray-item-:1.401/StatusNotifierItem')),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.keyboard_arrow_up_rounded), findsOneWidget);
      },
    );

    testWidgets('handles Left, Right, Middle, and Scroll gestures', (
      tester,
    ) async {
      final mockNotifier = _MockActionStatusNotifierController(
        StatusNotifierState.initial().copyWith(
          items: const [
            TrayItem(
              service: ':1.501',
              path: '/StatusNotifierItem',
              id: 'test-actions',
              title: 'Actions App',
              status: TrayItemStatus.active,
            ),
          ],
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [statusNotifierProvider.overrideWith(() => mockNotifier)],
          child: const MaterialApp(
            home: DenialLocalizationScope(
              child: Scaffold(body: TrayArea(side: SystemBarSide.bottom)),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      final itemFinder = find.byType(TrayItemButton);
      expect(itemFinder, findsOneWidget);

      // 1. Primary Tap -> Activate
      await tester.tap(itemFinder);
      await tester.pump();
      expect(mockNotifier.activateCalls, equals(1));

      // 2. Secondary Tap -> ContextMenu
      await tester.tap(itemFinder, buttons: kSecondaryMouseButton);
      await tester.pump();
      expect(mockNotifier.contextMenuCalls, equals(1));

      // 3. Middle Tap -> SecondaryActivate
      await tester.tap(itemFinder, buttons: kMiddleMouseButton);
      await tester.pump();
      expect(mockNotifier.secondaryActivateCalls, equals(1));

      // 4. Scroll -> Scroll
      final center = tester.getCenter(itemFinder);
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(pointer.hover(center));
      await tester.sendEventToBinding(
        pointer.scroll(const Offset(0.0, -100.0)),
      );
      await tester.pump();
      expect(mockNotifier.scrollCalls, greaterThanOrEqualTo(1));
    });
  });
}

class _FakeStatusNotifierController extends StatusNotifierController {
  _FakeStatusNotifierController(this._initialState);

  final StatusNotifierState _initialState;

  @override
  StatusNotifierState build() => _initialState;
}

class _MockActionStatusNotifierController extends StatusNotifierController {
  _MockActionStatusNotifierController(this._initialState);

  final StatusNotifierState _initialState;
  int activateCalls = 0;
  int secondaryActivateCalls = 0;
  int contextMenuCalls = 0;
  int scrollCalls = 0;

  @override
  StatusNotifierState build() => _initialState;

  @override
  Future<void> activate(TrayItem item, {int x = 0, int y = 0}) async {
    activateCalls++;
  }

  @override
  Future<void> secondaryActivate(TrayItem item, {int x = 0, int y = 0}) async {
    secondaryActivateCalls++;
  }

  @override
  Future<void> contextMenu(TrayItem item, {int x = 0, int y = 0}) async {
    contextMenuCalls++;
  }

  @override
  Future<void> scroll(TrayItem item, int delta, String orientation) async {
    scrollCalls++;
  }
}
