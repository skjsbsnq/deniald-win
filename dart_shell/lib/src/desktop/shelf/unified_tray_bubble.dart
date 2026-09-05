import 'dart:math' as math;

import 'package:flutter/material.dart' show Icons;
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
import '../../state/system_status.dart';
import '../../theme/motion.dart';
import '../../theme/shell_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/connectivity/bluetooth_detail_surface.dart';
import '../../widgets/connectivity/wifi_detail_surface.dart';
import '../../widgets/notification_banner.dart';
import '../../widgets/session/power_session_surface.dart';
import '../../widgets/shade/quick_settings_tiles.dart';
import '../../widgets/shade/range_bar.dart';
import '../../widgets/shell_backdrop_blur.dart';
import '../../widgets/shell_surface_host.dart';

/// The popup bubble originating from the unified tray on the shelf.
class UnifiedTrayBubble extends ConsumerStatefulWidget {
  const UnifiedTrayBubble({
    required this.visible,
    this.onDismiss,
    this.onOpenOverview,
    this.shelfHeight = 56.0,
    super.key,
  });

  final bool visible;
  final VoidCallback? onDismiss;
  final VoidCallback? onOpenOverview;
  final double shelfHeight;

  @override
  ConsumerState<UnifiedTrayBubble> createState() => _UnifiedTrayBubbleState();
}

class _UnifiedTrayBubbleState extends ConsumerState<UnifiedTrayBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController.unbounded(
      vsync: this,
      value: widget.visible ? 1.0 : 0.0,
    );
  }

  @override
  void didUpdateWidget(covariant UnifiedTrayBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible != widget.visible) {
      springTo(
        _controller,
        widget.visible ? 1.0 : 0.0,
        spring: Motion.expressiveSpatialDefault,
        telemetryLabel: 'tray_bubble_toggle',
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final progress = _controller.value;
        if (progress <= 0.001 && !widget.visible) {
          return const SizedBox.shrink();
        }

        final theme = context.shellTheme;
        final colors = context.shellColors;
        final size = MediaQuery.sizeOf(context);
        final clampedProgress = progress.clamp(0.0, 1.0);
        final scale = math.max(0.0, 0.88 + 0.12 * progress);
        final bubbleRadius = theme.borderRadius(ShellShapeScale.extraLarge);
        final bubbleWidth = math.min(size.width - 16.0, 420.0);

        return Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: widget.onDismiss,
              child: const SizedBox.expand(),
            ),
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
                        color: theme.panelColor(colors.surfaceContainerLow),
                        borderRadius: bubbleRadius,
                        border: Border.all(
                          color: colors.hairlineSoft.withValues(alpha: 0.70),
                          width: 1.0,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: _TrayBubbleContent(
                          onDismiss: widget.onDismiss,
                          onOpenOverview: widget.onOpenOverview,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TrayBubbleContent extends ConsumerWidget {
  const _TrayBubbleContent({this.onDismiss, this.onOpenOverview});

  final VoidCallback? onDismiss;
  final VoidCallback? onOpenOverview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.shellTheme;
    final colors = context.shellColors;
    final l10n = context.l10n;

    final quickSettings = ref.watch(
      quickSettingsProvider.select(
        (state) => (
          rotationLock: state.rotationLock,
          profile: state.profile,
          brightness: state.brightness,
          volume: state.volume,
        ),
      ),
    );
    final quickSettingsController = ref.read(quickSettingsProvider.notifier);

    final network = ref.watch(networkConnectivityProvider);
    final networkController = ref.read(networkConnectivityProvider.notifier);
    final bluetooth = ref.watch(bluetoothProvider);
    final bluetoothController = ref.read(bluetoothProvider.notifier);
    final notificationPolicy = ref.watch(
      desktopNotificationsProvider.select(
        (state) => (
          doNotDisturb: state.doNotDisturb,
          loaded: state.policyLoaded,
          history: state.history,
        ),
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

    final records = notificationPolicy.history;

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
          profile: quickSettings.profile,
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
        RangeBar(
          icon: Icons.brightness_6_rounded,
          value: quickSettings.brightness,
          activeColor: theme.accent,
          inactiveColor: colors.surfaceContainerHighest,
          onChanged: quickSettingsController.setBrightness,
          onChangeEnd: quickSettingsController.commitBrightness,
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
        ),
        const SizedBox(height: 8.0),
        RangeBar(
          icon: Icons.volume_up_rounded,
          value: quickSettings.volume,
          activeColor: theme.accent,
          inactiveColor: colors.surfaceContainerHighest,
          onChangeStart: quickSettingsController.beginVolumeInteraction,
          onChanged: quickSettingsController.setVolume,
          onChangeEnd: quickSettingsController.commitVolume,
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
        ),
        if (records.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12.0),
            child: Container(height: 1.0, color: colors.hairlineSoft),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 180.0),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: records.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8.0),
              itemBuilder: (context, index) {
                final record = records[index];
                return NotificationCard(
                  key: ValueKey('tray-notification-${record.notification.id}'),
                  notification: record.notification,
                  compact: true,
                  onDismiss: () => notificationController.dismissFromHistory(
                    record.notification.id,
                  ),
                  onDefaultAction: record.active
                      ? () => notificationController.invokeDefaultAction(
                          record.notification.id,
                        )
                      : null,
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

class _TrayHeader extends ConsumerWidget {
  const _TrayHeader({this.onDismiss});

  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.shellColors;
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    final title = isZh ? '操作面板' : 'Quick Settings';

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
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
    final isZh = Localizations.localeOf(context).languageCode == 'zh';

    final battery = ref.watch(batteryProvider);
    final capacity = battery.capacity;

    final String batteryText;
    final IconData batteryIcon;
    if (capacity != null) {
      if (battery.charging) {
        batteryIcon = Icons.battery_charging_full_rounded;
        batteryText = '$capacity% · ${l10n.batteryCharging}';
      } else if (battery.full || battery.acOnline) {
        batteryIcon = Icons.battery_full_rounded;
        batteryText = '$capacity% · ${l10n.batteryFullyCharged}';
      } else {
        batteryIcon = capacity >= 95
            ? Icons.battery_full_rounded
            : capacity >= 50
            ? Icons.battery_5_bar_rounded
            : capacity >= 20
            ? Icons.battery_2_bar_rounded
            : Icons.battery_alert_rounded;
        batteryText = '$capacity% · ${l10n.batteryDischarging}';
      }
    } else {
      batteryIcon = Icons.bolt_rounded;
      batteryText = isZh ? '交流电源已连接' : 'AC Power Connected';
    }

    final activeAppsCount = ref.watch(
      desktopWorkspaceProvider.select((state) => state.placements.length),
    );

    final appsText = activeAppsCount == 1
        ? l10n.quickSettingsOneAppActive
        : (isZh ? '$activeAppsCount 个活动应用' : '$activeAppsCount active apps');

    return Row(
      children: [
        _TrayStatusChip(
          icon: batteryIcon,
          label: batteryText,
          onPressed: () {
            launchSettingsPage(
              ref,
              context,
              SettingsPageId.power,
              onDispatched: onDismiss,
            );
          },
        ),
        const SizedBox(width: 8),
        _TrayStatusChip(
          icon: Icons.info_outline_rounded,
          label: appsText,
          onPressed: () {
            if (onOpenOverview != null) {
              onOpenOverview?.call();
            }
            onDismiss?.call();
          },
        ),
      ],
    );
  }
}

class _TrayHeaderActionButton extends StatefulWidget {
  const _TrayHeaderActionButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  State<_TrayHeaderActionButton> createState() =>
      _TrayHeaderActionButtonState();
}

class _TrayHeaderActionButtonState extends State<_TrayHeaderActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = context.shellColors;
    final radius = theme.borderRadius(ShellShapeScale.full);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: Motion.pill,
          curve: Curves.easeOut,
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: _hovered
                ? colors.panelHighlight
                : colors.surfaceContainerHigh,
            borderRadius: radius,
            border: Border.all(color: colors.hairlineSoft),
          ),
          child: Center(
            child: Icon(widget.icon, size: 18, color: colors.textPrimary),
          ),
        ),
      ),
    );
  }
}

class _TrayTrailingActionButton extends StatefulWidget {
  const _TrayTrailingActionButton({
    required this.icon,
    required this.onPressed,
  });

  final IconData icon;
  final VoidCallback onPressed;

  @override
  State<_TrayTrailingActionButton> createState() =>
      _TrayTrailingActionButtonState();
}

class _TrayTrailingActionButtonState extends State<_TrayTrailingActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = context.shellColors;
    final radius = theme.borderRadius(ShellShapeScale.full);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: Motion.pill,
          curve: Curves.easeOut,
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: _hovered
                ? colors.panelHighlight
                : colors.surfaceContainerHighest,
            borderRadius: radius,
            border: Border.all(color: colors.hairlineSoft),
          ),
          child: Center(
            child: Icon(widget.icon, size: 18, color: colors.textPrimary),
          ),
        ),
      ),
    );
  }
}

class _TrayStatusChip extends StatefulWidget {
  const _TrayStatusChip({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  State<_TrayStatusChip> createState() => _TrayStatusChipState();
}

class _TrayStatusChipState extends State<_TrayStatusChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = context.shellColors;
    final radius = theme.borderRadius(ShellShapeScale.full);

    return Expanded(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: Motion.pill,
            curve: Curves.easeOut,
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: _hovered
                  ? colors.panelHighlight
                  : colors.surfaceContainerHigh,
              borderRadius: radius,
              border: Border.all(color: colors.hairlineSoft),
            ),
            child: Row(
              children: [
                Icon(widget.icon, size: 16, color: colors.textPrimary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    widget.label,
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
        ),
      ),
    );
  }
}
