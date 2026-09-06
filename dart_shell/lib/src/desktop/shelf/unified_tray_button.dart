import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../localization/denial_localizations.dart';
import '../../services/network_backend.dart';
import '../../state/bluetooth.dart';
import '../../state/desktop_notifications.dart';
import '../../state/network_connectivity.dart';
import '../../state/system_status.dart';
import '../../theme/motion.dart';
import '../../theme/shell_theme.dart';
import '../../theme/tokens.dart';

/// The aggregated tray button on the right edge of the shelf.
class UnifiedTrayButton extends ConsumerStatefulWidget {
  const UnifiedTrayButton({
    required this.expanded,
    required this.onPressed,
    this.onClockPressed,
    super.key,
  });

  final bool expanded;
  final VoidCallback onPressed;
  final VoidCallback? onClockPressed;

  @override
  ConsumerState<UnifiedTrayButton> createState() => _UnifiedTrayButtonState();
}

class _UnifiedTrayButtonState extends ConsumerState<UnifiedTrayButton> {
  bool _statusHovered = false;
  bool _clockHovered = false;

  IconData _batteryIcon(int? capacity, bool charging) {
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

  IconData _networkIcon(NetworkSnapshot snapshot) {
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
  Widget build(BuildContext context) {
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

    // Both capsules idle on a solid accent container like the reference
    // design; hover keeps the shared panel highlight and no border is drawn.
    final statusBgColor = _statusHovered
        ? colors.panelHighlight
        : theme.accentPalette.container;

    final statusFgColor = _statusHovered
        ? colors.textPrimary
        : theme.accentPalette.onContainer;

    final clockBgColor = _clockHovered
        ? colors.panelHighlight
        : theme.accentPalette.container;

    final clockFgColor = _clockHovered
        ? colors.textPrimary
        : theme.accentPalette.onContainer;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _statusHovered = true),
          onExit: (_) => setState(() => _statusHovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onPressed,
            child: AnimatedContainer(
              duration: Motion.pill,
              curve: Curves.easeOut,
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: statusBgColor,
                borderRadius: theme.borderRadius(ShellShapeScale.full),
              ),
              child: Row(
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
                          borderRadius: theme.borderRadius(
                            ShellShapeScale.full,
                          ),
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
              ),
            ),
          ),
        ),
        const SizedBox(width: 8.0),
        MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _clockHovered = true),
          onExit: (_) => setState(() => _clockHovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onClockPressed ?? widget.onPressed,
            child: AnimatedContainer(
              duration: Motion.pill,
              curve: Curves.easeOut,
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: clockBgColor,
                borderRadius: theme.borderRadius(ShellShapeScale.full),
              ),
              child: Center(
                child: Text(
                  time,
                  style: ShellText.trayClock.copyWith(
                    color: clockFgColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
