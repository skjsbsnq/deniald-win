import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'weather_visibility.dart';

/// Rolling-number animation for weather readouts, the `WeatherAnimatedValue`
/// equivalent: the first valid value counts up from 0 over 1000 ms, later
/// changes glide over 500 ms, both on the emphasized-decel curve
/// (`Cubic(0.05, 0.7, 0.1, 1)`, `CLAVIS/Common/Animations.qml` L16).
class WeatherAnimatedValue extends StatefulWidget {
  const WeatherAnimatedValue({
    super.key,
    required this.value,
    required this.builder,
    this.enabled = true,
    this.initialDuration = const Duration(milliseconds: 1000),
    this.updateDuration = const Duration(milliseconds: 500),
  });

  /// Target value; null means "no reading" and shows the builder's null
  /// branch instead of animating.
  final double? value;

  /// Builds the readout for the currently displayed value.
  final Widget Function(BuildContext context, double? value) builder;

  /// Master switch: reduce-motion and parked pages pass false so the value
  /// snaps to target without a ticker.
  final bool enabled;
  final Duration initialDuration;
  final Duration updateDuration;

  @override
  State<WeatherAnimatedValue> createState() => _WeatherAnimatedValueState();
}

class _WeatherAnimatedValueState extends State<WeatherAnimatedValue>
    with SingleTickerProviderStateMixin {
  static const Curve _curve = Cubic(0.05, 0.7, 0.1, 1);

  late final AnimationController _controller = AnimationController(vsync: this);
  late final CurvedAnimation _eased = CurvedAnimation(
    parent: _controller,
    curve: _curve,
  );

  double? _from;
  double? _to;
  bool _hasAnimated = false;
  bool _initialResolved = false;
  ValueListenable<bool>? _activity;

  @override
  void initState() {
    super.initState();
    _to = widget.value;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _syncValue();
      }
    });
  }

  @override
  void didUpdateWidget(covariant WeatherAnimatedValue oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value ||
        oldWidget.enabled != widget.enabled) {
      _syncValue();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The page-activity flag is a ValueListenable, not an inherited-field
    // change, so the resume-after-uncover path needs its own subscription —
    // mirroring `WeatherAnimatedValue.qml`'s `onActiveChanged: syncValue`.
    final next = WeatherPageActivity.maybeOf(context)?.active;
    if (!identical(next, _activity)) {
      _activity?.removeListener(_syncValue);
      _activity = next;
      _activity?.addListener(_syncValue);
    }
    _syncValue();
  }

  @override
  void dispose() {
    _activity?.removeListener(_syncValue);
    _eased.dispose();
    _controller.dispose();
    super.dispose();
  }

  bool get _active => WeatherPageActivity.readOf(context)?.active.value ?? true;

  void _syncValue() {
    final target = widget.value;
    if (target == null || !target.isFinite) {
      _controller.stop();
      setState(() {
        _from = null;
        _to = null;
        _hasAnimated = false;
        _initialResolved = false;
      });
      return;
    }

    final scope = WeatherPageActivity.readOf(context);
    final scale = scope?.durationScale ?? 1.0;
    final animationsEnabled =
        scope?.animationsEnabled ??
        !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    final active = _active && widget.enabled && animationsEnabled && scale > 0;

    // First bind: rolling from 0 is the 1000 ms entrance the reference runs —
    // but only when the page is actually playing; mounted-under-another-tab
    // or reduce-motion binds settle silently and stay settled (the value is
    // already the truth, re-rolling on uncover would be noise).
    if (!_initialResolved) {
      _initialResolved = true;
      if (active) {
        _from = 0;
        _to = target;
        _hasAnimated = true;
        _run(widget.initialDuration, scale);
      } else {
        _controller.stop();
        setState(() {
          _from = target;
          _to = target;
        });
      }
      return;
    }

    if (!active) {
      _controller.stop();
      setState(() {
        _from = target;
        _to = target;
      });
      return;
    }

    if (_to == target) {
      return;
    }

    final duration = _hasAnimated
        ? widget.updateDuration
        : widget.initialDuration;
    _from = _hasAnimated ? _displayedValue : 0;
    _to = target;
    _hasAnimated = true;
    _run(duration, scale);
  }

  void _run(Duration duration, double scale) {
    _controller
      ..stop()
      ..duration = Duration(
        microseconds: (duration.inMicroseconds * scale).round(),
      )
      ..forward(from: 0);
  }

  double? get _displayedValue {
    final from = _from;
    final to = _to;
    if (to == null) {
      return null;
    }
    if (from == null) {
      return to;
    }
    return from + (to - from) * _eased.value;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _eased,
      builder: (context, _) => widget.builder(context, _displayedValue),
    );
  }
}
