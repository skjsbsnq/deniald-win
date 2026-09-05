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
  final VoidCallback? onChangeStart;
  final Widget? trailing;

  @override
  State<RangeBar> createState() => _RangeBarState();
}

class _RangeBarState extends State<RangeBar> {
  static const _wheelStep = 0.05;

  double? _gestureValue;

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
        final clamped = _displayValue;
        final theme = context.shellTheme;
        final colors = context.shellColors;
        final radius = theme.borderRadius(widget.height / 2);

        const splitGap = 4.0;
        final isNearEmpty = clamped <= 0.02;
        final isNearFull = clamped >= 0.98;

        final double activeWidth;
        final double inactiveWidth;
        if (isNearEmpty) {
          activeWidth = 0.0;
          inactiveWidth = totalWidth;
        } else if (isNearFull) {
          activeWidth = totalWidth;
          inactiveWidth = 0.0;
        } else {
          activeWidth = (totalWidth * clamped - splitGap / 2).clamp(
            0.0,
            totalWidth,
          );
          inactiveWidth = (totalWidth - activeWidth - splitGap).clamp(
            0.0,
            totalWidth,
          );
        }

        final showDot = !isNearFull && inactiveWidth > 40.0;
        final dotX = totalWidth * 0.82;
        final showDotAtX =
            showDot &&
            (dotX > (activeWidth + splitGap + 8.0)) &&
            (dotX < totalWidth - 12.0);

        final iconOnActive = activeWidth >= 28.0;
        final iconColor = iconOnActive
            ? theme.accentPalette.onPrimary
            : colors.textPrimary;

        return Listener(
          onPointerSignal: _handlePointerSignal,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) {
              _updateFromPosition(details.localPosition, totalWidth);
            },
            onTapUp: (details) {
              _updateFromPosition(details.localPosition, totalWidth);
              _endGesture();
            },
            onTapCancel: _endGesture,
            onHorizontalDragStart: (details) {
              if (details.kind == PointerDeviceKind.trackpad) {
                _startRelativeGesture();
              } else {
                _updateFromPosition(details.localPosition, totalWidth);
              }
            },
            onHorizontalDragUpdate: (details) {
              if (details.kind == PointerDeviceKind.trackpad) {
                _updateFromDelta(details.primaryDelta ?? 0, totalWidth);
              } else {
                _updateFromPosition(details.localPosition, totalWidth);
              }
            },
            onHorizontalDragEnd: (_) => _endGesture(),
            onHorizontalDragCancel: _endGesture,
            child: SizedBox(
              height: widget.height,
              child: Stack(
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
                      left: activeWidth > 0 ? activeWidth + splitGap : 0,
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
