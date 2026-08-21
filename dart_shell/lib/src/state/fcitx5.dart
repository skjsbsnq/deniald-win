import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/fcitx5_service.dart';

final fcitx5ServiceProvider = Provider<Fcitx5Backend>((ref) {
  if (Platform.environment['FLUTTER_TEST'] == 'true') {
    return const _UnavailableFcitx5Backend();
  }
  final service = Fcitx5Service();
  ref.onDispose(() => unawaited(service.dispose()));
  return service;
});

final fcitx5Provider = NotifierProvider<Fcitx5Controller, Fcitx5Snapshot>(
  Fcitx5Controller.new,
);

class Fcitx5Controller extends Notifier<Fcitx5Snapshot> {
  Fcitx5Backend? _service;
  StreamSubscription<Fcitx5Snapshot>? _subscription;

  @override
  Fcitx5Snapshot build() {
    final service = ref.watch(fcitx5ServiceProvider);
    _service = service;
    _subscription = service.snapshots.listen((snapshot) => state = snapshot);
    ref.onDispose(() => unawaited(_subscription?.cancel()));
    unawaited(service.start());
    return service.current;
  }

  Future<void> setChinese(bool chinese) async {
    final service = _service;
    if (service == null) return;
    try {
      await service.setChinese(chinese);
    } on Object {
      await service.refresh();
    }
  }

  Future<void> refresh() => _service?.refresh() ?? Future<void>.value();
}

class _UnavailableFcitx5Backend implements Fcitx5Backend {
  const _UnavailableFcitx5Backend();

  @override
  Fcitx5Snapshot get current => const Fcitx5Snapshot.unavailable();

  @override
  Stream<Fcitx5Snapshot> get snapshots => const Stream<Fcitx5Snapshot>.empty();

  @override
  Future<void> dispose() => Future<void>.value();

  @override
  Future<void> refresh() => Future<void>.value();

  @override
  Future<void> setChinese(bool chinese) => Future<void>.value();

  @override
  Future<void> start() => Future<void>.value();
}
