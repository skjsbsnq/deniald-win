part of 'desktop_widgets.dart';

/// The shared MD3E widget container: a tonal fill clipped to an arbitrary
/// outline (blob or pill) with a grouped backdrop blur and no border
/// (02-VISUAL-SPEC.md §6 — widget 容器: tonal 填充 + blur + 无描边).
///
/// The fill goes through [ShellThemeData.cardColor], so `cardOpacity` keeps
/// governing translucency; when the effective card opacity reaches 1 the
/// blur is skipped exactly like the panel/card surfaces do.
class DesktopWidgetSurface extends StatelessWidget {
  const DesktopWidgetSurface({
    super.key,
    required this.shape,
    required this.color,
    required this.child,
    this.padding = EdgeInsets.zero,
  });

  /// Outline used for both the tonal fill and the clip.
  final ShapeBorder shape;

  /// Semantic role color; [ShellThemeData.cardColor] applies the user's
  /// card-opacity alpha before it is painted.
  final Color color;

  final EdgeInsetsGeometry padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return ClipPath.shape(
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: ShellBackdropBlur(
        blur: theme.effectiveCardOpacity < 1.0,
        grouped: true,
        child: DecoratedBox(
          decoration: ShapeDecoration(
            shape: shape,
            color: theme.cardColor(color),
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Convenience surface whose outline is one of the [DesktopBlobShape]
/// expressive blobs, with `cornerRadiusScale` fed into the corner cuts.
class DesktopBlobContainer extends StatelessWidget {
  const DesktopBlobContainer({
    super.key,
    required this.shape,
    required this.color,
    required this.child,
    this.padding = EdgeInsets.zero,
  });

  final DesktopBlobShape shape;
  final Color color;
  final EdgeInsetsGeometry padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DesktopWidgetSurface(
      shape: BlobShapeBorder(
        shape: shape,
        roundnessScale: context.shellTheme.cornerRadiusScale,
      ),
      color: color,
      padding: padding,
      child: child,
    );
  }
}

/// One-shot entrance for a freshly mounted widget: springs the subtree from
/// a slightly reduced scale to identity with `expressiveSpatialFast`
/// (02-VISUAL-SPEC.md §5/§6). Reduce-motion sessions start at the final
/// value so nothing animates; no ticker stays alive after the settle.
class DesktopWidgetEntrance extends StatefulWidget {
  const DesktopWidgetEntrance({super.key, required this.child});

  final Widget child;

  @override
  State<DesktopWidgetEntrance> createState() => _DesktopWidgetEntranceState();
}

class _DesktopWidgetEntranceState extends State<DesktopWidgetEntrance>
    with SingleTickerProviderStateMixin {
  static const double _restScale = 0.86;

  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController.unbounded(vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // MediaQuery flags resolve against the element's context, so the
    // reduce-motion check must wait for the first dependency pass.
    if (_controller.isAnimating || _controller.value != 0) {
      return;
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
      return;
    }
    unawaited(
      springTo(
        _controller,
        1,
        spring: Motion.expressiveSpatialFast,
        telemetryLabel: 'desktop_widget_entrance',
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final t = _controller.value.clamp(0.0, 1.0);
        if (t >= 1) {
          return child!;
        }
        return Transform.scale(
          scale: _restScale + (1 - _restScale) * t,
          child: child,
        );
      },
    );
  }
}
