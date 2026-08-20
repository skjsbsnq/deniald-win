import 'dart:async';

import 'package:dbus/dbus.dart';

import '../models/dbus_menu_node.dart';

/// Client for interacting with a remote `com.canonical.dbusmenu` D-Bus object.
///
/// Implements the DBusMenu protocol specification:
/// - Lazy menu generation via `AboutToShow`
/// - Full/incremental layout retrieval via `GetLayout`
/// - Action callbacks via `Event('clicked', ...)` and `Event('closed', ...)`
/// - Real-time item property updates via `ItemsPropertiesUpdated` and `LayoutUpdated`
/// - Strict timeouts to prevent unresponsive D-Bus applications from freezing the shell.
class DBusMenuClient {
  DBusMenuClient({
    required this.service,
    required this.menuPath,
    required DBusClient client,
    this.onLayoutChanged,
  }) : _client = client,
       _remoteObject = DBusRemoteObject(
         client,
         name: service,
         path: DBusObjectPath(menuPath),
       );

  static const String interfaceName = 'com.canonical.dbusmenu';
  static const Duration _readTimeout = Duration(milliseconds: 2500);
  static const Duration _eventTimeout = Duration(milliseconds: 1500);

  final String service;
  final String menuPath;
  final DBusClient _client;
  final DBusRemoteObject _remoteObject;
  void Function(DBusMenuNode root)? onLayoutChanged;

  StreamSubscription<DBusSignal>? _signalSubscription;
  DBusMenuNode? _rootNode;
  int _revision = 0;
  final Map<int, int> _fetchGenerations = <int, int>{};
  final Set<int> _pendingFetchParentIds = <int>{};
  bool _disposed = false;
  bool _isMenuOpen = false;
  bool _isLoading = false;
  String? _error;

  /// Current immutable root node of the menu tree.
  DBusMenuNode? get rootNode => _rootNode;

  /// Current menu layout revision number.
  int get revision => _revision;

  /// Whether the menu is currently in the open state.
  bool get isMenuOpen => _isMenuOpen;

  /// Whether an asynchronous fetch operation is currently active.
  bool get isLoading => _isLoading;

  /// Last error message (if any).
  String? get error => _error;

  /// Whether this client instance has been disposed.
  bool get isDisposed => _disposed;

  /// Starts listening to DBusMenu signals (`LayoutUpdated`, `ItemsPropertiesUpdated`, `ItemActivationRequested`).
  void startListening() {
    if (_disposed || _signalSubscription != null) return;

    if (service.startsWith(':')) {
      _attachSignalStream(service);
    } else if (service.isNotEmpty) {
      unawaited(
        _client
            .getNameOwner(service)
            .timeout(_readTimeout)
            .then((uniqueSender) {
              if (!_disposed && _signalSubscription == null) {
                _attachSignalStream(uniqueSender);
              }
            })
            .catchError((error) {
              if (!_disposed) {
                _error = 'Unable to resolve DBusMenu owner: $error';
              }
            }),
      );
    }
  }

  void _attachSignalStream(String? uniqueSender) {
    if (_disposed || _signalSubscription != null || uniqueSender == null) {
      return;
    }
    _signalSubscription =
        DBusSignalStream(
          _client,
          sender: uniqueSender,
          path: DBusObjectPath(menuPath),
          interface: interfaceName,
        ).listen((signal) {
          if (signal.sender != uniqueSender) {
            return;
          }
          _handleSignal(signal);
        }, onError: (_) {});
  }

  /// Invalidates in-flight fetches for [parentId] and all its known descendant nodes.
  void _invalidateSubtreeGenerations(int parentId) {
    final nextGeneration = (_fetchGenerations[parentId] ?? 0) + 1;
    if (parentId == 0) {
      _fetchGenerations.clear();
      _fetchGenerations[parentId] = nextGeneration;
      return;
    }
    final target = _rootNode?.findNode(parentId);
    if (target != null) {
      for (final id in target.collectAllNodeIds()) {
        if (id != parentId) _fetchGenerations.remove(id);
      }
    }
    // Keep the parent generation monotonic so an older response cannot become
    // valid again after invalidation and a new fetch.
    _fetchGenerations[parentId] = nextGeneration;
  }

  /// Prunes generational tracking for node IDs that no longer exist in the active tree,
  /// exempting any IDs currently in-flight in [_pendingFetchParentIds].
  void _pruneStaleGenerations() {
    final root = _rootNode;
    if (root == null) {
      _fetchGenerations.removeWhere(
        (id, _) => !_pendingFetchParentIds.contains(id),
      );
      return;
    }
    final activeIds = root.collectAllNodeIds()..add(0);
    _fetchGenerations.removeWhere(
      (id, _) =>
          !activeIds.contains(id) && !_pendingFetchParentIds.contains(id),
    );
  }

  /// Opens the menu: triggers `AboutToShow(0)`, retrieves the layout, sends `opened` event,
  /// and returns the parsed [DBusMenuNode] root.
  Future<DBusMenuNode?> openMenu() async {
    if (_disposed) return null;
    startListening();

    _isLoading = true;
    _error = null;
    _isMenuOpen = true;

    final timestamp = _currentUnixTimestamp();

    // 1. Notify remote that menu opened (fire-and-forget)
    unawaited(_sendEvent(0, 'opened', const DBusString(''), timestamp));

    _pendingFetchParentIds.add(0);
    try {
      // 2. Call AboutToShow(0) to allow lazy initialization
      await aboutToShow(0);
      if (_disposed || !_isMenuOpen) return null;

      // 3. Invalidate any pending child subtree fetches and fetch root
      _invalidateSubtreeGenerations(0);
      final generation = (_fetchGenerations[0] ?? 0) + 1;
      _fetchGenerations[0] = generation;
      final node = await getLayout(parentId: 0, recursionDepth: -1);
      if (_disposed ||
          !_isMenuOpen ||
          _fetchGenerations[0] != generation ||
          node == null) {
        return _rootNode;
      }

      _rootNode = node;
      _pruneStaleGenerations();
      onLayoutChanged?.call(node);
      return node;
    } catch (e) {
      _error = e.toString();
      return null;
    } finally {
      _pendingFetchParentIds.remove(0);
      _isLoading = false;
    }
  }

  /// Refreshes one lazily-loaded submenu and merges it into the current tree.
  Future<DBusMenuNode?> openSubmenu(int parentId) async {
    if (_disposed || !_isMenuOpen || parentId == 0) return null;

    _pendingFetchParentIds.add(parentId);
    try {
      await aboutToShow(parentId);
      if (_disposed || !_isMenuOpen) return null;

      _invalidateSubtreeGenerations(parentId);
      final generation = (_fetchGenerations[parentId] ?? 0) + 1;
      _fetchGenerations[parentId] = generation;
      final subtree = await getLayout(parentId: parentId, recursionDepth: -1);
      final root = _rootNode;
      if (_disposed ||
          !_isMenuOpen ||
          _fetchGenerations[parentId] != generation ||
          subtree == null ||
          root == null ||
          root.findNode(parentId) == null) {
        return subtree;
      }

      final updatedRoot = root.updateSubtree(parentId, subtree.children);
      _rootNode = updatedRoot;
      _pruneStaleGenerations();
      onLayoutChanged?.call(updatedRoot);
      return subtree;
    } finally {
      _pendingFetchParentIds.remove(parentId);
    }
  }

  /// Calls `AboutToShow(id)` on the remote DBusMenu object.
  ///
  /// Returns `true` if the remote object indicated that an update is needed.
  Future<bool> aboutToShow(int id) async {
    if (_disposed) return false;
    try {
      final response = await _remoteObject
          .callMethod(interfaceName, 'AboutToShow', <DBusValue>[
            DBusInt32(id),
          ], replySignature: DBusSignature('b'))
          .timeout(_readTimeout);

      if (response.values.isNotEmpty && response.values[0] is DBusBoolean) {
        return (response.values[0] as DBusBoolean).value;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Calls `GetLayout(parentId, recursionDepth, propertyNames)` and parses the result.
  /// Returns null if the call fails or times out, preserving existing tree state.
  Future<DBusMenuNode?> getLayout({
    int parentId = 0,
    int recursionDepth = -1,
    List<String> propertyNames = const <String>[],
  }) async {
    if (_disposed) return null;

    try {
      final response = await _remoteObject
          .callMethod(interfaceName, 'GetLayout', <DBusValue>[
            DBusInt32(parentId),
            DBusInt32(recursionDepth),
            DBusArray.string(propertyNames),
          ], replySignature: DBusSignature('u(ia{sv}av)'))
          .timeout(_readTimeout);

      if (response.values.length >= 2) {
        if (response.values[0] is DBusUint32) {
          final replyRev = (response.values[0] as DBusUint32).value;
          if (replyRev > _revision) {
            _revision = replyRev;
          }
        }
        final layoutVal = response.values[1];
        return parseDBusMenuLayout(layoutVal);
      }
    } catch (e) {
      _error = e.toString();
    }

    return null;
  }

  /// Triggers a click event on the menu item with the specified [id].
  Future<void> sendClicked(int id) async {
    if (_disposed) return;
    final timestamp = _currentUnixTimestamp();
    await _sendEvent(id, 'clicked', const DBusString(''), timestamp);
  }

  /// Triggers a hover event on the menu item with the specified [id].
  Future<void> sendHovered(int id) async {
    if (_disposed) return;
    final timestamp = _currentUnixTimestamp();
    await _sendEvent(id, 'hovered', const DBusString(''), timestamp);
  }

  /// Closes the menu, sends `closed` event, and cleans up open state.
  Future<void> closeMenu() async {
    if (_disposed || !_isMenuOpen) return;
    _isMenuOpen = false;
    final timestamp = _currentUnixTimestamp();
    await _sendEvent(0, 'closed', const DBusString(''), timestamp);
  }

  Future<void> _sendEvent(
    int id,
    String eventId,
    DBusValue data,
    int timestamp,
  ) async {
    if (_disposed) return;
    try {
      await _remoteObject
          .callMethod(interfaceName, 'Event', <DBusValue>[
            DBusInt32(id),
            DBusString(eventId),
            DBusVariant(data),
            DBusUint32(timestamp),
          ], replySignature: DBusSignature(''))
          .timeout(_eventTimeout);
    } catch (_) {
      // Non-critical event failure
    }
  }

  void _handleSignal(DBusSignal signal) {
    if (_disposed) return;

    if (signal.interface == interfaceName) {
      switch (signal.name) {
        case 'LayoutUpdated':
          _handleLayoutUpdated(signal);
          break;
        case 'ItemsPropertiesUpdated':
          _handleItemsPropertiesUpdated(signal);
          break;
        case 'ItemActivationRequested':
          // Handle item activation requested by the application
          break;
      }
    }
  }

  void _handleLayoutUpdated(DBusSignal signal) {
    if (_disposed || !_isMenuOpen) return;

    int newRevision = 0;
    int parentId = 0;

    if (signal.values.length >= 2) {
      newRevision = _asInt(signal.values[0]);
      parentId = _asInt(signal.values[1]);
    }

    // Ignore signals with stale revision if a newer revision was already processed
    if (newRevision > 0 && newRevision < _revision) {
      return;
    }

    // Invalidate in-flight child fetches under parentId
    _invalidateSubtreeGenerations(parentId);
    final generation = (_fetchGenerations[parentId] =
        (_fetchGenerations[parentId] ?? 0) + 1);

    if (parentId == 0 || _rootNode == null) {
      _pendingFetchParentIds.add(0);
      unawaited(() async {
        try {
          final node = await getLayout(parentId: 0, recursionDepth: -1);
          if (_disposed ||
              !_isMenuOpen ||
              _fetchGenerations[0] != generation ||
              node == null) {
            return;
          }
          if (newRevision > _revision) _revision = newRevision;
          _rootNode = node;
          _pruneStaleGenerations();
          onLayoutChanged?.call(node);
        } finally {
          _pendingFetchParentIds.remove(0);
        }
      }());
    } else {
      _pendingFetchParentIds.add(parentId);
      unawaited(() async {
        try {
          final subNode = await getLayout(
            parentId: parentId,
            recursionDepth: -1,
          );
          final root = _rootNode;
          if (_disposed ||
              !_isMenuOpen ||
              _fetchGenerations[parentId] != generation ||
              subNode == null ||
              root == null ||
              root.findNode(parentId) == null) {
            return;
          }
          if (newRevision > _revision) _revision = newRevision;
          final updatedRoot = root.updateSubtree(parentId, subNode.children);
          _rootNode = updatedRoot;
          _pruneStaleGenerations();
          onLayoutChanged?.call(updatedRoot);
        } finally {
          _pendingFetchParentIds.remove(parentId);
        }
      }());
    }
  }

  void _handleItemsPropertiesUpdated(DBusSignal signal) {
    if (_disposed || !_isMenuOpen || _rootNode == null) return;
    if (signal.values.isEmpty) return;

    var currentRoot = _rootNode!;
    bool changed = false;

    // signal.values[0]: a(ia{sv}) updated
    if (_unwrap(signal.values[0]) is DBusArray) {
      final updatedArray = _unwrap(signal.values[0])! as DBusArray;
      for (final elem in updatedArray.children) {
        if (elem is DBusStruct && elem.children.length >= 2) {
          final id = _asInt(elem.children[0]);
          final propDict = _parseProps(elem.children[1]);
          currentRoot = currentRoot.updateProperties(id, propDict);
          changed = true;
        }
      }
    }

    // signal.values[1]: a(ias) removed
    if (signal.values.length >= 2 && _unwrap(signal.values[1]) is DBusArray) {
      final removedArray = _unwrap(signal.values[1])! as DBusArray;
      for (final elem in removedArray.children) {
        if (elem is DBusStruct && elem.children.length >= 2) {
          final id = _asInt(elem.children[0]);
          final removedNames = _parseStringList(elem.children[1]);
          currentRoot = currentRoot.updateProperties(
            id,
            const <String, DBusValue>{},
            removedNames,
          );
          changed = true;
        }
      }
    }

    if (changed) {
      _rootNode = currentRoot;
      onLayoutChanged?.call(currentRoot);
    }
  }

  static Map<String, DBusValue> _parseProps(DBusValue value) {
    final result = <String, DBusValue>{};
    final unwrapped = _unwrap(value);
    if (unwrapped is DBusDict) {
      var count = 0;
      unwrapped.children.forEach((k, v) {
        if (count >= maxDBusMenuProperties) return;
        if (k is DBusString) {
          final bounded = _boundPropertyValue(_unwrap(v));
          if (bounded != null) {
            result[k.value] = bounded;
            count += 1;
          }
        }
      });
    }
    return result;
  }

  static List<String> _parseStringList(DBusValue value) {
    final unwrapped = _unwrap(value);
    if (unwrapped is DBusArray) {
      return unwrapped.children
          .whereType<DBusString>()
          .take(maxDBusMenuChildren)
          .map((s) => s.value)
          .toList();
    }
    return const <String>[];
  }

  static int _asInt(DBusValue? value) {
    final unwrapped = _unwrap(value);
    if (unwrapped is DBusInt32) return unwrapped.value;
    if (unwrapped is DBusUint32) return unwrapped.value;
    if (unwrapped is DBusInt64) return unwrapped.value;
    if (unwrapped is DBusUint64) return unwrapped.value;
    if (unwrapped is DBusByte) return unwrapped.value;
    return 0;
  }

  static DBusValue? _unwrap(DBusValue? value) {
    var current = value;
    while (current is DBusVariant) {
      current = current.value;
    }
    return current;
  }

  static DBusValue? _boundPropertyValue(DBusValue? value) {
    if (value == null) return null;
    if (value is DBusString) {
      if (value.value.length <= maxDBusMenuStringLength) return value;
      return DBusString(value.value.substring(0, maxDBusMenuStringLength));
    }
    if (value is DBusArray && value.children.length > maxDBusMenuIconBytes) {
      return null;
    }
    return value;
  }

  static int _currentUnixTimestamp() {
    return DateTime.now().millisecondsSinceEpoch ~/ 1000;
  }

  /// Disposes this client, unregistering signal streams and notifying closed if open.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true; // Cut off all incoming / external calls immediately
    final wasOpen = _isMenuOpen;
    _isMenuOpen = false;
    _fetchGenerations.clear();
    _pendingFetchParentIds.clear();

    if (wasOpen) {
      try {
        await _remoteObject
            .callMethod(interfaceName, 'Event', <DBusValue>[
              DBusInt32(0),
              const DBusString('closed'),
              const DBusVariant(DBusString('')),
              DBusUint32(_currentUnixTimestamp()),
            ], replySignature: DBusSignature(''))
            .timeout(_eventTimeout);
      } catch (_) {
        // Non-critical event failure during teardown
      }
    }

    await _signalSubscription?.cancel();
    _signalSubscription = null;
  }
}
