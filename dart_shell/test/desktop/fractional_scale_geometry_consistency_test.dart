import 'package:denial_dart_shell/src/desktop/desktop_workspace.dart';
import 'package:denial_dart_shell/src/widgets/window_surface_tree.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const testScales = <double>[1.0, 1.25, 4.0 / 3.0, 1.5, 1.6, 1.75, 2.0];
  const outputPhysicalSize = Size(2560.0, 1600.0);

  group('P9-02 Fractional scale geometry consistency', () {
    for (final scale in testScales) {
      test('scale=$scale fullscreen geometry and 1:1 buffer consistency', () {
        final logicalWidth = outputPhysicalSize.width / scale;
        final logicalHeight = outputPhysicalSize.height / scale;

        // Configure sent to client (Wayland logical integers)
        final configureWidth = logicalWidth.round();
        final configureHeight = logicalHeight.round();

        // Client buffer allocated at fractional scale
        final clientBufferWidth = (configureWidth * scale).ceil();
        final clientBufferHeight = (configureHeight * scale).ceil();

        // Desktop window target device pixel size
        final targetDeviceWidth = (logicalWidth * scale).round();
        final targetDeviceHeight = (logicalHeight * scale).round();

        expect(targetDeviceWidth, outputPhysicalSize.width.round());
        expect(targetDeviceHeight, outputPhysicalSize.height.round());

        // Overhang rows/columns must be at most 1 pixel and cropped from edges
        final croppedCols = clientBufferWidth - targetDeviceWidth;
        final croppedRows = clientBufferHeight - targetDeviceHeight;
        expect(croppedCols, lessThanOrEqualTo(1));
        expect(croppedCols, greaterThanOrEqualTo(0));
        expect(croppedRows, lessThanOrEqualTo(1));
        expect(croppedRows, greaterThanOrEqualTo(0));
      });
    }

    for (final scale in testScales) {
      testWidgets('scale=$scale _sampledFilterQuality evaluates to 1:1', (
        tester,
      ) async {
        final logicalSize = Size(
          outputPhysicalSize.width / scale,
          outputPhysicalSize.height / scale,
        );

        // Layer with fractional scale edge crop matching target device size
        final sourceWidth = (logicalSize.width * scale).roundToDouble();
        final sourceHeight = (logicalSize.height * scale).roundToDouble();

        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(devicePixelRatio: scale),
            child: Builder(
              builder: (context) {
                final quality = sampledFilterQualityForTesting(
                  context,
                  requested: FilterQuality.none,
                  target: logicalSize,
                  sourceWidth: sourceWidth,
                  sourceHeight: sourceHeight,
                );
                expect(quality, FilterQuality.none);
                return const SizedBox.shrink();
              },
            ),
          ),
        );
      });
    }

    for (final scale in testScales) {
      test(
        'scale=$scale windowed contentRect origin lands on integer device pixels across 5 positions',
        () {
          final testOrigins = <Offset>[
            const Offset(100.0, 100.0),
            const Offset(101.0, 101.0),
            const Offset(153.33333333333334, 187.66666666666666),
            const Offset(245.5, 311.5),
            const Offset(389.25, 421.75),
          ];

          for (final origin in testOrigins) {
            // Snapped frame as produced by workspace manager
            final snappedLeft = (origin.dx * scale).roundToDouble() / scale;
            final snappedTop = (origin.dy * scale).roundToDouble() / scale;
            final snappedWidth = (800.0 * scale).roundToDouble() / scale;
            final snappedHeight = (600.0 * scale).roundToDouble() / scale;
            final frame = Rect.fromLTWH(
              snappedLeft,
              snappedTop,
              snappedWidth,
              snappedHeight,
            );

            final placement = DesktopWindowPlacement(
              objectId: 1,
              frame: frame,
              z: 0,
              monitorId: 0,
              serverSideDecorated: true,
              fullscreen: false,
              devicePixelRatio: scale,
            );

            final contentRect = placement.contentRect;
            final contentDeviceLeft = contentRect.left * scale;
            final contentDeviceTop = contentRect.top * scale;
            final contentDeviceWidth = contentRect.width * scale;
            final contentDeviceHeight = contentRect.height * scale;

            // Verify exact device pixel alignment
            expect(
              (contentDeviceLeft - contentDeviceLeft.round()).abs(),
              lessThan(1e-5),
              reason:
                  'contentRect.left not aligned at scale $scale origin $origin',
            );
            expect(
              (contentDeviceTop - contentDeviceTop.round()).abs(),
              lessThan(1e-5),
              reason:
                  'contentRect.top not aligned at scale $scale origin $origin',
            );
            expect(
              (contentDeviceWidth - contentDeviceWidth.round()).abs(),
              lessThan(1e-5),
              reason:
                  'contentRect.width not aligned at scale $scale origin $origin',
            );
            expect(
              (contentDeviceHeight - contentDeviceHeight.round()).abs(),
              lessThan(1e-5),
              reason:
                  'contentRect.height not aligned at scale $scale origin $origin',
            );
          }
        },
      );
    }
  });
}
