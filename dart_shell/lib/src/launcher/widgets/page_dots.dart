import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/motion.dart';
import '../../theme/shell_theme.dart';
import '../../theme/tokens.dart';

class PageDots extends StatelessWidget {
  const PageDots({super.key, required this.count, required this.active});

  final int count;
  final int active;

  @override
  Widget build(BuildContext context) {
    if (count <= 1) {
      return const SizedBox(height: 8);
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var index = 0; index < count; index += 1)
          _PageDot(key: ValueKey<int>(index), active: index == active),
      ],
    );
  }
}

class _PageDot extends StatefulWidget {
  const _PageDot({super.key, required this.active});

  final bool active;

  @override
  State<_PageDot> createState() => _PageDotState();
}

class _PageDotState extends State<_PageDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _widthController;

  @override
  void initState() {
    super.initState();
    _widthController = AnimationController.unbounded(
      vsync: this,
      value: widget.active ? 20.0 : 7.0,
    );
  }

  @override
  void didUpdateWidget(covariant _PageDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) {
      springTo(
        _widthController,
        widget.active ? 20.0 : 7.0,
        spring: Motion.expressiveSpatialFast,
        telemetryLabel: 'page_dot_width',
      );
    }
  }

  @override
  void dispose() {
    _widthController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final borderRadius = context.shellTheme.borderRadius(
      ShellShapeScale.extraSmall,
    );

    return AnimatedBuilder(
      animation: _widthController,
      builder: (context, child) {
        final currentWidth = math.max(0.0, _widthController.value);
        final t = ((currentWidth - 7.0) / 13.0).clamp(0.0, 1.0);
        final color = Color.lerp(
          ShellMediaColors.lightForeground.withValues(alpha: 0.33),
          ShellMediaColors.lightForeground.withValues(alpha: 0.87),
          t,
        );

        return Container(
          width: currentWidth,
          height: 7,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(color: color, borderRadius: borderRadius),
        );
      },
    );
  }
}
