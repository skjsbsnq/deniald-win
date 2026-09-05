import 'package:flutter/material.dart';

import '../../theme/motion.dart';
import '../../theme/shell_theme.dart';
import '../../theme/tokens.dart';

/// The launcher entry button on the left edge of the shelf.
class ShelfLauncherButton extends StatefulWidget {
  const ShelfLauncherButton({this.onPressed, super.key});

  final VoidCallback? onPressed;

  @override
  State<ShelfLauncherButton> createState() => _ShelfLauncherButtonState();
}

class _ShelfLauncherButtonState extends State<ShelfLauncherButton>
    with TickerProviderStateMixin {
  late final AnimationController _hoverController;
  late final AnimationController _pressController;
  bool _hovered = false;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _hoverController = AnimationController.unbounded(vsync: this, value: 0.0);
    _pressController = AnimationController.unbounded(vsync: this, value: 0.0);
  }

  @override
  void dispose() {
    _hoverController.dispose();
    _pressController.dispose();
    super.dispose();
  }

  void _updateHover(bool hovered) {
    if (_hovered == hovered) return;
    setState(() => _hovered = hovered);
    springTo(
      _hoverController,
      hovered ? 1.0 : 0.0,
      spring: Motion.expressiveSpatialFast,
      telemetryLabel: 'shelf_launcher_hover',
    );
  }

  void _updatePress(bool pressed) {
    if (_pressed == pressed) return;
    setState(() => _pressed = pressed);
    springTo(
      _pressController,
      pressed ? 1.0 : 0.0,
      spring: Motion.expressiveSpatialFast,
      telemetryLabel: 'shelf_launcher_press',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = context.shellColors;
    final borderRadius = theme.borderRadius(ShellShapeScale.full);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _updateHover(true),
      onExit: (_) => _updateHover(false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _updatePress(true),
        onTapUp: (_) => _updatePress(false),
        onTapCancel: () => _updatePress(false),
        onTap: widget.onPressed,
        child: SizedBox(
          width: 40,
          height: 40,
          child: AnimatedBuilder(
            animation: Listenable.merge([_hoverController, _pressController]),
            builder: (context, child) {
              final hoverT = _hoverController.value.clamp(0.0, 1.0);
              final pressT = _pressController.value.clamp(0.0, 1.0);
              final hoverColor = Color.lerp(
                Colors.transparent,
                colors.panelHighlight,
                hoverT,
              );
              final backgroundColor = Color.lerp(
                hoverColor,
                theme.accentPalette.subtle,
                pressT,
              );
              final scale = 1.0 - 0.08 * _pressController.value;

              return Transform.scale(
                scale: scale,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: backgroundColor,
                    borderRadius: borderRadius,
                  ),
                  child: child,
                ),
              );
            },
            child: Icon(
              Icons.apps_rounded,
              size: 28,
              color: colors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
