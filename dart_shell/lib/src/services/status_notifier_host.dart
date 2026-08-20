import 'dart:async';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/tray_item.dart';
import 'dbus_menu_client.dart';
import 'status_notifier_item.dart';
import 'status_notifier_watcher.dart';

final statusNotifierHostServiceProvider = Provider<StatusNotifierHostService>((
  ref,
) {
  final host = StatusNotifierHostService();
  ref.onDispose(() => unawaited(host.dispose()));
  return host;
});

/// Service acting as a StatusNotifierHost (SNI host), maintaining the registry
/// of tracked StatusNotifierItems, subscribing to watcher events, and handling
/// process lifecycles and crash cleanups.
class StatusNotifierHostService {
  factory StatusNotifierHostService({
    DBusClient? client,
    StatusNotifierWatcherService? watcherService,
    int? customPid,
  }) {
    final sessionClient = client ?? DBusClient.session();
    final watcher =
        watcherService ?? StatusNotifierWatcherService(client: sessionClient);
    return StatusNotifierHostService.custom(
      client: sessionClient,
      watcherService: watcher,
      customPid: customPid ?? pid,
    );
  }

  @visibleForTesting
  StatusNotifierHostService.custom({
    required DBusClient client,
    required this._watcherService,
    required int customPid,
  }) : _client = client,
       _hostName = 'org.kde.StatusNotifierHost-$customPid',
       _watcherObject = DBusRemoteObject(
         client,
         name: StatusNotifierWatcherService.wellKnownName,
         path: DBusObjectPath(StatusNotifierWatcherService.objectPath),
       );

  static const Duration _readTimeout = Duration(seconds: 2);
  static const Duration _methodTimeout = Duration(seconds: 4);

  final DBusClient _client;
  final StatusNotifierWatcherService _watcherService;
  final String _hostName;
  final DBusRemoteObject _watcherObject;

  final Map<String, StatusNotifierItemClient> _itemClients =
      <String, StatusNotifierItemClient>{};
  final StreamController<List<TrayItem>> _snapshotsController =
      StreamController<List<TrayItem>>.broadcast(sync: true);

  StreamSubscription<DBusSignal>? _watcherSignalSubscription;
  StreamSubscription<DBusNameOwnerChangedEvent>? _nameOwnerSubscription;
  StreamSubscription<StatusNotifierAddress>? _localRegisteredSub;
  StreamSubscription<String>? _localUnregisteredSub;
  Timer? _reconnectTimer;

  bool _started = false;
  bool _disposed = false;
  bool _hostNameAcquired = false;

  Stream<List<TrayItem>> get snapshots => _snapshotsController.stream;
  List<TrayItem> get currentItems {
    final list = <TrayItem>[];
    for (final client in _itemClients.values) {
      final current = client.current;
      if (current != null) {
        list.add(current);
      }
    }
    return List<TrayItem>.unmodifiable(list);
  }

  StatusNotifierWatcherService get watcherService => _watcherService;
  String get hostName => _hostName;
  bool get isHostRegistered => _hostNameAcquired;
  DBusClient get dbusClient => _client;

  /// Creates a [DBusMenuClient] for the given [item] if it provides a valid [TrayItem.menuPath].
  DBusMenuClient? createMenuClient(TrayItem item) {
    if (item.menuPath.isEmpty) return null;
    return DBusMenuClient(
      service: item.service,
      menuPath: item.menuPath,
      client: _client,
    );
  }

  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;

    // 1. Start local watcher service (it handles primary/secondary fallback)
    await _watcherService.start();

    // 2. Direct in-process notification hook from local watcher
    _localRegisteredSub = _watcherService.onItemRegistered.listen((address) {
      if (!_disposed) {
        _addItem(address);
      }
    });
    _localUnregisteredSub = _watcherService.onItemUnregistered.listen((key) {
      if (!_disposed) {
        unawaited(_removeItem(key));
      }
    });

    // 3. Listen for name owner changes across the bus (for crash cleanup and watcher restarts)
    _nameOwnerSubscription = _client.nameOwnerChanged.listen(
      _handleNameOwnerChanged,
    );

    // 4. Acquire unique host bus name and register with the watcher
    await _acquireHostNameAndRegister();

    // 5. Subscribe to signals on the Watcher with resolved unique sender matching
    String? watcherUniqueSender;
    if (_watcherService.isPrimaryWatcher) {
      watcherUniqueSender = _client.uniqueName;
    } else {
      watcherUniqueSender = await _resolveUniqueBusName(
        StatusNotifierWatcherService.wellKnownName,
      );
    }

    // A missing owner is a degraded session-bus state, not permission to
    // subscribe to every sender on the bus.
    if (watcherUniqueSender != null) {
      _watcherSignalSubscription =
          DBusSignalStream(
            _client,
            sender: watcherUniqueSender,
            path: DBusObjectPath(StatusNotifierWatcherService.objectPath),
            interface: StatusNotifierWatcherService.interfaceName,
          ).listen((signal) {
            if (signal.sender != watcherUniqueSender) return;
            _handleWatcherSignal(signal);
          });
    }

    // 6. Initial sync of registered items (syncs local watcher & remote watcher snapshot)
    if (_watcherService.isPrimaryWatcher) {
      await _syncItemsWithList(_watcherService.registeredItemKeys);
    }
    await refresh();
  }

  Future<String?> _resolveUniqueBusName(String name) async {
    if (name.startsWith(':')) return name;
    try {
      return await _client.getNameOwner(name).timeout(_readTimeout);
    } catch (_) {
      return null;
    }
  }

  Future<void> _acquireHostNameAndRegister() async {
    if (_disposed) return;

    try {
      final reply = await _client
          .requestName(_hostName, flags: {DBusRequestNameFlag.doNotQueue})
          .timeout(_readTimeout);

      if (reply == DBusRequestNameReply.primaryOwner ||
          reply == DBusRequestNameReply.alreadyOwner) {
        _hostNameAcquired = true;
      }
    } on Object {
      // Failed to acquire host name (bus unavailable or name clash)
      _hostNameAcquired = false;
    }

    await _registerHostWithWatcher();
  }

  Future<void> _registerHostWithWatcher() async {
    if (_disposed) return;

    try {
      // If we are the primary watcher in this process, we can also register directly
      if (_watcherService.isPrimaryWatcher) {
        await _watcherService.registerHost(_hostName);
      }

      // Call RegisterStatusNotifierHost on the D-Bus watcher object
      await _watcherObject
          .callMethod(
            StatusNotifierWatcherService.interfaceName,
            'RegisterStatusNotifierHost',
            <DBusValue>[DBusString(_hostName)],
            replySignature: DBusSignature(''),
          )
          .timeout(_methodTimeout);
    } on Object {
      // Watcher not ready or call failed
    }
  }

  Future<void> refresh() async {
    if (_disposed) return;

    try {
      final itemsValue = await _watcherObject
          .getProperty(
            StatusNotifierWatcherService.interfaceName,
            'RegisteredStatusNotifierItems',
          )
          .timeout(_readTimeout);

      if (itemsValue is DBusArray) {
        final rawItems = itemsValue.children
            .whereType<DBusString>()
            .map((s) => s.value)
            .toList(growable: false);

        await _syncItemsWithList(rawItems);
      }
    } on Object {
      // Watcher query failed; if local watcher has items, sync with it
      if (_watcherService.isPrimaryWatcher) {
        await _syncItemsWithList(_watcherService.registeredItemKeys);
      }
    }
  }

  Future<void> _syncItemsWithList(List<String> rawItems) async {
    if (_disposed) return;

    final targetKeys = <String>{};
    for (final raw in rawItems) {
      try {
        final address = StatusNotifierAddress.parse(raw);
        if (address.service.isNotEmpty) {
          final key = address.toWireString();
          targetKeys.add(key);
          if (!_itemClients.containsKey(key)) {
            _addItem(address);
          }
        }
      } on Object {
        // Skip malformed entries without disrupting other items
      }
    }

    // Remove any items no longer present
    final keysToRemove = _itemClients.keys
        .where((key) => !targetKeys.contains(key))
        .toList(growable: false);

    for (final key in keysToRemove) {
      await _removeItem(key);
    }

    _emitSnapshots();
  }

  void _handleWatcherSignal(DBusSignal signal) {
    if (_disposed) return;

    if (signal.interface == StatusNotifierWatcherService.interfaceName) {
      switch (signal.name) {
        case 'StatusNotifierItemRegistered':
          if (signal.values.isNotEmpty && signal.values[0] is DBusString) {
            final raw = (signal.values[0] as DBusString).value;
            try {
              final address = StatusNotifierAddress.parse(raw);
              if (address.service.isNotEmpty) {
                _addItem(address);
              }
            } on Object {
              // Ignore malformed signal values
            }
          }
          break;
        case 'StatusNotifierItemUnregistered':
          if (signal.values.isNotEmpty && signal.values[0] is DBusString) {
            final raw = (signal.values[0] as DBusString).value;
            try {
              final address = StatusNotifierAddress.parse(raw);
              unawaited(_removeItem(address.toWireString()));
            } on Object {
              // Ignore unregister errors for malformed item strings
            }
          }
          break;
        case 'StatusNotifierHostRegistered':
        case 'StatusNotifierHostUnregistered':
          // Re-verify host registration if needed
          break;
      }
    }
  }

  void _handleNameOwnerChanged(DBusNameOwnerChangedEvent event) {
    if (_disposed) return;

    if (event.name == StatusNotifierWatcherService.wellKnownName) {
      if (event.newOwner != null) {
        // Watcher restarted or new watcher took over: re-register host and sync
        _reconnectTimer?.cancel();
        _reconnectTimer = Timer(const Duration(milliseconds: 100), () {
          unawaited(_registerHostWithWatcher());
          unawaited(refresh());
        });
      }
      return;
    }

    // A well-known item name can lose its owner and immediately acquire a
    // replacement. Rebuild the client on both transitions so its signal
    // subscription is always bound to the current unique owner.
    final affected = _itemClients.entries
        .where((entry) => entry.value.address.service == event.name)
        .map((entry) => MapEntry(entry.key, entry.value.address))
        .toList(growable: false);
    for (final entry in affected) {
      if (event.newOwner == null) {
        unawaited(_removeItem(entry.key));
      } else {
        unawaited(_restartItem(entry.key, entry.value));
      }
    }
  }

  void _addItem(StatusNotifierAddress address) {
    final key = address.toWireString();
    if (_itemClients.containsKey(key)) {
      unawaited(_itemClients[key]?.refresh());
      return;
    }

    try {
      final client = StatusNotifierItemClient(
        address: address,
        client: _client,
        onChanged: (_) => _emitSnapshots(),
      );

      _itemClients[key] = client;
      unawaited(
        client.start().catchError((_) {
          // Degraded items or startup failures handled inside client
        }),
      );
    } on Object {
      _itemClients.remove(key);
    }
  }

  Future<void> _removeItem(String key) async {
    final client = _itemClients.remove(key);
    if (client != null) {
      await client.dispose();
      _emitSnapshots();
    }
  }

  Future<void> _restartItem(String key, StatusNotifierAddress address) async {
    await _removeItem(key);
    if (!_disposed) _addItem(address);
  }

  void _emitSnapshots() {
    if (_disposed || _snapshotsController.isClosed) return;
    _snapshotsController.add(currentItems);
  }

  Future<void> activate(TrayItem item, {int x = 0, int y = 0}) async {
    final client =
        _itemClients[item.key] ??
        _itemClients.values.cast<StatusNotifierItemClient?>().firstWhere(
          (c) => c?.address.service == item.service,
          orElse: () => null,
        );
    await client?.activate(x: x, y: y);
  }

  Future<void> secondaryActivate(TrayItem item, {int x = 0, int y = 0}) async {
    final client =
        _itemClients[item.key] ??
        _itemClients.values.cast<StatusNotifierItemClient?>().firstWhere(
          (c) => c?.address.service == item.service,
          orElse: () => null,
        );
    await client?.secondaryActivate(x: x, y: y);
  }

  Future<void> contextMenu(TrayItem item, {int x = 0, int y = 0}) async {
    final client =
        _itemClients[item.key] ??
        _itemClients.values.cast<StatusNotifierItemClient?>().firstWhere(
          (c) => c?.address.service == item.service,
          orElse: () => null,
        );
    await client?.contextMenu(x: x, y: y);
  }

  Future<void> scroll(TrayItem item, int delta, String orientation) async {
    final client =
        _itemClients[item.key] ??
        _itemClients.values.cast<StatusNotifierItemClient?>().firstWhere(
          (c) => c?.address.service == item.service,
          orElse: () => null,
        );
    await client?.scroll(delta, orientation);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    await _localRegisteredSub?.cancel();
    _localRegisteredSub = null;

    await _localUnregisteredSub?.cancel();
    _localUnregisteredSub = null;

    await _watcherSignalSubscription?.cancel();
    _watcherSignalSubscription = null;

    await _nameOwnerSubscription?.cancel();
    _nameOwnerSubscription = null;

    for (final client in _itemClients.values) {
      await client.dispose();
    }
    _itemClients.clear();

    if (_hostNameAcquired) {
      try {
        await _client.releaseName(_hostName);
      } on Object {
        // Ignore errors during teardown
      }
      _hostNameAcquired = false;
    }

    await _watcherService.dispose();
    await _snapshotsController.close();
    await _client.close();
  }
}
