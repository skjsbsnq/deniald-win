import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../../theme/motion.dart';
import '../../theme/shell_theme.dart';
import '../../theme/tokens.dart';

/// A pill-shaped horizontal slider used for brightness and volume. Tapping or
/// dragging anywhere along the track sets the value.
///
/// Value changes that arrive through [value] without an active gesture (wheel
/// steps, keyboard nudges from a wrapping control, external state) settle onto
/// the fill with `Motion.expressiveEffectsDefault`; pointer gestures keep the
/// fill glued to the finger with no animation lag.
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
    this.leadingIcon,
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

  /// Optional detached leading icon segment: a Ø40 circle on
  /// `surfaceContainerHigh` placed ahead of the track (02-VISUAL-SPEC §4).
  /// When set it replaces the in-track [icon].
  final IconData? leadingIcon;

  final Widget? trailing;

  @override
  State<RangeBar> createState() => _RangeBarState();
}

class _RangeBarState extends State<RangeBar>
    with SingleTickerProviderStateMixin {
  static const _wheelStep = 0.05;

  double? _gestureValue;

  /// Rendered fill fraction. Gestures snap it to the finger; non-gesture
  /// [RangeBar.value] changes settle onto it with an effects spring.
  late final AnimationController _valueController;

  @override
  void initState() {
    super.initState();
    _valueController = AnimationController.unbounded(
      vsync: this,
      value: widget.value.clamp(0.0, 1.0).toDouble(),
    );
  }

  @override
  void dispose() {
    _valueController.dispose();
    super.dispose();
  }

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
    // Outside a gesture the controller owns the displayed value; a new
    // [RangeBar.value] (wheel step, keyboard nudge, external state) settles
    // onto the fill with the effects spring. While a gesture is in flight the
    // finger already owns the controller via [_snapToGesture].
    if (_gestureValue == null) {
      _settleOnTarget();
    }
  }

  double get _targetValue => widget.value.clamp(0.0, 1.0).toDouble();

  double get _displayValue =>
      (_gestureValue ?? _valueController.value).clamp(0.0, 1.0).toDouble();

  /// Gesture-driven updates keep the fill glued to the finger — no spring,
  /// no lag — while keeping the controller synced so releasing the gesture
  /// continues from the dragged position instead of snapping back.
  void _snapToGesture(double value) {
    _valueController.stop();
    _valueController.value = value;
  }

  /// Springs the fill toward the committed [RangeBar.value]; reduce-motion
  /// users get the target immediately.
  void _settleOnTarget() {
    final target = _targetValue;
    if (_valueController.value == target) {
      return;
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      _valueController.stop();
      _valueController.value = target;
      return;
    }
    springTo(
      _valueController,
      target,
      velocity: _valueController.velocity,
      spring: Motion.expressiveEffectsDefault,
      telemetryLabel: 'range_bar_value',
    );
  }

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
    _snapToGesture(next);
    widget.onChanged(next);
  }

  void _startRelativeGesture() {
    if (_gestureValue != null) {
      return;
    }
    widget.onChangeStart?.call();
    setState(() {
      _gestureValue = _targetValue;
    });
    _snapToGesture(_gestureValue!);
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
    _snapToGesture(next);
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
    // The committed value may differ from the last drag position (rounding,
    // clamps applied by the caller). Settle onto it rather than snapping.
    _settleOnTarget();
  }

  @override
  Widget build(BuildContext context) {
    final leadingIcon = widget.leadingIcon;
    final trailingWidget = widget.trailing;
    if (leadingIcon == null && trailingWidget == null) {
      return _buildTrack(context);
    }
    return Row(
      children: [
        if (leadingIcon != null) ...[
          _buildLeadingIcon(context, leadingIcon),
          const SizedBox(width: ShellSpacing.sm),
        ],
        Expanded(child: _buildTrack(context)),
        if (trailingWidget != null) ...[
          const SizedBox(width: ShellSpacing.sm),
          trailingWidget,
        ],
      ],
    );
  }

  /// Detached leading icon segment — a Ø40 circle on `surfaceContainerHigh`,
  /// matching the M3E slider composition in 02-VISUAL-SPEC §4.
  Widget _buildLeadingIcon(BuildContext context, IconData icon) {
    final colors = context.shellColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        shape: BoxShape.circle,
      ),
      child: SizedBox(
        width: 40.0,
        height: 40.0,
        child: Icon(
          icon,
          size: 20.0,
          color: widget.enabled ? colors.textPrimary : colors.textTertiary,
        ),
      ),
    );
  }

  Widget _buildTrack(BuildContext context) {
    return AnimatedBuilder(
      animation: _valueController,
      builder: (context, _) {
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
              inactiveWidth = (totalWidth - inactiveLeft).clamp(
                0.0,
                totalWidth,
              );
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
                          _updateFromPosition(
                            details.localPosition,
                            totalWidth,
                          );
                        }
                      }
                    : null,
                onHorizontalDragUpdate: enabled
                    ? (details) {
                        if (details.kind == PointerDeviceKind.trackpad) {
                          _updateFromDelta(
                            details.primaryDelta ?? 0,
                            totalWidth,
                          );
                        } else {
                          _updateFromPosition(
                            details.localPosition,
                            totalWidth,
                          );
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
                                color: colors.hairlineSoft.withValues(
                                  alpha: 0.50,
                                ),
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
                              color: colors.textTertiary.withValues(
                                alpha: 0.55,
                              ),
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
                      if (widget.leadingIcon == null)
                        Positioned(
                          left: 12.0,
                          top: 0,
                          bottom: 0,
                          child: Center(
                            child: Icon(
                              widget.icon,
                              color: iconColor,
                              size: 20.0,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
