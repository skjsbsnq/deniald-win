import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../launcher/launcher_providers.dart';
import '../launcher/runtime_paths.dart';

final todoStoreProvider = Provider<TodoStore>((ref) {
  return TodoRepository(paths: ref.watch(runtimePathsProvider));
}, isAutoDispose: true);

/// One persisted task. Stable ids let the UI toggle completion without
/// rebuilding the whole list.
@immutable
class TodoItem {
  const TodoItem({required this.id, required this.title, this.done = false});

  final int id;
  final String title;
  final bool done;

  TodoItem copyWith({String? title, bool? done}) {
    return TodoItem(
      id: id,
      title: title ?? this.title,
      done: done ?? this.done,
    );
  }

  Map<String, Object> toJson() {
    return <String, Object>{'id': id, 'title': title, 'done': done};
  }

  static TodoItem? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final map = raw.cast<Object?, Object?>();
    final id = map['id'];
    final title = map['title'];
    if (id is! int || title is! String || title.trim().isEmpty) {
      return null;
    }
    return TodoItem(id: id, title: title, done: map['done'] == true);
  }
}

abstract interface class TodoStore {
  Future<List<TodoItem>> read();

  Future<void> write(List<TodoItem> items);
}

/// Persists the dashboard todo list to XDG state, mirroring the atomic
/// write-then-rename pattern used by the notification policy store.
class TodoRepository implements TodoStore {
  const TodoRepository({required this.paths});

  final RuntimePaths paths;

  @override
  Future<List<TodoItem>> read() async {
    try {
      final file = await _file();
      if (!await file.exists()) {
        return const <TodoItem>[];
      }
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) {
        return const <TodoItem>[];
      }
      final list = decoded['items'];
      if (list is! List) {
        return const <TodoItem>[];
      }
      return list
          .map(TodoItem.fromJson)
          .whereType<TodoItem>()
          .toList(growable: false);
    } on Object {
      return const <TodoItem>[];
    }
  }

  @override
  Future<void> write(List<TodoItem> items) async {
    try {
      final file = await _file();
      final temporary = File('${file.path}.tmp');
      final payload = jsonEncode(<String, Object>{
        'version': 1,
        'items': [for (final item in items) item.toJson()],
      });
      await temporary.writeAsString('$payload\n', flush: true);
      await temporary.rename(file.path);
    } on Object {
      // Best-effort persistence: the in-memory list stays authoritative for
      // this session even when the disk write fails.
    }
  }

  Future<File> _file() async {
    final dir = Directory(p.join(paths.stateHome, 'denial'));
    await dir.create(recursive: true);
    return File(p.join(dir.path, 'todo.json'));
  }
}
