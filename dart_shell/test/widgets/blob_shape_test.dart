import 'package:denial_dart_shell/src/widgets/desktop_widgets/desktop_widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

double _pathLength(Path path) {
  var total = 0.0;
  for (final metric in path.computeMetrics()) {
    total += metric.length;
  }
  return total;
}

void main() {
  const rect = Rect.fromLTWH(0, 0, 320, 160);

  group('DesktopBlobPath', () {
    test('is deterministic for identical arguments', () {
      for (final shape in DesktopBlobShape.values) {
        final first = DesktopBlobPath.build(shape, rect);
        final second = DesktopBlobPath.build(shape, rect);
        expect(_pathLength(first), _pathLength(second));
        expect(first.getBounds(), second.getBounds());
      }
    });

    test('variants produce distinct outlines', () {
      final lengths = <double>{
        for (final shape in DesktopBlobShape.values)
          _pathLength(DesktopBlobPath.build(shape, rect)),
      };
      expect(lengths.length, DesktopBlobShape.values.length);
    });

    test('outline stays inside the rect for every variant', () {
      for (final shape in DesktopBlobShape.values) {
        final path = DesktopBlobPath.build(shape, rect);
        final bounds = path.getBounds();
        expect(bounds.left, greaterThanOrEqualTo(rect.left));
        expect(bounds.top, greaterThanOrEqualTo(rect.top));
        expect(bounds.right, lessThanOrEqualTo(rect.right));
        expect(bounds.bottom, lessThanOrEqualTo(rect.bottom));
      }
    });

    test('zero roundness still produces a closed non-empty outline', () {
      for (final shape in DesktopBlobShape.values) {
        final path = DesktopBlobPath.build(
          shape,
          rect,
          roundnessScale: 0,
        );
        expect(_pathLength(path), greaterThan(0));
        expect(path.getBounds().isEmpty, isFalse);
      }
    });

    test('empty rect produces an empty path', () {
      expect(
        _pathLength(DesktopBlobPath.build(DesktopBlobShape.clover, Rect.zero)),
        0,
      );
    });

    test('non-square rects keep the inscribed-ellipse proportions', () {
      final path = DesktopBlobPath.build(
        DesktopBlobShape.cookie,
        const Rect.fromLTWH(0, 0, 400, 100),
      );
      final bounds = path.getBounds();
      expect(bounds.width, greaterThan(bounds.height * 2));
    });
  });

  group('BlobShapeBorder', () {
    test('outer path matches the deterministic builder', () {
      const border = BlobShapeBorder(
        shape: DesktopBlobShape.clover,
        roundnessScale: 0.5,
      );
      final viaBorder = border.getOuterPath(rect);
      final direct = DesktopBlobPath.build(
        DesktopBlobShape.clover,
        rect,
        roundnessScale: 0.5,
      );
      expect(_pathLength(viaBorder), _pathLength(direct));
      expect(viaBorder.getBounds(), direct.getBounds());
    });

    test('scale adjusts only the roundness factor', () {
      const border = BlobShapeBorder(shape: DesktopBlobShape.puffy);
      final scaled = border.scale(0.5);
      expect(scaled, isA<BlobShapeBorder>());
      expect((scaled as BlobShapeBorder).roundnessScale, 0.5);
      expect(scaled.shape, DesktopBlobShape.puffy);
    });
  });
}
