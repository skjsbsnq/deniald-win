import 'dart:typed_data';

import 'package:denial_dart_shell/src/models/dbus_menu_node.dart';
import 'package:denial_dart_shell/src/services/dbus_menu_client.dart';
import 'package:denial_dart_shell/src/theme/shell_theme.dart';
import 'package:denial_dart_shell/src/widgets/tray/tray_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TrayMenu Widget rendering tests', () {
    testWidgets('renders menu items, separators, and toggle icons correctly', (
      tester,
    ) async {
      final pngBytes = Uint8List.fromList([
        0x89,
        0x50,
        0x4E,
        0x47,
        0x0D,
        0x0A,
        0x1A,
        0x0A,
      ]);

      final items = [
        const DBusMenuNode(
          id: 1,
          label: '_New Document',
          cleanLabel: 'New Document',
          enabled: true,
          shortcut: [
            ['Control', 'N'],
          ],
        ),
        const DBusMenuNode(id: 2, type: 'separator'),
        const DBusMenuNode(
          id: 3,
          label: 'Show Toolbar',
          cleanLabel: 'Show Toolbar',
          toggleType: DBusMenuToggleType.checkmark,
          toggleState: 1,
        ),
        const DBusMenuNode(
          id: 4,
          label: 'Autosave',
          cleanLabel: 'Autosave',
          toggleType: DBusMenuToggleType.checkmark,
          toggleState: 0,
        ),
        const DBusMenuNode(
          id: 5,
          label: 'Radio Selected',
          cleanLabel: 'Radio Selected',
          toggleType: DBusMenuToggleType.radio,
          toggleState: 1,
        ),
        const DBusMenuNode(
          id: 6,
          label: 'Disabled Action',
          cleanLabel: 'Disabled Action',
          enabled: false,
        ),
        DBusMenuNode(
          id: 7,
          label: 'Custom PNG Item',
          cleanLabel: 'Custom PNG Item',
          iconData: pngBytes,
        ),
        const DBusMenuNode(
          id: 8,
          label: 'More Options',
          cleanLabel: 'More Options',
          childrenDisplay: 'submenu',
          children: [
            DBusMenuNode(id: 81, label: 'Sub Item 1', cleanLabel: 'Sub Item 1'),
          ],
        ),
      ];

      final mockClient = _MockDBusMenuClient(
        mockRoot: DBusMenuNode(id: 0, children: items),
      );

      bool closed = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: ShellTheme(
              data: const ShellThemeData(),
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: SizedBox(
                  width: 300,
                  height: 600,
                  child: TrayMenuOverlay(
                    onClose: () => closed = true,
                    client: mockClient,
                    anchorPosition: const Offset(50, 50),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // 1. Verify text labels rendered
      expect(find.text('New Document'), findsOneWidget);
      expect(find.text('Show Toolbar'), findsOneWidget);
      expect(find.text('Autosave'), findsOneWidget);
      expect(find.text('Radio Selected'), findsOneWidget);
      expect(find.text('Disabled Action'), findsOneWidget);
      expect(find.text('Custom PNG Item'), findsOneWidget);
      expect(find.text('More Options'), findsOneWidget);

      // 2. Verify shortcut label rendered
      expect(find.text('Control+N'), findsOneWidget);

      // 3. Verify checkmark and radio icons rendered
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(find.byIcon(Icons.radio_button_checked_rounded), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);

      // 4. Click enabled item
      await tester.tap(find.text('New Document'));
      await tester.pump();
      expect(mockClient.clickedIds, [1]);
      expect(closed, isTrue);

      // 5. Click disabled item
      closed = false;
      await tester.tap(find.text('Disabled Action'));
      await tester.pump();
      expect(mockClient.clickedIds, [1]); // Still only [1]
      expect(closed, isFalse);
    });

    testWidgets('shows loading indicator and error state correctly', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: const Scaffold(
            body: ShellTheme(
              data: ShellThemeData(),
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: SizedBox(
                  width: 250,
                  height: 300,
                  child: TrayMenuOverlay(
                    client: _MockDBusMenuClient(
                      mockRoot: null,
                      mockLoading: true,
                    ),
                    anchorPosition: Offset(10, 10),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('加载中...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}

class _MockDBusMenuClient implements DBusMenuClient {
  const _MockDBusMenuClient({this.mockRoot, this.mockLoading = false});

  final DBusMenuNode? mockRoot;
  final bool mockLoading;
  static final List<int> _clicked = <int>[];
  List<int> get clickedIds => _clicked;

  @override
  String get service => 'mock.service';

  @override
  String get menuPath => '/MenuBar';

  @override
  void Function(DBusMenuNode root)? get onLayoutChanged => null;

  @override
  set onLayoutChanged(void Function(DBusMenuNode root)? value) {}

  @override
  String? get error => null;

  @override
  bool get isLoading => mockLoading;

  @override
  bool get isMenuOpen => true;

  @override
  bool get isDisposed => false;

  @override
  int get revision => 1;

  @override
  DBusMenuNode? get rootNode => mockRoot;

  @override
  void startListening() {}

  @override
  Future<DBusMenuNode?> openMenu() async => mockRoot;

  @override
  Future<DBusMenuNode?> openSubmenu(int parentId) async => mockRoot;

  @override
  Future<bool> aboutToShow(int id) async => false;

  @override
  Future<DBusMenuNode?> getLayout({
    int parentId = 0,
    int recursionDepth = -1,
    List<String> propertyNames = const <String>[],
  }) async => mockRoot ?? const DBusMenuNode(id: 0);

  @override
  Future<void> sendClicked(int id) async {
    _clicked.add(id);
  }

  @override
  Future<void> sendHovered(int id) async {}

  @override
  Future<void> closeMenu() async {}

  @override
  Future<void> dispose() async {}
}
