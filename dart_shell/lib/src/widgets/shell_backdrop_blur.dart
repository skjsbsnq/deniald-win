import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../theme/shell_theme.dart';

/// A tightly clipped, layout-aware blur for translucent compositor surfaces.
///
/// Every instance owns its backdrop unless [grouped] is true. Windows must
/// never be grouped because they can overlap; non-overlapping siblings such as
/// system-bar pills can opt into one shared engine blur through [BackdropGroup].
/// Ungrouped instances retain their own layer, so callers do not need to add a
/// [RepaintBoundary] of their own.
class ShellBackdropBlur extends StatelessWidget {
  const ShellBackdropBlur({
    required this.child,
    this.blur = true,
    this.grouped = false,
    this.borderRadius,
    // `src` replaces the destination outright, so any region where the engine
    // cannot reproduce the backdrop -- an unrestored partial-repaint rect, a
    // filter result the backend leaves transparent -- lands as an opaque black
    // rectangle. `srcOver` composites instead, so the same failure degrades to
    // "this patch is not blurred" rather than "this patch is black".
    this.blendMode = ui.BlendMode.srcOver,
    super.key,
  });

  final Widget child;
  final bool blur;
  final bool grouped;
  final BorderRadiusGeometry? borderRadius;
  final ui.BlendMode blendMode;

  @override
  Widget build(BuildContext context) {
    final theme = ShellTheme.of(context);
    final enabled =
        blur && theme.backdropBlurEnabled && theme.backdropBlurSigma > 0;
    final Widget filtered;
    if (enabled) {
      final filterConfig = ImageFilterConfig.blur(
        sigmaX: theme.backdropBlurSigma,
        sigmaY: theme.backdropBlurSigma,
        tileMode: ui.TileMode.clamp,
      );
      filtered = grouped
          ? BackdropFilter.grouped(
              filterConfig: filterConfig,
              blendMode: blendMode,
              child: child,
            )
          : BackdropFilter(
              filterConfig: filterConfig,
              blendMode: blendMode,
              child: child,
            );
    } else {
      filtered = child;
    }

    final radius = borderRadius;
    final Widget clipped;
    if (radius == null) {
      clipped = enabled
          ? ClipRect(clipBehavior: Clip.hardEdge, child: filtered)
          : filtered;
    } else if (radius == BorderRadius.zero) {
      clipped = ClipRect(clipBehavior: Clip.hardEdge, child: filtered);
    } else {
      clipped = ClipRRect(
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: filtered,
      );
    }

    // Retain the blurred panel in its own layer. Without one, anything that
    // dirties a small rect above the panel -- the software cursor moving, a
    // tooltip appearing -- drags the filter through a partial repaint that
    // cannot reproduce the backdrop. Grouped filters are excluded so they keep
    // sharing a single engine blur through their [BackdropGroup].
    if (!enabled || grouped) {
      return clipped;
    }
    return RepaintBoundary(child: clipped);
  }
}
