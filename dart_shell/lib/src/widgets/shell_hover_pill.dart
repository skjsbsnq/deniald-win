import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';
import 'shell_expressive_surface.dart';

/// A hoverable, keyboard-activatable capsule control for shell chrome.
///
/// This is the shared replacement for the hand-copied quintuple that
/// proliferated across shelf and dashboard surfaces — a per-site
/// StatefulWidget holding `MouseRegion(onEnter/onExit → setState)` +
/// `GestureDetector` + `AnimatedContainer(duration: Motion.pill)`. Input
/// plumbing and lifecycle now live in [ShellExpressiveSurface]; paint stays
/// declarative at the call site through [color]/[hoverColor]/[border]/
/// [hoverBorder].
///
/// Unlike the hand-rolled copies, the control is focusable: Tab reaches it,
/// Enter and Space activate it, and the focused state is exposed to
/// [childBuilder] so surfaces can draw their own focus treatment.
///
/// Provide either [child] for static content or [childBuilder] when the
/// content itself reacts to hover (e.g. a foreground color that follows the
/// surface).
class ShellHoverPill extends StatelessWidget {
  const ShellHoverPill({
    required this.onTap,
    required this.child,
    this.color,
    this.hoverColor,
    this.border,
    this.hoverBorder,
    this.radius = ShellShapeScale.full,
    this.width,
    this.height,
    this.padding,
    this.alignment = Alignment.center,
    this.enabled = true,
    this.autofocus = false,
    this.semanticLabel,
    super.key,
  }) : childBuilder = null;

  const ShellHoverPill.builder({
    required this.onTap,
    required this.childBuilder,
    this.color,
    this.hoverColor,
    this.border,
    this.hoverBorder,
    this.radius = ShellShapeScale.full,
    this.width,
    this.height,
    this.padding,
    this.alignment = Alignment.center,
    this.enabled = true,
    this.autofocus = false,
    this.semanticLabel,
    super.key,
  }) : child = null;

  /// Activation callback. A null callback (or [enabled] = false) disables
  /// the pill: basic cursor, no hover styling, no keyboard activation.
  final VoidCallback? onTap;

  /// Resting container color. Null leaves the surface transparent.
  final Color? color;

  /// Container color while hovered; falls back to [color].
  final Color? hoverColor;

  /// Resting container border.
  final Border? border;

  /// Container border while hovered; falls back to [border].
  final Border? hoverBorder;

  /// Base radius for the container, resolved through the shell theme;
  /// defaults to a fully rounded capsule ([ShellShapeScale.full]).
  final double radius;

  /// Optional fixed size and inner padding.
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;

  /// Alignment of the content within the container.
  final AlignmentGeometry alignment;

  final bool enabled;
  final bool autofocus;

  /// Accessibility label for controls whose visual content is not
  /// self-describing (icon-only buttons).
  final String? semanticLabel;

  final Widget? child;

  /// Content builder receiving the live [hovered] and [focused] flags, for
  /// surfaces whose foreground follows the interaction state.
  final Widget Function(BuildContext context, bool hovered, bool focused)?
  childBuilder;

  @override
  Widget build(BuildContext context) {
    final builder = childBuilder;
    if (builder != null) {
      return ShellExpressiveSurface.builder(
        onPressed: onTap,
        shape: radius,
        color: color,
        // A null [hoverColor] historically meant "no hover tint"; the
        // surface's default state-layer overlay would add one, so pin the
        // resting color.
        hoverColor: hoverColor ?? color,
        border: border,
        hoverBorder: hoverBorder,
        // The pill historically paints no press scale and no focus treatment
        // of its own — call sites that care draw through [childBuilder]. Keep
        // that contract while the plumbing moves to the shared surface.
        enablePressScale: false,
        showFocusRing: false,
        highlightOnFocus: false,
        width: width,
        height: height,
        padding: padding,
        alignment: alignment,
        enabled: enabled,
        autofocus: autofocus,
        semanticLabel: semanticLabel,
        childBuilder: (context, state) =>
            builder(context, state.hovered, state.focused),
      );
    }
    return ShellExpressiveSurface(
      onPressed: onTap,
      shape: radius,
      color: color,
      hoverColor: hoverColor ?? color,
      border: border,
      hoverBorder: hoverBorder,
      enablePressScale: false,
      showFocusRing: false,
      highlightOnFocus: false,
      width: width,
      height: height,
      padding: padding,
      alignment: alignment,
      enabled: enabled,
      autofocus: autofocus,
      semanticLabel: semanticLabel,
      child: child,
    );
  }
}
