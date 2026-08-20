import 'package:flutter/material.dart' show Icons, Tooltip;
import 'package:flutter/services.dart' show KeyDownEvent, LogicalKeyboardKey;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../desktop/desktop_workspace.dart';
import '../input/shell_interaction_registry.dart';
import '../localization/denial_localizations.dart';
import '../services/network_manager_service.dart';
import '../state/network_connectivity.dart';
import '../state/quick_settings.dart';
import '../state/system_status.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';
import '../wallpaper/state/wallpaper_accent.dart';
import '../widgets/shade/status_glyphs.dart';
import '../widgets/shell_cursor.dart';

/// The status icon cluster for the desktop system bar.
///
/// Follows the Windows 11 status cluster ordering (Network -> Volume -> Battery)
/// and integrates with the shell's reactive system providers. Icons reflect
/// live hardware states (Wi-Fi signal levels, mute state, battery charging)
/// with full accessibility semantics.
///
/// Clicking or keyboard-activating the cluster toggles the desktop control center
/// (dashboard). Visual feedback is provided on hover, press, active panel state,
/// and keyboard focus.
class DesktopStatusCluster extends ConsumerStatefulWidget {
  const DesktopStatusCluster({
    super.key,
    this.horizontal = true,
    this.color,
    this.onTap,
  });

  /// Whether the parent system bar is arranged horizontally.
  final bool horizontal;

  /// Optional foreground color override for glyphs. When null, defaults to
  /// [ShellColors.textPrimary].
  final Color? color;

  /// Callback invoked when the status cluster is tapped or activated.
  final VoidCallback? onTap;

  static const double _iconSize = 18.5;
  static const double _itemGap = 9.0;
  static const double _paddingHorizontal = 8.0;
  static const double _paddingVertical = 4.0;

  @override
  ConsumerState<DesktopStatusCluster> createState() =>
      _DesktopStatusClusterState();

  static IconData resolveNetworkIcon(NetworkConnectivityState state) =>
      _resolveNetworkIcon(state);

  static IconData resolveSignalStrengthIcon(int strength) =>
      _resolveSignalStrengthIcon(strength);

  static String resolveNetworkSemanticLabel(
    BuildContext context,
    NetworkConnectivityState state,
  ) => _resolveNetworkSemanticLabel(context, state);

  static IconData resolveVolumeIcon(double volume) =>
      _resolveVolumeIcon(volume);

  static String resolveVolumeSemanticLabel(
    BuildContext context,
    double volume,
  ) => _resolveVolumeSemanticLabel(context, volume);

  static IconData _resolveNetworkIcon(NetworkConnectivityState state) {
    if (state.initializing) {
      return Icons.wifi_find_rounded;
    }
    final snapshot = state.snapshot;
    if (!snapshot.serviceAvailable || !snapshot.wifiDeviceAvailable) {
      return Icons.signal_wifi_off_rounded;
    }
    if (!snapshot.wirelessHardwareEnabled || !snapshot.wirelessEnabled) {
      return Icons.wifi_off_rounded;
    }
    return switch (snapshot.status) {
      NetworkConnectivityStatus.online ||
      NetworkConnectivityStatus.limited ||
      NetworkConnectivityStatus.local ||
      NetworkConnectivityStatus.captivePortal =>
        snapshot.connectedNetwork != null
            ? _resolveSignalStrengthIcon(snapshot.connectedNetwork!.strength)
            : Icons.wifi_rounded,
      NetworkConnectivityStatus.connecting => Icons.wifi_find_rounded,
      NetworkConnectivityStatus.disabled => Icons.wifi_off_rounded,
      NetworkConnectivityStatus.disconnected ||
      NetworkConnectivityStatus.unavailable => Icons.signal_wifi_off_rounded,
    };
  }

  static IconData _resolveSignalStrengthIcon(int strength) {
    if (strength >= 70) {
      return Icons.wifi_rounded;
    }
    if (strength >= 40) {
      return Icons.network_wifi_2_bar_rounded;
    }
    if (strength > 0) {
      return Icons.network_wifi_1_bar_rounded;
    }
    return Icons.network_wifi_1_bar_rounded;
  }

  static String _resolveNetworkSemanticLabel(
    BuildContext context,
    NetworkConnectivityState state,
  ) {
    final l10n = context.l10n;
    if (state.initializing) {
      return l10n.statusNetworkConnecting;
    }
    final snapshot = state.snapshot;
    if (!snapshot.serviceAvailable || !snapshot.wifiDeviceAvailable) {
      return l10n.statusNetworkUnavailable;
    }
    if (!snapshot.wirelessHardwareEnabled || !snapshot.wirelessEnabled) {
      return l10n.statusNetworkDisabled;
    }
    final network = snapshot.connectedNetwork;
    return switch (snapshot.status) {
      NetworkConnectivityStatus.online ||
      NetworkConnectivityStatus.limited ||
      NetworkConnectivityStatus.local ||
      NetworkConnectivityStatus.captivePortal =>
        network != null
            ? (network.ssid.isNotEmpty
                  ? l10n.statusNetworkWifi(network.ssid, network.strength)
                  : l10n.statusNetworkOnline)
            : l10n.statusNetworkOnline,
      NetworkConnectivityStatus.connecting => l10n.statusNetworkConnecting,
      NetworkConnectivityStatus.disabled => l10n.statusNetworkDisabled,
      NetworkConnectivityStatus.disconnected => l10n.statusNetworkDisconnected,
      NetworkConnectivityStatus.unavailable => l10n.statusNetworkUnavailable,
    };
  }

  static IconData _resolveVolumeIcon(double volume) {
    if (volume <= 0.01) {
      return Icons.volume_off_rounded;
    }
    if (volume < 0.5) {
      return Icons.volume_down_rounded;
    }
    return Icons.volume_up_rounded;
  }

  static String _resolveVolumeSemanticLabel(
    BuildContext context,
    double volume,
  ) {
    if (volume <= 0.01) {
      return context.l10n.statusVolumeMuted;
    }
    return context.l10n.statusVolumeLevel((volume * 100).round());
  }
}

class _DesktopStatusClusterState extends ConsumerState<DesktopStatusCluster> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final networkState = ref.watch(networkConnectivityProvider);
    final volume = ref.watch(
      quickSettingsProvider.select((state) => state.volume),
    );
    final battery = ref.watch(batteryProvider);
    final accent = ref.watch(shellAccentProvider);
    final dashboardOpen = ref.watch(
      desktopWorkspaceProvider.select((state) => state.dashboardOpen),
    );

    final foreground = widget.color ?? ShellColors.textPrimary;
    final hasBattery = battery.capacity != null;

    final networkIcon = DesktopStatusCluster._resolveNetworkIcon(networkState);
    final networkLabel = DesktopStatusCluster._resolveNetworkSemanticLabel(
      context,
      networkState,
    );

    final volumeIcon = DesktopStatusCluster._resolveVolumeIcon(volume);
    final volumeLabel = DesktopStatusCluster._resolveVolumeSemanticLabel(
      context,
      volume,
    );

    final children = <Widget>[
      Semantics(
        label: networkLabel,
        child: Icon(
          networkIcon,
          size: DesktopStatusCluster._iconSize,
          color: foreground,
        ),
      ),
      SizedBox(
        width: widget.horizontal ? DesktopStatusCluster._itemGap : null,
        height: widget.horizontal ? null : DesktopStatusCluster._itemGap,
      ),
      Semantics(
        label: volumeLabel,
        child: Icon(
          volumeIcon,
          size: DesktopStatusCluster._iconSize,
          color: foreground,
        ),
      ),
      if (hasBattery) ...[
        SizedBox(
          width: widget.horizontal ? DesktopStatusCluster._itemGap : null,
          height: widget.horizontal ? null : DesktopStatusCluster._itemGap,
        ),
        Semantics(
          label: battery.charging
              ? context.l10n.statusBatteryLevelCharging(battery.capacity!)
              : context.l10n.statusBatteryLevel(battery.capacity!),
          child: BatteryIconMark(
            status: battery,
            scale: 1.0,
            color: widget.color,
          ),
        ),
      ],
      SizedBox(
        width: widget.horizontal ? DesktopStatusCluster._itemGap : null,
        height: widget.horizontal ? null : DesktopStatusCluster._itemGap,
      ),
      Icon(
        Icons.tune_rounded,
        size: DesktopStatusCluster._iconSize,
        color: foreground,
      ),
    ];

    Color pillColor;
    if (_pressed) {
      pillColor = accent.color.withValues(alpha: 0.28);
    } else if (dashboardOpen) {
      pillColor = accent.color.withValues(alpha: 0.20);
    } else if (_hovered) {
      pillColor = accent.color.withValues(alpha: 0.12);
    } else if (_focused) {
      pillColor = accent.color.withValues(alpha: 0.08);
    } else {
      pillColor = const Color(0x00000000);
    }

    final clusterSemanticLabel = dashboardOpen
        ? context.l10n.statusClusterCloseControlCenter
        : context.l10n.statusClusterOpenControlCenter;

    const borderRadius = BorderRadius.all(Radius.circular(999));

    return ShellInputRegion(
      debugLabel: 'Desktop status cluster',
      child: Semantics(
        button: true,
        label: clusterSemanticLabel,
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
          child: MouseRegion(
            cursor: ShellMouseCursors.link,
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() {
              _hovered = false;
              _pressed = false;
            }),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (_) => setState(() => _pressed = true),
              onTapUp: (_) => setState(() => _pressed = false),
              onTapCancel: () => setState(() => _pressed = false),
              onTap: widget.onTap,
              child: AnimatedContainer(
                duration: Motion.tile,
                curve: Curves.easeOut,
                padding: EdgeInsets.symmetric(
                  horizontal: widget.horizontal
                      ? DesktopStatusCluster._paddingHorizontal
                      : DesktopStatusCluster._paddingVertical,
                  vertical: widget.horizontal
                      ? DesktopStatusCluster._paddingVertical
                      : DesktopStatusCluster._paddingHorizontal,
                ),
                decoration: BoxDecoration(
                  color: pillColor,
                  borderRadius: borderRadius,
                  border: _focused
                      ? Border.all(
                          color: accent.color.withValues(alpha: 0.65),
                          width: 1.5,
                        )
                      : Border.all(color: const Color(0x00000000), width: 1.5),
                ),
                child: Tooltip(
                  message: clusterSemanticLabel,
                  waitDuration: const Duration(milliseconds: 400),
                  child: Flex(
                    direction: widget.horizontal
                        ? Axis.horizontal
                        : Axis.vertical,
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: children,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
