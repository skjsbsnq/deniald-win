import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Result of [resolveImePanelPlacement].
typedef ImePanelPlacement = ({Rect rect, bool aboveCaret});

/// Caret-anchored candidate-panel placement.
///
/// This mirrors the compositor's `place_input_method_popup`
/// (compositor/.../surface_pipeline.rs) so the Flutter-rendered panel lands
/// exactly where a native input-method popup would: anchored to the caret's
/// bottom-left corner, preferring below-caret placement, flipping above when
/// the space below does not fit, and clamped inside [bounds] (the output
/// holding the caret).
///
/// [bounds] is supplied by the caller because output lookup needs the shell's
/// display layout, which this helper deliberately does not depend on. Pass
/// the full canvas when no output information is available.
ImePanelPlacement resolveImePanelPlacement({
  required Rect caret,
  required Size panelSize,
  required Rect bounds,
  double gap = 0,
}) {
  final width = math
      .max(1.0, panelSize.width)
      .clamp(1.0, math.max(1.0, bounds.width))
      .toDouble();
  final height = math
      .max(1.0, panelSize.height)
      .clamp(1.0, math.max(1.0, bounds.height))
      .toDouble();
  final right = math.max(bounds.left, bounds.right - width);
  final bottom = math.max(bounds.top, bounds.bottom - height);
  final x = caret.left.clamp(bounds.left, right).toDouble();
  final below = caret.bottom + gap;
  final above = caret.top - gap - height;
  final fitsBelow = below <= bottom;
  final y = (fitsBelow ? below : above).clamp(bounds.top, bottom).toDouble();
  return (rect: Rect.fromLTWH(x, y, width, height), aboveCaret: !fitsBelow);
}
