import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../localization/denial_localizations.dart';
import '../../services/media_player_service.dart';
import '../../theme/shell_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/notification_media.dart';
import '../../widgets/shell_expressive_surface.dart';

/// Shared playback card extracted from the shelf media popup: cover artwork,
/// title/artist, a read-only progress bar, and the three transport keys.
///
/// The shelf popup renders it at a fixed [width]/[height]; the tray bubble
/// embeds the [compact] variant (smaller artwork and padding, an inner-card
/// surface, intrinsic height) between the status chips and the quick
/// settings tiles.
class ShelfMediaCard extends StatelessWidget {
  const ShelfMediaCard({
    required this.playback,
    required this.now,
    required this.onPrevious,
    required this.onPlayPause,
    required this.onNext,
    this.width,
    this.height,
    this.compact = false,
    super.key,
  });

  /// Playback snapshot. [now] feeds the read-only wall-clock progress
  /// extrapolation done by [MprisPlaybackState.positionAt]; seeking is not
  /// supported by the player service.
  final MprisPlaybackState playback;
  final DateTime now;
  final VoidCallback onPrevious;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;

  /// Fixed card width. Null leaves sizing to the parent — the tray bubble
  /// stretches the card across its column.
  final double? width;

  /// Fixed card height. Null sizes the card to its content (compact mode).
  final double? height;

  /// Compact variant for embedding inside other surfaces: reduced artwork
  /// and padding, an inner-card fill, and no "now playing" eyebrow.
  final bool compact;

  static const double _artworkSize = 140;
  static const double _compactArtworkSize = 72;
  // Paused covers shrink like the clavis media card (scale 0.8, easeOutQuint).
  static const double _pausedArtworkScale = 0.8;
  static const Duration _artworkScaleDuration = Duration(milliseconds: 400);

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = context.shellColors;
    final l10n = context.l10n;
    final position = playback.positionAt(now);
    final length = playback.length;
    final progress = length > Duration.zero
        ? (position.inMilliseconds / length.inMilliseconds)
              .clamp(0.0, 1.0)
              .toDouble()
        : 0.0;
    final secondary = playback.artistLabel.isNotEmpty
        ? playback.artistLabel
        : playback.album.isNotEmpty
        ? playback.album
        : playback.identity;
    final intrinsicHeight = height == null;
    return Material(
      type: MaterialType.transparency,
      child: Container(
        width: width,
        height: height,
        padding: EdgeInsets.all(compact ? ShellSpacing.md : ShellSpacing.lg),
        decoration: BoxDecoration(
          color: theme.panelColor(
            compact ? colors.surfaceContainer : colors.surfaceContainerLow,
          ),
          borderRadius: theme.borderRadius(
            compact
                ? ShellShapeScale.largeIncreased
                : ShellShapeScale.extraLarge,
          ),
          border: compact
              ? Border.all(color: colors.hairlineSoft, width: 1.0)
              : null,
        ),
        child: Row(
          children: [
            AnimatedScale(
              scale: playback.playing ? 1.0 : _pausedArtworkScale,
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : _artworkScaleDuration,
              curve: Curves.easeOutQuint,
              child: _ShelfMediaCardArtwork(
                playback: playback,
                size: compact ? _compactArtworkSize : _artworkSize,
              ),
            ),
            SizedBox(width: compact ? ShellSpacing.md : ShellSpacing.lg),
            Expanded(
              child: Column(
                mainAxisSize: intrinsicHeight
                    ? MainAxisSize.min
                    : MainAxisSize.max,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!compact) ...[
                    Row(
                      children: [
                        Icon(
                          Icons.graphic_eq_rounded,
                          size: 14,
                          color: theme.accent,
                        ),
                        const SizedBox(width: ShellSpacing.xs),
                        Text(
                          l10n.mediaNowPlaying.toUpperCase(),
                          style: ShellText.systemBarCaption.copyWith(
                            color: theme.accent,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: ShellSpacing.xs),
                  ],
                  Text(
                    playback.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ShellText.titleMedium.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                  Text(
                    secondary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ShellText.labelSmall.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  if (intrinsicHeight)
                    const SizedBox(height: ShellSpacing.sm)
                  else
                    const Spacer(),
                  Semantics(
                    value:
                        '${_formatMediaTime(position)} / '
                        '${_formatMediaTime(length)}',
                    child: ClipRRect(
                      borderRadius: theme.borderRadius(ShellShapeScale.full),
                      child: LinearProgressIndicator(
                        minHeight: 4,
                        value: progress,
                        color: theme.accent,
                        backgroundColor: colors.surfaceContainerHighest,
                      ),
                    ),
                  ),
                  const SizedBox(height: ShellSpacing.xs),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _formatMediaTime(position),
                          style: ShellText.systemBarCaption.copyWith(
                            color: colors.textTertiary,
                          ),
                        ),
                      ),
                      Text(
                        _formatMediaTime(length),
                        style: ShellText.systemBarCaption.copyWith(
                          color: colors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: ShellSpacing.xs),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _ShelfMediaCardControlButton(
                        label: l10n.mediaPrevious,
                        icon: Icons.skip_previous_rounded,
                        enabled: playback.canGoPrevious,
                        onPressed: onPrevious,
                      ),
                      const SizedBox(width: ShellSpacing.sm),
                      _ShelfMediaCardControlButton(
                        label: playback.playing
                            ? l10n.mediaPause
                            : l10n.mediaPlay,
                        icon: playback.playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        prominent: true,
                        enabled: playback.playing
                            ? playback.canPause
                            : playback.canPlay,
                        onPressed: onPlayPause,
                      ),
                      const SizedBox(width: ShellSpacing.sm),
                      _ShelfMediaCardControlButton(
                        label: l10n.mediaNext,
                        icon: Icons.skip_next_rounded,
                        enabled: playback.canGoNext,
                        onPressed: onNext,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One round transport button inside the media card.
class _ShelfMediaCardControlButton extends StatelessWidget {
  const _ShelfMediaCardControlButton({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.onPressed,
    this.prominent = false,
  });

  final String label;
  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    final colors = context.shellColors;
    final accent = context.shellTheme.accentPalette;
    final size = prominent ? 32.0 : 28.0;
    return ShellExpressiveSurface(
      onPressed: onPressed,
      enabled: enabled,
      shape: ShellShapeScale.full,
      pressedShape: ShellShapeScale.medium,
      width: size,
      height: size,
      color: prominent ? accent.primary : colors.surfaceContainerHigh,
      tooltip: label,
      semanticLabel: label,
      child: Icon(
        icon,
        size: prominent ? 20 : 17,
        color: enabled
            ? prominent
                  ? accent.onPrimary
                  : colors.textPrimary
            : colors.glyphInactive,
      ),
    );
  }
}

class _ShelfMediaCardArtwork extends ConsumerWidget {
  const _ShelfMediaCardArtwork({required this.playback, required this.size});

  final MprisPlaybackState playback;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uri = Uri.tryParse(playback.artUrl);
    Widget artwork = const _ShelfMediaCardArtworkFallback();
    if (uri?.scheme == 'file') {
      String? path;
      try {
        path = uri!.toFilePath();
      } on UnsupportedError {
        path = null;
      }
      if (path != null) {
        final bytes = ref.watch(notificationStaticImageProvider(path)).value;
        if (bytes != null) {
          artwork = Image.memory(
            bytes,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
            cacheWidth: 320,
            cacheHeight: 320,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => const _ShelfMediaCardArtworkFallback(),
          );
        }
      }
    } else if (uri?.scheme == 'http' || uri?.scheme == 'https') {
      artwork = Image.network(
        playback.artUrl,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        cacheWidth: 320,
        cacheHeight: 320,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => const _ShelfMediaCardArtworkFallback(),
      );
    }
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: size,
        child: ClipRRect(
          borderRadius: context.shellTheme.borderRadius(ShellShapeScale.large),
          child: artwork,
        ),
      ),
    );
  }
}

class _ShelfMediaCardArtworkFallback extends StatelessWidget {
  const _ShelfMediaCardArtworkFallback();

  @override
  Widget build(BuildContext context) {
    final colors = context.shellColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            context.shellTheme.accentPalette.container,
            colors.surfaceContainerHighest,
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.music_note_rounded,
          size: 48,
          color: colors.textPrimary,
        ),
      ),
    );
  }
}

String _formatMediaTime(Duration value) {
  final seconds = value.inSeconds.clamp(0, 7 * 24 * 60 * 60);
  final hours = seconds ~/ 3600;
  final minutes = (seconds ~/ 60) % 60;
  final remainder = seconds % 60;
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:'
        '${remainder.toString().padLeft(2, '0')}';
  }
  return '$minutes:${remainder.toString().padLeft(2, '0')}';
}
