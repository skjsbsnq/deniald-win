import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'weather_visibility.dart';

/// Staggered card entrance, the `WeatherRevealCard` equivalent: once the card
/// crosses the scroll viewport threshold it fades in while rising 120 → 0 and
/// scaling 1.025 → 1. Cards stagger 200 ms apart and the travel animation
/// shrinks by 50 ms per index, matching `WeatherRevealCard.qml`'s
/// `entryDelay`/`entryDuration` formulas.
class WeatherReveal extends StatefulWidget {
  const WeatherReveal({
    super.key,
    required this.child,
    this.staggerIndex = 0,
    this.entryTravel = 120,
  });

  final Widget child;
  final int staggerIndex;

  /// Pixels the card rises through on entry (clavis `entryTravel`, 120).
  final double entryTravel;

  @override
  State<WeatherReveal> createState() => _WeatherRevealState();
}

class _WeatherRevealState extends State<WeatherReveal>
    with SingleTickerProviderStateMixin {
  // Curves from CLAVIS/Common/Animations.qml: expressiveDefaultEffects for
  // opacity, expressiveDefaultSpatial for travel, standardDecel for scale.
  static const Curve _opacityCurve = Cubic(0.34, 0.8, 0.34, 1);
  static const Curve _offsetCurve = Cubic(0.38, 1.21, 0.22, 1);
  static const Curve _scaleCurve = Cubic(0, 0, 0, 1);

  late final AnimationController _controller = AnimationController(vsync: this);

  ScrollPosition? _scrollPosition;
  ValueListenable<bool>? _activity;
  bool _revealed = false;
  bool _settled = false;

  int get _entryDelay => math.max(0, widget.staggerIndex) * 200;

  int get _entryDuration =>
      math.max(250, 500 - math.max(0, widget.staggerIndex) * 50);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _syncGate();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Scrollable.position is the scroll listenable that tells each card when
    // it has crossed the reveal threshold — no controller plumbing needed.
    final scrollable = Scrollable.maybeOf(context);
    final position = scrollable?.position;
    if (!identical(position, _scrollPosition)) {
      _scrollPosition?.removeListener(_maybeReveal);
      _scrollPosition = position;
      _scrollPosition?.addListener(_maybeReveal);
    }
    final activity = WeatherPageActivity.maybeOf(context)?.active;
    if (!identical(activity, _activity)) {
      _activity?.removeListener(_syncGate);
      _activity = activity;
      _activity?.addListener(_syncGate);
    }
  }

  @override
  void dispose() {
    _scrollPosition?.removeListener(_maybeReveal);
    _activity?.removeListener(_syncGate);
    _controller.dispose();
    super.dispose();
  }

  /// Whether the card's reveal depth (the first `entryTravel` pixels, capped
  /// at its own height) has reached the viewport's bottom edge — the
  /// `thresholdCrossed` check of `WeatherRevealCard.qml`.
  bool get _thresholdCrossed {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return false;
    }
    final topLeft = renderObject.localToGlobal(Offset.zero);
    final viewport = context.findAncestorRenderObjectOfType<RenderViewport>();
    if (viewport == null) {
      // Outside a scroll viewport (tests, flat hosts) the card is always
      // "in view".
      return true;
    }
    final viewportTop = viewport.localToGlobal(Offset.zero).dy;
    final viewportBottom = viewportTop + viewport.size.height;
    final revealDepth = math.min(renderObject.size.height, widget.entryTravel);
    final inViewport =
        topLeft.dy + renderObject.size.height > viewportTop &&
        topLeft.dy < viewportBottom;
    return inViewport && topLeft.dy + revealDepth <= viewportBottom;
  }

  bool get _gateActive {
    final scope = WeatherPageActivity.readOf(context);
    final active = scope?.active.value ?? true;
    final enabled = scope?.animationsEnabled ?? true;
    return active && enabled;
  }

  void _syncGate() {
    if (!mounted) {
      return;
    }
    final scope = WeatherPageActivity.readOf(context);
    final enabled = scope?.animationsEnabled ?? true;
    final active = scope?.active.value ?? true;
    if (!enabled) {
      // Reduce-motion: the card simply exists; no ticker ever runs. Give the
      // controller the full entry span first so the interval curves below
      // evaluate to their settled end state (opacity 1, offset 0).
      final scale = scope?.durationScale ?? 1.0;
      _controller
        ..stop()
        ..duration = Duration(
          milliseconds: math.max(
            1,
            ((_entryDelay + _entryDuration) * scale).round(),
          ),
        )
        ..value = 1;
      _revealed = true;
      _settled = true;
      return;
    }
    if (!active) {
      // Covered by another tab: settle a started reveal, or hold the card in
      // its hidden pre-entry state so uncovering replays the entrance —
      // `settleReveal`/`cancelPendingReveal` in the reference.
      _controller.stop();
      _controller.value = _revealed ? 1 : 0;
      _settled = _revealed;
      return;
    }
    _maybeReveal();
  }

  void _maybeReveal() {
    if (!mounted ||
        _revealed ||
        _settled ||
        !_gateActive ||
        !_thresholdCrossed) {
      return;
    }
    _revealed = true;
    final scale = WeatherPageActivity.readOf(context)?.durationScale ?? 1.0;
    final delay = (_entryDelay * scale).round();
    final duration = math.max(1, (_entryDuration * scale).round());
    _controller
      ..stop()
      ..duration = Duration(milliseconds: delay + duration)
      ..forward(from: 0);
  }

  double _intervalValue(double beginMs, double endMs, Curve curve) {
    final total = _controller.duration?.inMilliseconds.toDouble() ?? 1;
    final t = (_controller.value * total).clamp(beginMs, endMs).toDouble();
    final progress = (t - beginMs) / math.max(1.0, endMs - beginMs);
    return curve.transform(progress);
  }

  @override
  Widget build(BuildContext context) {
    final scale = WeatherPageActivity.durationScaleOf(context);
    final delay = (_entryDelay * scale);
    final end = delay + math.max(1.0, _entryDuration * scale);
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final opacity = _intervalValue(delay, end, _opacityCurve);
        final offset =
            (1 - _intervalValue(delay, end, _offsetCurve)) * widget.entryTravel;
        final scaleValue =
            1.025 - _intervalValue(delay, end, _scaleCurve) * 0.025;
        return Opacity(
          opacity: opacity.clamp(0.0, 1.0).toDouble(),
          child: Transform.translate(
            offset: Offset(0, offset),
            child: Transform.scale(
              scale: scaleValue,
              alignment: Alignment.center,
              child: child,
            ),
          ),
        );
      },
    );
  }
}
