import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/motion.dart';
import '../../theme/shell_theme.dart';

/// Container edge of the M3E loading indicator (`02-VISUAL-SPEC.md` §3.10).
const double settingsLoadingIndicatorSize = 48;

/// Long axis of the morphing active shape (§3.10 `ActiveSize`).
const double settingsLoadingIndicatorActiveSize = 38;

const double _shortAxisSize = 24;
const double _staticRingStroke = 4;

/// M3E morphing loading indicator (`02-VISUAL-SPEC.md` §3.10).
///
/// A 48×48 container whose active shape continuously deforms between a circle
/// and a rotated pill with a 38dp long axis. The morph is painted by a single
/// [CustomPainter] driven by one [AnimationController]; no third-party package
/// is involved. When the platform asks for reduced motion the shape settles
/// into a static ring.
class SettingsLoadingIndicator extends StatefulWidget {
  const SettingsLoadingIndicator({this.semanticsLabel, super.key});

  /// Accessible label announced for the indicator.
  final String? semanticsLabel;

  @override
  State<SettingsLoadingIndicator> createState() =>
      _SettingsLoadingIndicatorState();
}

class _SettingsLoadingIndicatorState extends State<SettingsLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  var _animationsDisabled = false;

  @override
  void initState() {
    super.initState();
    // A continuous morph cycle reuses a shell Motion token rather than a
    // literal so the shell keeps one motion vocabulary (constraint §D4).
    _controller = AnimationController(
      vsync: this,
      duration: Motion.wallpaperReveal,
    )..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final disabled = MediaQuery.disableAnimationsOf(context);
    if (disabled == _animationsDisabled) {
      return;
    }
    _animationsDisabled = disabled;
    if (disabled) {
      _controller.stop();
    } else {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShellTheme.of(context);
    return Semantics(
      label: widget.semanticsLabel,
      child: SizedBox.square(
        dimension: settingsLoadingIndicatorSize,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return CustomPaint(
              size: const Size.square(settingsLoadingIndicatorSize),
              painter: _SettingsLoadingIndicatorPainter(
                progress: _controller.value,
                color: theme.accentPalette.primary,
                cornerRadiusScale: theme.cornerRadiusScale,
                static: _animationsDisabled,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SettingsLoadingIndicatorPainter extends CustomPainter {
  const _SettingsLoadingIndicatorPainter({
    required this.progress,
    required this.color,
    required this.cornerRadiusScale,
    required this.static,
  });

  final double progress;
  final Color color;
  final double cornerRadiusScale;
  final bool static;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    if (static) {
      canvas.drawCircle(
        center,
        settingsLoadingIndicatorActiveSize / 2,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = _staticRingStroke,
      );
      return;
    }
    // Two opposing half-cosines make the long and short axes trade places once
    // per cycle. The long axis stays pinned at the spec's 38dp.
    final cycle = 2 * math.pi * progress;
    final longPhase = 0.5 - 0.5 * math.cos(cycle);
    final shortPhase = 0.5 - 0.5 * math.cos(cycle + math.pi);
    final width =
        settingsLoadingIndicatorActiveSize -
        (settingsLoadingIndicatorActiveSize - _shortAxisSize) * longPhase;
    final height =
        settingsLoadingIndicatorActiveSize -
        (settingsLoadingIndicatorActiveSize - _shortAxisSize) * shortPhase;
    final maximumRadius = math.min(width, height) / 2;
    final radius = (maximumRadius * cornerRadiusScale).clamp(
      0.0,
      maximumRadius,
    );
    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: width,
      height: height,
    );
    canvas
      ..save()
      ..translate(center.dx, center.dy)
      ..rotate(cycle / 2)
      ..drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(radius)),
        Paint()..color = color,
      )
      ..restore();
  }

  @override
  bool shouldRepaint(covariant _SettingsLoadingIndicatorPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.cornerRadiusScale != cornerRadiusScale ||
        oldDelegate.static != static;
  }
}
