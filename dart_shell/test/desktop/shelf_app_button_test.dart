import 'package:denial_dart_shell/src/desktop/shelf/shelf_app_button.dart';
import 'package:denial_dart_shell/src/theme/shell_theme.dart';
import 'package:denial_dart_shell/src/widgets/shell_menu.dart';
import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shelf button defers context menu construction until open', (
    tester,
  ) async {
    var menuBuilds = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ShellTheme(
          data: const ShellThemeData(),
          child: Center(
            child: ShelfAppButton(
              appId: 'org.example.test',
              icon: Icons.apps_rounded,
              title: 'Test',
              windowCount: 1,
              menuBuilder: (context) {
                menuBuilds++;
                return <Widget>[
                  ShellMenuItem(label: 'Pin to shelf', onPressed: () {}),
                ];
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(menuBuilds, 0);
    expect(find.text('Pin to shelf'), findsNothing);

    await tester.tap(find.byType(ShelfAppButton), buttons: kSecondaryButton);
    await tester.pumpAndSettle();

    expect(menuBuilds, 1);
    expect(find.text('Pin to shelf'), findsOneWidget);
  });
}
