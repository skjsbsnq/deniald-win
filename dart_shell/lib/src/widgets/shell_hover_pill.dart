import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../theme/motion.dart';
import '../theme/shell_theme.dart';
import '../theme/tokens.dart';

/// A hoverable, keyboard-activatable capsule control for shell chrome.
///
/// This is the shared replacement for the hand-copied quintuple that
/// proliferated across shelf and dashboard surfaces — a per-site
/// StatefulWidget holding `MouseRegion(onEnter/onExit → setState)` +
/// `GestureDetector` + `AnimatedContainer(duration: Motion.pill)`. Input
/// plumbing and lifecycle live here; paint stays declarative at the call
/// site through [color]/[hoverColor]/[border]/[hoverBorder].
///
/// Unlike the hand-rolled copies, the control is focusable: Tab reaches it,
/// Enter and Space activate it, and the focused state is exposed to
/// [childBuilder] so surfaces can draw their own focus treatment.
///
/// Provide either [child] for static content or [childBuilder] when the
/// content itself reacts to hover (e.g. a foreground color that follows the
/// surface).
class ShellHoverPill extends StatefulWidget {
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
  State<ShellHoverPill> createState() => _ShellHoverPillState();
}

class _ShellHoverPillState extends State<ShellHoverPill> {
  bool _hovered = false;
  bool _focused = false;

  bool get _active => widget.enabled && widget.onTap != null;

  @override
  Widget build(BuildContext context) {
    final hovered = _active && _hovered;
    final theme = context.shellTheme;
    final content =
        widget.childBuilder?.call(context, hovered, _focused) ?? widget.child!;

    Widget pill = AnimatedContainer(
      duration: Motion.pill,
      curve: Curves.easeOut,
      width: widget.width,
      height: widget.height,
      padding: widget.padding,
      alignment: widget.alignment,
      decoration: BoxDecoration(
        color: hovered ? (widget.hoverColor ?? widget.color) : widget.color,
        borderRadius: theme.borderRadius(widget.radius),
        border: hovered ? (widget.hoverBorder ?? widget.border) : widget.border,
      ),
      child: content,
    );

    if (widget.semanticLabel != null) {
      pill = Semantics(
        button: true,
        enabled: _active,
        label: widget.semanticLabel,
        child: pill,
      );
    }

    return FocusableActionDetector(
      enabled: _active,
      autofocus: widget.autofocus,
      mouseCursor: _active
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onShowHoverHighlight: (value) {
        if (_hovered != value) {
          setState(() => _hovered = value);
        }
      },
      onShowFocusHighlight: (value) {
        if (_focused != value) {
          setState(() => _focused = value);
        }
      },
      shortcuts: _active
          ? const <ShortcutActivator, Intent>{
              SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
              SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
            }
          : null,
      actions: _active
          ? <Type, Action<Intent>>{
              ActivateIntent: CallbackAction<ActivateIntent>(
                onInvoke: (_) => widget.onTap!.call(),
              ),
            }
          : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _active ? widget.onTap : null,
        child: pill,
      ),
    );
  }
}
