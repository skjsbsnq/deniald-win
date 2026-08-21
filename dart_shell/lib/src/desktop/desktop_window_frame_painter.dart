import 'dart:math' as math;

import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/widgets.dart';

import '../theme/shell_theme.dart';
import '../theme/tokens.dart';
import '../widgets/shell_cursor.dart';
import 'desktop_window_render_telemetry.dart';
import 'desktop_workspace.dart';

/// Keeps the static server-side decoration isolated from the live client
/// texture and from the stateful focus border.
///
/// Only the shadow/frame picture is marked complex. Applying the hint to a
/// single [CustomPaint] with both a background and foreground painter would
/// also force a full-window cache for the inexpensive focus border.
class DesktopWindowFrameLayers extends StatelessWidget {
  const DesktopWindowFrameLayers({
    required this.windowId,
    required this.borderPainter,
    required this.child,
    this.resizeHotRegions = const <DesktopWindowResizeHotRegion>[],
    this.onBeginResize,
    this.onResizeBy,
    this.onEndResize,
    super.key,
  });

  final int windowId;
  final CustomPainter borderPainter;
  final Widget child;
  final List<DesktopWindowResizeHotRegion> resizeHotRegions;
  final void Function(DesktopWindowResizeEdge edge)? onBeginResize;
  final ValueChanged<Offset>? onResizeBy;
  final VoidCallback? onEndResize;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        DesktopWindowRepaintBoundary(
          outset: DesktopWindowFramePainter.shadowOutset,
          child: IgnorePointer(
            child: CustomPaint(
              painter: DesktopWindowFramePainter(
                windowId: windowId,
                radius: ShellTheme.of(context).windowRadius,
              ),
              isComplex: true,
              willChange: false,
            ),
          ),
        ),
        child,
        if (resizeHotRegions.isNotEmpty &&
            onBeginResize != null &&
            onResizeBy != null &&
            onEndResize != null)
          for (final region in resizeHotRegions)
            Positioned.fromRect(
              rect: region.rect,
              child: _DesktopWindowResizeHandle(
                edge: region.edge,
                onBeginResize: onBeginResize!,
                onResizeBy: onResizeBy!,
                onEndResize: onEndResize!,
              ),
            ),
        IgnorePointer(child: CustomPaint(painter: borderPainter)),
      ],
    );
  }
}

class _DesktopWindowResizeHandle extends StatefulWidget {
  const _DesktopWindowResizeHandle({
    required this.edge,
    required this.onBeginResize,
    required this.onResizeBy,
    required this.onEndResize,
  });

  final DesktopWindowResizeEdge edge;
  final void Function(DesktopWindowResizeEdge edge) onBeginResize;
  final ValueChanged<Offset> onResizeBy;
  final VoidCallback onEndResize;

  @override
  State<_DesktopWindowResizeHandle> createState() =>
      _DesktopWindowResizeHandleState();
}

class _DesktopWindowResizeHandleState
    extends State<_DesktopWindowResizeHandle> {
  MouseCursor get _cursor => switch (widget.edge) {
    DesktopWindowResizeEdge.top ||
    DesktopWindowResizeEdge.bottom => ShellMouseCursors.verticalResize,
    DesktopWindowResizeEdge.left ||
    DesktopWindowResizeEdge.right => ShellMouseCursors.horizontalResize,
  };

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: _cursor,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => widget.onBeginResize(widget.edge),
        onPanUpdate: (details) => widget.onResizeBy(details.delta),
        onPanEnd: (_) => widget.onEndResize(),
        onPanCancel: widget.onEndResize,
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// A retained layer whose damage bounds include deliberate child overdraw.
///
/// [DesktopWindowFramePainter] paints its shadow outside the window's layout
/// rectangle. A normal [RepaintBoundary] would advertise only that rectangle,
/// leaving the outsetting shadow outside partial-repaint damage.
class DesktopWindowRepaintBoundary extends RepaintBoundary {
  const DesktopWindowRepaintBoundary({
    required this.outset,
    super.child,
    super.key,
  });

  final double outset;

  @override
  RenderDesktopWindowRepaintBoundary createRenderObject(BuildContext context) {
    return RenderDesktopWindowRepaintBoundary(outset);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderDesktopWindowRepaintBoundary renderObject,
  ) {
    renderObject.outset = outset;
  }
}

class RenderDesktopWindowRepaintBoundary extends RenderRepaintBoundary {
  RenderDesktopWindowRepaintBoundary(this._outset) : assert(_outset >= 0);

  double _outset;

  set outset(double value) {
    assert(value >= 0);
    if (_outset == value) {
      return;
    }
    _outset = value;
    markNeedsPaint();
  }

  @override
  Rect get paintBounds => super.paintBounds.inflate(_outset);
}

/// Paints the shadow and opaque frame ring around a decorated client surface.
///
/// The center is deliberately left clear so client-provided per-pixel alpha is
/// preserved instead of being composited over a shell-owned window backdrop.
class DesktopWindowFramePainter extends CustomPainter {
  const DesktopWindowFramePainter({
    this.windowId = 0,
    this.radius = ShellRadii.window,
  });

  final int windowId;
  final double radius;

  static const double shadowOutset = 64;

  @override
  void paint(Canvas canvas, Size size) {
    DesktopWindowRenderTelemetry.recordShadowPaint(windowId, size);
    if (size.isEmpty) {
      return;
    }

    final frame = Offset.zero & size;
    final frameShape = RRect.fromRectAndRadius(frame, Radius.circular(radius));
    final outsideFrame = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(frame.inflate(shadowOutset))
      ..addRRect(frameShape);
    final shadowRect = frame.shift(const Offset(0, 12)).inflate(2);
    final shadowPaint = Paint()
      ..color = ShellColors.shadow
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16.5);

    canvas
      ..save()
      ..clipPath(outsideFrame)
      ..drawRRect(
        RRect.fromRectAndRadius(shadowRect, Radius.circular(radius + 2)),
        shadowPaint,
      )
      ..restore();

    final innerFrame = frame.deflate(DesktopMetrics.frameBorder);
    if (innerFrame.isEmpty) {
      canvas.drawRRect(
        frameShape,
        Paint()..color = ShellColors.windowFrameSurface,
      );
      return;
    }

    canvas.drawDRRect(
      frameShape,
      RRect.fromRectAndRadius(
        innerFrame,
        Radius.circular(math.max(0.0, radius - DesktopMetrics.frameBorder)),
      ),
      Paint()..color = ShellColors.windowFrameSurface,
    );
  }

  @override
  bool shouldRepaint(covariant DesktopWindowFramePainter oldDelegate) {
    return windowId != oldDelegate.windowId || radius != oldDelegate.radius;
  }
}
