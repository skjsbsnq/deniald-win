import 'dart:convert';

import '../../launcher/models/desktop_app.dart';
import '../../launcher/models/home_grid_item.dart';
import '../../launcher/runtime_paths.dart';
import '../models/desktop_tile.dart';

/// Reads and writes the desktop start menu's pin board.
///
/// Unlike the mobile home screen's repository this one actually inspects
/// `version`: that field is written there but never read, so a future schema
/// change would be decoded as if it were the current one. Here an unknown
/// version discards the document and the board starts empty, because guessing
/// at the shape of a layout written by a newer shell is how a board ends up
/// half-migrated.
class DesktopTileRepository {
  const DesktopTileRepository({required this._paths});

  static const int schemaVersion = 1;
  static const String appIdPrefix = 'app:';
  static const String localAppIdPrefix = 'local:';

  final RuntimePaths _paths;

  /// The saved groups, or null when there is nothing usable to restore.
  ///
  /// Every failure — missing file, unreadable file, malformed JSON, unknown
  /// version — answers null rather than throwing, so a corrupt board degrades
  /// to an empty one instead of taking the start menu down with it.
  Future<List<DesktopTileGroupLayout>?> readSavedLayout() async {
    try {
      final file = await _paths.desktopTilesFile();
      if (!await file.exists()) {
        return null;
      }

      final content = await file.readAsString();
      if (content.trim().isEmpty) {
        return null;
      }

      final decoded = jsonDecode(content);
      if (decoded is! Map<String, Object?>) {
        return null;
      }
      if (decoded['version'] != schemaVersion) {
        return null;
      }

      final rawGroups = decoded['groups'];
      if (rawGroups is! List) {
        return null;
      }

      return <DesktopTileGroupLayout>[
        for (final group in rawGroups) ?_decodeGroup(group),
      ];
    } on Object {
      return null;
    }
  }

  Future<void> saveLayout(List<DesktopTileGroup> groups) async {
    try {
      final file = await _paths.desktopTilesFile();
      final payload = jsonEncode({
        'version': schemaVersion,
        'groups': <Object?>[
          for (final group in groups)
            <String, Object?>{
              'name': group.name,
              'slots': group.slots.map(_encodeSlot).toList(growable: false),
            },
        ],
      });
      await file.writeAsString('$payload\n', flush: true);
    } on Object {
      // Persistence is best effort; the in-memory board remains valid.
    }
  }

  /// The name to show when a slot names no application, which only happens in
  /// a hand-written file. `firefox.desktop` reads better than nothing at all.
  static String displayNameForId(String slotId) {
    var name = slotId;
    for (final prefix in const <String>[appIdPrefix, localAppIdPrefix]) {
      if (name.startsWith(prefix)) {
        name = name.substring(prefix.length);
        break;
      }
    }
    const suffix = '.desktop';
    if (name.length > suffix.length && name.endsWith(suffix)) {
      name = name.substring(0, name.length - suffix.length);
    }
    return name;
  }

  DesktopTileGroupLayout? _decodeGroup(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final slots = raw['slots'];
    if (slots is! List) {
      return null;
    }
    final name = raw['name'];
    return DesktopTileGroupLayout(
      name: name is String ? name : '',
      slots: slots.map(_decodeSlot).toList(growable: false),
    );
  }

  DesktopTileSlot? _decodeSlot(Object? raw) {
    if (raw is String && raw.isNotEmpty) {
      return DesktopTileSlot(
        id: raw,
        app: _decodeApp(raw, const <Object?, Object?>{}),
      );
    }

    if (raw is Map) {
      final id = raw['id'];
      if (id is! String || id.isEmpty) {
        return null;
      }
      final colSpan = raw['colSpan'];
      final rowSpan = raw['rowSpan'];
      return DesktopTileSlot(
        id: id,
        colSpan: colSpan is int
            ? colSpan.clamp(
                HomeGridItem.pinnedMinColSpan,
                HomeGridItem.pinnedMaxColSpan,
              )
            : null,
        rowSpan: rowSpan is int
            ? rowSpan.clamp(
                HomeGridItem.pinnedMinRowSpan,
                HomeGridItem.pinnedMaxRowSpan,
              )
            : null,
        app: _decodeApp(id, raw),
      );
    }

    return null;
  }

  DesktopApp? _decodeApp(String slotId, Map<Object?, Object?> raw) {
    if (!slotId.startsWith(appIdPrefix)) {
      return null;
    }
    final appId = slotId.substring(appIdPrefix.length);
    if (appId.isEmpty) {
      return null;
    }

    String? text(String key) {
      final value = raw[key];
      return value is String && value.isNotEmpty ? value : null;
    }

    return DesktopApp(
      id: appId,
      name: text('name') ?? displayNameForId(slotId),
      exec: text('exec') ?? '',
      desktopPath: text('desktopPath') ?? '',
      categories: const <String>[],
      icon: text('icon'),
      iconPath: text('iconPath'),
      startupWmClass: text('startupWmClass'),
    );
  }

  Object? _encodeSlot(HomeGridItem? item) {
    if (item == null) {
      return null;
    }

    final payload = <String, Object?>{
      'id': item.id,
      'colSpan': item.colSpan,
      'rowSpan': item.rowSpan,
    };
    if (item.app case final app?) {
      payload['name'] = app.name;
      payload['exec'] = app.exec;
      payload['desktopPath'] = app.desktopPath;
      if (app.icon case final icon?) {
        payload['icon'] = icon;
      }
      if (app.iconPath case final iconPath?) {
        payload['iconPath'] = iconPath;
      }
      if (app.startupWmClass case final wmClass?) {
        payload['startupWmClass'] = wmClass;
      }
    }
    return payload;
  }
}
