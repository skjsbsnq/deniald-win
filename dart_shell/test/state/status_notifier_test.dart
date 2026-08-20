import 'dart:async';

import 'package:dbus/dbus.dart';
import 'package:denial_dart_shell/src/models/tray_item.dart';
import 'package:denial_dart_shell/src/services/status_notifier_host.dart';
import 'package:denial_dart_shell/src/services/status_notifier_watcher.dart';
import 'package:denial_dart_shell/src/state/status_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeStatusNotifierWatcherService extends StatusNotifierWatcherService {
  _FakeStatusNotifierWatcherService() : super(client: DBusClient.session());

  @override
  bool get isPrimaryWatcher => true;

  @override
  List<String> get registeredItemKeys => const <String>[];

  @override
  Future<void> start() async {}

  @override
  Future<void> dispose() async {}
}

class _FakeStatusNotifierHostService extends StatusNotifierHostService {
  _FakeStatusNotifierHostService()
    : _fakeWatcher = _FakeStatusNotifierWatcherService(),
      super.custom(
        client: DBusClient.session(),
        watcherService: _FakeStatusNotifierWatcherService(),
        customPid: 99999,
      );

  final _FakeStatusNotifierWatcherService _fakeWatcher;
  final StreamController<List<TrayItem>> _controller =
      StreamController<List<TrayItem>>.broadcast();

  List<TrayItem> _items = <TrayItem>[];
  bool started = false;
  bool refreshed = false;
  TrayItem? activatedItem;
  TrayItem? contextMenuItem;

  @override
  StatusNotifierWatcherService get watcherService => _fakeWatcher;

  @override
  bool get isHostRegistered => true;

  @override
  Stream<List<TrayItem>> get snapshots => _controller.stream;

  @override
  List<TrayItem> get currentItems => _items;

  @override
  Future<void> start() async {
    started = true;
  }

  @override
  Future<void> refresh() async {
    refreshed = true;
  }

  @override
  Future<void> activate(TrayItem item, {int x = 0, int y = 0}) async {
    activatedItem = item;
  }

  @override
  Future<void> contextMenu(TrayItem item, {int x = 0, int y = 0}) async {
    contextMenuItem = item;
  }

  void emit(List<TrayItem> items) {
    _items = items;
    _controller.add(items);
  }

  @override
  Future<void> dispose() async {
    await _controller.close();
  }
}

void main() {
  group('StatusNotifierState', () {
    test('initial state defaults', () {
      final state = StatusNotifierState.initial();
      expect(state.serviceAvailable, isFalse);
      expect(state.isWatcher, isFalse);
      expect(state.isHostRegistered, isFalse);
      expect(state.items, isEmpty);
      expect(state.activeItems, isEmpty);
      expect(state.passiveItems, isEmpty);
      expect(state.initializing, isTrue);
      expect(state.refreshing, isFalse);
      expect(state.error, isNull);
    });

    test('separates active and passive items correctly', () {
      const active1 = TrayItem(
        service: ':1.1',
        path: '/StatusNotifierItem',
        id: 'active_app',
        title: 'Active App',
        status: TrayItemStatus.active,
      );
      const attention = TrayItem(
        service: ':1.2',
        path: '/StatusNotifierItem',
        id: 'urgent_app',
        title: 'Urgent App',
        status: TrayItemStatus.needsAttention,
      );
      const passive1 = TrayItem(
        service: ':1.3',
        path: '/StatusNotifierItem',
        id: 'passive_app',
        title: 'Passive App',
        status: TrayItemStatus.passive,
      );

      final state = StatusNotifierState.initial().copyWith(
        items: <TrayItem>[active1, attention, passive1],
      );

      expect(state.activeItems, <TrayItem>[active1, attention]);
      expect(state.passiveItems, <TrayItem>[passive1]);
    });

    test('copyWith and equality behavior', () {
      final stateA = StatusNotifierState.initial().copyWith(
        serviceAvailable: true,
        isWatcher: true,
      );
      final stateB = stateA.copyWith();
      expect(stateA, equals(stateB));
      expect(stateA.hashCode, equals(stateB.hashCode));

      final stateC = stateA.copyWith(error: 'Some error');
      expect(stateC.error, 'Some error');
      expect(stateC == stateA, isFalse);

      final stateD = stateC.copyWith(clearError: true);
      expect(stateD.error, isNull);
      expect(stateD, equals(stateA));
    });
  });

  group('StatusNotifierController', () {
    test('initializes and updates with host service snapshots', () async {
      final fakeHost = _FakeStatusNotifierHostService();
      addTearDown(fakeHost.dispose);

      final container = ProviderContainer(
        overrides: [
          statusNotifierHostServiceProvider.overrideWithValue(fakeHost),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(statusNotifierProvider.notifier);
      expect(container.read(statusNotifierProvider).initializing, isTrue);

      // Allow microtask to run
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(fakeHost.started, isTrue);
      expect(container.read(statusNotifierProvider).serviceAvailable, isTrue);
      expect(container.read(statusNotifierProvider).isWatcher, isTrue);
      expect(container.read(statusNotifierProvider).isHostRegistered, isTrue);

      const testItem = TrayItem(
        service: ':1.42',
        path: '/StatusNotifierItem',
        id: 'fcitx',
        title: 'Input Method',
        status: TrayItemStatus.active,
      );

      fakeHost.emit(<TrayItem>[testItem]);
      await Future<void>.delayed(Duration.zero);

      final updatedState = container.read(statusNotifierProvider);
      expect(updatedState.items, <TrayItem>[testItem]);
      expect(updatedState.activeItems, <TrayItem>[testItem]);

      await controller.refresh();
      expect(fakeHost.refreshed, isTrue);

      await controller.activate(testItem);
      expect(fakeHost.activatedItem, testItem);

      await controller.contextMenu(testItem);
      expect(fakeHost.contextMenuItem, testItem);
    });
  });
}
