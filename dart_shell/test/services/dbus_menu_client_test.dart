import 'dart:typed_data';

import 'package:dbus/dbus.dart';
import 'package:denial_dart_shell/src/models/dbus_menu_node.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('stripMnemonic', () {
    test('removes single underscore mnemonic prefixes', () {
      expect(stripMnemonic('_File'), 'File');
      expect(stripMnemonic('Save _As...'), 'Save As...');
      expect(stripMnemonic('E_xit'), 'Exit');
      expect(stripMnemonic('Open _Recent _Files'), 'Open Recent Files');
    });

    test('preserves escaped double underscores as single underscore', () {
      expect(stripMnemonic('Foo__Bar'), 'Foo_Bar');
      expect(stripMnemonic('__Special'), '_Special');
      expect(stripMnemonic('A___B'), 'A_B');
    });

    test('handles empty and clean strings', () {
      expect(stripMnemonic(''), '');
      expect(stripMnemonic('Plain Text'), 'Plain Text');
    });
  });

  group('parseDBusMenuLayout pure parser', () {
    test('parses single layer menu with normal items', () {
      // (0, {}, [ (1, {'label': '_Open', 'enabled': true}, []), (2, {'label': '_Save'}, []) ])
      final layout = DBusStruct([
        DBusInt32(0),
        DBusDict(DBusSignature('s'), DBusSignature('v'), {}),
        DBusArray(DBusSignature('v'), [
          DBusVariant(
            DBusStruct([
              DBusInt32(1),
              DBusDict(DBusSignature('s'), DBusSignature('v'), {
                DBusString('label'): DBusVariant(DBusString('_Open')),
                DBusString('enabled'): DBusVariant(DBusBoolean(true)),
                DBusString('icon-name'): DBusVariant(
                  DBusString('document-open'),
                ),
              }),
              DBusArray(DBusSignature('v'), const []),
            ]),
          ),
          DBusVariant(
            DBusStruct([
              DBusInt32(2),
              DBusDict(DBusSignature('s'), DBusSignature('v'), {
                DBusString('label'): DBusVariant(DBusString('_Save')),
              }),
              DBusArray(DBusSignature('v'), const []),
            ]),
          ),
        ]),
      ]);

      final root = parseDBusMenuLayout(layout);
      expect(root.id, 0);
      expect(root.children.length, 2);

      final item1 = root.children[0];
      expect(item1.id, 1);
      expect(item1.label, '_Open');
      expect(item1.cleanLabel, 'Open');
      expect(item1.displayLabel, 'Open');
      expect(item1.enabled, true);
      expect(item1.visible, true);
      expect(item1.iconName, 'document-open');
      expect(item1.isSeparator, false);
      expect(item1.hasSubmenu, false);

      final item2 = root.children[1];
      expect(item2.id, 2);
      expect(item2.cleanLabel, 'Save');
      expect(item2.enabled, true); // default
      expect(item2.visible, true); // default
    });

    test('recognizes separator items', () {
      final layout = DBusStruct([
        DBusInt32(0),
        DBusDict(DBusSignature('s'), DBusSignature('v'), {}),
        DBusArray(DBusSignature('v'), [
          DBusVariant(
            DBusStruct([
              DBusInt32(10),
              DBusDict(DBusSignature('s'), DBusSignature('v'), {
                DBusString('type'): DBusVariant(DBusString('separator')),
              }),
              DBusArray(DBusSignature('v'), const []),
            ]),
          ),
        ]),
      ]);

      final root = parseDBusMenuLayout(layout);
      expect(root.children.length, 1);
      expect(root.children[0].id, 10);
      expect(root.children[0].isSeparator, true);
      expect(root.children[0].type, 'separator');
    });

    test('parses tri-state toggle items (0 / 1 / -1)', () {
      final layout = DBusStruct([
        DBusInt32(0),
        DBusDict(DBusSignature('s'), DBusSignature('v'), {}),
        DBusArray(DBusSignature('v'), [
          DBusVariant(
            DBusStruct([
              DBusInt32(1),
              DBusDict(DBusSignature('s'), DBusSignature('v'), {
                DBusString('label'): DBusVariant(DBusString('Checked')),
                DBusString('toggle-type'): DBusVariant(DBusString('checkmark')),
                DBusString('toggle-state'): DBusVariant(DBusInt32(1)),
              }),
              DBusArray(DBusSignature('v'), const []),
            ]),
          ),
          DBusVariant(
            DBusStruct([
              DBusInt32(2),
              DBusDict(DBusSignature('s'), DBusSignature('v'), {
                DBusString('label'): DBusVariant(DBusString('Unchecked')),
                DBusString('toggle-type'): DBusVariant(DBusString('checkmark')),
                DBusString('toggle-state'): DBusVariant(DBusInt32(0)),
              }),
              DBusArray(DBusSignature('v'), const []),
            ]),
          ),
          DBusVariant(
            DBusStruct([
              DBusInt32(3),
              DBusDict(DBusSignature('s'), DBusSignature('v'), {
                DBusString('label'): DBusVariant(DBusString('Indeterminate')),
                DBusString('toggle-type'): DBusVariant(DBusString('checkmark')),
                DBusString('toggle-state'): DBusVariant(DBusInt32(-1)),
              }),
              DBusArray(DBusSignature('v'), const []),
            ]),
          ),
        ]),
      ]);

      final root = parseDBusMenuLayout(layout);
      expect(root.children.length, 3);
      expect(root.children[0].toggleType, DBusMenuToggleType.checkmark);
      expect(root.children[0].toggleState, 1);
      expect(root.children[1].toggleType, DBusMenuToggleType.checkmark);
      expect(root.children[1].toggleState, 0);
      expect(root.children[2].toggleType, DBusMenuToggleType.checkmark);
      expect(root.children[2].toggleState, -1);
    });

    test('parses radio button items', () {
      final layout = DBusStruct([
        DBusInt32(0),
        DBusDict(DBusSignature('s'), DBusSignature('v'), {}),
        DBusArray(DBusSignature('v'), [
          DBusVariant(
            DBusStruct([
              DBusInt32(1),
              DBusDict(DBusSignature('s'), DBusSignature('v'), {
                DBusString('label'): DBusVariant(DBusString('Option A')),
                DBusString('toggle-type'): DBusVariant(DBusString('radio')),
                DBusString('toggle-state'): DBusVariant(DBusInt32(1)),
              }),
              DBusArray(DBusSignature('v'), const []),
            ]),
          ),
          DBusVariant(
            DBusStruct([
              DBusInt32(2),
              DBusDict(DBusSignature('s'), DBusSignature('v'), {
                DBusString('label'): DBusVariant(DBusString('Option B')),
                DBusString('toggle-type'): DBusVariant(DBusString('radio')),
                DBusString('toggle-state'): DBusVariant(DBusInt32(0)),
              }),
              DBusArray(DBusSignature('v'), const []),
            ]),
          ),
        ]),
      ]);

      final root = parseDBusMenuLayout(layout);
      expect(root.children[0].toggleType, DBusMenuToggleType.radio);
      expect(root.children[0].toggleState, 1);
      expect(root.children[1].toggleType, DBusMenuToggleType.radio);
      expect(root.children[1].toggleState, 0);
    });

    test('parses disabled and hidden items', () {
      final layout = DBusStruct([
        DBusInt32(0),
        DBusDict(DBusSignature('s'), DBusSignature('v'), {}),
        DBusArray(DBusSignature('v'), [
          DBusVariant(
            DBusStruct([
              DBusInt32(1),
              DBusDict(DBusSignature('s'), DBusSignature('v'), {
                DBusString('label'): DBusVariant(DBusString('Disabled Item')),
                DBusString('enabled'): DBusVariant(DBusBoolean(false)),
              }),
              DBusArray(DBusSignature('v'), const []),
            ]),
          ),
          DBusVariant(
            DBusStruct([
              DBusInt32(2),
              DBusDict(DBusSignature('s'), DBusSignature('v'), {
                DBusString('label'): DBusVariant(DBusString('Hidden Item')),
                DBusString('visible'): DBusVariant(DBusBoolean(false)),
              }),
              DBusArray(DBusSignature('v'), const []),
            ]),
          ),
        ]),
      ]);

      final root = parseDBusMenuLayout(layout);
      expect(root.children[0].enabled, false);
      expect(root.children[0].visible, true);
      expect(root.children[1].enabled, true);
      expect(root.children[1].visible, false);
    });

    test('parses multi-level nested submenus', () {
      final layout = DBusStruct([
        DBusInt32(0),
        DBusDict(DBusSignature('s'), DBusSignature('v'), {}),
        DBusArray(DBusSignature('v'), [
          DBusVariant(
            DBusStruct([
              DBusInt32(1),
              DBusDict(DBusSignature('s'), DBusSignature('v'), {
                DBusString('label'): DBusVariant(DBusString('Level 1 Submenu')),
                DBusString('children-display'): DBusVariant(
                  DBusString('submenu'),
                ),
              }),
              DBusArray(DBusSignature('v'), [
                DBusVariant(
                  DBusStruct([
                    DBusInt32(11),
                    DBusDict(DBusSignature('s'), DBusSignature('v'), {
                      DBusString('label'): DBusVariant(
                        DBusString('Level 2 Submenu'),
                      ),
                      DBusString('children-display'): DBusVariant(
                        DBusString('submenu'),
                      ),
                    }),
                    DBusArray(DBusSignature('v'), [
                      DBusVariant(
                        DBusStruct([
                          DBusInt32(111),
                          DBusDict(DBusSignature('s'), DBusSignature('v'), {
                            DBusString('label'): DBusVariant(
                              DBusString('Deep Leaf'),
                            ),
                          }),
                          DBusArray(DBusSignature('v'), const []),
                        ]),
                      ),
                    ]),
                  ]),
                ),
              ]),
            ]),
          ),
        ]),
      ]);

      final root = parseDBusMenuLayout(layout);
      expect(root.children.length, 1);
      final l1 = root.children[0];
      expect(l1.id, 1);
      expect(l1.hasSubmenu, true);
      expect(l1.children.length, 1);

      final l2 = l1.children[0];
      expect(l2.id, 11);
      expect(l2.hasSubmenu, true);
      expect(l2.children.length, 1);

      final leaf = l2.children[0];
      expect(leaf.id, 111);
      expect(leaf.cleanLabel, 'Deep Leaf');
      expect(leaf.hasSubmenu, false);
      expect(leaf.children, isEmpty);

      // Verify recursive lookup
      expect(root.findNode(111), leaf);
      expect(root.findNode(999), isNull);
    });

    test('parses icon-data raw byte array correctly', () {
      final pngBytes = Uint8List.fromList([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG magic
      ]);

      final layout = DBusStruct([
        DBusInt32(0),
        DBusDict(DBusSignature('s'), DBusSignature('v'), {}),
        DBusArray(DBusSignature('v'), [
          DBusVariant(
            DBusStruct([
              DBusInt32(1),
              DBusDict(DBusSignature('s'), DBusSignature('v'), {
                DBusString('label'): DBusVariant(DBusString('PNG Icon Item')),
                DBusString('icon-data'): DBusVariant(
                  DBusArray(
                    DBusSignature('y'),
                    pngBytes.map((b) => DBusByte(b)).toList(),
                  ),
                ),
              }),
              DBusArray(DBusSignature('v'), const []),
            ]),
          ),
        ]),
      ]);

      final root = parseDBusMenuLayout(layout);
      final item = root.children[0];
      expect(item.iconData, isNotNull);
      expect(item.iconData!.length, 8);
      expect(item.iconData![0], 0x89);
      expect(item.iconData![1], 0x50);
    });

    test('parses shortcuts correctly', () {
      // shortcut: aas -> [['Control', 'Shift'], 'N']
      final layout = DBusStruct([
        DBusInt32(0),
        DBusDict(DBusSignature('s'), DBusSignature('v'), {}),
        DBusArray(DBusSignature('v'), [
          DBusVariant(
            DBusStruct([
              DBusInt32(1),
              DBusDict(DBusSignature('s'), DBusSignature('v'), {
                DBusString('label'): DBusVariant(DBusString('New Window')),
                DBusString('shortcut'): DBusVariant(
                  DBusArray(DBusSignature('as'), [
                    DBusArray(DBusSignature('s'), [
                      DBusString('Control'),
                      DBusString('Shift'),
                      DBusString('N'),
                    ]),
                  ]),
                ),
              }),
              DBusArray(DBusSignature('v'), const []),
            ]),
          ),
        ]),
      ]);

      final root = parseDBusMenuLayout(layout);
      final item = root.children[0];
      expect(item.shortcut.length, 1);
      expect(item.shortcut[0], ['Control', 'Shift', 'N']);
      expect(item.formattedShortcut, 'Control+Shift+N');
    });

    test('handles malformed inputs and cycles safely', () {
      // 1. Completely wrong DBusValue type
      final wrongVal = DBusString('not a struct');
      final fallback = parseDBusMenuLayout(wrongVal);
      expect(fallback.id, 0);
      expect(fallback.children, isEmpty);

      // 2. Struct with insufficient children
      final truncatedStruct = DBusStruct([DBusInt32(0)]);
      final fallback2 = parseDBusMenuLayout(truncatedStruct);
      expect(fallback2.id, 0);
      expect(fallback2.children, isEmpty);

      // 3. Circular self-referencing structure
      // Wrap in child array to simulate loop
      final loopStruct = DBusStruct([
        DBusInt32(1),
        DBusDict(DBusSignature('s'), DBusSignature('v'), {
          DBusString('label'): DBusVariant(DBusString('Root 1')),
        }),
        DBusArray(DBusSignature('v'), [
          DBusVariant(
            DBusStruct([
              DBusInt32(1), // Same ID in recursion path
              DBusDict(DBusSignature('s'), DBusSignature('v'), {
                DBusString('label'): DBusVariant(DBusString('Child 1')),
              }),
              DBusArray(DBusSignature('v'), const []),
            ]),
          ),
        ]),
      ]);

      final looped = parseDBusMenuLayout(loopStruct);
      expect(looped.id, 1);
      expect(looped.children.length, 1);
      // Child had ID 1 which was already in visitedIds, so recursion was capped (0 children)
      expect(looped.children[0].children, isEmpty);
    });

    test('updateProperties updates a target node immutably', () {
      final initialLayout = DBusStruct([
        DBusInt32(0),
        DBusDict(DBusSignature('s'), DBusSignature('v'), {}),
        DBusArray(DBusSignature('v'), [
          DBusVariant(
            DBusStruct([
              DBusInt32(5),
              DBusDict(DBusSignature('s'), DBusSignature('v'), {
                DBusString('label'): DBusVariant(
                  DBusString('Last Sync: 10:00'),
                ),
                DBusString('enabled'): DBusVariant(DBusBoolean(true)),
              }),
              DBusArray(DBusSignature('v'), const []),
            ]),
          ),
          DBusVariant(
            DBusStruct([
              DBusInt32(6),
              DBusDict(DBusSignature('s'), DBusSignature('v'), {
                DBusString('label'): DBusVariant(DBusString('Pause')),
              }),
              DBusArray(DBusSignature('v'), const []),
            ]),
          ),
        ]),
      ]);

      final root = parseDBusMenuLayout(initialLayout);
      expect(root.findNode(5)?.cleanLabel, 'Last Sync: 10:00');

      // Update node 5 properties
      final updated = root.updateProperties(5, {
        'label': DBusString('Last Sync: 10:05'),
        'enabled': DBusBoolean(false),
      });

      // Original is unchanged
      expect(root.findNode(5)?.cleanLabel, 'Last Sync: 10:00');
      expect(root.findNode(5)?.enabled, true);

      // Updated has new values
      expect(updated.findNode(5)?.cleanLabel, 'Last Sync: 10:05');
      expect(updated.findNode(5)?.enabled, false);
      expect(updated.findNode(6)?.cleanLabel, 'Pause');
    });
  });
}
