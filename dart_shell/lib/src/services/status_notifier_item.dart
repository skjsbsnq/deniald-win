import 'dart:async';
import 'dart:typed_data';

import 'package:dbus/dbus.dart';

import '../models/tray_item.dart';
import 'sni_pixmap_decoder.dart';
import 'status_notifier_watcher.dart';

/// Client representing a remote StatusNotifierItem on D-Bus.
class StatusNotifierItemClient {
  StatusNotifierItemClient({
    required this.address,
    required DBusClient client,
    this.onChanged,
  }) : _client = client,
       _remoteObject = DBusRemoteObject(
         client,
         name: address.service,
         path: DBusObjectPath(address.path),
       );

  static const String interfaceName = 'org.kde.StatusNotifierItem';
  static const Duration _readTimeout = Duration(seconds: 2);
  static const Duration _methodTimeout = Duration(seconds: 4);
  static const Duration _coalesceDuration = Duration(milliseconds: 50);
  static const int _maxTextLength = 4096;
  static const int _maxPixmapVariants = 32;
  static const int _maxTotalPixmapBytes = 32 * 1024 * 1024;

  final StatusNotifierAddress address;
  final DBusClient _client;
  final DBusRemoteObject _remoteObject;
  final void Function(TrayItem item)? onChanged;

  StreamSubscription<DBusSignal>? _signalSubscription;
  Timer? _coalesceTimer;
  TrayItem? _current;
  bool _disposed = false;
  bool _refreshing = false;
  bool _refreshAgain = false;
  bool _needsTrailingRefresh = false;

  TrayItem? get current => _current;
  bool get isDisposed => _disposed;

  /// Starts listening to signals and fetches initial properties.
  Future<void> start() async {
    if (_disposed) return;

    String? uniqueSender;
    if (address.service.startsWith(':')) {
      uniqueSender = address.service;
    } else if (address.service.isNotEmpty) {
      try {
        uniqueSender = await _client
            .getNameOwner(address.service)
            .timeout(_readTimeout);
      } catch (_) {
        uniqueSender = null;
      }
    }

    if (_disposed) return;

    // Never subscribe without a resolved unique sender. A wildcard signal
    // subscription would allow another session-bus peer to spoof item state.
    if (uniqueSender != null) {
      _signalSubscription =
          DBusSignalStream(
            _client,
            sender: uniqueSender,
            path: DBusObjectPath(address.path),
            interface: interfaceName,
          ).listen((signal) {
            if (signal.sender != uniqueSender) return;
            _handleSignal(signal);
          }, onError: (_) => _scheduleRefresh());
    }

    await refresh();
  }

  /// Triggers an asynchronous refresh of the item's properties using `GetAll`.
  Future<void> refresh() async {
    if (_disposed) return;
    if (_refreshing) {
      _refreshAgain = true;
      return;
    }
    _refreshing = true;

    try {
      do {
        _refreshAgain = false;
        try {
          final properties = await _fetchProperties();
          if (_disposed) return;

          final item = _parseProperties(properties);
          _current = item;
          onChanged?.call(item);
        } catch (_) {
          // If fetching fails, provide a degraded fallback if we don't already have one
          if (_current == null && !_disposed) {
            final fallback = TrayItem(
              service: address.service,
              path: address.path,
              id: address.service,
              title: address.service,
            );
            _current = fallback;
            onChanged?.call(fallback);
          }
        }
      } while (_refreshAgain && !_disposed);
    } finally {
      _refreshing = false;
    }
  }

  Future<Map<String, DBusValue>> _fetchProperties() async {
    try {
      return await _remoteObject
          .getAllProperties(interfaceName)
          .timeout(_readTimeout);
    } on Object {
      // If GetAll is rejected or unsupported, attempt individual gets as fallback
      return _fetchPropertiesIndividually();
    }
  }

  Future<Map<String, DBusValue>> _fetchPropertiesIndividually() async {
    final propertyNames = <String>[
      'Category',
      'Id',
      'Title',
      'Status',
      'WindowId',
      'IconName',
      'IconThemePath',
      'IconPixmap',
      'OverlayIconName',
      'OverlayIconPixmap',
      'AttentionIconName',
      'AttentionIconPixmap',
      'Menu',
      'ItemIsMenu',
      'ToolTip',
    ];

    try {
      final futures = propertyNames.map((name) async {
        if (_disposed) return null;
        try {
          final val = await _remoteObject
              .getProperty(interfaceName, name)
              .timeout(_readTimeout);
          return MapEntry<String, DBusValue>(name, val);
        } on Object {
          return null;
        }
      });

      final entries = await Future.wait(futures);
      final result = <String, DBusValue>{};
      for (final entry in entries) {
        if (entry != null) {
          result[entry.key] = entry.value;
        }
      }
      return result;
    } on Object {
      return const <String, DBusValue>{};
    }
  }

  TrayItem _parseProperties(Map<String, DBusValue> props) {
    final id = _asString(props['Id'], fallback: address.service);
    final title = _asString(props['Title'], fallback: id);
    final statusStr = _asString(props['Status'], fallback: 'Active');
    final categoryStr = _asString(
      props['Category'],
      fallback: 'ApplicationStatus',
    );
    final windowId = _asInt(props['WindowId']);
    final iconName = _asString(props['IconName']);
    final iconThemePath = _asString(props['IconThemePath']);
    final iconPixmap = _parsePixmaps(props['IconPixmap']);
    final overlayIconName = _asString(props['OverlayIconName']);
    final overlayIconPixmap = _parsePixmaps(props['OverlayIconPixmap']);
    final attentionIconName = _asString(props['AttentionIconName']);
    final attentionIconPixmap = _parsePixmaps(props['AttentionIconPixmap']);
    final menuPath = _asObjectPath(props['Menu']);
    final itemIsMenu = _asBool(props['ItemIsMenu']);

    final toolTip = _parseToolTip(props['ToolTip']);

    return TrayItem(
      service: address.service,
      path: address.path,
      id: id,
      title: title,
      status: TrayItemStatus.fromString(statusStr),
      category: TrayItemCategory.fromString(categoryStr),
      windowId: windowId,
      iconName: iconName,
      iconThemePath: iconThemePath,
      iconPixmap: iconPixmap,
      overlayIconName: overlayIconName,
      overlayIconPixmap: overlayIconPixmap,
      attentionIconName: attentionIconName,
      attentionIconPixmap: attentionIconPixmap,
      menuPath: menuPath,
      itemIsMenu: itemIsMenu,
      toolTipIconName: toolTip.iconName,
      toolTipIconPixmap: toolTip.iconPixmap,
      toolTipTitle: toolTip.title,
      toolTipDescription: toolTip.description,
    );
  }

  List<TrayPixmap> _parsePixmaps(DBusValue? value) {
    if (value == null) return const <TrayPixmap>[];
    final list = <TrayPixmap>[];
    var totalBytes = 0;
    final unwrapped = _unwrap(value);
    if (unwrapped is DBusArray) {
      if (unwrapped.children.length > _maxPixmapVariants) {
        return const <TrayPixmap>[];
      }
      for (final elem in unwrapped.children) {
        if (elem is DBusStruct && elem.children.length >= 3) {
          final w = _asInt(elem.children[0]);
          final h = _asInt(elem.children[1]);
          final requiredBytes = sniPixmapByteCount(w, h);
          if (requiredBytes == null ||
              totalBytes + requiredBytes > _maxTotalPixmapBytes) {
            continue;
          }
          final byteVal = _unwrap(elem.children[2]);
          Uint8List? bytes;
          if (byteVal is DBusArray) {
            if (byteVal.children.length < requiredBytes ||
                byteVal.children.length > maxSniPixmapBytes) {
              continue;
            }
            final values = <int>[];
            var valid = true;
            for (final child in byteVal.children) {
              if (child is DBusByte) {
                values.add(child.value);
              } else {
                valid = false;
                break;
              }
            }
            if (!valid) continue;
            bytes = Uint8List.fromList(values);
          }
          if (bytes != null && bytes.length >= requiredBytes) {
            list.add(TrayPixmap(width: w, height: h, bytes: bytes));
            totalBytes += requiredBytes;
          }
        }
      }
    }
    return list;
  }

  _ToolTipInfo _parseToolTip(DBusValue? value) {
    if (value is DBusStruct) {
      final children = value.children;
      if (children.length >= 4) {
        final iconName = _asString(children[0]);
        final iconPixmaps = _parsePixmaps(children[1]);
        final title = _asString(children[2]);
        final desc = _asString(children[3]);
        return _ToolTipInfo(
          iconName: iconName,
          iconPixmap: iconPixmaps,
          title: title,
          description: desc,
        );
      } else if (children.length >= 2) {
        final title = _asString(children[0]);
        final desc = _asString(children[1]);
        return _ToolTipInfo(title: title, description: desc);
      }
    }
    return const _ToolTipInfo(title: '', description: '');
  }

  void _handleSignal(DBusSignal signal) {
    if (_disposed) return;

    if (signal is DBusPropertiesChangedSignal) {
      if (signal.propertiesInterface == interfaceName) {
        _scheduleRefresh();
      }
      return;
    }

    if (signal.interface == interfaceName) {
      switch (signal.name) {
        case 'NewTitle':
        case 'NewIcon':
        case 'NewAttentionIcon':
        case 'NewOverlayIcon':
        case 'NewToolTip':
        case 'NewMenu':
          _scheduleRefresh();
          break;
        case 'NewStatus':
          if (signal.values.isNotEmpty && signal.values[0] is DBusString) {
            final newStatus = (signal.values[0] as DBusString).value;
            if (_current != null) {
              final updated = _current!.copyWith(
                status: TrayItemStatus.fromString(newStatus),
              );
              _current = updated;
              onChanged?.call(updated);
            }
          }
          _scheduleRefresh();
          break;
        default:
          _scheduleRefresh();
      }
    }
  }

  void _scheduleRefresh() {
    if (_disposed) return;
    if (_coalesceTimer != null && _coalesceTimer!.isActive) {
      _needsTrailingRefresh = true;
      return;
    }
    _needsTrailingRefresh = false;
    _coalesceTimer = Timer(_coalesceDuration, () {
      _coalesceTimer = null;
      if (!_disposed) {
        unawaited(refresh());
        if (_needsTrailingRefresh) {
          _scheduleRefresh();
        }
      }
    });
  }

  Future<void> activate({int x = 0, int y = 0}) async {
    if (_disposed) return;
    try {
      await _remoteObject
          .callMethod(interfaceName, 'Activate', <DBusValue>[
            DBusInt32(x),
            DBusInt32(y),
          ], replySignature: DBusSignature(''))
          .timeout(_methodTimeout);
    } catch (_) {}
  }

  Future<void> secondaryActivate({int x = 0, int y = 0}) async {
    if (_disposed) return;
    try {
      await _remoteObject
          .callMethod(interfaceName, 'SecondaryActivate', <DBusValue>[
            DBusInt32(x),
            DBusInt32(y),
          ], replySignature: DBusSignature(''))
          .timeout(_methodTimeout);
    } catch (_) {}
  }

  Future<void> contextMenu({int x = 0, int y = 0}) async {
    if (_disposed) return;
    try {
      await _remoteObject
          .callMethod(interfaceName, 'ContextMenu', <DBusValue>[
            DBusInt32(x),
            DBusInt32(y),
          ], replySignature: DBusSignature(''))
          .timeout(_methodTimeout);
    } catch (_) {}
  }

  Future<void> scroll(int delta, String orientation) async {
    if (_disposed) return;
    try {
      await _remoteObject
          .callMethod(interfaceName, 'Scroll', <DBusValue>[
            DBusInt32(delta),
            DBusString(orientation),
          ], replySignature: DBusSignature(''))
          .timeout(_methodTimeout);
    } catch (_) {}
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _coalesceTimer?.cancel();
    _coalesceTimer = null;
    await _signalSubscription?.cancel();
    _signalSubscription = null;
    defaultSniPixmapDecoder.evict(address.toWireString());
    defaultSniPixmapDecoder.evict(address.service);
  }

  static String _asString(DBusValue? value, {String fallback = ''}) {
    final unwrapped = _unwrap(value);
    if (unwrapped is DBusString) {
      final text = unwrapped.value.trim();
      return text.length <= _maxTextLength
          ? text
          : text.substring(0, _maxTextLength);
    }
    return fallback;
  }

  static String _asObjectPath(DBusValue? value, {String fallback = ''}) {
    final unwrapped = _unwrap(value);
    final candidate = switch (unwrapped) {
      DBusObjectPath path => path.value.trim(),
      DBusString string => string.value.trim(),
      _ => '',
    };
    if (candidate.isEmpty) return fallback;
    try {
      DBusObjectPath(candidate);
      return candidate;
    } on Object {
      return fallback;
    }
  }

  static int _asInt(DBusValue? value, {int fallback = 0}) {
    final unwrapped = _unwrap(value);
    if (unwrapped is DBusInt32) return unwrapped.value;
    if (unwrapped is DBusUint32) return unwrapped.value;
    if (unwrapped is DBusInt64) return unwrapped.value;
    if (unwrapped is DBusUint64) return unwrapped.value;
    if (unwrapped is DBusByte) return unwrapped.value;
    return fallback;
  }

  static bool _asBool(DBusValue? value, {bool fallback = false}) {
    final unwrapped = _unwrap(value);
    if (unwrapped is DBusBoolean) return unwrapped.value;
    return fallback;
  }

  static DBusValue? _unwrap(DBusValue? value) {
    var current = value;
    while (current is DBusVariant) {
      current = current.value;
    }
    return current;
  }
}

class _ToolTipInfo {
  const _ToolTipInfo({
    this.iconName = '',
    this.iconPixmap = const <TrayPixmap>[],
    required this.title,
    required this.description,
  });

  final String iconName;
  final List<TrayPixmap> iconPixmap;
  final String title;
  final String description;
}
