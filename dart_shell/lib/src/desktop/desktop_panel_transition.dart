import 'package:flutter/widgets.dart';

import '../input/shell_interaction_registry.dart';
import '../input/shell_visual_registry.dart';
import '../theme/motion.dart';
import '../theme/shell_theme.dart';
import '../widgets/shell_backdrop_blur.dart';
import 'desktop_panel_blur_policy.dart';

/// Slides a desktop panel while keeping its element and state trees warm.
///
/// Closed panels stay offstage instead of being removed. This avoids making
/// the first frame of every opening animation also construct the full panel,
/// while [IgnorePointer], [ExcludeSemantics], and the keyboard policy keep the
/// retained subtree inert until it is visible again.
class DesktopPanelTransition extends StatefulWidget {
  const DesktopPanelTransition({
    super.key,
    required this.inputDebugLabel,
    required this.visible,
    required this.child,
    this.entryDirection = const Offset(-1, 0),
    this.entryDistance = 0,
    this.durationScale = 1,
    this.keyboardPolicy = ShellKeyboardPolicy.none,
    this.onOpened,
  });

  final String inputDebugLabel;
  final bool visible;
  final Widget child;
  final Offset entryDirection;
  final double entryDistance;
  final double durationScale;
  final ShellKeyboardPolicy keyboardPolicy;
  final VoidCallback? onOpened;

  @override
  State<DesktopPanelTransition> createState() => _DesktopPanelTransitionState();
}

class _DesktopPanelTransitionState extends State<DesktopPanelTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _progress;
  late bool _offstage;

  @override
  void initState() {
    super.initState();
    _offstage = !widget.visible;
    _controller = AnimationController(
      vsync: this,
      value: widget.visible ? 1.0 : 0.0,
      duration: _scaledDuration(Motion.desktopPanelOpen, widget.durationScale),
      reverseDuration: _scaledDuration(
        Motion.desktopPanelClose,
        widget.durationScale,
      ),
    );
    _progress = CurvedAnimation(
      parent: _controller,
      curve: Motion.md3EmphasizedDecelerate,
      reverseCurve: Motion.md3EmphasizedAccelerate,
    );
    _controller.addStatusListener(_handleAnimationStatus);
  }

  void _handleAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && widget.visible) {
      widget.onOpened?.call();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateDurations();
  }

  @override
  void didUpdateWidget(covariant DesktopPanelTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.durationScale != oldWidget.durationScale) {
      _updateDurations();
    }
    if (widget.visible == oldWidget.visible) {
      return;
    }

    if (widget.visible) {
      if (_offstage) {
        setState(() => _offstage = false);
      }
      _controller.forward();
      return;
    }

    _controller.reverse().whenCompleteOrCancel(() {
      if (!mounted || widget.visible || _controller.value != 0.0) {
        return;
      }
      setState(() => _offstage = true);
    });
  }

  void _updateDurations() {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    _controller
      ..duration = reduceMotion
          ? Duration.zero
          : _scaledDuration(Motion.desktopPanelOpen, widget.durationScale)
      ..reverseDuration = reduceMotion
          ? Duration.zero
          : _scaledDuration(Motion.desktopPanelClose, widget.durationScale);
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_handleAnimationStatus);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ShellInputRegion(
      debugLabel: widget.inputDebugLabel,
      active: widget.visible,
      keyboardPolicy: widget.visible
          ? widget.keyboardPolicy
          : ShellKeyboardPolicy.none,
      child: ShellVisualRegion(
        debugLabel: widget.inputDebugLabel,
        active: widget.visible,
        revision: widget.visible ? 1 : 0,
        requiresClientSampling:
            widget.visible && ShellTheme.of(context).panelOpacity < 1.0,
        child: IgnorePointer(
          ignoring: !widget.visible,
          child: ExcludeSemantics(
            excluding: !widget.visible,
            child: ExcludeFocus(
              excluding: !widget.visible,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final direction = widget.entryDirection;
                  final travel = Offset(
                    direction.dx *
                        (constraints.maxWidth + widget.entryDistance),
                    direction.dy *
                        (constraints.maxHeight + widget.entryDistance),
                  );
                  return Offstage(
                    offstage: _offstage,
                    child: ClipRect(
                      clipper: _DesktopPanelVisibleClipper(
                        progress: _progress,
                        travel: travel,
                      ),
                      child: ShellBackdropBlur(
                        blur: shouldBlurDesktopPanel(
                          panelOpacity: ShellTheme.of(context).panelOpacity,
                        ),
                        borderRadius: BorderRadius.circular(
                          ShellTheme.of(context).panelRadius,
                        ),
                        child: RepaintBoundary(
                          child: AnimatedBuilder(
                            animation: _progress,
                            child: widget.child,
                            builder: (context, child) => Transform.translate(
                              offset: travel * (1.0 - _progress.value),
                              child: child,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopPanelVisibleClipper extends CustomClipper<Rect> {
  _DesktopPanelVisibleClipper({
    required Animation<double> progress,
    required this.travel,
  }) : _progress = progress,
       super(reclip: progress);

  final Animation<double> _progress;
  final Offset travel;

  @override
  Rect getClip(Size size) => desktopPanelVisibleClip(
    size: size,
    offset: travel * (1.0 - _progress.value),
  );

  @override
  bool shouldReclip(covariant _DesktopPanelVisibleClipper oldClipper) {
    return oldClipper._progress != _progress || oldClipper.travel != travel;
  }
}

Duration _scaledDuration(Duration duration, double scale) {
  return Duration(microseconds: (duration.inMicroseconds * scale).round());
}
