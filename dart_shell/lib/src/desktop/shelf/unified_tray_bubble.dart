import 'dart:math' as math;

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../desktop_workspace.dart';
import '../../localization/denial_localizations.dart';
import '../../services/network_backend.dart';
import '../../settings/settings_application.dart';
import '../../settings/widgets/settings_navigation.dart';
import '../../state/bluetooth.dart';
import '../../state/desktop_notifications.dart';
import '../../state/network_connectivity.dart';
import '../../state/quick_settings.dart';
import '../../theme/motion.dart';
import '../../theme/shell_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/connectivity/bluetooth_detail_surface.dart';
import '../../widgets/connectivity/wifi_detail_surface.dart';
import '../../widgets/session/power_session_surface.dart';
import '../../widgets/shade/quick_settings_tiles.dart';
import '../../widgets/shade/range_bar.dart';
import '../../widgets/shell_backdrop_blur.dart';
import '../../widgets/shell_hover_pill.dart';
import '../../widgets/shell_surface_host.dart';

/// The popup bubble originating from the unified tray on the shelf.
class UnifiedTrayBubble extends ConsumerStatefulWidget {
  const UnifiedTrayBubble({
    required this.visible,
    this.onDismiss,
    this.onOpenOverview,
    this.shelfHeight = 56.0,
    this.outputRect,
    super.key,
  });

  final bool visible;
  final VoidCallback? onDismiss;
  final VoidCallback? onOpenOverview;
  final double shelfHeight;

  /// The logical rect of the output whose shelf anchors this bubble. Null
  /// docks to the full canvas, which is the single-output behavior.
  final Rect? outputRect;

  @override
  ConsumerState<UnifiedTrayBubble> createState() => _UnifiedTrayBubbleState();
}

class _UnifiedTrayBubbleState extends ConsumerState<UnifiedTrayBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final FocusNode _contentFocus;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController.unbounded(
      vsync: this,
      value: widget.visible ? 1.0 : 0.0,
    );
    _contentFocus = FocusNode(debugLabel: 'unified-tray-bubble');
  }

  @override
  void didUpdateWidget(covariant UnifiedTrayBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible != widget.visible) {
      if (widget.visible) {
        // The bubble takes keyboard focus when it opens so Tab traversal
        // and the Escape dismiss work like every other shell surface.
        // Descendants that later take focus keep it; requestFocus only
        // claims the initially unowned focus scope.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && widget.visible && !_contentFocus.hasFocus) {
            _contentFocus.requestFocus();
          }
        });
      }
      // Reduce-motion users get the end state directly; the settle spring
      // is a purely decorative overshoot.
      if (MediaQuery.disableAnimationsOf(context)) {
        _controller.value = widget.visible ? 1.0 : 0.0;
      } else {
        springTo(
          _controller,
          widget.visible ? 1.0 : 0.0,
          spring: Motion.expressiveSpatialDefault,
          telemetryLabel: 'tray_bubble_toggle',
        );
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _contentFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      // The content is lifted out of the builder so the settle spring only
      // rebuilds the blur/scale shell, and wrapped in a RepaintBoundary so the
      // per-tick backdrop re-filter cannot re-paint the content layer.
      builder: (context, child) {
        final progress = _controller.value;
        if (progress <= 0.001 && !widget.visible) {
          return const SizedBox.shrink();
        }

        final theme = context.shellTheme;
        final colors = context.shellColors;
        final size = MediaQuery.sizeOf(context);
        // The bubble docks to the corner of the anchoring output, not the
        // global canvas corner, so a shelf clone on another output opens its
        // bubble beside itself (COR-5).
        final anchorRect = widget.outputRect ?? (Offset.zero & size);
        final clampedProgress = progress.clamp(0.0, 1.0);
        final scale = math.max(0.0, 0.88 + 0.12 * progress);
        final bubbleRadius = theme.borderRadius(ShellShapeScale.extraLarge);
        final bubbleWidth = math.min(anchorRect.width - 16.0, 420.0);

        return Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: widget.onDismiss,
              child: const SizedBox.expand(),
            ),
            Positioned.fromRect(
              rect: anchorRect,
              child: Stack(
                children: [
                  Positioned(
                    right: 8.0,
                    bottom: widget.shelfHeight + 8.0,
                    child: Transform.scale(
                      scale: scale,
                      alignment: Alignment.bottomRight,
                      child: SizedBox(
                        width: bubbleWidth,
                        child: ShellBackdropBlur(
                          strength: clampedProgress,
                          borderRadius: bubbleRadius,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              // Frosted surface blending with desktop
                              // background tones.
                              color: theme.panelColor(
                                colors.surfaceContainerLow,
                              ),
                              borderRadius: bubbleRadius,
                              border: Border.all(
                                color: colors.hairlineSoft,
                                width: 1.0,
                              ),
                            ),
                            child: child,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
      child: RepaintBoundary(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Focus(
            focusNode: _contentFocus,
            autofocus: widget.visible,
            child: FocusTraversalGroup(
              child: CallbackShortcuts(
                bindings: <ShortcutActivator, VoidCallback>{
                  const SingleActivator(LogicalKeyboardKey.escape): () =>
                      widget.onDismiss?.call(),
                },
                child: _TrayBubbleContent(
                  onDismiss: widget.onDismiss,
                  onOpenOverview: widget.onOpenOverview,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TrayBubbleContent extends ConsumerWidget {
  const _TrayBubbleContent({this.onDismiss, this.onOpenOverview});

  final VoidCallback? onDismiss;
  final VoidCallback? onOpenOverview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;

    // The sliders watch their own value in narrow consumers below; this
    // widget only subscribes to the profile so a drag does not rebuild the
    // whole column (header, chips, and tiles) on every pointer delta.
    final profile = ref.watch(
      quickSettingsProvider.select((state) => state.profile),
    );
    final quickSettingsController = ref.read(quickSettingsProvider.notifier);

    final network = ref.watch(networkConnectivityProvider);
    final networkController = ref.read(networkConnectivityProvider.notifier);
    final bluetooth = ref.watch(bluetoothProvider);
    final bluetoothController = ref.read(bluetoothProvider.notifier);
    // The bubble itself no longer lists notifications; the dashboard panel's
    // Info page owns the full grouped history. Only the do-not-disturb state
    // stays here to keep the quick settings tile live.
    final notificationPolicy = ref.watch(
      desktopNotificationsProvider.select(
        (state) =>
            (doNotDisturb: state.doNotDisturb, loaded: state.policyLoaded),
      ),
    );
    final notificationController = ref.read(
      desktopNotificationsProvider.notifier,
    );

    final networkSnapshot = network.snapshot;
    final wifiToggleEnabled =
        !network.initializing &&
        networkSnapshot.serviceAvailable &&
        networkSnapshot.wifiDeviceAvailable &&
        networkSnapshot.wirelessHardwareEnabled &&
        networkSnapshot.radioPermission != NetworkPermission.denied &&
        !network.radioChanging;
    final bluetoothToggleEnabled =
        !bluetooth.initializing &&
        bluetooth.serviceAvailable &&
        bluetooth.available &&
        !bluetooth.powerChanging;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TrayHeader(onDismiss: onDismiss),
        const SizedBox(height: 10.0),
        _TrayStatusChips(onDismiss: onDismiss, onOpenOverview: onOpenOverview),
        const SizedBox(height: 10.0),
        QuickSettingsTiles(
          wifi:
              networkSnapshot.wirelessEnabled &&
              networkSnapshot.wifiDeviceAvailable,
          wifiSubtitle: wifiStatusLabel(network, l10n),
          wifiEnabled: wifiToggleEnabled,
          wifiBusy: network.radioChanging,
          bluetooth: bluetooth.powered && bluetooth.available,
          bluetoothSubtitle: bluetoothStatusLabel(bluetooth, l10n),
          bluetoothEnabled: bluetoothToggleEnabled,
          bluetoothBusy: bluetooth.powerChanging,
          dnd: notificationPolicy.doNotDisturb,
          dndReady: notificationPolicy.loaded,
          profile: profile,
          onToggleWifi: networkController.toggleWireless,
          onOpenWifi: () {
            ref
                .read(shellSurfaceControllerProvider.notifier)
                .show(
                  keyName: 'wifi-details',
                  debugLabel: 'Wi-Fi details',
                  builder: (_, handle) =>
                      WifiDetailSurface(onClose: handle.close),
                );
          },
          onToggleBluetooth: bluetoothController.togglePower,
          onOpenBluetooth: () {
            ref
                .read(shellSurfaceControllerProvider.notifier)
                .show(
                  keyName: 'bluetooth-details',
                  debugLabel: 'Bluetooth details',
                  builder: (_, handle) =>
                      BluetoothDetailSurface(onClose: handle.close),
                );
          },
          onToggleDnd: notificationController.toggleDoNotDisturb,
          onCycleProfile: quickSettingsController.cycleProfile,
          onScreenshot: () {
            onDismiss?.call();
            quickSettingsController.takeScreenshot();
          },
        ),
        const SizedBox(height: 10.0),
        _BrightnessRangeBar(onDismiss: onDismiss),
        const SizedBox(height: 8.0),
        _VolumeRangeBar(onDismiss: onDismiss),
      ],
    );
  }
}

/// Brightness slider in its own consumer so drag deltas only rebuild this
/// row; the rest of the bubble stays untouched while the value streams in.
class _BrightnessRangeBar extends ConsumerWidget {
  const _BrightnessRangeBar({this.onDismiss});

  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.shellTheme;
    final colors = context.shellColors;
    final brightness = ref.watch(
      quickSettingsProvider.select((state) => state.brightness),
    );
    final controller = ref.read(quickSettingsProvider.notifier);
    return RangeBar(
      icon: Icons.brightness_6_rounded,
      value: brightness,
      activeColor: theme.accent,
      inactiveColor: colors.surfaceContainerHighest,
      onChanged: controller.setBrightness,
      onChangeEnd: controller.commitBrightness,
      height: 36.0,
      trailing: _TrayTrailingActionButton(
        icon: Icons.brightness_auto_rounded,
        onPressed: () {
          launchSettingsPage(
            ref,
            context,
            SettingsPageId.displays,
            onDispatched: onDismiss,
          );
        },
      ),
    );
  }
}

/// Volume slider in its own consumer; see [_BrightnessRangeBar].
class _VolumeRangeBar extends ConsumerWidget {
  const _VolumeRangeBar({this.onDismiss});

  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.shellTheme;
    final colors = context.shellColors;
    final volume = ref.watch(
      quickSettingsProvider.select((state) => state.volume),
    );
    final controller = ref.read(quickSettingsProvider.notifier);
    return RangeBar(
      icon: Icons.volume_up_rounded,
      value: volume,
      activeColor: theme.accent,
      inactiveColor: colors.surfaceContainerHighest,
      onChangeStart: controller.beginVolumeInteraction,
      onChanged: controller.setVolume,
      onChangeEnd: controller.commitVolume,
      height: 36.0,
      trailing: _TrayTrailingActionButton(
        icon: Icons.chevron_right_rounded,
        onPressed: () {
          launchSettingsPage(
            ref,
            context,
            SettingsPageId.audio,
            onDispatched: onDismiss,
          );
        },
      ),
    );
  }
}

class _TrayHeader extends ConsumerWidget {
  const _TrayHeader({this.onDismiss});

  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.shellColors;
    final l10n = context.l10n;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.quickSettingsTitle,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'Denial OS',
                style: TextStyle(
                  color: colors.textTertiary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  height: 1.1,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
        _TrayHeaderActionButton(
          icon: Icons.settings_outlined,
          onPressed: () {
            launchSettingsPage(ref, context, null, onDispatched: onDismiss);
          },
        ),
        const SizedBox(width: 8),
        _TrayHeaderActionButton(
          icon: Icons.power_settings_new_rounded,
          onPressed: () {
            showPowerSessionSurface(ref);
            onDismiss?.call();
          },
        ),
        const SizedBox(width: 8),
        _TrayHeaderActionButton(
          icon: Icons.edit_rounded,
          onPressed: () {
            launchSettingsPage(
              ref,
              context,
              SettingsPageId.appearance,
              onDispatched: onDismiss,
            );
          },
        ),
      ],
    );
  }
}

class _TrayStatusChips extends ConsumerWidget {
  const _TrayStatusChips({this.onDismiss, this.onOpenOverview});

  final VoidCallback? onDismiss;
  final VoidCallback? onOpenOverview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;

    final network = ref.watch(networkConnectivityProvider);
    final networkSnapshot = network.snapshot;
    final isWifiConnected =
        networkSnapshot.wirelessEnabled &&
        (networkSnapshot.status == NetworkConnectivityStatus.online ||
            networkSnapshot.status == NetworkConnectivityStatus.captivePortal ||
            networkSnapshot.status == NetworkConnectivityStatus.local);
    final ssid = networkSnapshot.connectedNetwork?.ssid;

    final String networkLabel;
    final IconData networkIcon;
    if (isWifiConnected && ssid != null && ssid.isNotEmpty) {
      networkIcon = Icons.vpn_key_rounded;
      networkLabel = l10n.networkStatusConnectedTo(ssid);
    } else if (networkSnapshot.wirelessEnabled) {
      networkIcon = Icons.vpn_key_rounded;
      networkLabel = l10n.networkStatusSecured;
    } else {
      networkIcon = Icons.wifi_off_rounded;
      networkLabel = l10n.networkStatusDisconnected;
    }

    final activeAppsCount = ref.watch(
      desktopWorkspaceProvider.select((state) => state.placements.length),
    );

    final appsText = activeAppsCount == 1
        ? l10n.quickSettingsOneAppActive
        : l10n.quickSettingsAppsActive(activeAppsCount);

    return Row(
      children: [
        _TrayStatusChip(
          icon: networkIcon,
          label: networkLabel,
          onPressed: () {
            ref
                .read(shellSurfaceControllerProvider.notifier)
                .show(
                  keyName: 'wifi-details',
                  debugLabel: 'Wi-Fi details',
                  builder: (_, handle) =>
                      WifiDetailSurface(onClose: handle.close),
                );
          },
        ),
        const SizedBox(width: 8),
        _TrayStatusChip(
          icon: Icons.info_outline_rounded,
          label: appsText,
          onPressed: () {
            onOpenOverview?.call();
            onDismiss?.call();
          },
        ),
      ],
    );
  }
}

class _TrayHeaderActionButton extends StatelessWidget {
  const _TrayHeaderActionButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.shellColors;

    return ShellHoverPill(
      onTap: onPressed,
      width: 34,
      height: 34,
      color: colors.surfaceContainerHigh,
      hoverColor: colors.panelHighlight,
      border: Border.all(color: colors.hairlineSoft),
      child: Icon(icon, size: 18, color: colors.textPrimary),
    );
  }
}

class _TrayTrailingActionButton extends StatelessWidget {
  const _TrayTrailingActionButton({
    required this.icon,
    required this.onPressed,
  });

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.shellColors;

    return ShellHoverPill(
      onTap: onPressed,
      width: 36,
      height: 36,
      color: colors.surfaceContainerHighest,
      hoverColor: colors.panelHighlight,
      border: Border.all(color: colors.hairlineSoft),
      child: Icon(icon, size: 18, color: colors.textPrimary),
    );
  }
}

class _TrayStatusChip extends StatelessWidget {
  const _TrayStatusChip({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.shellColors;

    return Expanded(
      child: ShellHoverPill(
        onTap: onPressed,
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        color: colors.surfaceContainerHighest,
        hoverColor: colors.panelHighlight,
        border: Border.all(color: colors.hairlineSoft),
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            Icon(icon, size: 16, color: colors.textPrimary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ShellText.base.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: colors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
