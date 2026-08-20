import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';

const int maxDBusMenuDepth = 16;
const int maxDBusMenuNodes = 1024;
const int maxDBusMenuChildren = 256;
const int maxDBusMenuProperties = 128;
const int maxDBusMenuStringLength = 4096;
const int maxDBusMenuIconBytes = 1024 * 1024;

/// Toggle behavior of a DBusMenu item.
enum DBusMenuToggleType {
  none,
  checkmark,
  radio;

  static DBusMenuToggleType fromString(String? raw) {
    switch (raw?.trim().toLowerCase()) {
      case 'checkmark':
        return DBusMenuToggleType.checkmark;
      case 'radio':
        return DBusMenuToggleType.radio;
      default:
        return DBusMenuToggleType.none;
    }
  }
}

/// Visual disposition of a DBusMenu item.
enum DBusMenuDisposition {
  normal,
  informative,
  warning,
  alert;

  static DBusMenuDisposition fromString(String? raw) {
    switch (raw?.trim().toLowerCase()) {
      case 'informative':
        return DBusMenuDisposition.informative;
      case 'warning':
        return DBusMenuDisposition.warning;
      case 'alert':
        return DBusMenuDisposition.alert;
      case 'normal':
      default:
        return DBusMenuDisposition.normal;
    }
  }
}

/// Strips single mnemonic underscore prefixes while preserving escaped double underscores.
///
/// Example:
/// - `_File` -> `File`
/// - `Save _As...` -> `Save As...`
/// - `Foo__Bar` -> `Foo_Bar`
/// - `___Three` -> `_Three`
String stripMnemonic(String label) {
  if (label.isEmpty) return '';
  final buffer = StringBuffer();
  for (int i = 0; i < label.length; i++) {
    if (label[i] == '_') {
      if (i + 1 < label.length && label[i + 1] == '_') {
        buffer.write('_');
        i++; // skip the escaped underscore
      } else {
        // Single mnemonic indicator, omit it
      }
    } else {
      buffer.write(label[i]);
    }
  }
  return buffer.toString();
}

/// An immutable node in a DBusMenu hierarchy.
@immutable
class DBusMenuNode {
  const DBusMenuNode({
    required this.id,
    this.type = 'standard',
    this.label = '',
    this.cleanLabel = '',
    this.enabled = true,
    this.visible = true,
    this.iconName = '',
    this.iconData,
    this.toggleType = DBusMenuToggleType.none,
    this.toggleState = 0,
    this.childrenDisplay = '',
    this.disposition = DBusMenuDisposition.normal,
    this.shortcut = const <List<String>>[],
    this.accessibleDesc = '',
    this.children = const <DBusMenuNode>[],
    this.rawProperties = const <String, DBusValue>{},
  });

  /// Menu item ID (0 is typically the root layout container).
  final int id;

  /// Item type: `'standard'` or `'separator'`.
  final String type;

  /// Raw label string (may contain mnemonic `_`).
  final String label;

  /// Clean display label with mnemonics stripped.
  final String cleanLabel;

  /// Whether this item is enabled/interactable (default `true`).
  final bool enabled;

  /// Whether this item is visible (default `true`).
  final bool visible;

  /// Icon name from the current icon theme.
  final String iconName;

  /// Raw PNG image bytes (if provided by `icon-data`).
  final Uint8List? iconData;

  /// Toggle mode: checkmark, radio, or none.
  final DBusMenuToggleType toggleType;

  /// Toggle state: 1 (checked), 0 (unchecked), -1 (indeterminate/partial).
  final int toggleState;

  /// `'submenu'` if this item has children that should be shown as a sub-menu.
  final String childrenDisplay;

  /// Visual severity or disposition style.
  final DBusMenuDisposition disposition;

  /// Shortcut key sequences, e.g. `[['Control', 'Shift'], 'N']`.
  final List<List<String>> shortcut;

  /// Accessible description text.
  final String accessibleDesc;

  /// Child menu items.
  final List<DBusMenuNode> children;

  /// Original raw property map for custom extension inspection.
  final Map<String, DBusValue> rawProperties;

  /// Returns `true` if this item acts as a visual divider/separator.
  bool get isSeparator => type.toLowerCase() == 'separator';

  /// Returns `true` if this item has child nodes or requests submenu display.
  bool get hasSubmenu =>
      childrenDisplay.toLowerCase() == 'submenu' || children.isNotEmpty;

  /// Returns the preferred display text.
  String get displayLabel =>
      cleanLabel.isNotEmpty ? cleanLabel : (label.isNotEmpty ? label : '');

  /// Returns a human-friendly string formatted representation of the primary shortcut (if any).
  String? get formattedShortcut {
    if (shortcut.isEmpty) return null;
    final primary = shortcut.first;
    if (primary.isEmpty) return null;
    return primary.join('+');
  }

  /// Recursively finds a node by its [targetId].
  DBusMenuNode? findNode(int targetId) {
    if (id == targetId) return this;
    for (final child in children) {
      final found = child.findNode(targetId);
      if (found != null) return found;
    }
    return null;
  }

  /// Collects this node's ID and all descendant node IDs recursively.
  Set<int> collectAllNodeIds() {
    final ids = <int>{id};
    for (final child in children) {
      ids.addAll(child.collectAllNodeIds());
    }
    return ids;
  }

  /// Returns a new tree with the node matching [targetId] updated with [updatedProps] and [removedProps].
  DBusMenuNode updateProperties(
    int targetId,
    Map<String, DBusValue> updatedProps, [
    List<String>? removedProps,
  ]) {
    if (id == targetId) {
      final mergedProps = Map<String, DBusValue>.from(rawProperties);
      if (removedProps != null) {
        for (final key in removedProps) {
          mergedProps.remove(key);
        }
      }
      mergedProps.addAll(updatedProps);
      return parseSingleNodeProperties(id, mergedProps, children);
    }

    bool anyChildChanged = false;
    final updatedChildren = <DBusMenuNode>[];
    for (final child in children) {
      final updatedChild = child.updateProperties(
        targetId,
        updatedProps,
        removedProps,
      );
      if (!identical(updatedChild, child)) {
        anyChildChanged = true;
      }
      updatedChildren.add(updatedChild);
    }

    if (!anyChildChanged) return this;

    return copyWith(children: updatedChildren);
  }

  /// Returns a new tree with the subtree of [parentId] replaced by [newChildren].
  DBusMenuNode updateSubtree(int parentId, List<DBusMenuNode> newChildren) {
    if (id == parentId) {
      return copyWith(children: newChildren);
    }

    bool anyChildChanged = false;
    final updatedChildren = <DBusMenuNode>[];
    for (final child in children) {
      final updatedChild = child.updateSubtree(parentId, newChildren);
      if (!identical(updatedChild, child)) {
        anyChildChanged = true;
      }
      updatedChildren.add(updatedChild);
    }

    if (!anyChildChanged) return this;

    return copyWith(children: updatedChildren);
  }

  DBusMenuNode copyWith({
    int? id,
    String? type,
    String? label,
    String? cleanLabel,
    bool? enabled,
    bool? visible,
    String? iconName,
    Uint8List? iconData,
    DBusMenuToggleType? toggleType,
    int? toggleState,
    String? childrenDisplay,
    DBusMenuDisposition? disposition,
    List<List<String>>? shortcut,
    String? accessibleDesc,
    List<DBusMenuNode>? children,
    Map<String, DBusValue>? rawProperties,
  }) {
    return DBusMenuNode(
      id: id ?? this.id,
      type: type ?? this.type,
      label: label ?? this.label,
      cleanLabel: cleanLabel ?? this.cleanLabel,
      enabled: enabled ?? this.enabled,
      visible: visible ?? this.visible,
      iconName: iconName ?? this.iconName,
      iconData: iconData ?? this.iconData,
      toggleType: toggleType ?? this.toggleType,
      toggleState: toggleState ?? this.toggleState,
      childrenDisplay: childrenDisplay ?? this.childrenDisplay,
      disposition: disposition ?? this.disposition,
      shortcut: shortcut ?? this.shortcut,
      accessibleDesc: accessibleDesc ?? this.accessibleDesc,
      children: children ?? this.children,
      rawProperties: rawProperties ?? this.rawProperties,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DBusMenuNode &&
        other.id == id &&
        other.type == type &&
        other.label == label &&
        other.cleanLabel == cleanLabel &&
        other.enabled == enabled &&
        other.visible == visible &&
        other.iconName == iconName &&
        _byteArraysEqual(other.iconData, iconData) &&
        other.toggleType == toggleType &&
        other.toggleState == toggleState &&
        other.childrenDisplay == childrenDisplay &&
        other.disposition == disposition &&
        other.accessibleDesc == accessibleDesc &&
        listEquals(other.children, children);
  }

  @override
  int get hashCode => Object.hash(
    id,
    type,
    label,
    cleanLabel,
    enabled,
    visible,
    iconName,
    iconData != null ? Object.hashAll(iconData!) : null,
    toggleType,
    toggleState,
    childrenDisplay,
    disposition,
    accessibleDesc,
    Object.hashAll(children),
  );

  @override
  String toString() =>
      'DBusMenuNode(id: $id, label: "$displayLabel", type: $type, children: ${children.length})';
}

bool _byteArraysEqual(Uint8List? a, Uint8List? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  return listEquals(a, b);
}

/// Parses properties for a single node without recursing down children.
DBusMenuNode parseSingleNodeProperties(
  int id,
  Map<String, DBusValue> props,
  List<DBusMenuNode> children,
) {
  final type = _asString(props['type'], fallback: 'standard');
  final rawLabel = _asString(props['label']);
  final cleanLabel = stripMnemonic(rawLabel);
  final enabled = _asBool(props['enabled'], fallback: true);
  final visible = _asBool(props['visible'], fallback: true);
  final iconName = _asString(props['icon-name']);
  final iconData = _asByteArray(props['icon-data']);
  final toggleType = DBusMenuToggleType.fromString(
    _asString(props['toggle-type']),
  );
  final toggleState = _asInt(props['toggle-state'], fallback: 0);
  final childrenDisplay = _asString(props['children-display']);
  final disposition = DBusMenuDisposition.fromString(
    _asString(props['disposition']),
  );
  final accessibleDesc = _asString(props['accessible-desc']);
  final shortcut = _parseShortcut(props['shortcut']);

  return DBusMenuNode(
    id: id,
    type: type,
    label: rawLabel,
    cleanLabel: cleanLabel,
    enabled: enabled,
    visible: visible,
    iconName: iconName,
    iconData: iconData,
    toggleType: toggleType,
    toggleState: toggleState,
    childrenDisplay: childrenDisplay,
    disposition: disposition,
    shortcut: shortcut,
    accessibleDesc: accessibleDesc,
    children: children,
    rawProperties: props,
  );
}

/// Pure function to parse a raw D-Bus layout `DBusValue` into an immutable [DBusMenuNode] tree.
///
/// Features:
/// - Strips single underscore mnemonics (e.g. `_File` -> `File`, `__` -> `_`).
/// - Defaults missing properties (`enabled: true`, `visible: true`, `type: 'standard'`).
/// - Handles PNG `icon-data` byte arrays.
/// - Cycle detection and recursion depth capping (default max 16 levels) to prevent stack overflows.
/// - Resilient to malformed inputs (non-struct, type mismatches, missing fields).
DBusMenuNode parseDBusMenuLayout(
  DBusValue layout, {
  int maxDepth = maxDBusMenuDepth,
  Set<int>? visitedIds,
}) {
  final state = _DBusMenuParseState(maxDepth: maxDepth, initialIds: visitedIds);
  return _parseDBusMenuLayoutNode(layout, state, 0) ??
      const DBusMenuNode(id: 0);
}

class _DBusMenuParseState {
  _DBusMenuParseState({required int maxDepth, Set<int>? initialIds})
    : maxDepth = maxDepth.clamp(1, maxDBusMenuDepth).toInt(),
      seenIds = <int>{...?initialIds};

  final int maxDepth;
  final Set<int> seenIds;
  final Set<int> pathIds = <int>{};
  int nodeCount = 0;
}

DBusMenuNode? _parseDBusMenuLayoutNode(
  DBusValue layout,
  _DBusMenuParseState state,
  int depth,
) {
  DBusValue unwrapped = layout;
  while (unwrapped is DBusVariant) {
    unwrapped = unwrapped.value;
  }

  if (unwrapped is! DBusStruct || unwrapped.children.length < 3) {
    return null;
  }

  final id = _asInt(unwrapped.children[0]);
  final propsMap = _parsePropertiesDict(unwrapped.children[1]);

  if (state.pathIds.contains(id)) {
    // Preserve the visible node but refuse to recurse through a cycle.
    return parseSingleNodeProperties(id, propsMap, const <DBusMenuNode>[]);
  }
  if (state.seenIds.contains(id) || state.nodeCount >= maxDBusMenuNodes) {
    // A repeated ID is not a second menu item. Dropping it prevents ambiguous
    // updates and bounds the amount of retained tree state.
    return null;
  }

  state.seenIds.add(id);
  state.pathIds.add(id);
  state.nodeCount += 1;

  final parsedChildren = <DBusMenuNode>[];
  final rawChildren = unwrapped.children[2];

  if (depth < state.maxDepth && rawChildren is DBusArray) {
    final childCount = rawChildren.children.length
        .clamp(0, maxDBusMenuChildren)
        .toInt();
    for (var index = 0; index < childCount; index += 1) {
      final childVal = rawChildren.children[index];
      DBusValue unwrappedChild = childVal;
      while (unwrappedChild is DBusVariant) {
        unwrappedChild = unwrappedChild.value;
      }
      if (unwrappedChild is DBusStruct) {
        final childNode = _parseDBusMenuLayoutNode(
          unwrappedChild,
          state,
          depth + 1,
        );
        if (childNode != null) parsedChildren.add(childNode);
      }
    }
  }

  state.pathIds.remove(id);
  return parseSingleNodeProperties(
    id,
    propsMap,
    List<DBusMenuNode>.unmodifiable(parsedChildren),
  );
}

Map<String, DBusValue> _parsePropertiesDict(DBusValue dictVal) {
  DBusValue unwrapped = dictVal;
  while (unwrapped is DBusVariant) {
    unwrapped = unwrapped.value;
  }

  final result = <String, DBusValue>{};

  if (unwrapped is DBusDict) {
    var count = 0;
    unwrapped.children.forEach((k, v) {
      if (count >= maxDBusMenuProperties) return;
      if (k is DBusString) {
        DBusValue val = v;
        while (val is DBusVariant) {
          val = val.value;
        }
        final bounded = _boundPropertyValue(val);
        if (bounded != null) {
          result[k.value] = bounded;
          count += 1;
        }
      }
    });
  } else if (unwrapped is DBusArray) {
    var count = 0;
    for (final elem in unwrapped.children) {
      if (count >= maxDBusMenuProperties) break;
      DBusValue unwrappedElem = elem;
      while (unwrappedElem is DBusVariant) {
        unwrappedElem = unwrappedElem.value;
      }
      if (unwrappedElem is DBusDict) {
        unwrappedElem.children.forEach((k, v) {
          if (k is DBusString) {
            DBusValue val = v;
            while (val is DBusVariant) {
              val = val.value;
            }
            final bounded = _boundPropertyValue(val);
            if (bounded != null) {
              result[k.value] = bounded;
              count += 1;
            }
          }
        });
      } else if (unwrappedElem is DBusStruct &&
          unwrappedElem.children.length >= 2) {
        final k = unwrappedElem.children[0];
        final v = unwrappedElem.children[1];
        if (k is DBusString) {
          DBusValue val = v;
          while (val is DBusVariant) {
            val = val.value;
          }
          final bounded = _boundPropertyValue(val);
          if (bounded != null) {
            result[k.value] = bounded;
            count += 1;
          }
        }
      }
    }
  }

  return result;
}

List<List<String>> _parseShortcut(DBusValue? value) {
  if (value == null) return const <List<String>>[];
  DBusValue unwrapped = value;
  while (unwrapped is DBusVariant) {
    unwrapped = unwrapped.value;
  }

  if (unwrapped is! DBusArray) return const <List<String>>[];

  final result = <List<String>>[];
  for (final combo in unwrapped.children.take(maxDBusMenuChildren)) {
    DBusValue unwrappedCombo = combo;
    while (unwrappedCombo is DBusVariant) {
      unwrappedCombo = unwrappedCombo.value;
    }
    if (unwrappedCombo is DBusArray) {
      final keys = <String>[];
      for (final key in unwrappedCombo.children.take(maxDBusMenuChildren)) {
        final keyStr = _asString(key);
        if (keyStr.isNotEmpty) {
          keys.add(keyStr);
        }
      }
      if (keys.isNotEmpty) {
        result.add(keys);
      }
    }
  }
  return result;
}

String _asString(DBusValue? value, {String fallback = ''}) {
  if (value == null) return fallback;
  DBusValue unwrapped = value;
  while (unwrapped is DBusVariant) {
    unwrapped = unwrapped.value;
  }
  if (unwrapped is DBusString) {
    return unwrapped.value.length <= maxDBusMenuStringLength
        ? unwrapped.value
        : unwrapped.value.substring(0, maxDBusMenuStringLength);
  }
  return fallback;
}

int _asInt(DBusValue? value, {int fallback = 0}) {
  if (value == null) return fallback;
  DBusValue unwrapped = value;
  while (unwrapped is DBusVariant) {
    unwrapped = unwrapped.value;
  }
  if (unwrapped is DBusInt32) return unwrapped.value;
  if (unwrapped is DBusInt16) return unwrapped.value;
  if (unwrapped is DBusInt64) return unwrapped.value;
  if (unwrapped is DBusUint32) return unwrapped.value;
  if (unwrapped is DBusUint16) return unwrapped.value;
  if (unwrapped is DBusUint64) return unwrapped.value;
  if (unwrapped is DBusByte) return unwrapped.value;
  return fallback;
}

bool _asBool(DBusValue? value, {bool fallback = false}) {
  if (value == null) return fallback;
  DBusValue unwrapped = value;
  while (unwrapped is DBusVariant) {
    unwrapped = unwrapped.value;
  }
  if (unwrapped is DBusBoolean) return unwrapped.value;
  return fallback;
}

Uint8List? _asByteArray(DBusValue? value) {
  if (value == null) return null;
  DBusValue unwrapped = value;
  while (unwrapped is DBusVariant) {
    unwrapped = unwrapped.value;
  }
  if (unwrapped is DBusArray) {
    if (unwrapped.children.length > maxDBusMenuIconBytes) return null;
    final bytes = <int>[];
    for (final elem in unwrapped.children) {
      if (elem is DBusByte) {
        bytes.add(elem.value);
      } else if (elem is DBusInt32 || elem is DBusUint32) {
        bytes.add(_asInt(elem) & 0xFF);
      } else {
        return null;
      }
    }
    return Uint8List.fromList(bytes);
  }
  return null;
}

DBusValue? _boundPropertyValue(DBusValue value) {
  if (value is DBusString) {
    if (value.value.length <= maxDBusMenuStringLength) return value;
    return DBusString(value.value.substring(0, maxDBusMenuStringLength));
  }
  if (value is DBusArray && value.children.length > maxDBusMenuIconBytes) {
    return null;
  }
  return value;
}
