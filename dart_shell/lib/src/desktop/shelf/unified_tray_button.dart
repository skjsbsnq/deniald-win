import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../localization/denial_localizations.dart';
import '../../services/network_backend.dart';
import '../../state/bluetooth.dart';
import '../../state/desktop_notifications.dart';
import '../../state/network_connectivity.dart';
import '../../state/system_status.dart';
import '../../theme/shell_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/shell_hover_pill.dart';

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
    final theme = context.shellTheme;
    final colors = context.shellColors;
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
        ShellHoverPill.builder(
          onTap: onPressed,
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          // Both capsules idle on a solid accent container like the reference
          // design; when opened (expanded), the active capsule transitions to
          // the primary accent; hover keeps the shared panel highlight and no
          // border is drawn.
          color: expanded
              ? theme.accentPalette.primary
              : theme.accentPalette.container,
          hoverColor: expanded
              ? theme.accentPalette.primary
              : colors.panelHighlight,
          childBuilder: (context, hovered, focused) {
            final statusFgColor = expanded
                ? theme.accentPalette.onPrimary
                : (hovered
                      ? colors.textPrimary
                      : theme.accentPalette.onContainer);
            return Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (unreadCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: statusFgColor.withValues(alpha: 0.15),
                        borderRadius: theme.borderRadius(ShellShapeScale.full),
                      ),
                      child: Text(
                        unreadCount > 9 ? '9+' : '$unreadCount',
                        style: ShellText.base.copyWith(
                          color: statusFgColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                if (doNotDisturb)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(
                      Icons.do_not_disturb_on_rounded,
                      size: 16,
                      color: statusFgColor,
                    ),
                  ),
                if (bluetooth)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(
                      Icons.bluetooth_rounded,
                      size: 16,
                      color: statusFgColor,
                    ),
                  ),
                Icon(
                  _networkIcon(connectivity),
                  size: 16,
                  color: statusFgColor,
                ),
                if (hasBattery) ...[
                  const SizedBox(width: 6),
                  Icon(
                    _batteryIcon(capacity, battery.charging),
                    size: 16,
                    color: statusFgColor,
                  ),
                ],
              ],
            );
          },
        ),
        const SizedBox(width: 8.0),
        ShellHoverPill.builder(
          onTap: onClockPressed ?? onPressed,
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          color: clockExpanded
              ? theme.accentPalette.primary
              : theme.accentPalette.container,
          hoverColor: clockExpanded
              ? theme.accentPalette.primary
              : colors.panelHighlight,
          childBuilder: (context, hovered, focused) {
            final clockFgColor = clockExpanded
                ? theme.accentPalette.onPrimary
                : (hovered
                      ? colors.textPrimary
                      : theme.accentPalette.onContainer);
            return Center(
              child: Text(
                time,
                style: ShellText.trayClock.copyWith(
                  color: clockFgColor,
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
