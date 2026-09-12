import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/display_layout.dart';
import '../state/display_layout.dart';
import '../theme/motion.dart';
import '../theme/shell_theme.dart';
import '../theme/tokens.dart';
import '../wallpaper/state/wallpaper_controller.dart';
import '../wallpaper/wallpaper.dart';
import '../wallpaper/widgets/wallpaper_image.dart';

export '../wallpaper/widgets/wallpaper_image.dart'
    show blurredWallpaperImageProvider;

/// Rewrites the provider a wallpaper image resolves through, letting a
/// surface substitute a filtered variant of the decoded frame. The lock
/// screen uses this to paint pre-blurred frames instead of convolving the
/// live scene on its first frame.
typedef WallpaperImageTransformer =
    ImageProvider<Object> Function(
      ImageProvider<Object> imageProvider, {
      required Size targetPixelSize,
      required Size targetLogicalSize,
    });

class ShellWallpaper extends ConsumerWidget {
  const ShellWallpaper({super.key, this.imageTransformer});

  final WallpaperImageTransformer? imageTransformer;

  static const String assetPath = defaultShellWallpaperAsset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallpaper = ref.watch(
      wallpaperControllerProvider.select(
        (state) => (
          assignment: state.assignment,
          outgoingAssignment: state.outgoingAssignment,
          transitionTarget: state.transitionTarget,
          revealOriginFraction: state.revealOriginFraction,
          transitionId: state.transitionId,
        ),
      ),
    );
    final displayLayout = ref.watch(displayLayoutProvider);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final canvas = Offset.zero & constraints.biggest;
        final outputs = _visibleOutputs(displayLayout, canvas);
        final spanRect = _spanRect(outputs, canvas);
        final spanPixelSize =
            displayLayout?.pixelSize ??
            spanRect.size * MediaQuery.devicePixelRatioOf(context);
        final transitionRect = _transitionRect(
          wallpaper.transitionTarget,
          outputs,
          spanRect,
        );
        // spanPixelSize describes the whole layout, not the surface the
        // span fallback paints on; keep its device-per-logical ratio at the
        // engine scale so an offscreen layout cannot inflate it.
        final spanPixelScale =
            displayLayout?.engineScale ??
            MediaQuery.devicePixelRatioOf(context);
        final transitionBounds = transitionRect.intersect(canvas);
        final outgoing = wallpaper.outgoingAssignment;
        final animateOutgoing =
            outgoing != null && !reduceMotion && !transitionRect.isEmpty;
        if (outgoing != null && !animateOutgoing) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _completeTransition(ref, wallpaper.transitionId);
          });
        }

        return RepaintBoundary(
          child: ColoredBox(
            color: context.shellColors.launchSurface,
            child: Stack(
              fit: StackFit.expand,
              children: [
                WallpaperScene(
                  assignment: wallpaper.assignment,
                  outputs: outputs,
                  spanRect: spanRect,
                  spanPixelSize: spanPixelSize,
                  spanPixelScale: spanPixelScale,
                  imageTransformer: imageTransformer,
                ),
                // The reveal path is strictly bounded by the output being
                // changed, so the transition subtree only spans that rect:
                // the anti-aliased clip never covers the rest of the canvas.
                if (animateOutgoing)
                  Positioned.fromRect(
                    rect: transitionBounds,
                    child: TweenAnimationBuilder<double>(
                      key: ValueKey<int>(wallpaper.transitionId),
                      tween: Tween<double>(begin: 0.0, end: 1.0),
                      duration: Motion.wallpaperReveal,
                      curve: Motion.md3Emphasized,
                      onEnd: () =>
                          _completeTransition(ref, wallpaper.transitionId),
                      builder: (context, progress, child) {
                        return ClipPath(
                          clipper: _ExpandingWallpaperHoleClipper(
                            targetRect: Offset.zero & transitionBounds.size,
                            originFraction: wallpaper.revealOriginFraction,
                            progress: progress,
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: child,
                        );
                      },
                      // The outgoing scene is static while the clip ticks;
                      // keeping it behind its own repaint boundary stops the
                      // per-frame reclip from re-recording every image.
                      child: RepaintBoundary(
                        child: Transform.translate(
                          offset: -transitionBounds.topLeft,
                          child: OverflowBox(
                            minWidth: canvas.width,
                            maxWidth: canvas.width,
                            minHeight: canvas.height,
                            maxHeight: canvas.height,
                            alignment: Alignment.topLeft,
                            child: WallpaperScene(
                              assignment: outgoing,
                              outputs: outputs,
                              spanRect: spanRect,
                              spanPixelSize: spanPixelSize,
                              spanPixelScale: spanPixelScale,
                              imageTransformer: imageTransformer,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<DisplayOutput> _visibleOutputs(DisplayLayout? layout, Rect canvas) {
    if (layout == null || canvas.isEmpty) {
      return const <DisplayOutput>[];
    }
    return layout.outputs
        .where((output) => !output.logicalRect.intersect(canvas).isEmpty)
        .toList(growable: false);
  }

  Rect _spanRect(List<DisplayOutput> outputs, Rect canvas) {
    if (outputs.isEmpty) {
      return canvas;
    }
    var result = outputs.first.logicalRect.intersect(canvas);
    for (final output in outputs.skip(1)) {
      result = result.expandToInclude(output.logicalRect.intersect(canvas));
    }
    return result;
  }

  Rect _transitionRect(
    WallpaperTarget target,
    List<DisplayOutput> outputs,
    Rect spanRect,
  ) {
    final outputName = target.outputName;
    if (outputName == null) {
      return spanRect;
    }
    for (final output in outputs) {
      if (output.name == outputName) {
        return output.logicalRect;
      }
    }
    return Rect.zero;
  }

  void _completeTransition(WidgetRef ref, int transitionId) {
    ref
        .read(wallpaperControllerProvider.notifier)
        .completeTransition(transitionId);
  }
}

/// Paints one output's wallpaper in output-local coordinates.
///
/// Filtering the complete irregular desktop atlas lets a blur kernel sample
/// the empty space around rotated or offset monitors. A local, fully opaque
/// wallpaper gives security surfaces a real edge for every output instead.
class ShellOutputWallpaper extends ConsumerWidget {
  const ShellOutputWallpaper({
    required this.output,
    this.imageTransformer,
    super.key,
  });

  final DisplayOutput output;
  final WallpaperImageTransformer? imageTransformer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assignment = ref.watch(
      wallpaperControllerProvider.select((state) => state.assignment),
    );
    final darkness = assignment.darknessForOutput(output.name);
    return RepaintBoundary(
      child: ColoredBox(
        color: context.shellColors.launchSurface,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _WallpaperImage(
              key: ValueKey<String>('wallpaper-image-output-${output.name}'),
              resource: assignment.forOutput(output.name),
              targetPixelSize: output.pixelSize,
              targetLogicalSize: output.logicalRect.size,
              alignment: Alignment(
                assignment.alignmentForOutput(output.name).x,
                assignment.alignmentForOutput(output.name).y,
              ),
              imageTransformer: imageTransformer,
            ),
            if (darkness > 0)
              _WallpaperDarknessLayer(
                key: ValueKey<String>('wallpaper-darkness-${output.name}'),
                darkness: darkness,
              ),
          ],
        ),
      ),
    );
  }
}

class WallpaperScene extends StatelessWidget {
  const WallpaperScene({
    super.key,
    required this.assignment,
    required this.outputs,
    required this.spanRect,
    required this.spanPixelSize,
    required this.spanPixelScale,
    this.imageTransformer,
  });

  final WallpaperAssignment assignment;
  final List<DisplayOutput> outputs;
  final Rect spanRect;
  final Size spanPixelSize;

  /// Device pixels per logical pixel of the surface the span fallback is
  /// painted on. Unlike the per-output paths, [spanPixelSize] can describe a
  /// layout wider than this surface, so the ratio cannot be derived from
  /// [spanRect].
  final double spanPixelScale;

  final WallpaperImageTransformer? imageTransformer;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (outputs.isEmpty)
          Positioned.fromRect(
            rect: spanRect,
            child: _WallpaperImage(
              key: const ValueKey<String>('wallpaper-image-fallback'),
              resource: assignment.all,
              targetPixelSize: spanPixelSize,
              targetLogicalSize: spanPixelSize / spanPixelScale,
              alignment: Alignment(
                assignment.spanAlignment.x,
                assignment.spanAlignment.y,
              ),
              imageTransformer: imageTransformer,
            ),
          ),
        for (final output in outputs)
          Positioned.fromRect(
            rect: output.logicalRect,
            child: _WallpaperImage(
              key: ValueKey<String>('wallpaper-image-output-${output.name}'),
              resource: assignment.forOutput(output.name),
              targetPixelSize: output.pixelSize,
              targetLogicalSize: output.logicalRect.size,
              alignment: Alignment(
                assignment.alignmentForOutput(output.name).x,
                assignment.alignmentForOutput(output.name).y,
              ),
              imageTransformer: imageTransformer,
            ),
          ),
        if (outputs.isEmpty && assignment.allDarkness > 0.0)
          Positioned.fromRect(
            rect: spanRect,
            child: _WallpaperDarknessLayer(
              key: const ValueKey<String>('wallpaper-darkness-all'),
              darkness: assignment.allDarkness,
            ),
          ),
        for (final output in outputs)
          if (assignment.darknessForOutput(output.name) > 0.0)
            Positioned.fromRect(
              rect: output.logicalRect,
              child: _WallpaperDarknessLayer(
                key: ValueKey<String>('wallpaper-darkness-${output.name}'),
                darkness: assignment.darknessForOutput(output.name),
              ),
            ),
      ],
    );
  }
}

class _WallpaperDarknessLayer extends StatelessWidget {
  const _WallpaperDarknessLayer({super.key, required this.darkness});

  final double darkness;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ColoredBox(
        color: ShellMediaColors.darkness.withValues(alpha: darkness),
      ),
    );
  }
}

class _WallpaperImage extends StatelessWidget {
  const _WallpaperImage({
    super.key,
    required this.resource,
    required this.targetPixelSize,
    required this.targetLogicalSize,
    this.alignment = Alignment.center,
    this.imageTransformer,
  });

  final WallpaperResource resource;
  final Size targetPixelSize;
  final Size targetLogicalSize;
  final Alignment alignment;
  final WallpaperImageTransformer? imageTransformer;

  @override
  Widget build(BuildContext context) {
    ImageProvider<Object> providerFor(WallpaperResource wallpaper) {
      final base = wallpaperImageProvider(
        wallpaper,
        targetPixelSize: targetPixelSize,
      );
      final transformer = imageTransformer;
      return transformer == null
          ? base
          : transformer(
              base,
              targetPixelSize: targetPixelSize,
              targetLogicalSize: targetLogicalSize,
            );
    }

    return Image(
      image: providerFor(resource),
      fit: BoxFit.cover,
      alignment: alignment,
      filterQuality: FilterQuality.low,
      gaplessPlayback: true,
      excludeFromSemantics: true,
      errorBuilder: (context, error, stackTrace) => Image(
        image: providerFor(WallpaperResource.defaultWallpaper),
        fit: BoxFit.cover,
        alignment: alignment,
        filterQuality: FilterQuality.low,
        excludeFromSemantics: true,
      ),
    );
  }
}

class _ExpandingWallpaperHoleClipper extends CustomClipper<Path> {
  const _ExpandingWallpaperHoleClipper({
    required this.targetRect,
    required this.originFraction,
    required this.progress,
  });

  final Rect targetRect;
  final Offset originFraction;
  final double progress;

  @override
  Path getClip(Size size) {
    return wallpaperRevealClipPath(
      size: size,
      targetRect: targetRect,
      originFraction: originFraction,
      progress: progress,
    );
  }

  @override
  bool shouldReclip(covariant _ExpandingWallpaperHoleClipper oldClipper) {
    return oldClipper.targetRect != targetRect ||
        oldClipper.originFraction != originFraction ||
        oldClipper.progress != progress;
  }
}

/// The outgoing wallpaper outside the growing reveal circle, strictly clipped
/// to the output being changed.
Path wallpaperRevealClipPath({
  required Size size,
  required Rect targetRect,
  required Offset originFraction,
  required double progress,
}) {
  final bounds = targetRect.intersect(Offset.zero & size);
  if (bounds.isEmpty) {
    return Path();
  }
  final safeOrigin = Offset(
    bounds.left + (originFraction.dx.clamp(0.0, 1.0) * bounds.width).toDouble(),
    bounds.top + (originFraction.dy.clamp(0.0, 1.0) * bounds.height).toDouble(),
  );
  final farthestX = math.max(
    safeOrigin.dx - bounds.left,
    bounds.right - safeOrigin.dx,
  );
  final farthestY = math.max(
    safeOrigin.dy - bounds.top,
    bounds.bottom - safeOrigin.dy,
  );
  final radius =
      math.sqrt(farthestX * farthestX + farthestY * farthestY) *
      progress.clamp(0.0, 1.0);
  return Path.combine(
    PathOperation.difference,
    Path()..addRect(bounds),
    Path()..addOval(Rect.fromCircle(center: safeOrigin, radius: radius)),
  );
}
