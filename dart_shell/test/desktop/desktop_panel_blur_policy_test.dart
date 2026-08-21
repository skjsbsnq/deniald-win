import 'package:denial_dart_shell/src/desktop/desktop_panel_blur_policy.dart';
import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('desktop panel blur stays disabled throughout motion', () {
    for (final status in const [
      AnimationStatus.dismissed,
      AnimationStatus.forward,
      AnimationStatus.reverse,
    ]) {
      expect(
        shouldBlurDesktopPanel(animationStatus: status, panelOpacity: 0.75),
        isFalse,
      );
    }
  });

  test('settled desktop panel blur follows panel opacity', () {
    expect(
      shouldBlurDesktopPanel(
        animationStatus: AnimationStatus.completed,
        panelOpacity: 0.75,
      ),
      isTrue,
    );
    expect(
      shouldBlurDesktopPanel(
        animationStatus: AnimationStatus.completed,
        panelOpacity: 1.0,
      ),
      isFalse,
    );
  });
}
