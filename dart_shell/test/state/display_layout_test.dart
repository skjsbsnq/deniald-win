import 'package:denial_dart_shell/src/models/display_layout.dart';
import 'package:denial_dart_shell/src/platform/denial_bridge.dart';
import 'package:denial_dart_shell/src/state/display_layout.dart';
import 'package:denial_dart_shell/src/state/shell_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a padding-only change publishes the configured system bar', () async {
    final bridge = _SystemBarPublishingBridge(
      DisplayLayout.fallback(const Size(1600, 900), 1),
    );
    addTearDown(bridge.dispose);
    final container = ProviderContainer(
      overrides: [denialBridgeProvider.overrideWithValue(bridge)],
    );
    addTearDown(container.dispose);
    final controller = container.read(displayLayoutProvider.notifier);
    await pumpEventQueue();
    expect(container.read(displayLayoutProvider), isNotNull);
    // The unconfigured shell never publishes; the native layout stays
    // authoritative until Settings applies persisted policy.
    expect(bridge.requests, isEmpty);

    // Same side, thickness, and monitors as the native layout: only the
    // maximize padding differs, which must still reach the work area.
    controller.applyShellConfiguration(
      side: SystemBarSide.top,
      outputNames: const <String>['default'],
      systemBarThickness: 32.0,
      maximizePadding: 24.0,
    );
    await pumpEventQueue();

    expect(bridge.requests, hasLength(1));
    final request = bridge.requests.single;
    expect(request.side, SystemBarSide.top);
    expect(request.monitorIds, const <int>[0]);
    expect(request.thickness, 32.0);
    expect(request.maximizePadding, 24.0);

    // Re-applying the same policy converges: the echoed native layout now
    // matches, so no further publish is queued.
    controller.applyShellConfiguration(
      side: SystemBarSide.top,
      outputNames: const <String>['default'],
      systemBarThickness: 32.0,
      maximizePadding: 24.0,
    );
    await pumpEventQueue();
    expect(bridge.requests, hasLength(1));
  });
}

class _RecordedSystemBarRequest {
  _RecordedSystemBarRequest({
    required this.side,
    required this.monitorIds,
    required this.thickness,
    required this.maximizePadding,
  });

  final SystemBarSide side;
  final List<int> monitorIds;
  final double thickness;
  final double maximizePadding;
}

class _SystemBarPublishingBridge extends DenialBridge {
  _SystemBarPublishingBridge(this.native);

  final DisplayLayout native;
  final List<_RecordedSystemBarRequest> requests =
      <_RecordedSystemBarRequest>[];

  @override
  Future<DisplayLayout?> getDisplayLayout() async => native;

  @override
  Future<DisplayLayout?> configureSystemBar({
    required SystemBarSide side,
    required List<int> monitorIds,
    required double thickness,
    double maximizePadding = 0,
  }) async {
    requests.add(
      _RecordedSystemBarRequest(
        side: side,
        monitorIds: monitorIds,
        thickness: thickness,
        maximizePadding: maximizePadding,
      ),
    );
    return native;
  }
}
