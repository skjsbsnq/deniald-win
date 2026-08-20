import 'dart:ui' show PointerDeviceKind;

import 'package:denial_dart_shell/src/desktop/desktop_calendar_panel.dart';
import 'package:denial_dart_shell/src/localization/denial_localizations.dart';
import 'package:denial_dart_shell/src/models/desktop_notification.dart';
import 'package:denial_dart_shell/src/models/display_layout.dart';
import 'package:denial_dart_shell/src/state/desktop_notifications.dart';
import 'package:denial_dart_shell/src/state/system_status.dart';
import 'package:denial_dart_shell/src/widgets/shell_surface_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DesktopCalendarPanel', () {
    testWidgets('renders month title, weekdays, and today date', (
      tester,
    ) async {
      await _pumpCalendarPanel(tester, now: DateTime(2026, 8, 18, 10, 30));

      // Time and date in header
      expect(find.text('10:30'), findsOneWidget);
      expect(find.text('August 2026'), findsOneWidget);
      expect(find.text('18'), findsOneWidget);
    });

    testWidgets(
      'navigates previous and next months and resets with today button',
      (tester) async {
        await _pumpCalendarPanel(tester, now: DateTime(2026, 8, 18, 10, 30));

        expect(find.text('August 2026'), findsOneWidget);
        expect(find.text('Today'), findsNothing);

        // Tap next month (down arrow)
        await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded));
        await tester.pumpAndSettle();

        expect(find.text('September 2026'), findsOneWidget);
        expect(find.text('Today'), findsOneWidget);

        // Tap Today button to return to August 2026
        await tester.tap(find.text('Today'));
        await tester.pumpAndSettle();

        expect(find.text('August 2026'), findsOneWidget);
        expect(find.text('Today'), findsNothing);

        // Tap previous month (up arrow)
        await tester.tap(find.byIcon(Icons.keyboard_arrow_up_rounded));
        await tester.pumpAndSettle();

        expect(find.text('July 2026'), findsOneWidget);
        expect(find.text('Today'), findsOneWidget);
      },
    );

    testWidgets(
      'renders notification summary empty state and items (Option C)',
      (tester) async {
        await _pumpCalendarPanel(
          tester,
          now: DateTime(2026, 8, 18, 10, 30),
          notifications: const DesktopNotificationsState(history: []),
        );

        expect(find.text('No new notifications'), findsOneWidget);
        expect(find.text('View all'), findsOneWidget);
      },
    );

    testWidgets('renders notification item and invokes view all callback', (
      tester,
    ) async {
      var viewAllClicked = false;
      await _pumpCalendarPanel(
        tester,
        now: DateTime(2026, 8, 18, 10, 30),
        onOpenNotifications: () => viewAllClicked = true,
        notifications: DesktopNotificationsState(
          history: [
            DesktopNotificationRecord(
              notification: const DesktopNotification(
                id: 1,
                sender: 'org.denial.mail',
                appName: 'Mail',
                appIcon: '',
                summary: 'New message from Alice',
                body: 'Meeting scheduled at 2 PM',
                actions: [],
                urgency: DesktopNotificationUrgency.normal,
                category: '',
                desktopEntry: '',
                imagePath: '',
                imageData: null,
                resident: false,
                transient: false,
                suppressSound: false,
                actionIcons: false,
                soundName: '',
                soundFile: '',
                x: 0,
                y: 0,
                hasPosition: false,
                progress: 0,
                hasProgress: false,
                expireTimeoutMs: 5000,
              ),
              sequence: 1,
              active: true,
              unread: true,
            ),
          ],
        ),
      );

      expect(find.text('Mail'), findsOneWidget);
      expect(find.text('New message from Alice'), findsOneWidget);

      await tester.tap(find.text('View all'));
      await tester.pumpAndSettle();
      expect(viewAllClicked, isTrue);
    });

    testWidgets('triggers onEnter and onExit on pointer hover', (tester) async {
      var entered = false;
      var exited = false;

      await _pumpCalendarPanel(
        tester,
        now: DateTime(2026, 8, 18, 10, 30),
        onEnter: () => entered = true,
        onExit: () => exited = true,
      );

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);

      // Move inside panel
      await gesture.moveTo(tester.getCenter(find.byType(DesktopCalendarPanel)));
      await tester.pumpAndSettle();
      expect(entered, isTrue);

      // Move outside panel
      await gesture.moveTo(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(exited, isTrue);
    });

    testWidgets('triggers onClose when close icon is tapped', (tester) async {
      var closed = false;

      await _pumpCalendarPanel(
        tester,
        now: DateTime(2026, 8, 18, 10, 30),
        onClose: () => closed = true,
      );

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(closed, isTrue);
    });
  });
}

class _DummySurfaceHandle implements ShellSurfaceHandle {
  bool closed = false;

  @override
  int get id => 1;

  @override
  void close() {
    closed = true;
  }
}

Future<void> _pumpCalendarPanel(
  WidgetTester tester, {
  required DateTime now,
  DesktopNotificationsState? notifications,
  VoidCallback? onOpenNotifications,
  VoidCallback? onEnter,
  VoidCallback? onExit,
  VoidCallback? onClose,
}) async {
  await tester.binding.setSurfaceSize(const Size(1280, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final handle = _DummySurfaceHandle();

  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        clockProvider.overrideWith((ref) => Stream<DateTime>.value(now)),
        desktopNotificationsProvider.overrideWithBuild(
          (ref, controller) =>
              notifications ?? const DesktopNotificationsState(),
        ),
      ],
      child: MaterialApp(
        home: DenialLocalizationScope(
          locale: const Locale('en'),
          child: Scaffold(
            body: Align(
              alignment: Alignment.bottomRight,
              child: SizedBox(
                width: DesktopCalendarPanel.panelWidth,
                height: DesktopCalendarPanel.panelHeight,
                child: DesktopCalendarPanel(
                  handle: handle,
                  onClose: onClose ?? handle.close,
                  onEnter: onEnter,
                  onExit: onExit,
                  onOpenNotifications: onOpenNotifications,
                  side: SystemBarSide.bottom,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
