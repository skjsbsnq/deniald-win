import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/startup_environment.dart';
import '../input/input_layout.dart';
import '../input/input_layout_debug.dart';
import '../input/shell_interaction_registry.dart';
import '../theme/shell_color_scheme.dart';
import '../theme/shell_theme.dart';
import '../theme/tokens.dart';

/// Paints the compositor input-routing rectangles for debugging.
///
/// Enabled with `DENIA_DEBUG_INPUT_REGIONS=1`: shell regions claimed for
/// Flutter are outlined in green, client window hit regions in amber, and
/// registered child-bound shell surfaces are outlined in the accent with
/// their debug labels. Scene-wide surfaces (tray bubble, lock screen, ...)
/// are listed along the top edge. The overlay never intercepts input and
/// release builds compile it out through [kDebugMode].
class InputRegionDebugOverlay extends ConsumerWidget {
  const InputRegionDebugOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!kDebugMode) {
      return const SizedBox.shrink();
    }
    final enabled = ref
        .watch(startupEnvironmentProvider)
        .flag('DENIA_DEBUG_INPUT_REGIONS');
    if (!enabled) {
      return const SizedBox.shrink();
    }
    final snapshot = ref.watch(debugInputLayoutSnapshotProvider);
    if (snapshot == null) {
      return const SizedBox.shrink();
    }
    final theme = ShellTheme.of(context);
    final surfaces = ref.watch(
      shellInteractionRegistryProvider.select(
        (snapshot) => snapshot.orderedSurfaces,
      ),
    );
    return IgnorePointer(
      child: CustomPaint(
        foregroundPainter: _InputRegionDebugPainter(
          snapshot: snapshot,
          surfaces: surfaces,
          colors: theme.colors,
          accent: theme.accent,
          labelStyle: ShellText.base.copyWith(
            color: theme.colors.textPrimary,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _InputRegionDebugPainter extends CustomPainter {
  _InputRegionDebugPainter({
    required this.snapshot,
    required this.surfaces,
    required this.colors,
    required this.accent,
    required this.labelStyle,
  });

  final InputLayoutSnapshot snapshot;
  final Iterable<ShellInteractionSurface> surfaces;
  final ShellColorScheme colors;
  final Color accent;
  final TextStyle labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final shellFill = Paint()
      ..style = PaintingStyle.fill
      ..color = colors.performanceGood.withValues(alpha: 0.08);
    final shellStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = colors.performanceGood.withValues(alpha: 0.9);
    for (final region in snapshot.shellRegions) {
      canvas.drawRect(region, shellFill);
      canvas.drawRect(region, shellStroke);
    }

    final windowStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = colors.performanceWarning.withValues(alpha: 0.9);
    for (final window in snapshot.windows) {
      canvas.drawRect(window.rect, windowStroke);
      _paintLabel(canvas, 'window z${window.z}', window.rect.topLeft);
    }

    final surfaceStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = accent.withValues(alpha: 0.9);
    var fullSceneRow = 0;
    for (final surface in surfaces) {
      final bounds = surface.bounds;
      if (surface.pointerPolicy == ShellPointerPolicy.childBounds &&
          bounds != null) {
        canvas.drawRect(bounds, surfaceStroke);
        _paintLabel(canvas, surface.debugLabel, bounds.topLeft);
        continue;
      }
      if (surface.pointerPolicy == ShellPointerPolicy.fullScene) {
        _paintLabel(
          canvas,
          '${surface.debugLabel} (fullScene)',
          Offset(8.0, 8.0 + fullSceneRow * 14.0),
        );
        fullSceneRow += 1;
      }
    }
  }

  void _paintLabel(Canvas canvas, String text, Offset position) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: labelStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final background = Paint()
      ..style = PaintingStyle.fill
      ..color = colors.background.withValues(alpha: 0.75);
    canvas.drawRect(
      position & Size(painter.width + 6.0, painter.height + 2.0),
      background,
    );
    painter.paint(canvas, position + const Offset(3.0, 1.0));
    painter.dispose();
  }

  @override
  bool shouldRepaint(covariant _InputRegionDebugPainter oldDelegate) {
    return oldDelegate.snapshot != snapshot ||
        !identical(oldDelegate.surfaces, surfaces) ||
        oldDelegate.accent != accent ||
        oldDelegate.colors != colors ||
        oldDelegate.labelStyle != labelStyle;
  }
}
