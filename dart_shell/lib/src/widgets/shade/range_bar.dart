import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../../theme/shell_theme.dart';

/// A pill-shaped horizontal slider used for brightness and volume. Tapping or
/// dragging anywhere along the track sets the value.
class RangeBar extends StatefulWidget {
  const RangeBar({
    super.key,
    required this.icon,
    required this.value,
    required this.activeColor,
    required this.inactiveColor,
    required this.onChanged,
    required this.onChangeEnd,
    required this.height,
    this.enabled = true,
    this.onChangeStart,
    this.trailing,
  });

  final IconData icon;
  final double value;
  final Color activeColor;
  final Color inactiveColor;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;
  final double height;

  /// Whether the bar accepts input and renders [value]. While disabled the
  /// track stays empty and dimmed so an unknown level never reads as a real
  /// position.
  final bool enabled;

  final VoidCallback? onChangeStart;
  final Widget? trailing;

  @override
  State<RangeBar> createState() => _RangeBarState();
}

class _RangeBarState extends State<RangeBar> {
  static const _wheelStep = 0.05;

  double? _gestureValue;

  @override
  void didUpdateWidget(covariant RangeBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A disabled bar delivers no gesture callbacks, so a gesture in flight
    // when `enabled` flips would never report its end — leaving the caller's
    // interaction state (e.g. an in-progress volume drag) stuck. Match the
    // gesture-cancel path by delivering onChangeEnd after this update, which
    // also keeps a stale gesture value from resurfacing on re-enable.
    final interrupted = _gestureValue;
    if (!widget.enabled && interrupted != null) {
      _gestureValue = null;
      // Deliver unconditionally: dropping it would leave the caller's
      // interaction state (e.g. an in-progress volume drag) stuck forever.
      final onChangeEnd = widget.onChangeEnd;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onChangeEnd(interrupted);
      });
    }
  }

  double get _displayValue =>
      (_gestureValue ?? widget.value).clamp(0.0, 1.0).toDouble();

  void _updateFromPosition(Offset position, double width) {
    if (width <= 0) {
      return;
    }
    if (_gestureValue == null) {
      widget.onChangeStart?.call();
    }
    final next = (position.dx / width).clamp(0.0, 1.0).toDouble();
    setState(() {
      _gestureValue = next;
    });
    widget.onChanged(next);
  }

  void _startRelativeGesture() {
    if (_gestureValue != null) {
      return;
    }
    widget.onChangeStart?.call();
    setState(() {
      _gestureValue = widget.value.clamp(0.0, 1.0).toDouble();
    });
  }

  void _updateFromDelta(double delta, double width) {
    if (width <= 0) {
      return;
    }
    _startRelativeGesture();
    final next = (_gestureValue! + delta / width).clamp(0.0, 1.0).toDouble();
    setState(() {
      _gestureValue = next;
    });
    widget.onChanged(next);
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) {
      return;
    }
    final delta = event.scrollDelta;
    final direction = delta.dy.abs() >= delta.dx.abs()
        ? -delta.dy.sign
        : delta.dx.sign;
    if (direction == 0) {
      return;
    }
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      final current = widget.value.clamp(0.0, 1.0).toDouble();
      final next = (current + direction * _wheelStep)
          .clamp(0.0, 1.0)
          .toDouble();
      if (next == current) {
        return;
      }
      widget.onChangeStart?.call();
      widget.onChanged(next);
      widget.onChangeEnd(next);
    });
  }

  void _endGesture() {
    final value = _gestureValue;
    if (value == null) {
      return;
    }
    widget.onChangeEnd(value);
    if (!mounted) {
      return;
    }
    setState(() {
      _gestureValue = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final trailingWidget = widget.trailing;
    if (trailingWidget != null) {
      return Row(
        children: [
          Expanded(child: _buildTrack(context)),
          const SizedBox(width: 8.0),
          trailingWidget,
        ],
      );
    }
    return _buildTrack(context);
  }

  Widget _buildTrack(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final enabled = widget.enabled;
        final clamped = enabled ? _displayValue : 0.0;
        final theme = context.shellTheme;
        final colors = context.shellColors;
        final radius = theme.borderRadius(widget.height / 2);

        // M3E split-pill track: the thumb is an accent bar straddling the
        // fill boundary, so the two track segments are separate pills with a
        // gap wide enough to seat it. When dragged to 100%, the active bar fills
        // cleanly across the entire track without leaving an empty gap.
        const thumbWidth = 5.0;
        const splitGap = 8.0;
        final thumbHeight = widget.height + 6.0;

        final isFull = clamped >= 0.985;
        final isZero = clamped <= 0.01;

        final double activeWidth;
        final double inactiveLeft;
        final double inactiveWidth;
        final double thumbLeft;

        if (isFull) {
          activeWidth = totalWidth;
          inactiveLeft = totalWidth;
          inactiveWidth = 0.0;
          thumbLeft = totalWidth - thumbWidth;
        } else if (isZero) {
          activeWidth = 0.0;
          inactiveLeft = 0.0;
          inactiveWidth = totalWidth;
          thumbLeft = 0.0;
        } else {
          final fillX = (totalWidth * clamped).clamp(0.0, totalWidth);
          activeWidth = (fillX - splitGap / 2).clamp(
            0.0,
            totalWidth - splitGap,
          );
          inactiveLeft = activeWidth + splitGap;
          inactiveWidth = (totalWidth - inactiveLeft).clamp(0.0, totalWidth);
          thumbLeft = (activeWidth + (splitGap - thumbWidth) / 2).clamp(
            0.0,
            totalWidth - thumbWidth,
          );
        }

        final dotX = totalWidth * 0.82;
        final showDotAtX =
            enabled &&
            !isFull &&
            inactiveWidth > 24.0 &&
            dotX > inactiveLeft + 6.0 &&
            dotX < totalWidth - 8.0;

        final iconOnActive = activeWidth >= 28.0;
        final iconColor = !enabled
            ? colors.textTertiary
            : iconOnActive
            ? theme.accentPalette.onPrimary
            : colors.textPrimary;

        return Listener(
          onPointerSignal: enabled ? _handlePointerSignal : null,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: enabled
                ? (details) {
                    _updateFromPosition(details.localPosition, totalWidth);
                  }
                : null,
            onTapUp: enabled
                ? (details) {
                    _updateFromPosition(details.localPosition, totalWidth);
                    _endGesture();
                  }
                : null,
            onTapCancel: enabled ? _endGesture : null,
            onHorizontalDragStart: enabled
                ? (details) {
                    if (details.kind == PointerDeviceKind.trackpad) {
                      _startRelativeGesture();
                    } else {
                      _updateFromPosition(details.localPosition, totalWidth);
                    }
                  }
                : null,
            onHorizontalDragUpdate: enabled
                ? (details) {
                    if (details.kind == PointerDeviceKind.trackpad) {
                      _updateFromDelta(details.primaryDelta ?? 0, totalWidth);
                    } else {
                      _updateFromPosition(details.localPosition, totalWidth);
                    }
                  }
                : null,
            onHorizontalDragEnd: enabled ? (_) => _endGesture() : null,
            onHorizontalDragCancel: enabled ? _endGesture : null,
            child: SizedBox(
              height: widget.height,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  if (activeWidth > 0)
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: activeWidth,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: widget.activeColor,
                          borderRadius: radius,
                        ),
                      ),
                    ),
                  if (inactiveWidth > 0)
                    Positioned(
                      left: inactiveLeft,
                      top: 0,
                      bottom: 0,
                      width: inactiveWidth,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: widget.inactiveColor,
                          borderRadius: radius,
                          border: Border.all(
                            color: colors.hairlineSoft.withValues(alpha: 0.50),
                            width: 1.0,
                          ),
                        ),
                      ),
                    ),
                  if (showDotAtX)
                    Positioned(
                      left: dotX - 2.0,
                      top: (widget.height - 4.0) / 2,
                      child: Container(
                        width: 4.0,
                        height: 4.0,
                        decoration: BoxDecoration(
                          color: colors.textTertiary.withValues(alpha: 0.55),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  if (activeWidth > 0 && !isFull)
                    Positioned(
                      left: thumbLeft,
                      top: (widget.height - thumbHeight) / 2,
                      child: Container(
                        width: thumbWidth,
                        height: thumbHeight,
                        decoration: BoxDecoration(
                          color: widget.activeColor,
                          borderRadius: theme.borderRadius(thumbWidth / 2),
                        ),
                      ),
                    ),
                  Positioned(
                    left: 12.0,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: Icon(widget.icon, color: iconColor, size: 20.0),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
