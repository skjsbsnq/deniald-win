import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Shared activity scope of the Weather page.
///
/// The dashboard keeps every visited tab mounted inside an `IndexedStack`,
/// so "mounted" does not mean "visible": a parked Weather page keeps its
/// element alive while another tab is on top. [WeatherBackground] publishes
/// the real page-activity flag into [active] (its ambient ticker probes the
/// ancestor stack every frame on live scenes, a 4 Hz probe does it while a
/// scene-less page keeps the ticker stopped); decorative
/// consumers — meteocons Lottie playback, reveal entrances, rolling values —
/// subscribe through this scope and idle while the page is covered.
///
/// [motionScale] mirrors `ShellAnimationSettings.durationScale` so ambient
/// and entrance motion follow the user's motion preference, and
/// [animationsEnabled] mirrors `MediaQuery.disableAnimationsOf` so every
/// consumer collapses to its static form under reduce-motion.
class WeatherPageActivity extends InheritedWidget {
  const WeatherPageActivity({
    super.key,
    required this.active,
    required this.durationScale,
    required this.animationsEnabled,
    required super.child,
  });

  /// Published by the page's ambient driver (`WeatherBackground`); true while
  /// the Weather page is the visible tab of an open panel.
  final ValueListenable<bool> active;

  /// `settings.animations.durationScale`; multiplies entrance/rolling
  /// durations and inversely scales ambient simulation speed.
  final double durationScale;

  /// `!MediaQuery.disableAnimationsOf(context)` at the page root.
  final bool animationsEnabled;

  static WeatherPageActivity? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<WeatherPageActivity>();
  }

  /// Snapshot read without registering a dependency — safe inside ticker and
  /// paint callbacks where `dependOnInheritedWidgetOfExactType` is illegal.
  static WeatherPageActivity? readOf(BuildContext context) {
    return context
            .getElementForInheritedWidgetOfExactType<WeatherPageActivity>()
            ?.widget
        as WeatherPageActivity?;
  }

  static double durationScaleOf(BuildContext context) {
    return maybeOf(context)?.durationScale ?? 1.0;
  }

  @override
  bool updateShouldNotify(WeatherPageActivity oldWidget) {
    return active != oldWidget.active ||
        durationScale != oldWidget.durationScale ||
        animationsEnabled != oldWidget.animationsEnabled;
  }
}

/// Whether [context]'s subtree is the currently painted child of the nearest
/// ancestor [IndexedStack]. The dashboard pages are kept alive but unpainted
/// when their tab is not selected; ambient animation must observe this.
///
/// Returns true when no `IndexedStack` ancestor exists (other hosts, tests).
bool dashboardPageSelected(BuildContext context) {
  final stack = context.findAncestorRenderObjectOfType<RenderIndexedStack>();
  if (stack == null) {
    return true;
  }
  RenderObject? node = context.findRenderObject();
  RenderObject? directChild;
  while (node != null) {
    final parent = node.parent;
    if (identical(parent, stack)) {
      directChild = node;
      break;
    }
    node = parent is RenderObject ? parent : null;
  }
  if (directChild == null) {
    return true;
  }
  var index = 0;
  RenderBox? child = stack.firstChild;
  while (child != null) {
    if (identical(child, directChild)) {
      return index == stack.index;
    }
    index += 1;
    child = stack.childAfter(child);
  }
  return true;
}
