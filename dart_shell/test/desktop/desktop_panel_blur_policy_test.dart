import 'package:denial_dart_shell/src/desktop/desktop_panel_blur_policy.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('desktop panel blur follows panel opacity during motion', () {
    expect(shouldBlurDesktopPanel(panelOpacity: 0.75), isTrue);
    expect(shouldBlurDesktopPanel(panelOpacity: 1.0), isFalse);
  });

  test('desktop panel blur is clipped to the translated visible portion', () {
    const size = Size(100, 80);

    expect(
      desktopPanelVisibleClip(size: size, offset: const Offset(-50, 0)),
      const Rect.fromLTWH(0, 0, 50, 80),
    );
    expect(
      desktopPanelVisibleClip(size: size, offset: const Offset(0, 40)),
      const Rect.fromLTWH(0, 40, 100, 40),
    );
    expect(
      desktopPanelVisibleClip(size: size, offset: const Offset(-120, 0)),
      Rect.zero,
    );
  });
}
