import 'dart:async';

import 'package:denial_dart_shell/src/widgets/app_icon.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('app icon load gate admits at most four concurrent loads', () async {
    final admitted = <Future<void>>[
      for (
        var index = 0;
        index < AppIconLoadGate.maximumConcurrent + 1;
        index++
      )
        AppIconLoadGate.acquire(),
    ];

    await Future.wait(admitted.take(AppIconLoadGate.maximumConcurrent));
    expect(AppIconLoadGate.activeCount, AppIconLoadGate.maximumConcurrent);

    var fifthAdmitted = false;
    unawaited(admitted.last.then((_) => fifthAdmitted = true));
    await Future<void>.delayed(Duration.zero);
    expect(fifthAdmitted, isFalse);

    AppIconLoadGate.release();
    await admitted.last;
    expect(fifthAdmitted, isTrue);
    expect(AppIconLoadGate.activeCount, AppIconLoadGate.maximumConcurrent);

    for (var index = 0; index < AppIconLoadGate.maximumConcurrent; index++) {
      AppIconLoadGate.release();
    }
    expect(AppIconLoadGate.activeCount, 0);
  });
}
