import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/motion.dart';
import '../../theme/shell_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/shell_menu.dart';

/// An individual application button with running indicator on the shelf.
class ShelfAppButton extends StatefulWidget {
  const ShelfAppButton({
    required this.appId,
    this.iconPath,
    this.icon,
    this.title,
    this.windowCount = 1,
    this.isActive = false,
    this.isPinned = false,
    this.onPressed,
    this.onSecondaryTapDown,
    this.menuBuilder,
    super.key,
  });

  final String appId;
  final String? iconPath;
  final IconData? icon;
  final String? title;
  final int windowCount;
  final bool isActive;
  final bool isPinned;
  final VoidCallback? onPressed;
  final void Function(TapDownDetails details)? onSecondaryTapDown;
  final List<Widget> Function(BuildContext context)? menuBuilder;

  @override
  State<ShelfAppButton> createState() => _ShelfAppButtonState();
}

class _ShelfAppButtonState extends State<ShelfAppButton>
    with TickerProviderStateMixin {
  late final AnimationController _hoverController;
  late final AnimationController _pressController;
  late final AnimationController _indicatorWidthController;
  late final MenuController _menuController;
  bool _hovered = false;
  bool _pressed = false;

  double _targetIndicatorWidth() {
    if (widget.windowCount > 1) {
      return 14.0;
    }
    if (widget.isActive) {
      return 12.0;
    }
    if (widget.windowCount > 0) {
      return 6.0;
    }
    if (widget.isPinned) {
      return 4.0;
    }
    return 0.0;
  }

  @override
  void initState() {
    super.initState();
    _hoverController = AnimationController.unbounded(vsync: this, value: 0.0);
    _pressController = AnimationController.unbounded(vsync: this, value: 0.0);
    _indicatorWidthController = AnimationController.unbounded(
      vsync: this,
      value: _targetIndicatorWidth(),
    );
    _menuController = MenuController();
  }

  @override
  void didUpdateWidget(covariant ShelfAppButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    final target = _targetIndicatorWidth();
    if (oldWidget.windowCount != widget.windowCount ||
        oldWidget.isActive != widget.isActive ||
        oldWidget.isPinned != widget.isPinned) {
      springTo(
        _indicatorWidthController,
        target,
        spring: Motion.expressiveSpatialFast,
        telemetryLabel: 'shelf_indicator_width',
      );
    }
  }

  @override
  void dispose() {
    _hoverController.dispose();
    _pressController.dispose();
    _indicatorWidthController.dispose();
    super.dispose();
  }

  void _updateHover(bool hovered) {
    if (_hovered == hovered) return;
    setState(() => _hovered = hovered);
    springTo(
      _hoverController,
      hovered ? 1.0 : 0.0,
      spring: Motion.expressiveSpatialFast,
      telemetryLabel: 'shelf_app_hover',
    );
  }

  void _updatePress(bool pressed) {
    if (_pressed == pressed) return;
    setState(() => _pressed = pressed);
    springTo(
      _pressController,
      pressed ? 1.0 : 0.0,
      spring: Motion.expressiveSpatialFast,
      telemetryLabel: 'shelf_app_press',
    );
  }

  void _handleSecondaryTapDown(TapDownDetails details) {
    widget.onSecondaryTapDown?.call(details);
    if (widget.menuBuilder != null) {
      if (_menuController.isOpen) {
        _menuController.close();
      } else {
        _menuController.open(position: details.localPosition);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = context.shellColors;
    final borderRadius = theme.borderRadius(ShellShapeScale.medium);

    final buttonContent = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _updateHover(true),
      onExit: (_) => _updateHover(false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _updatePress(true),
        onTapUp: (_) => _updatePress(false),
        onTapCancel: () => _updatePress(false),
        onTap: widget.onPressed,
        onSecondaryTapDown: _handleSecondaryTapDown,
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
            child: Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: widget.icon != null
                    ? Icon(widget.icon, size: 28, color: colors.textPrimary)
                    : AppIconImage(iconPath: widget.iconPath),
              ),
            ),
          ),
        ),
      ),
    );

    final tooltipMessage = widget.title ?? widget.appId;
    final indicatorColor = widget.isActive
        ? theme.accent
        : widget.windowCount > 0
        ? theme.accent.withValues(alpha: 0.5)
        : theme.accent.withValues(alpha: 0.35);

    return MenuAnchor(
      controller: _menuController,
      consumeOutsideTap: false,
      useRootOverlay: false,
      clipBehavior: Clip.antiAlias,
      style: shellMenuStyle(context),
      menuChildren: widget.menuBuilder != null
          ? widget.menuBuilder!(context)
          : const <Widget>[],
      child: Tooltip(
        message: tooltipMessage,
        textStyle: ShellText.shelfTooltip,
        waitDuration: const Duration(milliseconds: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 5),
            buttonContent,
            const SizedBox(height: 3),
            AnimatedBuilder(
              animation: _indicatorWidthController,
              builder: (context, _) {
                final currentWidth = math.max(
                  0.0,
                  _indicatorWidthController.value,
                );

                return Container(
                  width: currentWidth,
                  height: 2,
                  decoration: BoxDecoration(
                    color: indicatorColor,
                    borderRadius: theme.borderRadius(ShellShapeScale.full),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
