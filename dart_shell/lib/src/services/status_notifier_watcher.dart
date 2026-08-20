import 'dart:async';

import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';

/// Represents a parsed (service, path) pair for a StatusNotifierItem.
@immutable
class StatusNotifierAddress {
  const StatusNotifierAddress({required this.service, required this.path});

  /// The D-Bus bus name owning the item (e.g. `:1.42` or `org.kde.StatusNotifierItem-1024-1`).
  final String service;

  /// The D-Bus object path (e.g. `/StatusNotifierItem` or `/org/ayatana/NotificationItem/nm_applet`).
  final String path;

  static const String defaultPath = '/StatusNotifierItem';

  /// Sanitizes and validates a candidate D-Bus object path according to the Freedesktop spec.
  static String sanitizePath(String rawPath) {
    var p = rawPath.trim();
    if (!p.startsWith('/')) {
      p = '/$p';
    }
    // Replace consecutive slashes
    p = p.replaceAll(RegExp(r'/+'), '/');
    // Remove trailing slash if length > 1
    if (p.length > 1 && p.endsWith('/')) {
      p = p.substring(0, p.length - 1);
    }
    // Validate characters: [A-Za-z0-9_/]
    final sanitized = StringBuffer();
    for (var i = 0; i < p.length; i++) {
      final code = p.codeUnitAt(i);
      final isAlphaNum =
          (code >= 48 && code <= 57) || // 0-9
          (code >= 65 && code <= 90) || // A-Z
          (code >= 97 && code <= 122); // a-z
      if (isAlphaNum || code == 47 || code == 95) {
        sanitized.writeCharCode(code);
      } else {
        sanitized.write('_');
      }
    }
    var result = sanitized.toString().replaceAll(RegExp(r'/+'), '/');
    if (result.length > 1 && result.endsWith('/')) {
      result = result.substring(0, result.length - 1);
    }
    try {
      DBusObjectPath(result);
      return result;
    } on Object {
      return defaultPath;
    }
  }

  /// Parses a registration string parameter received from [RegisterStatusNotifierItem]
  /// or read from [RegisteredStatusNotifierItems].
  ///
  /// Supports:
  /// - Ayatana style: `/org/ayatana/NotificationItem/...` (takes [sender] as bus name)
  /// - KDE style: `:1.42` or `org.kde.StatusNotifierItem-123-1` (defaults path to `/StatusNotifierItem`)
  /// - Combined style: `:1.42/custom/path` or `org.example.App/StatusNotifierItem`
  static StatusNotifierAddress parse(String raw, {String? sender}) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      final fallbackSender = sender?.trim() ?? '';
      return StatusNotifierAddress(service: fallbackSender, path: defaultPath);
    }

    if (trimmed.startsWith('/')) {
      // Ayatana path-only style: sender supplies the bus name
      final serviceName = (sender != null && sender.trim().isNotEmpty)
          ? sender.trim()
          : '';
      return StatusNotifierAddress(
        service: serviceName,
        path: sanitizePath(trimmed),
      );
    }

    final slashIndex = trimmed.indexOf('/');
    if (slashIndex != -1) {
      final servicePart = trimmed.substring(0, slashIndex).trim();
      final pathPart = trimmed.substring(slashIndex).trim();
      return StatusNotifierAddress(
        service: servicePart.isNotEmpty ? servicePart : (sender?.trim() ?? ''),
        path: sanitizePath(pathPart),
      );
    }

    return StatusNotifierAddress(service: trimmed, path: defaultPath);
  }

  /// Formats this address into the canonical wire string for `RegisteredStatusNotifierItems`.
  String toWireString() {
    if (path == defaultPath) {
      return service;
    }
    return '$service$path';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StatusNotifierAddress &&
          other.service == service &&
          other.path == path;

  @override
  int get hashCode => Object.hash(service, path);

  @override
  String toString() => 'StatusNotifierAddress(service: $service, path: $path)';
}

/// D-Bus exported endpoint for `org.kde.StatusNotifierWatcher` on `/StatusNotifierWatcher`.
class StatusNotifierWatcherEndpoint extends DBusObject {
  StatusNotifierWatcherEndpoint({
    required this.onRegisterItem,
    required this.onRegisterHost,
    required this.onGetItems,
    required this.onGetHostRegistered,
    required this.onGetProtocolVersion,
  }) : super(DBusObjectPath(objectPath));

  static const String interfaceName = 'org.kde.StatusNotifierWatcher';
  static const String objectPath = '/StatusNotifierWatcher';

  final Future<void> Function(String service, String? sender) onRegisterItem;
  final Future<void> Function(String service, String? sender) onRegisterHost;
  final List<String> Function() onGetItems;
  final bool Function() onGetHostRegistered;
  final int Function() onGetProtocolVersion;

  @override
  List<DBusIntrospectInterface> introspect() => <DBusIntrospectInterface>[
    DBusIntrospectInterface(
      interfaceName,
      methods: <DBusIntrospectMethod>[
        DBusIntrospectMethod(
          'RegisterStatusNotifierItem',
          args: <DBusIntrospectArgument>[
            DBusIntrospectArgument(
              DBusSignature('s'),
              DBusArgumentDirection.in_,
              name: 'service',
            ),
          ],
        ),
        DBusIntrospectMethod(
          'RegisterStatusNotifierHost',
          args: <DBusIntrospectArgument>[
            DBusIntrospectArgument(
              DBusSignature('s'),
              DBusArgumentDirection.in_,
              name: 'service',
            ),
          ],
        ),
      ],
      signals: <DBusIntrospectSignal>[
        DBusIntrospectSignal(
          'StatusNotifierItemRegistered',
          args: <DBusIntrospectArgument>[
            DBusIntrospectArgument(
              DBusSignature('s'),
              DBusArgumentDirection.out,
              name: 'service',
            ),
          ],
        ),
        DBusIntrospectSignal(
          'StatusNotifierItemUnregistered',
          args: <DBusIntrospectArgument>[
            DBusIntrospectArgument(
              DBusSignature('s'),
              DBusArgumentDirection.out,
              name: 'service',
            ),
          ],
        ),
        DBusIntrospectSignal('StatusNotifierHostRegistered'),
        DBusIntrospectSignal('StatusNotifierHostUnregistered'),
      ],
      properties: <DBusIntrospectProperty>[
        DBusIntrospectProperty(
          'RegisteredStatusNotifierItems',
          DBusSignature('as'),
          access: DBusPropertyAccess.read,
        ),
        DBusIntrospectProperty(
          'IsStatusNotifierHostRegistered',
          DBusSignature('b'),
          access: DBusPropertyAccess.read,
        ),
        DBusIntrospectProperty(
          'ProtocolVersion',
          DBusSignature('i'),
          access: DBusPropertyAccess.read,
        ),
      ],
    ),
  ];

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    if (methodCall.interface != interfaceName) {
      return DBusMethodErrorResponse.unknownInterface();
    }

    switch (methodCall.name) {
      case 'RegisterStatusNotifierItem':
        if (methodCall.values.isEmpty || methodCall.values[0] is! DBusString) {
          return DBusMethodErrorResponse.invalidArgs();
        }
        final raw = (methodCall.values[0] as DBusString).value;
        await onRegisterItem(raw, methodCall.sender);
        return DBusMethodSuccessResponse(const <DBusValue>[]);

      case 'RegisterStatusNotifierHost':
        if (methodCall.values.isEmpty || methodCall.values[0] is! DBusString) {
          return DBusMethodErrorResponse.invalidArgs();
        }
        final raw = (methodCall.values[0] as DBusString).value;
        await onRegisterHost(raw, methodCall.sender);
        return DBusMethodSuccessResponse(const <DBusValue>[]);

      default:
        return DBusMethodErrorResponse.unknownMethod();
    }
  }

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    if (interface != interfaceName) {
      return DBusMethodErrorResponse.unknownInterface();
    }

    switch (name) {
      case 'RegisteredStatusNotifierItems':
        return DBusGetPropertyResponse(DBusArray.string(onGetItems()));
      case 'IsStatusNotifierHostRegistered':
        return DBusGetPropertyResponse(DBusBoolean(onGetHostRegistered()));
      case 'ProtocolVersion':
        return DBusGetPropertyResponse(DBusInt32(onGetProtocolVersion()));
      default:
        return DBusMethodErrorResponse.unknownProperty();
    }
  }

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async {
    if (interface != interfaceName) {
      return DBusMethodErrorResponse.unknownInterface();
    }

    return DBusGetAllPropertiesResponse(<String, DBusValue>{
      'RegisteredStatusNotifierItems': DBusArray.string(onGetItems()),
      'IsStatusNotifierHostRegistered': DBusBoolean(onGetHostRegistered()),
      'ProtocolVersion': DBusInt32(onGetProtocolVersion()),
    });
  }

  Future<void> emitItemRegistered(String itemEntry) async {
    await emitSignal(interfaceName, 'StatusNotifierItemRegistered', <DBusValue>[
      DBusString(itemEntry),
    ]);
  }

  Future<void> emitItemUnregistered(String itemEntry) async {
    await emitSignal(
      interfaceName,
      'StatusNotifierItemUnregistered',
      <DBusValue>[DBusString(itemEntry)],
    );
  }

  Future<void> emitHostRegistered() async {
    await emitSignal(
      interfaceName,
      'StatusNotifierHostRegistered',
      const <DBusValue>[],
    );
  }

  Future<void> emitHostUnregistered() async {
    await emitSignal(
      interfaceName,
      'StatusNotifierHostUnregistered',
      const <DBusValue>[],
    );
  }
}

/// Service managing the StatusNotifierWatcher D-Bus lifecycle, name acquisition,
/// and registered items/hosts registry.
class StatusNotifierWatcherService {
  StatusNotifierWatcherService({DBusClient? client})
    : _client = client ?? DBusClient.session();

  static const String wellKnownName = 'org.kde.StatusNotifierWatcher';
  static const String interfaceName = 'org.kde.StatusNotifierWatcher';
  static const String objectPath = '/StatusNotifierWatcher';
  static const Duration _readTimeout = Duration(seconds: 2);

  final DBusClient _client;
  final Map<String, StatusNotifierAddress> _items =
      <String, StatusNotifierAddress>{};
  final Set<String> _hosts = <String>{};
  final StreamController<StatusNotifierAddress> _itemRegisteredController =
      StreamController<StatusNotifierAddress>.broadcast();
  final StreamController<String> _itemUnregisteredController =
      StreamController<String>.broadcast();

  late final StatusNotifierWatcherEndpoint _endpoint =
      StatusNotifierWatcherEndpoint(
        onRegisterItem: _handleRegisterItem,
        onRegisterHost: _handleRegisterHost,
        onGetItems: () => _items.keys.toList(growable: false),
        onGetHostRegistered: () => _hosts.isNotEmpty,
        onGetProtocolVersion: () => 0,
      );

  StreamSubscription<DBusNameOwnerChangedEvent>? _ownerSubscription;
  bool _started = false;
  bool _disposed = false;
  bool _isPrimaryWatcher = false;
  bool _isObjectExported = false;

  bool get isPrimaryWatcher => _isPrimaryWatcher;
  bool get isHostRegistered => _hosts.isNotEmpty;
  Stream<StatusNotifierAddress> get onItemRegistered =>
      _itemRegisteredController.stream;
  Stream<String> get onItemUnregistered => _itemUnregisteredController.stream;
  List<String> get registeredItemKeys => _items.keys.toList(growable: false);
  List<StatusNotifierAddress> get registeredAddresses =>
      _items.values.toList(growable: false);

  Future<void> start() async {
    if (_started || _disposed) {
      return;
    }
    _started = true;

    // Listen for name owner changes to clean up crashed items/hosts
    // and to detect when an external watcher releases the well-known name.
    _ownerSubscription = _client.nameOwnerChanged.listen(
      _handleNameOwnerChanged,
    );

    await _acquireWatcherName();
  }

  Future<void> _acquireWatcherName() async {
    if (_disposed) return;
    try {
      final reply = await _client
          .requestName(wellKnownName, flags: {DBusRequestNameFlag.doNotQueue})
          .timeout(_readTimeout);

      if (reply == DBusRequestNameReply.primaryOwner ||
          reply == DBusRequestNameReply.alreadyOwner) {
        _isPrimaryWatcher = true;
        if (!_isObjectExported) {
          await _client.registerObject(_endpoint);
          _isObjectExported = true;
        }
      } else {
        // Another watcher is running. Gracefully fallback to host-only mode.
        _isPrimaryWatcher = false;
      }
    } on Object {
      // Session bus unavailable or request timeout. Graceful degradation.
      _isPrimaryWatcher = false;
    }
  }

  Future<void> _handleNameOwnerChanged(DBusNameOwnerChangedEvent event) async {
    if (_disposed) return;

    if (event.name == wellKnownName) {
      if (event.newOwner == null && !_isPrimaryWatcher) {
        // Previous external watcher disappeared; attempt to take over.
        await _acquireWatcherName();
      }
      return;
    }

    if (event.newOwner == null) {
      // A bus name has disconnected / crashed (e.g. kill -9).
      final disappearedName = event.name;

      // 1. Check if any registered item belongs to this name
      final itemsToRemove = <String>[];
      for (final entry in _items.entries) {
        if (entry.value.service == disappearedName) {
          itemsToRemove.add(entry.key);
        }
      }

      for (final key in itemsToRemove) {
        await unregisterItem(key);
      }

      // 2. Check if a registered host belongs to this name
      if (_hosts.contains(disappearedName)) {
        await unregisterHost(disappearedName);
      }
    }
  }

  Future<void> _handleRegisterItem(String raw, String? sender) async {
    final address = StatusNotifierAddress.parse(raw, sender: sender);
    if (address.service.isEmpty) {
      return;
    }
    final wireKey = address.toWireString();
    final isNew = !_items.containsKey(wireKey);
    _items[wireKey] = address;

    if (isNew && !_disposed && !_itemRegisteredController.isClosed) {
      _itemRegisteredController.add(address);
    }

    if (_isPrimaryWatcher && _isObjectExported) {
      await _endpoint.emitItemRegistered(wireKey);
      if (isNew) {
        await _endpoint.emitPropertiesChanged(
          interfaceName,
          changedProperties: {
            'RegisteredStatusNotifierItems': DBusArray.string(
              _items.keys.toList(growable: false),
            ),
          },
        );
      }
    }
  }

  Future<void> _handleRegisterHost(String raw, String? sender) async {
    final hostName = raw.trim().isNotEmpty
        ? raw.trim()
        : (sender?.trim() ?? '');
    if (hostName.isEmpty) return;

    final wasEmpty = _hosts.isEmpty;
    _hosts.add(hostName);

    if (_isPrimaryWatcher && _isObjectExported) {
      if (wasEmpty) {
        await _endpoint.emitHostRegistered();
        await _endpoint.emitPropertiesChanged(
          interfaceName,
          changedProperties: {
            'IsStatusNotifierHostRegistered': const DBusBoolean(true),
          },
        );
      }
    }
  }

  Future<void> registerItem(String raw, {String? sender}) =>
      _handleRegisterItem(raw, sender);

  Future<void> registerHost(String hostName) =>
      _handleRegisterHost(hostName, null);

  Future<void> unregisterItem(String wireKey) async {
    final removed = _items.remove(wireKey);
    if (removed != null) {
      if (!_disposed && !_itemUnregisteredController.isClosed) {
        _itemUnregisteredController.add(wireKey);
      }
      if (_isPrimaryWatcher && _isObjectExported) {
        await _endpoint.emitItemUnregistered(wireKey);
        await _endpoint.emitPropertiesChanged(
          interfaceName,
          changedProperties: {
            'RegisteredStatusNotifierItems': DBusArray.string(
              _items.keys.toList(growable: false),
            ),
          },
        );
      }
    }
  }

  Future<void> unregisterHost(String hostName) async {
    final removed = _hosts.remove(hostName);
    if (removed && _hosts.isEmpty && _isPrimaryWatcher && _isObjectExported) {
      await _endpoint.emitHostUnregistered();
      await _endpoint.emitPropertiesChanged(
        interfaceName,
        changedProperties: {
          'IsStatusNotifierHostRegistered': const DBusBoolean(false),
        },
      );
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _ownerSubscription?.cancel();
    _ownerSubscription = null;

    if (_isObjectExported) {
      try {
        await _client.unregisterObject(_endpoint);
      } on Object {
        // Ignore unregister errors during teardown
      }
      _isObjectExported = false;
    }

    if (_isPrimaryWatcher) {
      try {
        await _client.releaseName(wellKnownName);
      } on Object {
        // Ignore release errors during teardown
      }
      _isPrimaryWatcher = false;
    }

    if (!_itemRegisteredController.isClosed) {
      await _itemRegisteredController.close();
    }
    if (!_itemUnregisteredController.isClosed) {
      await _itemUnregisteredController.close();
    }

    _items.clear();
    _hosts.clear();
  }
}
