import 'package:denial_dart_shell/src/desktop/desktop_popup_surface_policy.dart';
import 'package:denial_dart_shell/src/desktop/desktop_workspace.dart';
import 'package:denial_dart_shell/src/models/denial_window.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('decorated popup uses the same client origin as input routing', () {
    const placement = DesktopWindowPlacement(
      objectId: 1,
      frame: Rect.fromLTWH(100, 80, 802, 636),
      z: 1,
      monitorId: 1,
    );

    expect(
      desktopPopupContentRect(
        placement: placement,
        visualFrame: placement.frame,
        drawsServerFrame: true,
      ),
      placement.contentRect,
    );
    expect(placement.contentRect.top - placement.frame.top, 35);
  });

  test('popup content follows a transformed visual frame without drift', () {
    const placement = DesktopWindowPlacement(
      objectId: 1,
      frame: Rect.fromLTWH(100, 80, 802, 636),
      z: 1,
      monitorId: 1,
    );
    const visualFrame = Rect.fromLTWH(240, 160, 402, 336);

    expect(
      desktopPopupContentRect(
        placement: placement,
        visualFrame: visualFrame,
        drawsServerFrame: true,
      ),
      placement.frameInsets.deflateRect(visualFrame),
    );
  });

  test('missing opaque region does not blur a client popup shadow', () {
    expect(desktopPopupBackdropBlurEnabled(_popup(opaque: false)), isFalse);
    expect(desktopPopupBackdropBlurEnabled(_popup(opaque: true)), isFalse);
    expect(
      desktopPopupBackdropBlurEnabled(_popup(opaque: false, opacity: 0.8)),
      isTrue,
    );
  });
}

DenialSurfaceLayer _popup({bool opaque = false, double opacity = 1}) {
  return DenialSurfaceLayer(
    surfaceId: 2,
    parentSurfaceId: 1,
    popupRootSurfaceId: 2,
    role: DenialSurfaceRole.popup,
    textureId: 1,
    width: 240,
    height: 180,
    surfaceX: 20,
    surfaceY: 30,
    surfaceWidth: 240,
    surfaceHeight: 180,
    textureSourceX: 0,
    textureSourceY: 0,
    textureSourceWidth: 240,
    textureSourceHeight: 180,
    transform: 0,
    scale120: 120,
    compositionOrder: 1,
    opacity: opacity,
    opaque: opaque,
  );
}
