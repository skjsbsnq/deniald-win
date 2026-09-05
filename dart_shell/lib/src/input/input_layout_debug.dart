import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/startup_environment.dart';
import 'input_layout.dart';

/// Debug mirror of the most recent input layout published to the compositor.
///
/// `DENIA_DEBUG_INPUT_REGIONS=1` makes the desktop input-layout publisher
/// mirror every snapshot here so the [InputRegionDebugOverlay] can paint the
/// rectangles the native side actually routes by. The provider is not
/// autoDispose on purpose: the publisher writes it from outside the subtree
/// that reads it, and an autoDispose provider would drop the latest snapshot
/// whenever the overlay is not mounted. Release builds compile every write
/// out through [kDebugMode].
final debugInputLayoutSnapshotProvider =
    NotifierProvider<DebugInputLayoutSnapshot, InputLayoutSnapshot?>(
      DebugInputLayoutSnapshot.new,
    );

class DebugInputLayoutSnapshot extends Notifier<InputLayoutSnapshot?> {
  @override
  InputLayoutSnapshot? build() => null;

  void publish(InputLayoutSnapshot snapshot) {
    state = snapshot;
  }
}

/// Whether the compositor input-routing rectangles should be visualized.
///
/// Always false in release builds: the flag check sits behind [kDebugMode],
/// so the constant folds and the tool's writes and overlay compile out.
bool inputRegionDebugEnabled(StartupEnvironment environment) {
  return kDebugMode && environment.flag('DENIA_DEBUG_INPUT_REGIONS');
}
