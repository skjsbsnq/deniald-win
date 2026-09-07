import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/todo_service.dart';

final todoListProvider = NotifierProvider<TodoListController, List<TodoItem>>(
  TodoListController.new,
  isAutoDispose: true,
);

/// In-memory todo state machine with serialized writes to the XDG state
/// store, mirroring the pinned-apps save queue so rapid toggles never race
/// each other on disk.
class TodoListController extends Notifier<List<TodoItem>> {
  bool _disposed = false;
  Future<void> _saveQueue = Future<void>.value();
  int _nextId = 1;

  @override
  List<TodoItem> build() {
    _disposed = false;
    _nextId = 1;
    final store = ref.watch(todoStoreProvider);
    unawaited(_load(store));
    ref.onDispose(() => _disposed = true);
    return const <TodoItem>[];
  }

  Future<void> _load(TodoStore store) async {
    final saved = await store.read();
    if (_disposed) {
      return;
    }
    for (final item in saved) {
      if (item.id >= _nextId) {
        _nextId = item.id + 1;
      }
    }
    state = saved;
  }

  void add(String title) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final next = <TodoItem>[...state, TodoItem(id: _nextId++, title: trimmed)];
    state = next;
    _queueSave(next);
  }

  void toggle(int id) {
    final next = <TodoItem>[
      for (final item in state)
        item.id == id ? item.copyWith(done: !item.done) : item,
    ];
    state = next;
    _queueSave(next);
  }

  void remove(int id) {
    final next = state.where((item) => item.id != id).toList(growable: false);
    if (next.length == state.length) {
      return;
    }
    state = next;
    _queueSave(next);
  }

  void clearCompleted() {
    final next = state.where((item) => !item.done).toList(growable: false);
    if (next.length == state.length) {
      return;
    }
    state = next;
    _queueSave(next);
  }

  void _queueSave(List<TodoItem> items) {
    final store = ref.read(todoStoreProvider);
    _saveQueue = _saveQueue.then((_) => store.write(items));
  }
}
