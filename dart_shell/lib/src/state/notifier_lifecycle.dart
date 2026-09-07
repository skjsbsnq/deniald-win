import 'dart:async';

import 'package:flutter/foundation.dart' show protected;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shared lifecycle guards for Notifiers that own asynchronous work.
///
/// A Riverpod 3 Notifier instance survives dependency-driven rebuilds while
/// its state and build-scoped resources do not. Capturing a generation keeps
/// work started by an old build from publishing into a newer one.
mixin NotifierLifecycle<StateT> on Notifier<StateT> {
  int _nextBuildGeneration = 0;
  int _activeBuildGeneration = 0;

  @protected
  int beginBuildGeneration() {
    final generation = ++_nextBuildGeneration;
    _activeBuildGeneration = generation;
    ref.onDispose(() {
      if (_activeBuildGeneration == generation) {
        _activeBuildGeneration = 0;
      }
    });
    return generation;
  }

  @protected
  bool isBuildGenerationActive(int generation) =>
      ref.mounted && _activeBuildGeneration == generation;

  /// The generation of the most recent build. Methods that start async work
  /// outside build() (explicit refreshes, user actions) capture this and
  /// validate with [isBuildGenerationActive].
  @protected
  int get currentBuildGeneration => _activeBuildGeneration;

  @protected
  void cancelOnDispose<T>(StreamSubscription<T> subscription) {
    ref.onDispose(() => unawaited(subscription.cancel()));
  }
}
