import 'package:flutter/animation.dart';

/// Keeps moving desktop panels off the backdrop-filter path.
///
/// The panel contents still move normally, but the expensive blur is restored
/// only after the entrance animation has settled. Closing panels remain
/// unblurred for their entire visible lifetime.
bool shouldBlurDesktopPanel({
  required AnimationStatus animationStatus,
  required double panelOpacity,
}) {
  return animationStatus == AnimationStatus.completed && panelOpacity < 1.0;
}
