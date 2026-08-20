import 'dart:typed_data';

import 'package:denial_dart_shell/src/models/tray_item.dart';
import 'package:denial_dart_shell/src/widgets/tray/tray_icon.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TrayIcon widget unit tests', () {
    testWidgets('renders fallback asset when item has no pixmap or iconName', (
      tester,
    ) async {
      const item = TrayItem(
        service: ':1.100',
        path: '/StatusNotifierItem',
        id: 'test-empty',
        title: 'Empty App',
      );

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(body: TrayIcon(item: item)),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.byType(TrayIcon), findsOneWidget);
    });

    testWidgets('renders pixmap icon when iconPixmap is provided', (
      tester,
    ) async {
      // 16x16 pure red pixmap
      final redBytes = Uint8List(16 * 16 * 4);
      for (int i = 0; i < redBytes.length; i += 4) {
        redBytes[i] = 0xFF; // A
        redBytes[i + 1] = 0xFF; // R
        redBytes[i + 2] = 0x00; // G
        redBytes[i + 3] = 0x00; // B
      }

      final item = TrayItem(
        service: ':1.101',
        path: '/StatusNotifierItem',
        id: 'test-pixmap',
        title: 'Pixmap App',
        iconPixmap: [TrayPixmap(width: 16, height: 16, bytes: redBytes)],
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(body: TrayIcon(item: item)),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.byType(TrayIcon), findsOneWidget);
    });

    testWidgets('triggers onTap and onSecondaryTap callbacks', (tester) async {
      var tapped = false;
      var secondaryTapped = false;

      const item = TrayItem(
        service: ':1.102',
        path: '/StatusNotifierItem',
        id: 'test-tap',
        title: 'Tap App',
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: TrayIcon(
                item: item,
                onTap: () => tapped = true,
                onSecondaryTap: () => secondaryTapped = true,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(find.byType(TrayIcon));
      expect(tapped, isTrue);

      await tester.tap(find.byType(TrayIcon), buttons: kSecondaryButton);
      expect(secondaryTapped, isTrue);
    });

    testWidgets('displays sanitized tooltip text', (tester) async {
      const item = TrayItem(
        service: ':1.103',
        path: '/StatusNotifierItem',
        id: 'test-tooltip',
        title: 'Tooltip App',
        toolTipTitle: '<b>App Title</b>',
        toolTipDescription: 'Description with <br/> newline &amp; bold',
      );

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(body: TrayIcon(item: item)),
          ),
        ),
      );

      await tester.pumpAndSettle();
      final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
      expect(tooltip.message, 'App Title\nDescription with \n newline & bold');
    });
  });
}
