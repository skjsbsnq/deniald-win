import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../input/shell_interaction_registry.dart';
import '../models/display_layout.dart';
import '../localization/denial_localizations.dart';
import '../services/media_player_service.dart';
import '../settings/settings_controller.dart';
import '../settings/shell_settings.dart';
import '../state/system_status.dart';
import '../theme/motion.dart';
import '../theme/shell_theme.dart';
import '../theme/tokens.dart';
import '../wallpaper/state/wallpaper_accent.dart';
import '../widgets/notification_media.dart';
import '../widgets/shell_backdrop_blur.dart';
import '../widgets/shell_cursor.dart';
import 'desktop_start_button.dart';
import 'desktop_status_cluster.dart';
import 'desktop_system_bar_layout.dart';
import 'desktop_taskbar.dart';

/// The desktop system bar. Its strip is reserved from the window work area,
/// so windows maximize beside it while true fullscreen covers it.
///
/// The strip itself paints nothing: modules float as borderless pill cards
/// over the bare wallpaper, and every card follows the wallpaper's extracted
/// accent. The bar uses a tripartite layout (leading, center, trailing). The
/// Start card and taskbar window buttons travel between the leading and center
/// zones according to [ShellLayoutSettings.systemBarAlignment]: centered they
/// are absolutely centered across the bar and degrade gracefully when space is
/// constrained, leading they sit flush against the bar's first edge.
class DesktopSystemBar extends ConsumerWidget {
  const DesktopSystemBar({
    required this.side,
    this.monitorId,
    this.showHardwareMeters = false,
    this.onToggleLauncher,
    this.onToggleDashboard,
    this.onToggleCalendar,
    super.key,
  });

  static const double _edgePadding = 8.0;
  static const double _cardMargin = 4.0;
  static const double _cardGap = 8.0;

  final SystemBarSide side;
  final int? monitorId;
  final bool showHardwareMeters;
  final VoidCallback? onToggleLauncher;
  final VoidCallback? onToggleDashboard;
  final VoidCallback? onToggleCalendar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (side == SystemBarSide.hidden) {
      return const SizedBox.shrink();
    }

    final accent = ref.watch(shellAccentProvider);
    final alignment = ref.watch(
      shellSettingsProvider.select(
        (settings) => settings.layout.systemBarAlignment,
      ),
    );
    final horizontal = side.isHorizontal;
    final clusterLeads = alignment == SystemBarAlignment.leading;

    // Cards slide in from the bar's own edge, one 60 ms beat apart, so the
    // sweep runs inward from that edge: the clock leads it and the Start card
    // closes it. When the Start card leads the bar it opens the sweep instead
    // and everything else shifts one beat later, which keeps a single unbroken
    // run in both modes rather than making the first card wait out five beats.
    final clockBeat = clusterLeads ? 1 : 0;
    final statusBeat = clockBeat + 1;
    final trayBeat = statusBeat + 1;
    final cpuBeat = trayBeat + 1;
    final mediaBeat = cpuBeat + 1;
    final startBeat = clusterLeads ? 0 : mediaBeat + 1;
    // The GPU band spans one beat per adapter, a count only the meters module
    // knows, so it takes the tail: every other beat then stays fixed instead of
    // colliding with a second adapter's card.
    final gpuBeat = math.max(startBeat, mediaBeat) + 1;

    final clusterWidgets = <Widget>[
      _SystemBarEntrance(
        key: const ValueKey('system-bar-start-button'),
        index: startBeat,
        horizontal: horizontal,
        child: Padding(
          padding: horizontal
              ? const EdgeInsets.only(right: _cardGap)
              : const EdgeInsets.only(bottom: _cardGap),
          child: _SystemBarCard(
            accent: accent,
            child: DesktopStartButton(side: side, onTap: onToggleLauncher),
          ),
        ),
      ),
      DesktopTaskbar(side: side, monitorId: monitorId),
    ];

    final trailingWidgets = <Widget>[
      _SystemBarMediaEntrance(
        accent: accent,
        side: side,
        horizontal: horizontal,
        cardGap: _cardGap,
        index: mediaBeat,
      ),
      if (showHardwareMeters) ...[
        _SystemBarGpuMeters(
          accent: accent,
          horizontal: horizontal,
          cardGap: _cardGap,
          index: gpuBeat,
        ),
        _SystemBarCpuEntrance(
          accent: accent,
          horizontal: horizontal,
          cardGap: _cardGap,
          index: cpuBeat,
        ),
      ],
      _SystemBarTrayEntrance(
        accent: accent,
        side: side,
        horizontal: horizontal,
        cardGap: _cardGap,
        index: trayBeat,
      ),
      _SystemBarEntrance(
        key: const ValueKey('system-bar-status-cluster'),
        index: statusBeat,
        horizontal: horizontal,
        child: Padding(
          padding: horizontal
              ? const EdgeInsets.only(right: _cardGap)
              : const EdgeInsets.only(bottom: _cardGap),
          child: _SystemBarCard(
            accent: accent,
            onTap: onToggleDashboard,
            child: DesktopStatusCluster(
              horizontal: horizontal,
              onTap: onToggleDashboard,
            ),
          ),
        ),
      ),
      _SystemBarEntrance(
        key: const ValueKey('system-bar-clock'),
        index: clockBeat,
        horizontal: horizontal,
        child: _SystemBarCard(
          accent: accent,
          onTap: onToggleCalendar,
          child: _ClockModule(accent: accent, onTap: onToggleCalendar),
        ),
      ),
    ];

    return Padding(
      padding: horizontal
          ? const EdgeInsets.symmetric(
              horizontal: _edgePadding,
              vertical: _cardMargin,
            )
          : const EdgeInsets.symmetric(
              horizontal: _cardMargin,
              vertical: _edgePadding,
            ),
      child: DesktopSystemBarLayout(
        side: side,
        leading: clusterLeads ? clusterWidgets : const <Widget>[],
        center: clusterLeads ? const <Widget>[] : clusterWidgets,
        trailing: trailingWidgets,
        gap: _cardGap,
      ),
    );
  }
}

class _SystemBarMediaEntrance extends ConsumerWidget {
  const _SystemBarMediaEntrance({
    required this.accent,
    required this.side,
    required this.horizontal,
    required this.cardGap,
    required this.index,
  });

  final WallpaperAccent accent;
  final SystemBarSide side;
  final bool horizontal;
  final double cardGap;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final media =
        ref.watch(mediaPlaybackProvider).value ??
        MprisPlaybackState.unavailable();
    if (!media.available) {
      return const SizedBox.shrink();
    }
    return _SystemBarEntrance(
      key: const ValueKey('system-bar-media'),
      index: index,
      horizontal: horizontal,
      child: Padding(
        padding: horizontal
            ? EdgeInsets.only(right: cardGap)
            : EdgeInsets.only(bottom: cardGap),
        child: _SystemBarCard(
          accent: accent,
          child: _MediaStatusModule(
            accent: accent,
            side: side,
            playback: media,
          ),
        ),
      ),
    );
  }
}

class _SystemBarTrayEntrance extends StatelessWidget {
  const _SystemBarTrayEntrance({
    required this.accent,
    required this.side,
    required this.horizontal,
    required this.cardGap,
    required this.index,
  });

  final WallpaperAccent accent;
  final SystemBarSide side;
  final bool horizontal;
  final double cardGap;
  final int index;

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}

class _SystemBarCpuEntrance extends ConsumerWidget {
  const _SystemBarCpuEntrance({
    required this.accent,
    required this.horizontal,
    required this.cardGap,
    required this.index,
  });

  final WallpaperAccent accent;
  final bool horizontal;
  final double cardGap;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cpu = ref.watch(cpuUsageProvider);
    if (cpu.current == null) {
      return const SizedBox.shrink();
    }
    return _SystemBarEntrance(
      key: const ValueKey('system-bar-cpu'),
      index: index,
      horizontal: horizontal,
      child: Padding(
        padding: horizontal
            ? EdgeInsets.only(right: cardGap)
            : EdgeInsets.only(bottom: cardGap),
        child: _SystemBarCard(
          accent: accent,
          child: _MeterModule(
            accent: accent,
            label: context.l10n.metricCpu,
            series: cpu,
          ),
        ),
      ),
    );
  }
}

class _SystemBarGpuMeters extends ConsumerWidget {
  const _SystemBarGpuMeters({
    required this.accent,
    required this.horizontal,
    required this.cardGap,
    required this.index,
  });

  final WallpaperAccent accent;
  final bool horizontal;
  final double cardGap;

  /// First beat of the band this row occupies; it spans one beat per adapter.
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gpus = ref.watch(gpuUsageProvider);
    if (gpus.isEmpty) {
      return const SizedBox.shrink();
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (int i = 0; i < gpus.length; i += 1)
          _SystemBarEntrance(
            key: ValueKey('system-bar-gpu-${gpus[i].id}'),
            index: index + (gpus.length - 1 - i),
            horizontal: horizontal,
            child: Padding(
              padding: horizontal
                  ? EdgeInsets.only(right: cardGap)
                  : EdgeInsets.only(bottom: cardGap),
              child: _SystemBarCard(
                accent: accent,
                child: _MeterModule(
                  accent: accent,
                  label: gpus[i].label,
                  series: gpus[i].series,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _MediaStatusModule extends ConsumerStatefulWidget {
  const _MediaStatusModule({
    required this.accent,
    required this.side,
    required this.playback,
  });

  final WallpaperAccent accent;
  final SystemBarSide side;
  final MprisPlaybackState playback;

  @override
  ConsumerState<_MediaStatusModule> createState() => _MediaStatusModuleState();
}

class _MediaStatusModuleState extends ConsumerState<_MediaStatusModule>
    with SingleTickerProviderStateMixin {
  static const Duration _closeDelay = Duration(milliseconds: 180);
  static const Duration _positionInterval = Duration(seconds: 1);
  static const double _popupGap = 9;

  final OverlayPortalController _portal = OverlayPortalController();
  late final AnimationController _popupMotion;
  late final CurvedAnimation _popupCurve;
  Timer? _closeTimer;
  Timer? _positionTimer;
  bool _hovered = false;
  DateTime _popupNow = DateTime.now();

  @override
  void initState() {
    super.initState();
    _popupMotion = AnimationController(
      vsync: this,
      duration: Motion.cardSettle,
      reverseDuration: Motion.tile,
    );
    _popupCurve = CurvedAnimation(
      parent: _popupMotion,
      curve: Motion.md3EmphasizedDecelerate,
      reverseCurve: Motion.md3EmphasizedAccelerate,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    _popupMotion
      ..duration = reduceMotion ? Duration.zero : Motion.cardSettle
      ..reverseDuration = reduceMotion ? Duration.zero : Motion.tile;
  }

  void _show() {
    _closeTimer?.cancel();
    _closeTimer = null;
    if (!_portal.isShowing) {
      _portal.show();
      _popupMotion.forward(from: 0);
    } else if (!_popupMotion.isCompleted) {
      _popupMotion.forward();
    }
    _popupNow = DateTime.now();
    _positionTimer ??= Timer.periodic(_positionInterval, (_) {
      if (mounted && _portal.isShowing) {
        setState(() => _popupNow = DateTime.now());
      }
    });
    if (!_hovered) {
      setState(() => _hovered = true);
    }
  }

  void _scheduleClose() {
    _closeTimer?.cancel();
    _closeTimer = Timer(_closeDelay, () {
      _closeTimer = null;
      unawaited(_close());
    });
  }

  Future<void> _close() async {
    if (!mounted || !_portal.isShowing) {
      return;
    }
    _positionTimer?.cancel();
    _positionTimer = null;
    if (_hovered) {
      setState(() => _hovered = false);
    }
    try {
      await _popupMotion.reverse().orCancel;
    } on TickerCanceled {
      return;
    }
    if (!mounted || _hovered || !_portal.isShowing) {
      return;
    }
    _portal.hide();
  }

  @override
  void didUpdateWidget(covariant _MediaStatusModule oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.playback.available) {
      _portal.hide();
      _popupMotion.reset();
      _positionTimer?.cancel();
      _positionTimer = null;
      _hovered = false;
    }
  }

  @override
  void dispose() {
    _closeTimer?.cancel();
    _positionTimer?.cancel();
    _popupCurve.dispose();
    _popupMotion.dispose();
    super.dispose();
  }

  Widget _animatePopup(Widget child) {
    final (entryOffset, scaleAlignment) = switch (widget.side) {
      SystemBarSide.top => (const Offset(0, -10), Alignment.topCenter),
      SystemBarSide.bottom => (const Offset(0, 10), Alignment.bottomCenter),
      SystemBarSide.left => (const Offset(-10, 0), Alignment.centerLeft),
      SystemBarSide.right ||
      SystemBarSide.hidden => (const Offset(10, 0), Alignment.centerRight),
    };
    return AnimatedBuilder(
      animation: _popupCurve,
      child: RepaintBoundary(child: child),
      builder: (context, child) {
        final progress = _popupCurve.value;
        return Transform.translate(
          offset: Offset.lerp(entryOffset, Offset.zero, progress)!,
          child: Transform.scale(
            scale: 0.94 + 0.06 * progress,
            alignment: scaleAlignment,
            child: child,
          ),
        );
      },
    );
  }

  Widget _buildPopup(
    BuildContext context,
    OverlayChildLayoutInfo layout,
    MediaPlayerService service,
  ) {
    if (layout.childPaintTransform.determinant() == 0) {
      return const SizedBox.shrink();
    }
    final anchor = MatrixUtils.transformRect(
      layout.childPaintTransform,
      Offset.zero & layout.childSize,
    );
    final popupSize = Size(
      math.min(_MediaPlaybackPopup.size.width, layout.overlaySize.width),
      math.min(_MediaPlaybackPopup.size.height, layout.overlaySize.height),
    );
    late final Offset preferredOrigin;
    switch (widget.side) {
      case SystemBarSide.top:
        preferredOrigin = Offset(
          anchor.center.dx - popupSize.width / 2,
          anchor.bottom + _popupGap,
        );
      case SystemBarSide.bottom:
        preferredOrigin = Offset(
          anchor.center.dx - popupSize.width / 2,
          anchor.top - popupSize.height - _popupGap,
        );
      case SystemBarSide.left:
        preferredOrigin = Offset(
          anchor.right + _popupGap,
          anchor.center.dy - popupSize.height / 2,
        );
      case SystemBarSide.right:
      case SystemBarSide.hidden:
        preferredOrigin = Offset(
          anchor.left - popupSize.width - _popupGap,
          anchor.center.dy - popupSize.height / 2,
        );
    }
    final origin = Offset(
      preferredOrigin.dx
          .clamp(0.0, math.max(0.0, layout.overlaySize.width - popupSize.width))
          .toDouble(),
      preferredOrigin.dy
          .clamp(
            0.0,
            math.max(0.0, layout.overlaySize.height - popupSize.height),
          )
          .toDouble(),
    );
    return Positioned(
      left: origin.dx,
      top: origin.dy,
      width: popupSize.width,
      height: popupSize.height,
      child: ShellInputRegion(
        debugLabel: 'System bar media popup',
        child: MouseRegion(
          onEnter: (_) => _show(),
          onExit: (_) => _scheduleClose(),
          child: _animatePopup(
            _MediaPlaybackPopup(
              accent: widget.accent,
              playback: widget.playback,
              now: _popupNow,
              onPrevious: () => unawaited(service.previous()),
              onPlayPause: () => unawaited(service.playPause()),
              onNext: () => unawaited(service.next()),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = ref.read(mediaPlayerServiceProvider);
    return ShellInputRegion(
      debugLabel: 'System bar media control',
      child: OverlayPortal.overlayChildLayoutBuilder(
        controller: _portal,
        overlayChildBuilder: (context, layout) =>
            _buildPopup(context, layout, service),
        child: Semantics(
          button: true,
          label: context.l10n.mediaControls,
          child: MouseRegion(
            cursor: ShellMouseCursors.link,
            onEnter: (_) => _show(),
            onExit: (_) => _scheduleClose(),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _show,
              child: AnimatedContainer(
                duration: Motion.pill,
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: _hovered
                      ? widget.accent.color.withValues(alpha: 0.18)
                      : Colors.transparent,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  widget.playback.playing
                      ? Icons.graphic_eq_rounded
                      : Icons.music_note_rounded,
                  size: 17,
                  color: widget.accent.color,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MediaPlaybackPopup extends StatelessWidget {
  const _MediaPlaybackPopup({
    required this.accent,
    required this.playback,
    required this.now,
    required this.onPrevious,
    required this.onPlayPause,
    required this.onNext,
  });

  final WallpaperAccent accent;
  final MprisPlaybackState playback;
  final DateTime now;
  final VoidCallback onPrevious;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;

  static const Size size = Size(380, 168);

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(24));
    final theme = ShellTheme.of(context);
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
    return Material(
      type: MaterialType.transparency,
      child: ShellBackdropBlur(
        borderRadius: radius,
        child: Container(
          width: size.width,
          height: size.height,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                theme.panelColor(
                  Color.alphaBlend(
                    accent.color.withValues(alpha: 0.13),
                    ShellColors.panelBackground.withValues(alpha: 1),
                  ),
                ),
                theme.panelColor(ShellColors.surfaceContainerLow),
              ],
            ),
            borderRadius: radius,
            border: Border.all(color: accent.color.withValues(alpha: 0.3)),
            boxShadow: const [
              BoxShadow(
                color: ShellColors.shadow,
                blurRadius: 34,
                spreadRadius: 2,
                offset: Offset(0, 14),
              ),
            ],
          ),
          child: Row(
            children: [
              _MediaArtwork(playback: playback, accent: accent, size: 140),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.graphic_eq_rounded,
                          size: 14,
                          color: accent.color,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          context.l10n.mediaNowPlaying.toUpperCase(),
                          style: ShellText.systemBarCaption.copyWith(
                            color: accent.color,
                            letterSpacing: 1.05,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Text(
                      playback.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ShellText.statusClock.copyWith(fontSize: 16),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      secondary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ShellText.base.copyWith(
                        color: ShellColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                    const Spacer(),
                    Semantics(
                      value:
                          '${_formatMediaTime(position)} / ${_formatMediaTime(length)}',
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          minHeight: 4,
                          value: progress,
                          color: accent.color,
                          backgroundColor: ShellColors.surfaceContainerHighest,
                        ),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _formatMediaTime(position),
                            style: ShellText.systemBarCaption.copyWith(
                              color: ShellColors.textTertiary,
                            ),
                          ),
                        ),
                        Text(
                          _formatMediaTime(length),
                          style: ShellText.systemBarCaption.copyWith(
                            color: ShellColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _MediaControlButton(
                          label: context.l10n.mediaPrevious,
                          icon: Icons.skip_previous_rounded,
                          enabled: playback.canGoPrevious,
                          onPressed: onPrevious,
                        ),
                        const SizedBox(width: 8),
                        _MediaControlButton(
                          label: playback.playing
                              ? context.l10n.mediaPause
                              : context.l10n.mediaPlay,
                          icon: playback.playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          prominent: true,
                          enabled: playback.playing
                              ? playback.canPause
                              : playback.canPlay,
                          onPressed: onPlayPause,
                        ),
                        const SizedBox(width: 8),
                        _MediaControlButton(
                          label: context.l10n.mediaNext,
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
      ),
    );
  }
}

class _MediaControlButton extends StatefulWidget {
  const _MediaControlButton({
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
  State<_MediaControlButton> createState() => _MediaControlButtonState();
}

class _MediaControlButtonState extends State<_MediaControlButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final accent = ShellTheme.of(context).accentPalette;
    final size = widget.prominent ? 32.0 : 28.0;
    return Tooltip(
      message: widget.label,
      child: Semantics(
        button: true,
        enabled: widget.enabled,
        label: widget.label,
        child: MouseRegion(
          cursor: widget.enabled
              ? ShellMouseCursors.link
              : ShellMouseCursors.normal,
          onEnter: widget.enabled
              ? (_) => setState(() => _hovered = true)
              : null,
          onExit: widget.enabled
              ? (_) => setState(() => _hovered = false)
              : null,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.enabled ? widget.onPressed : null,
            child: AnimatedContainer(
              duration: Motion.tile,
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: widget.prominent
                    ? accent.primary
                    : _hovered
                    ? ShellColors.surfaceContainerHighest
                    : ShellColors.surfaceContainerHigh,
                shape: BoxShape.circle,
              ),
              child: Icon(
                widget.icon,
                size: widget.prominent ? 20 : 17,
                color: widget.enabled
                    ? widget.prominent
                          ? accent.onPrimary
                          : ShellColors.textPrimary
                    : ShellColors.glyphInactive,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MediaArtwork extends ConsumerWidget {
  const _MediaArtwork({
    required this.playback,
    required this.accent,
    required this.size,
  });

  final MprisPlaybackState playback;
  final WallpaperAccent accent;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uri = Uri.tryParse(playback.artUrl);
    Widget artwork = _MediaArtworkFallback(accent: accent);
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
            errorBuilder: (_, _, _) => _MediaArtworkFallback(accent: accent),
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
        errorBuilder: (_, _, _) => _MediaArtworkFallback(accent: accent),
      );
    }
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: size,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: artwork,
        ),
      ),
    );
  }
}

class _MediaArtworkFallback extends StatelessWidget {
  const _MediaArtworkFallback({required this.accent});

  final WallpaperAccent accent;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.color.withValues(alpha: 0.64),
            ShellColors.surfaceContainerHighest,
          ],
        ),
      ),
      child: const Center(
        child: Icon(
          Icons.music_note_rounded,
          size: 48,
          color: ShellColors.textPrimary,
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

/// Date caption plus the ticking clock. The caption re-tints with the
/// wallpaper accent; minute changes crossfade with a small upward slide.
/// Interactive tap toggles the desktop calendar panel.
class _ClockModule extends ConsumerStatefulWidget {
  const _ClockModule({required this.accent, this.onTap});

  final WallpaperAccent accent;
  final VoidCallback? onTap;

  @override
  ConsumerState<_ClockModule> createState() => _ClockModuleState();
}

class _ClockModuleState extends ConsumerState<_ClockModule> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final accent = widget.accent;
    final time = localizedTime(context, now);
    final shortDate = localizedShortDate(context, now);
    final l10n = context.l10n;

    Widget child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedDefaultTextStyle(
          duration: Motion.wallpaperReveal,
          curve: Motion.standard,
          style: ShellText.systemBarCaption.copyWith(
            fontSize: 12.0,
            color: accent.captionColor,
            fontWeight: FontWeight.w500,
          ),
          child: Text(shortDate),
        ),
        const SizedBox(width: 8),
        AnimatedSwitcher(
          duration: Motion.cardSettle,
          switchInCurve: Motion.standard,
          switchOutCurve: Motion.standard,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.0, 0.25),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
          child: Text(
            time,
            key: ValueKey<String>(time),
            style: ShellText.systemBarValue.copyWith(
              fontSize: 14.0,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );

    if (widget.onTap != null) {
      child = Tooltip(
        message:
            '${localizedLongDate(context, now)}\n${l10n.desktopCalendarTitle}',
        waitDuration: const Duration(milliseconds: 600),
        child: Semantics(
          button: true,
          label: '$shortDate, $time · ${l10n.desktopCalendarOpenPanel}',
          child: Focus(
            onFocusChange: (focused) => setState(() => _focused = focused),
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent &&
                  (event.logicalKey == LogicalKeyboardKey.enter ||
                      event.logicalKey == LogicalKeyboardKey.space)) {
                widget.onTap?.call();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: _focused
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: accent.color, width: 1.5),
                    )
                  : null,
              child: child,
            ),
          ),
        ),
      );
    }

    return child;
  }
}

/// One load meter: a caption tag naming the source, a sparkline of the recent
/// history, the animated percentage, and an optional direct sensor reading.
/// Identity comes from the tag, never from the line color alone.
class _MeterModule extends StatelessWidget {
  const _MeterModule({
    required this.accent,
    required this.label,
    required this.series,
  });

  final WallpaperAccent accent;
  final String label;
  final LoadSeries series;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedDefaultTextStyle(
          duration: Motion.wallpaperReveal,
          curve: Motion.standard,
          style: ShellText.systemBarCaption.copyWith(
            fontSize: 12.0,
            color: accent.captionColor,
            fontWeight: FontWeight.w500,
          ),
          child: Text(label),
        ),
        const SizedBox(width: 6),
        RepaintBoundary(
          child: CustomPaint(
            size: const Size(42, 16),
            painter: _SparklinePainter(
              history: series.history,
              accent: accent.color,
            ),
          ),
        ),
        const SizedBox(width: 7),
        TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0.0, end: series.current ?? 0.0),
          duration: Motion.pill,
          curve: Motion.standard,
          builder: (context, value, _) => SizedBox(
            width: 36,
            child: Text.rich(
              TextSpan(
                text: context.l10n.numberValue((value * 100).round()),
                style: ShellText.systemBarValue.copyWith(fontSize: 13.5),
                children: [
                  TextSpan(
                    text: context.l10n.percentSign,
                    style: ShellText.systemBarCaption.copyWith(
                      fontSize: 11.5,
                      color: accent.captionColor,
                    ),
                  ),
                ],
              ),
              textAlign: TextAlign.right,
              maxLines: 1,
            ),
          ),
        ),
        if (series.temperatureC case final temperature?) ...[
          const SizedBox(width: 7),
          _TemperatureValue(accent: accent, temperatureC: temperature),
        ],
      ],
    );
  }
}

class _TemperatureValue extends StatelessWidget {
  const _TemperatureValue({required this.accent, required this.temperatureC});

  final WallpaperAccent accent;
  final double temperatureC;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        text: context.l10n.numberValue(temperatureC.round()),
        style: ShellText.systemBarValue,
        children: [
          TextSpan(
            text: context.l10n.celsiusUnit,
            style: ShellText.systemBarCaption.copyWith(
              color: accent.captionColor,
            ),
          ),
        ],
      ),
      maxLines: 1,
    );
  }
}

/// A borderless translucent pill hosting one system bar module. The softly
/// top-lit gradient animates between wallpaper accents at the wallpaper
/// reveal's pace so the bar re-themes as part of the same gesture.
class _SystemBarCard extends StatelessWidget {
  const _SystemBarCard({required this.accent, required this.child, this.onTap});

  final WallpaperAccent accent;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(999));
    final theme = ShellTheme.of(context);
    Widget card = ShellBackdropBlur(
      borderRadius: radius,
      child: AnimatedContainer(
        duration: Motion.wallpaperReveal,
        curve: Motion.standard,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              theme.panelColor(accent.cardFillTop),
              theme.panelColor(accent.cardFill),
            ],
          ),
          borderRadius: radius,
        ),
        alignment: Alignment.center,
        child: child,
      ),
    );

    if (onTap != null) {
      card = ShellInputRegion(
        debugLabel: 'System bar card',
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: card,
          ),
        ),
      );
    }

    return card;
  }
}

/// One-shot mount transition for a pill: it springs in from the trailing
/// edge, staggered by [index], while its main-axis extent grows so the
/// neighbouring pills glide instead of jumping. Costs nothing once settled.
class _SystemBarEntrance extends StatefulWidget {
  const _SystemBarEntrance({
    required this.index,
    required this.horizontal,
    required this.child,
    super.key,
  });

  final int index;
  final bool horizontal;
  final Widget child;

  @override
  State<_SystemBarEntrance> createState() => _SystemBarEntranceState();
}

class _SystemBarEntranceState extends State<_SystemBarEntrance>
    with SingleTickerProviderStateMixin {
  static const double _slideDistance = 12.0;
  static const Duration _stagger = Duration(milliseconds: 60);

  late final AnimationController _controller = AnimationController.unbounded(
    vsync: this,
  );
  Timer? _delay;

  @override
  void initState() {
    super.initState();
    _delay = Timer(_stagger * widget.index, () {
      if (mounted) {
        springTo(_controller, 1.0, telemetryLabel: 'system_bar_entrance');
      }
    });
  }

  @override
  void dispose() {
    _delay?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        final travel = (1.0 - t) * _slideDistance;
        return Align(
          alignment: widget.horizontal
              ? Alignment.centerRight
              : Alignment.bottomCenter,
          widthFactor: widget.horizontal ? unit(t) : null,
          heightFactor: widget.horizontal ? null : unit(t),
          child: Opacity(
            opacity: unit(t),
            child: Transform.translate(
              offset: widget.horizontal
                  ? Offset(travel, 0.0)
                  : Offset(0.0, travel),
              child: child,
            ),
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// Paints the CPU load history as an accent polyline over a gradient fill.
/// The newest sample hugs the trailing edge and the line slides left as the
/// window fills. Plain path drawing only — no mask filters, no save layers.
class _SparklinePainter extends CustomPainter {
  const _SparklinePainter({required this.history, required this.accent});

  final List<double> history;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final points = sparklinePoints(history, size);
    if (points.length < 2) {
      return;
    }
    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      line.lineTo(point.dx, point.dy);
    }
    final fill = Path.from(line)
      ..lineTo(points.last.dx, size.height)
      ..lineTo(points.first.dx, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            accent.withValues(alpha: 0.35),
            accent.withValues(alpha: 0.0),
          ],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    return oldDelegate.history != history || oldDelegate.accent != accent;
  }
}

/// Maps [history] (oldest first, 0-1 values) onto sparkline points inside
/// [size]. The newest sample sits on the right edge; a partial history leaves
/// the left side empty so the line grows leftward as samples arrive.
@visibleForTesting
List<Offset> sparklinePoints(List<double> history, Size size) {
  if (history.isEmpty || size.isEmpty) {
    return const <Offset>[];
  }
  final step = size.width / (LoadSeries.capacity - 1);
  return List<Offset>.generate(history.length, (index) {
    final fromEnd = history.length - 1 - index;
    return Offset(
      size.width - fromEnd * step,
      size.height * (1.0 - history[index].clamp(0.0, 1.0)),
    );
  }, growable: false);
}
