import 'dart:io';

import 'package:denial_dart_shell/src/launcher/models/home_battery_discharge_info.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition was not met in time');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late Directory directory;
  late File file;
  late HomeBatteryDischargeTailReader reader;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('battery-tail-test');
    file = File('${directory.path}/battery_discharge.tsv');
    file.writeAsStringSync(
      'ts_ms\tsrc\tstate\tcapacity\tcurrent_ma\tvoltage_mv\tpower_mw\n'
      '1000\tboot\tdischarging\t80\t-500\t12000\t6000\n',
    );
    reader = HomeBatteryDischargeTailReader(
      file: file,
      eventDebounce: const Duration(milliseconds: 10),
      recoveryInterval: const Duration(milliseconds: 50),
    );
  });

  tearDown(() async {
    await reader.dispose();
    directory.deleteSync(recursive: true);
  });

  test(
    'snapshots accepts a second subscription after the first cancels',
    () async {
      final first = await reader.snapshots.first;
      expect(first.points, hasLength(1));

      final second = await reader.snapshots.first;
      expect(second.points, hasLength(1));
    },
  );

  test('stops the watch and the recovery timer while unlistened', () async {
    final subscription = reader.snapshots.listen((_) {});
    await _waitFor(() => reader.debugHasActiveWatch);
    await _waitFor(() => reader.debugRecoveryTimerActive);

    await subscription.cancel();
    await _waitFor(
      () => !reader.debugHasActiveWatch && !reader.debugRecoveryTimerActive,
    );
  });

  test(
    're-establishes the watch when a subscription cancels mid-setup',
    () async {
      // The cancel lands while _ensureWatch is still inside its awaits; the
      // next listener must still get a working watch and watchdog.
      final first = reader.snapshots.listen((_) {});
      await first.cancel();

      final second = reader.snapshots.listen((_) {});
      await _waitFor(() => reader.debugHasActiveWatch);
      await _waitFor(() => reader.debugRecoveryTimerActive);
      await second.cancel();
    },
  );

  test('a dead watch is dropped and the watchdog re-establishes it', () async {
    final events = <HomeBatteryDischargeSeries>[];
    final subscription = reader.snapshots.listen(events.add);
    await _waitFor(() => reader.debugHasActiveWatch);

    // Deleting the watched directory ends the watch stream; its late
    // onDone/onError must drop only that generation of the watch.
    directory.deleteSync(recursive: true);
    await _waitFor(() => !reader.debugHasActiveWatch);

    directory.createSync();
    file.writeAsStringSync('3000\tboot\tdischarging\t78\t-450\t11800\t5400\n');
    await _waitFor(() => reader.debugHasActiveWatch);
    await _waitFor(
      () => events.isNotEmpty && events.last.latest?.wallMs == 3000,
    );
    await subscription.cancel();
  });

  test('a returning listener gets a fresh tail read', () async {
    final first = await reader.snapshots.first;
    expect(first.points, hasLength(1));

    file.writeAsStringSync(
      '2000\tboot\tdischarging\t79\t-480\t11900\t5800\n',
      mode: FileMode.append,
    );

    final second = await reader.snapshots.first;
    expect(second.points, hasLength(2));
    expect(second.latest?.wallMs, 2000);
    // Both samples sit inside the trailing 60 s window of the newest point.
    expect(second.averageDrawMa60, 490);
    expect(second.graph.hasValues, isTrue);
  });
}
