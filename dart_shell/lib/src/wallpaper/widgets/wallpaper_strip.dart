import 'package:flutter/material.dart';

import '../../localization/denial_localizations.dart';
import '../../theme/motion.dart';
import '../../theme/shell_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/shell_cursor.dart';
import '../wallpaper.dart';
import 'wallpaper_image.dart';

class WallpaperStrip extends StatefulWidget {
  const WallpaperStrip({
    super.key,
    required this.candidate,
    required this.current,
    required this.downloading,
    required this.downloadProgress,
    required this.onTapUp,
  });

  final WallpaperCandidate candidate;
  final bool current;
  final bool downloading;
  final double downloadProgress;
  final ValueChanged<Offset> onTapUp;

  @override
  State<WallpaperStrip> createState() => _WallpaperStripState();
}

class _WallpaperStripState extends State<WallpaperStrip>
    with
        SingleTickerProviderStateMixin,
        AutomaticKeepAliveClientMixin<WallpaperStrip> {
  late final AnimationController _press;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // Unbounded: the expressive fast spring overshoots below 1.0.
    _press = AnimationController.unbounded(vsync: this, value: 1.0);
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  void _setPressed(bool pressed) {
    springTo(
      _press,
      pressed ? 0.94 : 1.0,
      spring: Motion.expressiveSpatialFast,
      telemetryLabel: 'wallpaper_strip_press',
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final accent = ShellTheme.of(context).accentPalette;
    final candidate = widget.candidate;
    final label = candidate.id == 'default'
        ? context.l10n.wallpaperDefault
        : candidate.width > 0 && candidate.height > 0
        ? context.l10n.wallpaperDimensions(candidate.width, candidate.height)
        : candidate.label;
    return LayoutBuilder(
      builder: (context, constraints) {
        final cacheHeight =
            (constraints.maxHeight * MediaQuery.devicePixelRatioOf(context))
                .ceil();
        final image = wallpaperCandidateImageProvider(
          widget.candidate,
          cacheHeight: cacheHeight,
        );
        final radius = context.shellTheme.borderRadius(ShellShapeScale.large);
        return Semantics(
          button: true,
          selected: widget.current,
          label: context.l10n.wallpaperApplyCandidate(label),
          child: MouseRegion(
            cursor: ShellMouseCursors.link,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (_) => _setPressed(true),
              onTapUp: (details) {
                _setPressed(false);
                widget.onTapUp(details.globalPosition);
              },
              onTapCancel: () => _setPressed(false),
              child: AnimatedBuilder(
                animation: _press,
                builder: (context, child) =>
                    Transform.scale(scale: _press.value, child: child),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    border: Border.all(
                      color: widget.current
                          ? accent.outline
                          : context.shellColors.hairlineSoft,
                      width: widget.current ? 2 : 1,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: radius,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (image != null)
                          Image(
                            image: image,
                            fit: BoxFit.cover,
                            filterQuality: FilterQuality.high,
                            gaplessPlayback: true,
                            excludeFromSemantics: true,
                            errorBuilder: (context, error, stackTrace) =>
                                ColoredBox(
                                  color:
                                      context.shellColors.surfaceContainerHigh,
                                  child: Icon(
                                    Icons.broken_image_rounded,
                                    color: context.shellColors.textTertiary,
                                  ),
                                ),
                          )
                        else
                          ColoredBox(
                            color: context.shellColors.surfaceContainerHigh,
                            child: Icon(
                              Icons.image_rounded,
                              color: context.shellColors.textTertiary,
                            ),
                          ),
                        if (widget.downloading)
                          ColoredBox(
                            color: context.shellColors.overviewScrim,
                            child: Center(
                              child: SizedBox.square(
                                dimension: 42,
                                child: CircularProgressIndicator(
                                  value: widget.downloadProgress > 0.0
                                      ? widget.downloadProgress
                                      : null,
                                  color: accent.primary,
                                  backgroundColor: context
                                      .shellColors
                                      .surfaceContainerHighest,
                                  strokeWidth: 4,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
