import 'dart:async';

import 'package:denial_dart_shell/src/services/todo_service.dart';
import 'package:denial_dart_shell/src/state/todo_list.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A [TodoStore] whose [read] completes only when the test releases it, so
/// mutations can be issued while the cold-disk load is still in flight.
class _GatedTodoStore implements TodoStore {
  _GatedTodoStore(this.items);

  List<TodoItem> items;
  final Completer<List<TodoItem>> _readGate =
      Completer<List<TodoItem>>();

  @override
  Future<List<TodoItem>> read() => _readGate.future;

  /// Releases the pending read with the given disk contents.
  void releaseRead(List<TodoItem> saved) {
    items = List<TodoItem>.unmodifiable(saved);
    _readGate.complete(items);
  }

  @override
  Future<void> write(List<TodoItem> newItems) async {
    items = List<TodoItem>.unmodifiable(newItems);
  }
}

void main() {
  test('a mutation issued while the load is in flight survives it', () async {
    final store = _GatedTodoStore(const <TodoItem>[]);
    final container = ProviderContainer(
      overrides: [todoStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    // The provider is autoDispose; a listener keeps it (and the controller
    // instance under test) mounted across the awaited reads below.
    final subscription = container.listen(
      todoListProvider,
      (_, _) {},
    );
    addTearDown(subscription.close);

    // The dashboard opens, the cold-disk read starts, and the user adds a
    // task before the read lands.
    final controller = container.read(todoListProvider.notifier);
    controller.add('Ship task 11.2');

    store.releaseRead(const <TodoItem>[
      TodoItem(id: 1, title: 'Stale disk item'),
    ]);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final state = container.read(todoListProvider);
    expect(state, hasLength(1));
    expect(state.single.title, 'Ship task 11.2');
    // The merged result is written back: the disk no longer holds the stale
    // pre-mutation contents.
    expect(store.items.single.title, 'Ship task 11.2');
  });

  test('a load that lands before any mutation adopts the saved state', () async {
    final saved = const <TodoItem>[
      TodoItem(id: 2, title: 'Persisted', done: true),
      TodoItem(id: 5, title: 'Open'),
    ];
    final store = _GatedTodoStore(const <TodoItem>[]);
    final container = ProviderContainer(
      overrides: [todoStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    // The provider is autoDispose; a listener keeps it mounted across the
    // awaited reads below.
    final subscription = container.listen(
      todoListProvider,
      (_, _) {},
    );
    addTearDown(subscription.close);

    store.releaseRead(saved);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(todoListProvider), saved);
    // The next id continues past the highest persisted one.
    container.read(todoListProvider.notifier).add('After load');
    expect(container.read(todoListProvider).last.title, 'After load');
    expect(container.read(todoListProvider).last.id, 6);
  });

  test('a toggle issued while the load is in flight survives it', () async {
    final saved = const <TodoItem>[TodoItem(id: 1, title: 'Persisted')];
    final store = _GatedTodoStore(const <TodoItem>[]);
    final container = ProviderContainer(
      overrides: [todoStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    // The provider is autoDispose; a listener keeps it (and the controller
    // instance under test) mounted across the awaited reads below.
    final subscription = container.listen(
      todoListProvider,
      (_, _) {},
    );
    addTearDown(subscription.close);

    final controller = container.read(todoListProvider.notifier);
    controller.add('Raced');
    // Toggle the newly added item: the item exists only in the in-memory
    // state racing the load, exactly like a user tapping its row before the
    // cold read lands.
    controller.toggle(container.read(todoListProvider).first.id);

    store.releaseRead(saved);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final state = container.read(todoListProvider);
    // The current state wins wholesale: the toggle result survives and the
    // stale disk list is dropped (the mutation's queued save rewrites it).
    expect(state, hasLength(1));
    expect(state.single.title, 'Raced');
    expect(state.single.id, 1);
    expect(state.single.done, isTrue);
    expect(store.items, hasLength(1));
    expect(store.items.single.done, isTrue);
  });
}
