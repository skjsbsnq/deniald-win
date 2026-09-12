import 'package:flutter/material.dart' show Tooltip;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../theme/motion.dart';
import '../theme/shell_theme.dart';
import '../theme/tokens.dart';

/// Live interaction flags handed to [ShellExpressiveSurface.childBuilder] so
/// foreground content can follow the surface (icon colors, emphasis).
class ShellSurfaceInteraction {
  const ShellSurfaceInteraction({
    this.hovered = false,
    this.focused = false,
    this.pressed = false,
  });

  final bool hovered;
  final bool focused;
  final bool pressed;
}

/// Signature for [ShellExpressiveSurface.childBuilder].
typedef ShellSurfaceChildBuilder =
    Widget Function(BuildContext context, ShellSurfaceInteraction state);

/// Unified M3E interaction base for shell controls.
///
/// This widget is the single implementation of the pattern that used to be
/// hand-copied into `ShelfAppButton` / `ShelfLauncherButton` /
/// `ShelfWorkspaceButton` / `QuickTile`: a pair of unbounded animation
/// controllers lerping hover and press state. It provides, out of the box:
///
/// - a hover/focus **state layer** — [hoverColor], or an `onSurface`-alpha
///   overlay derived from `colors.panelHighlight` when unset — driven by
///   `Motion.expressiveEffectsDefault`;
/// - a **pressed** pair of springs: [pressScale] on
///   `Motion.expressiveSpatialFast` and the [pressedColor] tint (defaulting to
///   the same state-layer overlay) on `Motion.expressiveEffectsDefault`;
/// - an optional **shape-morph**: when [pressedShape] is set, the corner
///   radius interpolates to it while pressed on `Motion.expressiveEffectsFast`
///   (the `SettingsButton` precedent);
/// - `FocusableActionDetector` with Enter/Space activation, a focus ring
///   ([focusedBorder], or a default accent outline), pointer/tap and
///   `onLongPress` handling, plus `Semantics(button:)`;
/// - reduce-motion fallback: every controller snaps to its target when
///   `MediaQuery.disableAnimationsOf` is true.
///
/// [shape]/[pressedShape] accept a `ShellShapeScale` tier (a `double` resolved
/// through `theme.borderRadius`, so `cornerRadiusScale` keeps working), a
/// `BorderRadiusGeometry`, or a `RoundedRectangleBorder`.
class ShellExpressiveSurface extends StatefulWidget {
  const ShellExpressiveSurface({
    required this.child,
    this.onPressed,
    this.onLongPress,
    this.shape = ShellShapeScale.full,
    this.pressedShape,
    this.color,
    this.hoverColor,
    this.pressedColor,
    this.border,
    this.hoverBorder,
    this.focusedBorder,
    this.showFocusRing = true,
    this.highlightOnFocus = true,
    this.enablePressScale = true,
    this.pressScale = 0.94,
    this.width,
    this.height,
    this.padding,
    this.minSize,
    this.alignment = Alignment.center,
    this.tooltip,
    this.enabled = true,
    this.autofocus = false,
    this.focusNode,
    this.semanticLabel,
    super.key,
  }) : childBuilder = null,
       assert(
         shape == null ||
             shape is double ||
             shape is BorderRadiusGeometry ||
             shape is RoundedRectangleBorder,
         'shape must be a ShellShapeScale tier (double), a '
         'BorderRadiusGeometry, or a RoundedRectangleBorder',
       ),
       assert(
         pressedShape == null ||
             pressedShape is double ||
             pressedShape is BorderRadiusGeometry ||
             pressedShape is RoundedRectangleBorder,
         'pressedShape must be a ShellShapeScale tier (double), a '
         'BorderRadiusGeometry, or a RoundedRectangleBorder',
       );

  const ShellExpressiveSurface.builder({
    required this.childBuilder,
    this.onPressed,
    this.onLongPress,
    this.shape = ShellShapeScale.full,
    this.pressedShape,
    this.color,
    this.hoverColor,
    this.pressedColor,
    this.border,
    this.hoverBorder,
    this.focusedBorder,
    this.showFocusRing = true,
    this.highlightOnFocus = true,
    this.enablePressScale = true,
    this.pressScale = 0.94,
    this.width,
    this.height,
    this.padding,
    this.minSize,
    this.alignment = Alignment.center,
    this.tooltip,
    this.enabled = true,
    this.autofocus = false,
    this.focusNode,
    this.semanticLabel,
    super.key,
  }) : child = null,
       assert(
         shape == null ||
             shape is double ||
             shape is BorderRadiusGeometry ||
             shape is RoundedRectangleBorder,
         'shape must be a ShellShapeScale tier (double), a '
         'BorderRadiusGeometry, or a RoundedRectangleBorder',
       ),
       assert(
         pressedShape == null ||
             pressedShape is double ||
             pressedShape is BorderRadiusGeometry ||
             pressedShape is RoundedRectangleBorder,
         'pressedShape must be a ShellShapeScale tier (double), a '
         'BorderRadiusGeometry, or a RoundedRectangleBorder',
       );

  /// Activation callback. The surface is interactive while [enabled] and at
  /// least one of [onPressed]/[onLongPress] is set; otherwise it renders
  /// inertly (basic cursor, no highlights, no keyboard activation).
  final VoidCallback? onPressed;

  final VoidCallback? onLongPress;

  /// Resting shape. A `double` is treated as a `ShellShapeScale` tier and
  /// resolved through `ShellThemeData.borderRadius`.
  final Object? shape;

  /// Shape the corners morph toward while pressed (M3E shape-morph). Null
  /// keeps [shape] at all times.
  final Object? pressedShape;

  /// Resting container color; null leaves the surface transparent.
  final Color? color;

  /// Container color while hovered (and focused when [highlightOnFocus]).
  /// When null the M3 state-layer overlay (`colors.panelHighlight`, the
  /// `onSurface`-alpha token) is blended over the resting color instead.
  final Color? hoverColor;

  /// Container color while pressed; null falls back to the state-layer
  /// overlay blended over the current background.
  final Color? pressedColor;

  /// Resting border, and the border while hovered (falls back to [border]).
  final Border? border;
  final Border? hoverBorder;

  /// Border while keyboard-focused. Null falls back to a default accent
  /// outline when [showFocusRing] is true.
  final Border? focusedBorder;

  /// Whether keyboard focus paints a ring when [focusedBorder] is unset.
  /// Callers that draw their own focus treatment through [childBuilder] can
  /// turn this off.
  final bool showFocusRing;

  /// Whether keyboard focus also lights the hover state layer.
  final bool highlightOnFocus;

  /// Whether the surface scales down to [pressScale] while pressed.
  final bool enablePressScale;

  /// Scale factor at full press. Defaults to the M3E control press of 0.94.
  final double pressScale;

  /// Optional fixed size, inner padding and minimum touch-target size.
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final Size? minSize;

  /// Alignment of the content within the container.
  final AlignmentGeometry alignment;

  /// Optional tooltip text.
  final String? tooltip;

  final bool enabled;
  final bool autofocus;
  final FocusNode? focusNode;

  /// Accessibility label for controls whose content is not self-describing.
  final String? semanticLabel;

  final Widget? child;

  /// Content builder receiving the live interaction flags.
  final ShellSurfaceChildBuilder? childBuilder;

  @override
  State<ShellExpressiveSurface> createState() => _ShellExpressiveSurfaceState();
}

class _ShellExpressiveSurfaceState extends State<ShellExpressiveSurface>
    with TickerProviderStateMixin {
  // The three interaction tracks. Hover/focus drives the state layer, while
  // press owns a spatial spring (scale) and an effects spring (tint) so each
  // keeps its spec'd feel. A fourth controller is allocated lazily, only when
  // `pressedShape` asks for a corner morph.
  late final AnimationController _highlightController;
  late final AnimationController _pressScaleController;
  late final AnimationController _pressTintController;
  AnimationController? _shapeController;

  var _hovered = false;
  var _focused = false;
  var _pressed = false;

  bool get _interactive =>
      widget.enabled &&
      (widget.onPressed != null || widget.onLongPress != null);

  @override
  void initState() {
    super.initState();
    _highlightController = AnimationController.unbounded(vsync: this);
    _pressScaleController = AnimationController.unbounded(vsync: this);
    _pressTintController = AnimationController.unbounded(vsync: this);
  }

  @override
  void didUpdateWidget(covariant ShellExpressiveSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A control disabled mid-interaction never receives the matching
    // up/exit callbacks; release the tracked state so no highlight sticks.
    if (!_interactive && (_pressed || _hovered || _focused)) {
      _pressed = false;
      _updateHighlight(hovered: false, focused: false);
      _drivePress(target: 0);
    }
  }

  @override
  void dispose() {
    _highlightController.dispose();
    _pressScaleController.dispose();
    _pressTintController.dispose();
    _shapeController?.dispose();
    super.dispose();
  }

  AnimationController get _shapeProgress {
    return _shapeController ??= AnimationController.unbounded(vsync: this);
  }

  // Reduce-motion users get the end state directly; the springs are
  // decorative overshoot. Retargets keep the current velocity so a
  // mid-flight reversal stays continuous.
  void _drive(
    AnimationController controller,
    double target,
    SpringDescription spring,
    String label,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) {
      controller.stop();
      controller.value = target;
      return;
    }
    springTo(
      controller,
      target,
      velocity: controller.velocity,
      spring: spring,
      telemetryLabel: label,
    );
  }

  void _updateHighlight({bool? hovered, bool? focused}) {
    final nextHovered = hovered ?? _hovered;
    final nextFocused = focused ?? _focused;
    if (nextHovered == _hovered && nextFocused == _focused) {
      return;
    }
    setState(() {
      _hovered = nextHovered;
      _focused = nextFocused;
    });
    final highlighted =
        _interactive && (_hovered || (widget.highlightOnFocus && _focused));
    _drive(
      _highlightController,
      highlighted ? 1.0 : 0.0,
      Motion.expressiveEffectsDefault,
      'expressive_surface_highlight',
    );
  }

  void _setPressed(bool pressed) {
    if (_pressed == pressed) {
      return;
    }
    setState(() => _pressed = pressed);
    _drivePress(target: pressed ? 1.0 : 0.0);
  }

  void _drivePress({required double target}) {
    _drive(
      _pressScaleController,
      target,
      Motion.expressiveSpatialFast,
      'expressive_surface_press_scale',
    );
    _drive(
      _pressTintController,
      target,
      Motion.expressiveEffectsDefault,
      'expressive_surface_press_tint',
    );
    if (widget.pressedShape != null) {
      _drive(
        _shapeProgress,
        target,
        Motion.expressiveEffectsFast,
        'expressive_surface_shape',
      );
    }
  }

  BorderRadius _resolveShape(Object? shape, double fallbackTier) {
    final theme = context.shellTheme;
    final geometry = switch (shape) {
      RoundedRectangleBorder(:final borderRadius) => borderRadius,
      final BorderRadiusGeometry geometry => geometry,
      final double tier => theme.borderRadius(tier),
      _ => theme.borderRadius(fallbackTier),
    };
    return geometry.resolve(Directionality.of(context));
  }

  // M3 state layer: an onSurface-alpha overlay composited over the resting
  // color, unless the caller pinned an explicit hover/press color.
  Color _stateLayer(Color overlay, Color? base) {
    return base == null ? overlay : Color.alphaBlend(overlay, base);
  }

  void _handleActivate() {
    widget.onPressed?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = context.shellColors;
    final interactive = _interactive;
    final hovered = interactive && _hovered;
    final focused = interactive && _focused;

    final content =
        widget.childBuilder?.call(
          context,
          ShellSurfaceInteraction(
            hovered: hovered,
            focused: focused,
            pressed: interactive && _pressed,
          ),
        ) ??
        widget.child!;

    final listenables = <Listenable>[
      _highlightController,
      _pressScaleController,
      _pressTintController,
      if (widget.pressedShape != null) _shapeProgress,
    ];

    Widget surface = AnimatedBuilder(
      animation: Listenable.merge(listenables),
      builder: (context, _) {
        final highlightT = _highlightController.value.clamp(0.0, 1.0);
        final pressTintT = _pressTintController.value.clamp(0.0, 1.0);
        final pressScaleT = widget.enablePressScale
            ? _pressScaleController.value.clamp(0.0, 1.0)
            : 0.0;
        final shapeT = widget.pressedShape == null
            ? 0.0
            : _shapeProgress.value.clamp(0.0, 1.0);

        final restColor = widget.color;
        final highlightTarget =
            widget.hoverColor ?? _stateLayer(colors.panelHighlight, restColor);
        var background = Color.lerp(restColor, highlightTarget, highlightT);
        if (pressTintT > 0) {
          final pressedOverlay =
              widget.pressedColor ??
              _stateLayer(colors.panelHighlight, background);
          background = Color.lerp(background, pressedOverlay, pressTintT);
        }

        final restRadius = _resolveShape(widget.shape, ShellShapeScale.full);
        final pressedShape = widget.pressedShape;
        final radius = pressedShape == null
            ? restRadius
            : BorderRadius.lerp(
                restRadius,
                _resolveShape(pressedShape, ShellShapeScale.full),
                shapeT,
              )!;

        var effectiveBorder = hovered
            ? (widget.hoverBorder ?? widget.border)
            : widget.border;
        if (focused) {
          final ring =
              widget.focusedBorder ??
              (widget.showFocusRing
                  ? Border.all(color: theme.accentPalette.primary, width: 2)
                  : null);
          if (ring != null) {
            effectiveBorder = ring;
          }
        }

        Widget box = Container(
          width: widget.width,
          height: widget.height,
          constraints: widget.minSize == null
              ? null
              : BoxConstraints(
                  minWidth: widget.minSize!.width,
                  minHeight: widget.minSize!.height,
                ),
          padding: widget.padding,
          alignment: widget.alignment,
          decoration: BoxDecoration(
            color: background,
            borderRadius: radius,
            border: effectiveBorder,
          ),
          child: content,
        );

        if (widget.enablePressScale) {
          final scale = 1.0 - (1.0 - widget.pressScale) * pressScaleT;
          box = Transform.scale(scale: scale, child: box);
        }
        return box;
      },
    );

    surface = Semantics(
      button: true,
      enabled: interactive,
      label: widget.semanticLabel,
      onTap: interactive ? _handleActivate : null,
      onLongPress: interactive ? widget.onLongPress : null,
      child: surface,
    );

    surface = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: interactive ? widget.onPressed : null,
      onLongPress: interactive ? widget.onLongPress : null,
      onTapDown: interactive ? (_) => _setPressed(true) : null,
      onTapUp: interactive ? (_) => _setPressed(false) : null,
      onTapCancel: interactive ? () => _setPressed(false) : null,
      child: surface,
    );

    // Hover uses a raw MouseRegion rather than the detector's gated hover
    // highlight: surface feedback must appear on any hover-capable platform,
    // not only while the focus highlight mode is "traditional".
    surface = MouseRegion(
      onEnter: interactive ? (_) => _updateHighlight(hovered: true) : null,
      onExit: interactive ? (_) => _updateHighlight(hovered: false) : null,
      child: surface,
    );

    surface = FocusableActionDetector(
      enabled: interactive,
      autofocus: widget.autofocus,
      focusNode: widget.focusNode,
      mouseCursor: interactive
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onShowFocusHighlight: (value) => _updateHighlight(focused: value),
      shortcuts: interactive
          ? const <ShortcutActivator, Intent>{
              SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
              SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
            }
          : null,
      actions: interactive
          ? <Type, Action<Intent>>{
              ActivateIntent: CallbackAction<ActivateIntent>(
                onInvoke: (_) => _handleActivate(),
              ),
            }
          : null,
      child: surface,
    );

    final tooltip = widget.tooltip;
    if (tooltip != null) {
      surface = Tooltip(message: tooltip, child: surface);
    }

    return surface;
  }
}
