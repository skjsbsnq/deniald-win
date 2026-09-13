import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/motion.dart';
import '../../theme/shell_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/shell_expressive_surface.dart';
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
    with SingleTickerProviderStateMixin {
  late final AnimationController _indicatorWidthController;
  late final MenuController _menuController;
  bool _menuOpen = false;

  // Indicator geometry (02-VISUAL-SPEC §4): a running app gets a Ø4 dot, the
  // active app a stretched 16x4 capsule, and multiple windows a pair of dots
  // whose gap is the spacing `xs` tier. Pinned-but-closed apps show nothing.
  static const double _dotDiameter = ShellSpacing.xs;
  static const double _activePillWidth = ShellSpacing.lg;
  static const double _multiDotWidth =
      _dotDiameter * 2 + ShellSpacing.xs;

  double _targetIndicatorWidth() {
    if (widget.windowCount > 1) {
      return _multiDotWidth;
    }
    if (widget.isActive) {
      return _activePillWidth;
    }
    if (widget.windowCount > 0) {
      return _dotDiameter;
    }
    return 0.0;
  }

  @override
  void initState() {
    super.initState();
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
      if (MediaQuery.disableAnimationsOf(context)) {
        _indicatorWidthController.value = target;
        return;
      }
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
    _indicatorWidthController.dispose();
    super.dispose();
  }

  void _handleMenuOpen() {
    // Menu children are only built while open, so opening has to rebuild this
    // button before the anchor renders its overlay panel.
    setState(() => _menuOpen = true);
  }

  void _handleMenuClose() {
    if (!mounted) return;
    setState(() => _menuOpen = false);
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

  Widget _buildIndicator(BuildContext context) {
    final theme = context.shellTheme;
    final dotColor = widget.isActive
        ? theme.accentPalette.primary
        : theme.accentPalette.subtle;
    final dotDecoration = BoxDecoration(
      color: dotColor,
      borderRadius: theme.borderRadius(ShellShapeScale.full),
    );
    return AnimatedBuilder(
      animation: _indicatorWidthController,
      builder: (context, _) {
        final currentWidth = math.max(
          0.0,
          _indicatorWidthController.value,
        );
        return SizedBox(
          key: const ValueKey('shelf-app-indicator'),
          width: currentWidth,
          height: _dotDiameter,
          child: widget.windowCount > 1
              // Two anchored dots slide apart as the spring widens the lane;
              // a Stack keeps them legal even mid-flight below their natural
              // separation.
              ? Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: _dotDiameter,
                      child: DecoratedBox(decoration: dotDecoration),
                    ),
                    Positioned(
                      right: 0,
                      top: 0,
                      bottom: 0,
                      width: _dotDiameter,
                      child: DecoratedBox(decoration: dotDecoration),
                    ),
                  ],
                )
              : DecoratedBox(decoration: dotDecoration),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.shellColors;
    final tooltipMessage = widget.title ?? widget.appId;

    final buttonContent = GestureDetector(
      onSecondaryTapDown: _handleSecondaryTapDown,
      child: ShellExpressiveSurface(
        onPressed: widget.onPressed,
        shape: ShellShapeScale.full,
        // The circle morphs toward a squarer token while pressed, the M3E
        // press shape-morph already used by SettingsButton.
        pressedShape: ShellShapeScale.small,
        width: 40,
        height: 40,
        semanticLabel: tooltipMessage,
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
    );

    return MenuAnchor(
      controller: _menuController,
      consumeOutsideTap: false,
      useRootOverlay: false,
      clipBehavior: Clip.antiAlias,
      style: shellMenuStyle(context),
      onOpen: _handleMenuOpen,
      onClose: _handleMenuClose,
      // The full menu is only constructed while open, so the frequent strip
      // rebuilds never pay for menus that may never be shown.
      menuChildren: _menuOpen && widget.menuBuilder != null
          ? widget.menuBuilder!(context)
          : const <Widget>[],
      child: Tooltip(
        message: tooltipMessage,
        textStyle: ShellText.shelfTooltip,
        waitDuration: const Duration(milliseconds: 500),
        // The 40px circle centers on the 48px track while the Ø4 indicator
        // hugs the track's bottom edge, so the icon sits optically centered
        // instead of riding high above the dot.
        child: SizedBox(
          height: 48,
          child: Stack(
            children: [
              Center(child: buttonContent),
              Positioned(
                left: 0,
                right: 0,
                bottom: 1,
                child: Center(child: _buildIndicator(context)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
