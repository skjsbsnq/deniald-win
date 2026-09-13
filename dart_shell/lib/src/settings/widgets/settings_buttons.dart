import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/motion.dart';
import '../../theme/shell_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/shell_cursor.dart';

/// Visual variants of the M3E settings button family.
///
/// Values map onto the M3 button variants described in `02-VISUAL-SPEC.md`
/// §3.6: `filled` (single page primary action), `filledTonal` (secondary
/// action), `outlined` and `text` (low emphasis).
enum SettingsButtonVariant { filled, filledTonal, outlined, text }

/// Size family of the M3E settings button.
///
/// Geometry is fixed by `02-VISUAL-SPEC.md` §3.6: `small` is 40 high with 16
/// horizontal padding and a 20 icon; `medium` is 56 high with 24 horizontal
/// padding and a 24 icon.
enum SettingsButtonSize { small, medium }

/// Interaction flags surfaced to a [SettingsInteractiveSurface] builder so the
/// surface can paint its own hover/press/focus affordances.
@immutable
class SettingsInteractionState {
  const SettingsInteractionState({
    required this.hovered,
    required this.focused,
    required this.pressed,
  });

  final bool hovered;
  final bool focused;
  final bool pressed;
}

/// Builds the visual body of a [SettingsInteractiveSurface].
///
/// [radius] is the animated corner radius (full at rest, morphing toward the
/// pressed radius) and already carries the user's `cornerRadiusScale`.
typedef SettingsSurfaceBuilder =
    Widget Function(
      BuildContext context,
      BorderRadius radius,
      SettingsInteractionState state,
    );

/// Shared pressable primitive for the M3E control family.
///
/// It owns gesture, hover, focus and disabled handling so every control paints
/// the same six states, and it morphs its corner radius on press using the M3E
/// effects spring (`Motion.expressiveEffectsFast`) exactly as `02-VISUAL-SPEC.md`
/// §3.6 requires. Callers keep painting the surface through [builder].
class SettingsInteractiveSurface extends StatefulWidget {
  const SettingsInteractiveSurface({
    required this.builder,
    required this.height,
    required this.pressedRadius,
    required this.onPressed,
    this.enabled = true,
    this.focusNode,
    this.semanticsButton = true,
    this.semanticsEnabled,
    this.semanticsSelected,
    this.semanticsChecked,
    this.semanticsInMutuallyExclusiveGroup,
    this.semanticsExpanded,
    this.semanticsLabel,
    this.semanticsValue,
    this.shortcuts,
    this.actions,
    super.key,
  });

  final SettingsSurfaceBuilder builder;
  final double height;

  /// Base (unscaled) corner radius applied while pressed.
  final double pressedRadius;

  final VoidCallback? onPressed;
  final bool enabled;
  final FocusNode? focusNode;
  final bool semanticsButton;
  final bool? semanticsEnabled;
  final bool? semanticsSelected;
  final bool? semanticsChecked;
  final bool? semanticsInMutuallyExclusiveGroup;
  final bool? semanticsExpanded;
  final String? semanticsLabel;
  final String? semanticsValue;
  final Map<ShortcutActivator, Intent>? shortcuts;
  final Map<Type, Action<Intent>>? actions;

  @override
  State<SettingsInteractiveSurface> createState() =>
      SettingsInteractiveSurfaceState();
}

class SettingsInteractiveSurfaceState
    extends State<SettingsInteractiveSurface>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shapeController;
  var _hovered = false;
  var _focused = false;
  var _pressed = false;

  @override
  void initState() {
    super.initState();
    // No duration is needed: the shape is always driven by a spring.
    _shapeController = AnimationController(vsync: this);
  }

  @override
  void didUpdateWidget(covariant SettingsInteractiveSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isInteractive && _pressed) {
      _setPressed(false);
    }
  }

  @override
  void dispose() {
    _shapeController.dispose();
    super.dispose();
  }

  void _setPressed(bool pressed) {
    if (_pressed == pressed) {
      return;
    }
    setState(() => _pressed = pressed);
    final target = pressed ? 1.0 : 0.0;
    if (MediaQuery.disableAnimationsOf(context)) {
      _shapeController.value = target;
    } else {
      springTo(
        _shapeController,
        target,
        spring: Motion.expressiveEffectsFast,
        telemetryLabel: 'settings_surface_shape',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final interactive = widget.isInteractive;
    final motionDuration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : Motion.tile;
    return AnimatedOpacity(
      duration: motionDuration,
      opacity: interactive ? 1 : 0.46,
      child: AnimatedBuilder(
        animation: _shapeController,
        builder: (context, _) {
          final theme = ShellTheme.of(context);
          final t = _shapeController.value.clamp(0.0, 1.0);
          final radius =
              BorderRadius.lerp(
                theme.borderRadius(ShellShapeScale.full),
                theme.borderRadius(widget.pressedRadius),
                t,
              )!;
          return Semantics(
            button: widget.semanticsButton,
            enabled: widget.semanticsEnabled ?? interactive,
            selected: widget.semanticsSelected,
            checked: widget.semanticsChecked,
            inMutuallyExclusiveGroup: widget.semanticsInMutuallyExclusiveGroup,
            expanded: widget.semanticsExpanded,
            label: widget.semanticsLabel,
            value: widget.semanticsValue,
            child: FocusableActionDetector(
              focusNode: widget.focusNode,
              enabled: interactive,
              mouseCursor: interactive
                  ? ShellMouseCursors.link
                  : SystemMouseCursors.basic,
              onShowHoverHighlight: (value) =>
                  setState(() => _hovered = value),
              onShowFocusHighlight: (value) =>
                  setState(() => _focused = value),
              shortcuts: <ShortcutActivator, Intent>{
                const SingleActivator(LogicalKeyboardKey.enter):
                    ActivateIntent(),
                const SingleActivator(LogicalKeyboardKey.space):
                    ActivateIntent(),
                ...?widget.shortcuts,
              },
              actions: <Type, Action<Intent>>{
                ActivateIntent: CallbackAction<ActivateIntent>(
                  onInvoke: (_) {
                    widget.onPressed?.call();
                    return null;
                  },
                ),
                ...?widget.actions,
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: interactive ? (_) => _setPressed(true) : null,
                onTapUp: interactive ? (_) => _setPressed(false) : null,
                onTapCancel: interactive ? () => _setPressed(false) : null,
                onTap: interactive ? widget.onPressed : null,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: widget.height),
                  child: widget.builder(
                    context,
                    radius,
                    SettingsInteractionState(
                      hovered: _hovered,
                      focused: _focused,
                      pressed: _pressed,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

extension on SettingsInteractiveSurface {
  bool get isInteractive => enabled && onPressed != null;
}

/// M3E button family (`02-VISUAL-SPEC.md` §3.6).
///
/// Geometry and the full → 8/12 pressed shape morph are fixed by the spec; the
/// label uses the `settingsButtonLabel` role (§6).
class SettingsButton extends StatelessWidget {
  const SettingsButton({
    required this.label,
    required this.onPressed,
    this.variant = SettingsButtonVariant.filledTonal,
    this.size = SettingsButtonSize.small,
    this.icon,
    this.leading,
    this.trailing,
    this.focusNode,
    this.shortcuts,
    this.actions,
    this.semanticsLabel,
    this.semanticsValue,
    this.semanticsExpanded,
    this.surfaceKey,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final SettingsButtonVariant variant;
  final SettingsButtonSize size;
  final IconData? icon;
  final Widget? leading;
  final Widget? trailing;
  final FocusNode? focusNode;
  final Map<ShortcutActivator, Intent>? shortcuts;
  final Map<Type, Action<Intent>>? actions;

  /// Optional accessible label; defaults to [label] when omitted.
  final String? semanticsLabel;
  final String? semanticsValue;
  final bool? semanticsExpanded;

  /// Optional key applied to the background surface, for tests that assert the
  /// animated corner radius.
  final Key? surfaceKey;

  bool get _small => size == SettingsButtonSize.small;

  @override
  Widget build(BuildContext context) {
    final theme = ShellTheme.of(context);
    final colors = context.shellColors;
    final palette = theme.accentPalette;
    final height = _small ? 40.0 : 56.0;
    final padding = _small ? 16.0 : 24.0;
    final iconSize = _small ? 20.0 : 24.0;
    final pressedRadius = _small
        ? ShellShapeScale.small
        : ShellShapeScale.medium;

    final Color background;
    final Color foreground;
    final Color? borderColor;
    final Color stateLayer;
    switch (variant) {
      case SettingsButtonVariant.filled:
        background = palette.primary;
        foreground = palette.onPrimary;
        borderColor = null;
        stateLayer = palette.onPrimary;
      case SettingsButtonVariant.filledTonal:
        background = palette.container;
        foreground = palette.onContainer;
        borderColor = null;
        stateLayer = palette.onContainer;
      case SettingsButtonVariant.outlined:
        background = ShellMediaColors.transparentDark;
        foreground = colors.textPrimary;
        borderColor = colors.hairline;
        stateLayer = palette.primary;
      case SettingsButtonVariant.text:
        background = ShellMediaColors.transparentDark;
        foreground = palette.primary;
        borderColor = null;
        stateLayer = palette.primary;
    }

    final motionDuration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : Motion.tile;
    final labelStyle = ShellText.settingsButtonLabel.copyWith(
      color: foreground,
    );

    return SettingsInteractiveSurface(
      height: height,
      pressedRadius: pressedRadius,
      enabled: onPressed != null,
      onPressed: onPressed,
      focusNode: focusNode,
      shortcuts: shortcuts,
      actions: actions,
      semanticsLabel: semanticsLabel ?? label,
      semanticsValue: semanticsValue,
      semanticsExpanded: semanticsExpanded,
      builder: (context, radius, state) {
        return Stack(
          alignment: Alignment.center,
          children: <Widget>[
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  key: surfaceKey,
                  decoration: BoxDecoration(
                    color: background,
                    borderRadius: radius,
                    border: borderColor == null
                        ? null
                        : Border.all(color: borderColor),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  duration: motionDuration,
                  opacity: state.hovered || state.pressed ? 1 : 0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: stateLayer.withValues(
                        alpha: state.pressed ? 0.12 : 0.08,
                      ),
                      borderRadius: radius,
                    ),
                  ),
                ),
              ),
            ),
            if (state.focused)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: radius,
                      border: Border.all(color: palette.primary, width: 2),
                    ),
                  ),
                ),
              ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: padding),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  if (leading case final leading?) ...[
                    leading,
                    const SizedBox(width: 8),
                  ],
                  if (icon case final icon?) ...[
                    Icon(icon, size: iconSize, color: foreground),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: labelStyle,
                    ),
                  ),
                  if (trailing case final trailing?) ...[
                    const SizedBox(width: 8),
                    trailing,
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
