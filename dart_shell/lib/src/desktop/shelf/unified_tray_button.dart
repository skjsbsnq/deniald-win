import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../input/shell_interaction_registry.dart';
import '../../localization/denial_localizations.dart';
import '../../services/media_player_service.dart';
import '../../services/network_backend.dart';
import '../../state/bluetooth.dart';
import '../../state/desktop_notifications.dart';
import '../../state/network_connectivity.dart';
import '../../state/system_status.dart';
import '../../theme/motion.dart';
import '../../theme/shell_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/shell_backdrop_blur.dart';
import '../../widgets/shell_expressive_surface.dart';
import '../../widgets/shell_hover_pill.dart';
import 'shelf_media_card.dart';

/// The aggregated tray button on the right edge of the shelf.
class UnifiedTrayButton extends ConsumerWidget {
  const UnifiedTrayButton({
    required this.expanded,
    required this.onPressed,
    this.clockExpanded = false,
    this.onClockPressed,
    super.key,
  });

  final bool expanded;
  final bool clockExpanded;
  final VoidCallback onPressed;
  final VoidCallback? onClockPressed;

  static IconData _batteryIcon(int? capacity, bool charging) {
    if (capacity == null) {
      return Icons.battery_unknown_rounded;
    }
    if (charging) {
      return Icons.battery_charging_full_rounded;
    }
    if (capacity >= 95) return Icons.battery_full_rounded;
    if (capacity >= 80) return Icons.battery_6_bar_rounded;
    if (capacity >= 65) return Icons.battery_5_bar_rounded;
    if (capacity >= 50) return Icons.battery_4_bar_rounded;
    if (capacity >= 35) return Icons.battery_3_bar_rounded;
    if (capacity >= 20) return Icons.battery_2_bar_rounded;
    if (capacity >= 10) return Icons.battery_1_bar_rounded;
    return Icons.battery_alert_rounded;
  }

  static IconData _networkIcon(NetworkSnapshot snapshot) {
    final status = snapshot.status;
    if (status == NetworkConnectivityStatus.connecting) {
      return Icons.wifi_find_rounded;
    }
    if (status == NetworkConnectivityStatus.online ||
        status == NetworkConnectivityStatus.local ||
        status == NetworkConnectivityStatus.limited ||
        status == NetworkConnectivityStatus.captivePortal) {
      return Icons.wifi_rounded;
    }
    if (snapshot.wirelessEnabled) {
      return Icons.wifi_rounded;
    }
    return Icons.wifi_off_rounded;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = context.shellTheme.accentPalette;
    final battery = ref.watch(batteryProvider);
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final time = localizedTime(context, now);
    final bluetooth = ref.watch(
      bluetoothProvider.select((state) => state.powered),
    );
    final connectivity = ref.watch(
      networkConnectivityProvider.select((state) => state.snapshot),
    );
    final notifications = ref.watch(
      desktopNotificationsProvider.select(
        (state) => (state.doNotDisturb, state.unreadCount),
      ),
    );
    final doNotDisturb = notifications.$1;
    final unreadCount = notifications.$2;

    final capacity = battery.capacity;
    final hasBattery = capacity != null;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Media controls are an equivalent entry to the one the legacy system
        // bar carried: a circular button that reveals the playback popup.
        const _ShelfMediaModule(),
        _TrayCapsule(
          expanded: expanded,
          onTap: onPressed,
          padding: const EdgeInsets.symmetric(horizontal: ShellSpacing.md),
          childBuilder: (context, hovered, focused, foreground) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (unreadCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(right: ShellSpacing.sm),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: ShellSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color: accent.errorContainer,
                        borderRadius: context.shellTheme.borderRadius(
                          ShellShapeScale.full,
                        ),
                      ),
                      child: Text(
                        unreadCount > 9 ? '9+' : '$unreadCount',
                        style: ShellText.settingsBadgeLabel.copyWith(
                          color: accent.onErrorContainer,
                        ),
                      ),
                    ),
                  ),
                if (doNotDisturb)
                  Padding(
                    padding: const EdgeInsets.only(right: ShellSpacing.sm),
                    child: Icon(
                      Icons.do_not_disturb_on_rounded,
                      size: 16,
                      color: foreground,
                    ),
                  ),
                if (bluetooth)
                  Padding(
                    padding: const EdgeInsets.only(right: ShellSpacing.sm),
                    child: Icon(
                      Icons.bluetooth_rounded,
                      size: 16,
                      color: foreground,
                    ),
                  ),
                Icon(_networkIcon(connectivity), size: 16, color: foreground),
                if (hasBattery) ...[
                  const SizedBox(width: ShellSpacing.xs),
                  Icon(
                    _batteryIcon(capacity, battery.charging),
                    size: 16,
                    color: foreground,
                  ),
                ],
              ],
            );
          },
        ),
        const SizedBox(width: ShellSpacing.sm),
        _TrayCapsule(
          expanded: clockExpanded,
          onTap: onClockPressed ?? onPressed,
          padding: const EdgeInsets.symmetric(horizontal: ShellSpacing.lg),
          childBuilder: (context, hovered, focused, foreground) {
            return Center(
              child: Text(
                time,
                style: ShellText.trayClock.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w700,
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

/// One segmented tray capsule (status cluster or clock).
///
/// The resting fill is `surfaceContainerHigh`; while expanded it settles to
/// `primary` + `onPrimary`. Both colors glide on the effects spring instead
/// of snapping, per 02-VISUAL-SPEC §4.
class _TrayCapsule extends StatefulWidget {
  const _TrayCapsule({
    required this.expanded,
    required this.onTap,
    required this.padding,
    required this.childBuilder,
  });

  final bool expanded;
  final VoidCallback onTap;
  final EdgeInsetsGeometry padding;
  final Widget Function(
    BuildContext context,
    bool hovered,
    bool focused,
    Color foreground,
  )
  childBuilder;

  @override
  State<_TrayCapsule> createState() => _TrayCapsuleState();
}

class _TrayCapsuleState extends State<_TrayCapsule>
    with SingleTickerProviderStateMixin {
  // Unbounded: the effects spring may dip past [0, 1] while retargeting.
  late final AnimationController _expand = AnimationController.unbounded(
    vsync: this,
    value: widget.expanded ? 1.0 : 0.0,
  );

  @override
  void didUpdateWidget(covariant _TrayCapsule oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.expanded == widget.expanded) {
      return;
    }
    final target = widget.expanded ? 1.0 : 0.0;
    if (MediaQuery.disableAnimationsOf(context)) {
      _expand
        ..stop()
        ..value = target;
      return;
    }
    springTo(
      _expand,
      target,
      velocity: _expand.velocity,
      spring: Motion.expressiveEffectsDefault,
      telemetryLabel: 'shelf_tray_capsule_color',
    );
  }

  @override
  void dispose() {
    _expand.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.shellColors;
    final accent = context.shellTheme.accentPalette;
    return AnimatedBuilder(
      animation: _expand,
      builder: (context, _) {
        final t = _expand.value.clamp(0.0, 1.0);
        final background = Color.lerp(
          colors.surfaceContainerHigh,
          accent.primary,
          t,
        )!;
        final foreground = Color.lerp(colors.textPrimary, accent.onPrimary, t)!;
        return ShellHoverPill.builder(
          onTap: widget.onTap,
          height: 40,
          padding: widget.padding,
          color: background,
          // The expanded capsule holds its primary fill on hover; idle the
          // state-layer overlay composited over the resting container.
          hoverColor: widget.expanded
              ? background
              : Color.alphaBlend(colors.panelHighlight, background),
          childBuilder: (context, hovered, focused) =>
              widget.childBuilder(context, hovered, focused, foreground),
        );
      },
    );
  }
}

/// Mounts the media control button only while an MPRIS player reports an
/// active (playing or paused) track.
class _ShelfMediaModule extends ConsumerWidget {
  const _ShelfMediaModule();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(
      mediaPlaybackProvider.select((media) {
        final playback = media.value;
        return (
          available: playback?.available ?? false,
          playing: playback?.playing ?? false,
        );
      }),
    );
    if (!summary.available) {
      return const SizedBox.shrink();
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ShelfMediaButton(playing: summary.playing),
        const SizedBox(width: ShellSpacing.sm),
      ],
    );
  }
}

/// Circular shelf button that opens the media playback popup on hover or tap.
class _ShelfMediaButton extends ConsumerStatefulWidget {
  const _ShelfMediaButton({required this.playing});

  final bool playing;

  @override
  ConsumerState<_ShelfMediaButton> createState() => _ShelfMediaButtonState();
}

class _ShelfMediaButtonState extends ConsumerState<_ShelfMediaButton>
    with SingleTickerProviderStateMixin {
  // Hover-intent debounce and the position tick are timers, not animation
  // durations, so they stay local constants.
  static const Duration _closeDelay = Duration(milliseconds: 180);
  static const Duration _positionInterval = Duration(seconds: 1);

  final OverlayPortalController _portal = OverlayPortalController();
  late final AnimationController _popupMotion = AnimationController.unbounded(
    vsync: this,
  );
  Timer? _closeTimer;
  Timer? _positionTimer;
  DateTime _popupNow = DateTime.now();

  @override
  void dispose() {
    _closeTimer?.cancel();
    _positionTimer?.cancel();
    _popupMotion.dispose();
    super.dispose();
  }

  void _driveOpen() {
    if (MediaQuery.disableAnimationsOf(context)) {
      _popupMotion
        ..stop()
        ..value = 1.0;
      return;
    }
    springTo(
      _popupMotion,
      1.0,
      velocity: _popupMotion.velocity,
      spring: Motion.expressiveSpatialDefault,
      telemetryLabel: 'shelf_media_popup',
    );
  }

  void _show() {
    _closeTimer?.cancel();
    _closeTimer = null;
    if (!_portal.isShowing) {
      _portal.show();
      _driveOpen();
    } else if (_popupMotion.value < 1.0) {
      _driveOpen();
    }
    _popupNow = DateTime.now();
    _positionTimer ??= Timer.periodic(_positionInterval, (_) {
      if (mounted && _portal.isShowing) {
        setState(() => _popupNow = DateTime.now());
      }
    });
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
    if (MediaQuery.disableAnimationsOf(context)) {
      _popupMotion
        ..stop()
        ..value = 0.0;
      _portal.hide();
      return;
    }
    // Awaiting the TickerFuture resolves when the spring settles OR when a
    // re-hover retargets the controller; the value guard keeps it open then.
    await springTo(
      _popupMotion,
      0.0,
      velocity: _popupMotion.velocity,
      spring: Motion.expressiveSpatialDefault,
      telemetryLabel: 'shelf_media_popup',
    );
    if (!mounted || !_portal.isShowing) {
      return;
    }
    if (_popupMotion.value <= 0.05) {
      _portal.hide();
    }
  }

  Widget _buildPopup(
    BuildContext context,
    OverlayChildLayoutInfo layout,
    MediaPlayerService service,
    MprisPlaybackState playback,
  ) {
    if (layout.childPaintTransform.determinant() == 0) {
      return const SizedBox.shrink();
    }
    final anchor = MatrixUtils.transformRect(
      layout.childPaintTransform,
      Offset.zero & layout.childSize,
    );
    final popupSize = Size(
      math.min(_ShelfMediaPopup.size.width, layout.overlaySize.width),
      math.min(_ShelfMediaPopup.size.height, layout.overlaySize.height),
    );
    final preferred = Offset(
      anchor.center.dx - popupSize.width / 2,
      anchor.top - popupSize.height - ShellSpacing.sm,
    );
    final origin = Offset(
      preferred.dx
          .clamp(0.0, math.max(0.0, layout.overlaySize.width - popupSize.width))
          .toDouble(),
      preferred.dy
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
        debugLabel: 'Shelf media popup',
        child: MouseRegion(
          onEnter: (_) => _show(),
          onExit: (_) => _scheduleClose(),
          child: AnimatedBuilder(
            animation: _popupMotion,
            child: RepaintBoundary(
              child: _ShelfMediaPopup(
                playback: playback,
                now: _popupNow,
                onPrevious: () => unawaited(service.previous()),
                onPlayPause: () => unawaited(service.playPause()),
                onNext: () => unawaited(service.next()),
              ),
            ),
            builder: (context, child) {
              final progress = _popupMotion.value.clamp(0.0, 1.0);
              return Opacity(
                opacity: progress,
                child: Transform.translate(
                  offset: Offset(0, (1 - progress) * ShellSpacing.sm),
                  child: Transform.scale(
                    scale: 0.94 + 0.06 * progress,
                    alignment: Alignment.bottomCenter,
                    child: ShellBackdropBlur(
                      strength: progress,
                      borderRadius: context.shellTheme.borderRadius(
                        ShellShapeScale.extraLarge,
                      ),
                      child: child!,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.shellColors;
    final service = ref.read(mediaPlayerServiceProvider);
    return MouseRegion(
      onEnter: (_) => _show(),
      onExit: (_) => _scheduleClose(),
      child: OverlayPortal.overlayChildLayoutBuilder(
        controller: _portal,
        // The overlay builder closure outlives this build, so the playback
        // snapshot must be watched from inside the overlay child rather than
        // captured here — otherwise the card renders the stale pre-show state.
        overlayChildBuilder: (context, layout) => Consumer(
          builder: (context, ref, _) {
            final playback =
                ref.watch(mediaPlaybackProvider).value ?? service.current;
            return _buildPopup(context, layout, service, playback);
          },
        ),
        child: ShellExpressiveSurface(
          onPressed: _show,
          shape: ShellShapeScale.full,
          width: 40,
          height: 40,
          tooltip: context.l10n.mediaControls,
          semanticLabel: context.l10n.mediaControls,
          child: Icon(
            widget.playing
                ? Icons.graphic_eq_rounded
                : Icons.music_note_rounded,
            size: 18,
            color: colors.textPrimary,
          ),
        ),
      ),
    );
  }
}

/// The floating playback card anchored above the shelf media button. The
/// layout itself lives in the shared [ShelfMediaCard]; this wrapper only
/// pins the popup's fixed size.
class _ShelfMediaPopup extends StatelessWidget {
  const _ShelfMediaPopup({
    required this.playback,
    required this.now,
    required this.onPrevious,
    required this.onPlayPause,
    required this.onNext,
  });

  final MprisPlaybackState playback;
  final DateTime now;
  final VoidCallback onPrevious;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;

  static const Size size = Size(380, 168);

  @override
  Widget build(BuildContext context) {
    return ShelfMediaCard(
      playback: playback,
      now: now,
      onPrevious: onPrevious,
      onPlayPause: onPlayPause,
      onNext: onNext,
      width: size.width,
      height: size.height,
    );
  }
}
