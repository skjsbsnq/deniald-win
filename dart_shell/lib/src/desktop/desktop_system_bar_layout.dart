import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../models/display_layout.dart';

enum _SystemBarSlot { leading, center, trailing }

/// Three-zone layout for the desktop system bar (Leading, Center, Trailing).
///
/// Implements Windows 11-style absolute centering (Option A) where the center
/// cluster is positioned relative to the full bar extent, and automatically
/// degrades to elastic constrained positioning (Option B) when center contents
/// expand or collide with leading/trailing modules.
///
/// The zones follow the bar's main axis, not the screen: [leading] is the bar's
/// left in a Top or Bottom bar and its top in a Left or Right one, so a Windows
/// 10-style "left aligned" cluster reads as "top aligned" when the bar stands
/// vertical. Supports all four orientations and yields cleanly when Hidden.
class DesktopSystemBarLayout extends StatelessWidget {
  const DesktopSystemBarLayout({
    required this.side,
    this.leading = const <Widget>[],
    this.center = const <Widget>[],
    this.trailing = const <Widget>[],
    this.gap = 8.0,
    super.key,
  });

  final SystemBarSide side;
  final List<Widget> leading;
  final List<Widget> center;
  final List<Widget> trailing;
  final double gap;

  @override
  Widget build(BuildContext context) {
    if (side == SystemBarSide.hidden) {
      return const SizedBox.shrink();
    }

    final horizontal = side.isHorizontal;

    return CustomMultiChildLayout(
      delegate: _SystemBarLayoutDelegate(horizontal: horizontal, gap: gap),
      children: [
        if (leading.isNotEmpty)
          LayoutId(
            id: _SystemBarSlot.leading,
            child: horizontal
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: leading,
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: leading,
                  ),
          ),
        if (center.isNotEmpty)
          LayoutId(
            id: _SystemBarSlot.center,
            child: horizontal
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: center,
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: center,
                  ),
          ),
        if (trailing.isNotEmpty)
          LayoutId(
            id: _SystemBarSlot.trailing,
            child: horizontal
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: trailing,
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: trailing,
                  ),
          ),
      ],
    );
  }
}

class _SystemBarLayoutDelegate extends MultiChildLayoutDelegate {
  _SystemBarLayoutDelegate({required this.horizontal, required this.gap});

  final bool horizontal;
  final double gap;

  @override
  void performLayout(Size size) {
    if (horizontal) {
      _layoutHorizontal(size);
    } else {
      _layoutVertical(size);
    }
  }

  void _layoutHorizontal(Size size) {
    final hasLeading = hasChild(_SystemBarSlot.leading);
    final hasCenter = hasChild(_SystemBarSlot.center);
    final hasTrailing = hasChild(_SystemBarSlot.trailing);

    final trailingSize = hasTrailing
        ? layoutChild(_SystemBarSlot.trailing, BoxConstraints.loose(size))
        : Size.zero;
    final trailingExtent = trailingSize.width > 0
        ? trailingSize.width + gap
        : 0.0;

    // The leading zone gets whatever the trailing modules leave. The taskbar
    // reads this budget to decide when to fall back to icon-only buttons, and
    // a loose constraint here would let a bar full of window buttons run
    // straight under the status cards.
    final leadingSize = hasLeading
        ? layoutChild(
            _SystemBarSlot.leading,
            BoxConstraints(
              maxWidth: math.max(0.0, size.width - trailingExtent),
              maxHeight: size.height,
            ),
          )
        : Size.zero;
    final leadingExtent = leadingSize.width > 0 ? leadingSize.width + gap : 0.0;

    final availableCenterWidth = math.max(
      0.0,
      size.width - leadingExtent - trailingExtent,
    );
    final centerSize = hasCenter
        ? layoutChild(
            _SystemBarSlot.center,
            BoxConstraints(
              maxWidth: availableCenterWidth,
              maxHeight: size.height,
            ),
          )
        : Size.zero;

    if (hasLeading) {
      positionChild(
        _SystemBarSlot.leading,
        Offset(0.0, (size.height - leadingSize.height) / 2.0),
      );
    }

    if (hasTrailing) {
      positionChild(
        _SystemBarSlot.trailing,
        Offset(
          size.width - trailingSize.width,
          (size.height - trailingSize.height) / 2.0,
        ),
      );
    }

    if (hasCenter) {
      final idealLeft = (size.width - centerSize.width) / 2.0;
      final minLeft = leadingExtent;
      final maxLeft =
          size.width -
          trailingSize.width -
          (trailingSize.width > 0 ? gap : 0.0) -
          centerSize.width;
      final actualLeft = maxLeft >= minLeft
          ? idealLeft.clamp(minLeft, maxLeft)
          : minLeft;

      positionChild(
        _SystemBarSlot.center,
        Offset(actualLeft, (size.height - centerSize.height) / 2.0),
      );
    }
  }

  void _layoutVertical(Size size) {
    final hasLeading = hasChild(_SystemBarSlot.leading);
    final hasCenter = hasChild(_SystemBarSlot.center);
    final hasTrailing = hasChild(_SystemBarSlot.trailing);

    final trailingSize = hasTrailing
        ? layoutChild(_SystemBarSlot.trailing, BoxConstraints.loose(size))
        : Size.zero;
    final trailingExtent = trailingSize.height > 0
        ? trailingSize.height + gap
        : 0.0;

    final leadingSize = hasLeading
        ? layoutChild(
            _SystemBarSlot.leading,
            BoxConstraints(
              maxWidth: size.width,
              maxHeight: math.max(0.0, size.height - trailingExtent),
            ),
          )
        : Size.zero;
    final leadingExtent = leadingSize.height > 0
        ? leadingSize.height + gap
        : 0.0;

    final availableCenterHeight = math.max(
      0.0,
      size.height - leadingExtent - trailingExtent,
    );

    final centerSize = hasCenter
        ? layoutChild(
            _SystemBarSlot.center,
            BoxConstraints(
              maxWidth: size.width,
              maxHeight: availableCenterHeight,
            ),
          )
        : Size.zero;

    if (hasLeading) {
      positionChild(
        _SystemBarSlot.leading,
        Offset((size.width - leadingSize.width) / 2.0, 0.0),
      );
    }

    if (hasTrailing) {
      positionChild(
        _SystemBarSlot.trailing,
        Offset(
          (size.width - trailingSize.width) / 2.0,
          size.height - trailingSize.height,
        ),
      );
    }

    if (hasCenter) {
      final idealTop = (size.height - centerSize.height) / 2.0;
      final minTop = leadingExtent;
      final maxTop =
          size.height -
          trailingSize.height -
          (trailingSize.height > 0 ? gap : 0.0) -
          centerSize.height;
      final actualTop = maxTop >= minTop
          ? idealTop.clamp(minTop, maxTop)
          : minTop;

      positionChild(
        _SystemBarSlot.center,
        Offset((size.width - centerSize.width) / 2.0, actualTop),
      );
    }
  }

  @override
  bool shouldRelayout(covariant _SystemBarLayoutDelegate oldDelegate) {
    return oldDelegate.horizontal != horizontal || oldDelegate.gap != gap;
  }
}
