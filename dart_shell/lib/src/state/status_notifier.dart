import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/tray_item.dart';
import '../services/dbus_menu_client.dart';
import '../services/status_notifier_host.dart';
import 'notifier_lifecycle.dart';

/// Immutable state describing all tracked StatusNotifierItems on the system.
@immutable
class StatusNotifierState {
  const StatusNotifierState({
    required this.serviceAvailable,
    required this.isWatcher,
    required this.isHostRegistered,
    required this.items,
    required this.initializing,
    required this.refreshing,
    this.error,
  });

  factory StatusNotifierState.initial() => const StatusNotifierState(
    serviceAvailable: false,
    isWatcher: false,
    isHostRegistered: false,
    items: <TrayItem>[],
    initializing: true,
    refreshing: false,
    error: null,
  );

  final bool serviceAvailable;
  final bool isWatcher;
  final bool isHostRegistered;
  final List<TrayItem> items;
  final bool initializing;
  final bool refreshing;
  final String? error;

  /// Items that should be rendered in the primary tray area.
  List<TrayItem> get activeItems => items
      .where(
        (item) =>
            item.status == TrayItemStatus.active ||
            item.status == TrayItemStatus.needsAttention,
      )
      .toList(growable: false);

  /// Items that request to be placed in an overflow or passive area.
  List<TrayItem> get passiveItems => items
      .where((item) => item.status == TrayItemStatus.passive)
      .toList(growable: false);

  StatusNotifierState copyWith({
    bool? serviceAvailable,
    bool? isWatcher,
    bool? isHostRegistered,
    List<TrayItem>? items,
    bool? initializing,
    bool? refreshing,
    String? error,
    bool clearError = false,
  }) {
    return StatusNotifierState(
      serviceAvailable: serviceAvailable ?? this.serviceAvailable,
      isWatcher: isWatcher ?? this.isWatcher,
      isHostRegistered: isHostRegistered ?? this.isHostRegistered,
      items: items ?? this.items,
      initializing: initializing ?? this.initializing,
      refreshing: refreshing ?? this.refreshing,
      error: clearError ? null : (error ?? this.error),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StatusNotifierState &&
          other.serviceAvailable == serviceAvailable &&
          other.isWatcher == isWatcher &&
          other.isHostRegistered == isHostRegistered &&
          listEquals(other.items, items) &&
          other.initializing == initializing &&
          other.refreshing == refreshing &&
          other.error == error;

  @override
  int get hashCode => Object.hash(
    serviceAvailable,
    isWatcher,
    isHostRegistered,
    Object.hashAll(items),
    initializing,
    refreshing,
    error,
  );
}

final statusNotifierProvider =
    NotifierProvider<StatusNotifierController, StatusNotifierState>(
      StatusNotifierController.new,
    );

/// Controller managing the StatusNotifier (SNI) state and lifecycle.
class StatusNotifierController extends Notifier<StatusNotifierState>
    with NotifierLifecycle<StatusNotifierState> {
  late StatusNotifierHostService _service;
  late int _buildGeneration;

  @override
  StatusNotifierState build() {
    _service = ref.watch(statusNotifierHostServiceProvider);
    _buildGeneration = beginBuildGeneration();
    final generation = _buildGeneration;

    final snapshotSub = _service.snapshots.listen((items) {
      if (isBuildGenerationActive(generation)) {
        state = state.copyWith(
          items: items,
          isWatcher: _service.watcherService.isPrimaryWatcher,
          isHostRegistered: _service.isHostRegistered,
          serviceAvailable: true,
          initializing: false,
        );
      }
    });
    cancelOnDispose(snapshotSub);

    scheduleMicrotask(() {
      if (isBuildGenerationActive(generation)) {
        unawaited(_start(generation));
      }
    });

    return StatusNotifierState.initial();
  }

  Future<void> _start(int generation) async {
    try {
      await _service.start();
      if (isBuildGenerationActive(generation)) {
        state = state.copyWith(
          serviceAvailable: true,
          isWatcher: _service.watcherService.isPrimaryWatcher,
          isHostRegistered: _service.isHostRegistered,
          items: _service.currentItems,
          initializing: false,
        );
      }
    } on Object catch (e) {
      if (isBuildGenerationActive(generation)) {
        state = state.copyWith(
          serviceAvailable: false,
          initializing: false,
          error: 'Failed to start StatusNotifier service: $e',
        );
      }
    }
  }

  Future<void> refresh() async {
    if (state.refreshing) return;
    final generation = _buildGeneration;
    state = state.copyWith(refreshing: true, clearError: true);

    try {
      await _service.refresh();
      if (isBuildGenerationActive(generation)) {
        state = state.copyWith(
          items: _service.currentItems,
          isWatcher: _service.watcherService.isPrimaryWatcher,
          isHostRegistered: _service.isHostRegistered,
          refreshing: false,
        );
      }
    } on Object catch (e) {
      if (isBuildGenerationActive(generation)) {
        state = state.copyWith(refreshing: false, error: 'Refresh failed: $e');
      }
    }
  }

  Future<void> activate(TrayItem item, {int x = 0, int y = 0}) =>
      _service.activate(item, x: x, y: y);

  Future<void> secondaryActivate(TrayItem item, {int x = 0, int y = 0}) =>
      _service.secondaryActivate(item, x: x, y: y);

  Future<void> contextMenu(TrayItem item, {int x = 0, int y = 0}) =>
      _service.contextMenu(item, x: x, y: y);

  /// Creates a [DBusMenuClient] for the specified [item].
  DBusMenuClient? createMenuClient(TrayItem item) =>
      _service.createMenuClient(item);

  Future<void> scroll(TrayItem item, int delta, String orientation) =>
      _service.scroll(item, delta, orientation);

  void clearError() {
    if (state.error != null) {
      state = state.copyWith(clearError: true);
    }
  }
}
