import 'package:flutter/widgets.dart';

import '../models/denial_window.dart';
import 'desktop_workspace.dart';

/// Maps popup surfaces through the same client rectangle used by input
/// routing. The shell titlebar is outside the client's coordinate space.
Rect desktopPopupContentRect({
  required DesktopWindowPlacement placement,
  required Rect visualFrame,
  required bool drawsServerFrame,
}) => drawsServerFrame
    ? placement.frameInsets.deflateRect(visualFrame)
    : visualFrame;

/// Client popups paint their own background and transparent shadow margins.
/// A missing full-surface opaque guarantee must not create a shell blur layer.
bool desktopPopupBackdropBlurEnabled(DenialSurfaceLayer layer) =>
    layer.opacity < 1.0;
