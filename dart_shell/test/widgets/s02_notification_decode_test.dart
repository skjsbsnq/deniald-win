import 'dart:typed_data';

import 'package:denial_dart_shell/src/models/desktop_notification.dart';
import 'package:denial_dart_shell/src/services/notification_policy_repository.dart';
import 'package:denial_dart_shell/src/state/desktop_notifications.dart';
import 'package:denial_dart_shell/src/widgets/notification_banner.dart';
import 'package:denial_dart_shell/src/widgets/notification_media.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/desktop_notifications_harness.dart';
import '../support/notification_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('banner subscription slice', () {
    testWidgets('history and read churn do not rebuild banner subscribers', (
      tester,
    ) async {
      final harness = DesktopNotificationsTestHarness();
      addTearDown(harness.dispose);

      var builds = 0;
      NotificationBannerSlice? lastSlice;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: harness.container,
          child: Consumer(
            builder: (context, ref, _) {
              builds += 1;
              lastSlice = ref.watch(
                desktopNotificationsProvider.select(
                  NotificationBannerSlice.fromState,
                ),
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(builds, 1);
      expect(lastSlice!.notifications, isEmpty);

      // A presented banner changes the slice and rebuilds subscribers.
      harness.add(notificationEvent(notificationFixture(id: 1)));
      await tester.pump();
      expect(builds, 2);
      expect(lastSlice!.notifications.map((n) => n.id), [1]);

      // Read markers flip history records without touching the banners.
      harness.controller.markAllRead();
      await tester.pump();
      expect(builds, 2);

      // A history-only append never enters the banner queue.
      harness.add(
        notificationEvent(notificationFixture(id: 9, resident: true)),
      );
      await tester.pump();
      expect(builds, 2);
      expect(
        harness.state.history.map((record) => record.notification.id),
        contains(9),
      );

      // Replacing a presented notification swaps the list element.
      harness.add(
        notificationEvent(notificationFixture(id: 1, summary: 'Updated')),
      );
      await tester.pump();
      expect(builds, 3);
      expect(lastSlice!.notifications.single.summary, 'Updated');

      // The lock preview policy is part of the slice.
      harness.controller.setLockPreview(NotificationPreviewMode.hidden);
      await tester.pump();
      expect(builds, 4);
      expect(lastSlice!.lockPreview, NotificationPreviewMode.hidden);
    });
  });

  group('notification imageData rgba conversion', () {
    test('packed 4-channel payloads reuse the source buffer', () async {
      final data = Uint8List.fromList(
        List<int>.generate(16, (index) => index + 1),
      );
      final pixels = await notificationImageRgbaPixels(
        DesktopNotificationImageData(
          width: 2,
          height: 2,
          rowStride: 8,
          hasAlpha: true,
          bitsPerSample: 8,
          channels: 4,
          data: data,
        ),
      );
      expect(identical(pixels, data), isTrue);
    });

    test('3-channel payloads expand to opaque RGBA', () async {
      final data = Uint8List.fromList([
        10, 20, 30, 40, 50, 60, 99, 99, //
        70, 80, 90, 100, 110, 120, 88, 88,
      ]);
      final pixels = await notificationImageRgbaPixels(
        DesktopNotificationImageData(
          width: 2,
          height: 2,
          rowStride: 8,
          hasAlpha: false,
          bitsPerSample: 8,
          channels: 3,
          data: data,
        ),
      );
      expect(pixels, [
        10, 20, 30, 0xff, 40, 50, 60, 0xff, //
        70, 80, 90, 0xff, 100, 110, 120, 0xff,
      ]);
    });

    test(
      'padded 4-channel payloads match the zero-copy output bitwise',
      () async {
        final packedData = Uint8List.fromList(
          List<int>.generate(16, (index) => index + 1),
        );
        final packed = await notificationImageRgbaPixels(
          DesktopNotificationImageData(
            width: 2,
            height: 2,
            rowStride: 8,
            hasAlpha: true,
            bitsPerSample: 8,
            channels: 4,
            data: packedData,
          ),
        );

        final paddedData = Uint8List.fromList([
          1, 2, 3, 4, 5, 6, 7, 8, 0, 0, //
          9, 10, 11, 12, 13, 14, 15, 16, 0, 0,
        ]);
        final padded = await notificationImageRgbaPixels(
          DesktopNotificationImageData(
            width: 2,
            height: 2,
            rowStride: 10,
            hasAlpha: true,
            bitsPerSample: 8,
            channels: 4,
            data: paddedData,
          ),
        );

        expect(identical(padded, paddedData), isFalse);
        expect(padded, packed);
      },
    );

    test('unsupported layouts are rejected', () async {
      final valid = DesktopNotificationImageData(
        width: 2,
        height: 2,
        rowStride: 8,
        hasAlpha: true,
        bitsPerSample: 8,
        channels: 4,
        data: Uint8List(16),
      );
      expect(await notificationImageRgbaPixels(valid), isNotNull);

      Future<Uint8List?> convert(
        DesktopNotificationImageData Function() mutate,
      ) => notificationImageRgbaPixels(mutate());

      expect(
        await convert(
          () => DesktopNotificationImageData(
            width: 0,
            height: valid.height,
            rowStride: valid.rowStride,
            hasAlpha: true,
            bitsPerSample: 8,
            channels: 4,
            data: valid.data,
          ),
        ),
        isNull,
      );
      expect(
        await convert(
          () => DesktopNotificationImageData(
            width: valid.width,
            height: valid.height,
            rowStride: 4,
            hasAlpha: true,
            bitsPerSample: 8,
            channels: 4,
            data: valid.data,
          ),
        ),
        isNull,
      );
      expect(
        await convert(
          () => DesktopNotificationImageData(
            width: valid.width,
            height: valid.height,
            rowStride: valid.rowStride,
            hasAlpha: true,
            bitsPerSample: 8,
            channels: 4,
            data: Uint8List(8),
          ),
        ),
        isNull,
      );
    });
  });
}
