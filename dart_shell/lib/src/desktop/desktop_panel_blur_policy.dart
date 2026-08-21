import 'package:flutter/widgets.dart';

/// Keeps the panel backdrop stable while its contents move.
bool shouldBlurDesktopPanel({required double panelOpacity}) {
  return panelOpacity < 1.0;
}

/// Clips the fixed backdrop to the part occupied by the translated panel.
Rect desktopPanelVisibleClip({required Size size, required Offset offset}) {
  final bounds = Offset.zero & size;
  final visible = bounds.intersect(bounds.shift(offset));
  return visible.isEmpty ? Rect.zero : visible;
}
