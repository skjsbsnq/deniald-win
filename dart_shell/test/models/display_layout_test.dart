import 'package:denial_dart_shell/src/models/display_layout.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DisplayLayout workArea', () {
    test('bottom shelf preserves maximizePadding above the shelf', () {
      final base = DisplayLayout.fallback(const Size(1280, 800), 1.0);
      final layout = base.copyWithSystemBar(
        side: SystemBarSide.bottom,
        monitorIds: const [0],
        thickness: 56.0,
        windowPadding: 10.0,
      );

      final workArea = layout.workAreaWithin(
        const Rect.fromLTWH(0, 0, 1280, 800),
      );
      expect(workArea, const Rect.fromLTRB(10, 10, 1270, 734));

      // Top gap from screen top: 10
      expect(workArea.top, 10.0);
      // Bottom gap from shelf top (800 - 56 = 744): 744 - 734 = 10
      final shelf = layout.systemBarRectWithin(
        const Rect.fromLTWH(0, 0, 1280, 800),
      );
      expect(shelf.top - workArea.bottom, 10.0);
      // Left and right margins: 10
      expect(workArea.left, 10.0);
      expect(1280.0 - workArea.right, 10.0);
    });

    test('top system bar preserves maximizePadding below the bar', () {
      final base = DisplayLayout.fallback(const Size(1280, 800), 1.0);
      final layout = base.copyWithSystemBar(
        side: SystemBarSide.top,
        monitorIds: const [0],
        thickness: 32.0,
        windowPadding: 10.0,
      );

      final workArea = layout.workAreaWithin(
        const Rect.fromLTWH(0, 0, 1280, 800),
      );
      expect(workArea, const Rect.fromLTRB(10, 42, 1270, 790));

      // Gap below top bar (32.0): 42 - 32 = 10
      final bar = layout.systemBarRectWithin(
        const Rect.fromLTWH(0, 0, 1280, 800),
      );
      expect(workArea.top - bar.bottom, 10.0);
      // Bottom margin from screen bottom: 800 - 790 = 10
      expect(800.0 - workArea.bottom, 10.0);
    });

    test(
      'zero padding leaves maximized window flush to bar and screen edges',
      () {
        final base = DisplayLayout.fallback(const Size(1280, 800), 1.0);
        final layout = base.copyWithSystemBar(
          side: SystemBarSide.bottom,
          monitorIds: const [0],
          thickness: 56.0,
          windowPadding: 0.0,
        );

        final workArea = layout.workAreaWithin(
          const Rect.fromLTWH(0, 0, 1280, 800),
        );
        expect(workArea, const Rect.fromLTRB(0, 0, 1280, 744));
      },
    );

    test('hidden bar applies uniform padding to all four screen edges', () {
      final base = DisplayLayout.fallback(const Size(1280, 800), 1.0);
      final layout = base.copyWithSystemBar(
        side: SystemBarSide.hidden,
        monitorIds: const [],
        thickness: 56.0,
        windowPadding: 10.0,
      );

      final workArea = layout.workAreaWithin(
        const Rect.fromLTWH(0, 0, 1280, 800),
      );
      expect(workArea, const Rect.fromLTRB(10, 10, 1270, 790));
    });
  });
}
