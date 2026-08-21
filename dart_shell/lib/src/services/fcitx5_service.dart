import 'dart:async';
import 'dart:io';

import 'package:dbus/dbus.dart';

class Fcitx5Snapshot {
  const Fcitx5Snapshot({
    required this.available,
    required this.inputMethod,
    required this.label,
    required this.languageCode,
  });

  const Fcitx5Snapshot.unavailable()
    : available = false,
      inputMethod = '',
      label = '',
      languageCode = '';

  final bool available;
  final String inputMethod;
  final String label;
  final String languageCode;

  bool get isChinese =>
      languageCode.toLowerCase().startsWith('zh') || inputMethod == 'pinyin';

  String get shortLabel => isChinese ? '\u4e2d' : 'EN';
}

abstract interface class Fcitx5Backend {
  Fcitx5Snapshot get current;

  Stream<Fcitx5Snapshot> get snapshots;

  Future<void> start();

  Future<void> refresh();

  Future<void> setChinese(bool chinese);

  Future<void> dispose();
}

class Fcitx5Service implements Fcitx5Backend {
  factory Fcitx5Service({DBusClient? client}) {
    final sessionClient = client ?? DBusClient.session();
    return Fcitx5Service._(sessionClient);
  }

  Fcitx5Service._(DBusClient client)
    : _client = client,
      _controller = DBusRemoteObject(
        client,
        name: _serviceName,
        path: DBusObjectPath(_controllerPath),
      );

  static const _serviceName = 'org.fcitx.Fcitx5';
  static const _controllerPath = '/controller';
  static const _interfaceName = 'org.fcitx.Fcitx.Controller1';
  static const _pollInterval = Duration(milliseconds: 500);
  static const _timeout = Duration(seconds: 2);

  final DBusClient _client;
  final DBusRemoteObject _controller;
  final _snapshots = StreamController<Fcitx5Snapshot>.broadcast(sync: true);
  Timer? _pollTimer;
  Fcitx5Snapshot _current = const Fcitx5Snapshot.unavailable();
  bool _started = false;
  bool _disposed = false;
  bool _refreshing = false;
  bool _launchAttempted = false;

  @override
  Fcitx5Snapshot get current => _current;

  @override
  Stream<Fcitx5Snapshot> get snapshots => _snapshots.stream;

  @override
  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    await refresh();
    if (!_current.available) {
      await _launchFcitx5();
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await refresh();
    }
    if (!_disposed) {
      _pollTimer = Timer.periodic(_pollInterval, (_) => unawaited(refresh()));
    }
  }

  @override
  Future<void> refresh() async {
    if (_disposed || _refreshing) return;
    _refreshing = true;
    try {
      final current = await _controller
          .callMethod(
            _interfaceName,
            'CurrentInputMethod',
            const <DBusValue>[],
            replySignature: DBusSignature('s'),
          )
          .timeout(_timeout);
      final inputMethod = current.returnValues.single.asString();
      final info = await _controller
          .callMethod(
            _interfaceName,
            'CurrentInputMethodInfo',
            const <DBusValue>[],
            replySignature: DBusSignature('sssssssbsa{sv}'),
          )
          .timeout(_timeout);
      _emit(buildFcitx5Snapshot(inputMethod, info.returnValues));
    } on Object {
      _emit(const Fcitx5Snapshot.unavailable());
    } finally {
      _refreshing = false;
    }
  }

  @override
  Future<void> setChinese(bool chinese) async {
    final inputMethod = chinese ? 'pinyin' : 'keyboard-us';
    await _controller
        .callMethod(_interfaceName, 'SetCurrentIM', <DBusValue>[
          DBusString(inputMethod),
        ], replySignature: DBusSignature(''))
        .timeout(_timeout);
    await refresh();
  }

  Future<void> _launchFcitx5() async {
    if (_launchAttempted || _disposed) return;
    _launchAttempted = true;
    try {
      await Process.start('/usr/bin/fcitx5', const <String>[
        '-d',
      ], mode: ProcessStartMode.detached);
    } on Object {
      // Fcitx5 is optional. The unavailable state keeps the UI disabled.
    }
  }

  void _emit(Fcitx5Snapshot snapshot) {
    if (_current.inputMethod == snapshot.inputMethod &&
        _current.available == snapshot.available &&
        _current.languageCode == snapshot.languageCode &&
        _current.label == snapshot.label) {
      return;
    }
    _current = snapshot;
    if (!_snapshots.isClosed) _snapshots.add(snapshot);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _pollTimer?.cancel();
    await _snapshots.close();
    await _client.close();
  }
}

Fcitx5Snapshot buildFcitx5Snapshot(
  String inputMethod,
  List<DBusValue> infoValues,
) {
  return Fcitx5Snapshot(
    available: true,
    inputMethod: inputMethod,
    label: infoValues.length > 1 ? infoValues[1].asString() : inputMethod,
    languageCode: infoValues.length > 5 ? infoValues[5].asString() : '',
  );
}
