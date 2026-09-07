import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../localization/denial_localizations.dart';
import '../../../../models/desktop_notification.dart';
import '../../../../state/desktop_notifications.dart';
import '../../../../theme/motion.dart';
import '../../../../theme/shell_theme.dart';
import '../../../../theme/tokens.dart';
import '../../../../widgets/notification_banner.dart';
import '../../../../widgets/notification_media.dart';

/// Notification center for the dashboard Info view. History is grouped by
/// application with collapsible groups, an elastic swipe-to-dismiss gesture,
/// a do-not-disturb capsule, and a clear-all action.
class DashboardNotificationList extends ConsumerWidget {
  const DashboardNotificationList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final isZh = Localizations.localeOf(context).languageCode == 'zh';

    final notificationState = ref.watch(
      desktopNotificationsProvider.select(
        (state) => (
          doNotDisturb: state.doNotDisturb,
          policyLoaded: state.policyLoaded,
          history: state.history,
        ),
      ),
    );
    final controller = ref.read(desktopNotificationsProvider.notifier);

    final groups = <String, List<DesktopNotificationRecord>>{};
    for (final record in notificationState.history) {
      final label = notificationAppName(record.notification, l10n);
      groups
          .putIfAbsent(label, () => <DesktopNotificationRecord>[])
          .add(record);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (groups.isEmpty)
          const _DashboardNotificationEmptyState()
        else
          for (final entry in groups.entries)
            RepaintBoundary(
              child: _NotificationGroupCard(
                key: ValueKey('dashboard-group-${entry.key}'),
                label: entry.key,
                records: entry.value,
                onDismissGroup: () {
                  for (final record in entry.value) {
                    controller.dismissFromHistory(record.notification.id);
                  }
                },
                onDismissRecord: controller.dismissFromHistory,
                onDefaultAction: (record) =>
                    controller.invokeDefaultAction(record.notification.id),
              ),
            ),
        const SizedBox(height: 10),
        _NotificationListStatusBar(
          doNotDisturb: notificationState.doNotDisturb,
          policyLoaded: notificationState.policyLoaded,
          count: notificationState.history.length,
          isZh: isZh,
          onToggleDoNotDisturb: controller.toggleDoNotDisturb,
          onClearAll: controller.clearAll,
        ),
      ],
    );
  }
}

class _NotificationGroupCard extends StatefulWidget {
  const _NotificationGroupCard({
    required this.label,
    required this.records,
    required this.onDismissGroup,
    required this.onDismissRecord,
    required this.onDefaultAction,
    super.key,
  });

  final String label;
  final List<DesktopNotificationRecord> records;
  final VoidCallback onDismissGroup;
  final ValueChanged<int> onDismissRecord;
  final ValueChanged<DesktopNotificationRecord> onDefaultAction;

  @override
  State<_NotificationGroupCard> createState() => _NotificationGroupCardState();
}

class _NotificationGroupCardState extends State<_NotificationGroupCard>
    with SingleTickerProviderStateMixin {
  static const double _dismissDistance = 96;
  static const double _dismissFlingVelocity = 700;

  bool _expanded = false;
  late final AnimationController _drag = AnimationController.unbounded(
    vsync: this,
  );

  @override
  void dispose() {
    _drag.dispose();
    super.dispose();
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    _drag.value += details.delta.dx;
  }

  void _handleDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0.0;
    if (_drag.value.abs() > _dismissDistance ||
        velocity.abs() > _dismissFlingVelocity) {
      // Removing the records unmounts this card in the same frame, so no
      // settle animation is scheduled afterwards.
      widget.onDismissGroup();
      _drag.value = 0;
    } else {
      springTo(
        _drag,
        0.0,
        velocity: velocity,
        spring: Motion.expressiveSpatialFast,
        telemetryLabel: 'dashboard_notification_group_settle',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = context.shellColors;
    final isZh = Localizations.localeOf(context).languageCode == 'zh';

    final latest = widget.records.first;
    final latestSummary = _latestSummary(latest.notification);
    final hasUnread = widget.records.any((record) => record.unread);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.panelColor(colors.surfaceContainer),
        borderRadius: theme.borderRadius(ShellShapeScale.large),
        border: Border.all(color: colors.hairlineSoft, width: 1.0),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnimatedBuilder(
            animation: _drag,
            builder: (context, child) => Transform.translate(
              offset: Offset(_drag.value, 0),
              child: child,
            ),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _expanded = !_expanded),
              onHorizontalDragUpdate: _handleDragUpdate,
              onHorizontalDragEnd: _handleDragEnd,
              child: SizedBox(
                height: 52,
                child: Row(
                  children: [
                    NotificationArtwork(
                      notification: latest.notification,
                      size: 38,
                      preferContentImage: false,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  widget.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: colors.textPrimary,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    decoration: TextDecoration.none,
                                  ),
                                ),
                              ),
                              if (hasUnread) ...[
                                const SizedBox(width: 6),
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: theme.accentPalette.primary,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const SizedBox.square(dimension: 6),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            latestSummary,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colors.textSecondary,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    _GroupCountCapsule(
                      label: _groupCountLabel(widget.records.length, isZh),
                      expanded: _expanded,
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: Motion.cardSettle,
            curve: Motion.standard,
            alignment: Alignment.topCenter,
            child: _expanded
                ? Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (
                          var index = 0;
                          index < widget.records.length;
                          index += 1
                        ) ...[
                          if (index > 0) const SizedBox(height: 6),
                          () {
                            final record = widget.records[index];
                            return NotificationCard(
                              key: ValueKey(
                                'dashboard-notification-${record.notification.id}',
                              ),
                              notification: record.notification,
                              compact: true,
                              onDismiss: () => widget.onDismissRecord(
                                record.notification.id,
                              ),
                              onDefaultAction: record.active
                                  ? () => widget.onDefaultAction(record)
                                  : null,
                            );
                          }(),
                        ],
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  String _latestSummary(DesktopNotification notification) {
    final body = plainNotificationBody(notification.body);
    if (body.isNotEmpty) {
      return body;
    }
    return notification.summary;
  }
}

String _groupCountLabel(int count, bool isZh) {
  if (isZh) {
    return '$count 条通知';
  }
  return count == 1 ? '1 notification' : '$count notifications';
}

class _GroupCountCapsule extends StatelessWidget {
  const _GroupCountCapsule({required this.label, required this.expanded});

  final String label;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = context.shellColors;

    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: theme.borderRadius(ShellShapeScale.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.none,
            ),
          ),
          const SizedBox(width: 2),
          AnimatedRotation(
            turns: expanded ? 0.5 : 0,
            duration: Motion.cardSettle,
            curve: Motion.standard,
            child: Icon(
              Icons.expand_more_rounded,
              size: 14,
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationListStatusBar extends StatelessWidget {
  const _NotificationListStatusBar({
    required this.doNotDisturb,
    required this.policyLoaded,
    required this.count,
    required this.isZh,
    required this.onToggleDoNotDisturb,
    required this.onClearAll,
  });

  final bool doNotDisturb;
  final bool policyLoaded;
  final int count;
  final bool isZh;
  final VoidCallback onToggleDoNotDisturb;
  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Row(
      children: [
        _DoNotDisturbCapsule(
          active: doNotDisturb,
          enabled: policyLoaded,
          isZh: isZh,
          semanticsLabel: doNotDisturb
              ? l10n.notificationsDisableDoNotDisturb
              : l10n.notificationsEnableDoNotDisturb,
          onToggle: onToggleDoNotDisturb,
        ),
        Expanded(
          child: Center(
            child: Text(
              _groupCountLabel(count, isZh),
              style: TextStyle(
                color: context.shellColors.textTertiary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ),
        _ClearAllButton(
          enabled: count > 0,
          semanticsLabel: l10n.notificationsClearAll,
          onPressed: onClearAll,
        ),
      ],
    );
  }
}

class _DoNotDisturbCapsule extends StatefulWidget {
  const _DoNotDisturbCapsule({
    required this.active,
    required this.enabled,
    required this.isZh,
    required this.semanticsLabel,
    required this.onToggle,
  });

  final bool active;
  final bool enabled;
  final bool isZh;
  final String semanticsLabel;
  final VoidCallback onToggle;

  @override
  State<_DoNotDisturbCapsule> createState() => _DoNotDisturbCapsuleState();
}

class _DoNotDisturbCapsuleState extends State<_DoNotDisturbCapsule> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = context.shellColors;

    final Color bg;
    final Color fg;
    if (!widget.enabled) {
      bg = colors.tileOff;
      fg = colors.glyphInactive;
    } else if (widget.active) {
      bg = theme.accentPalette.container;
      fg = theme.accentPalette.onContainer;
    } else {
      bg = _hovered ? colors.panelHighlight : colors.surfaceContainerHighest;
      fg = colors.textPrimary;
    }

    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: widget.semanticsLabel,
      child: MouseRegion(
        cursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.enabled ? widget.onToggle : null,
          child: AnimatedContainer(
            duration: Motion.pill,
            curve: Curves.easeOut,
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 11),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: theme.borderRadius(ShellShapeScale.full),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.active
                      ? Icons.notifications_off_rounded
                      : Icons.notifications_active_rounded,
                  size: 15,
                  color: fg,
                ),
                const SizedBox(width: 6),
                Text(
                  widget.isZh ? '勿扰' : 'DND',
                  style: TextStyle(
                    color: fg,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ClearAllButton extends StatefulWidget {
  const _ClearAllButton({
    required this.enabled,
    required this.semanticsLabel,
    required this.onPressed,
  });

  final bool enabled;
  final String semanticsLabel;
  final VoidCallback onPressed;

  @override
  State<_ClearAllButton> createState() => _ClearAllButtonState();
}

class _ClearAllButtonState extends State<_ClearAllButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = context.shellColors;

    final bg = !widget.enabled
        ? colors.tileOff
        : (_hovered ? colors.panelHighlight : colors.surfaceContainerHighest);
    final fg = widget.enabled ? colors.textPrimary : colors.glyphInactive;

    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: widget.semanticsLabel,
      child: MouseRegion(
        cursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.enabled ? widget.onPressed : null,
          child: AnimatedContainer(
            duration: Motion.pill,
            curve: Curves.easeOut,
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: theme.borderRadius(ShellShapeScale.full),
            ),
            child: Center(
              child: Icon(Icons.delete_sweep_rounded, size: 16, color: fg),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashboardNotificationEmptyState extends StatelessWidget {
  const _DashboardNotificationEmptyState();

  @override
  Widget build(BuildContext context) {
    final colors = context.shellColors;
    final l10n = context.l10n;

    return Semantics(
      label: l10n.notificationsNone,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 26),
        decoration: BoxDecoration(
          color: context.shellTheme.panelColor(colors.surfaceContainer),
          borderRadius: context.shellTheme.borderRadius(ShellShapeScale.large),
          border: Border.all(color: colors.hairlineSoft, width: 1.0),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.notifications_none_rounded,
                size: 32,
                color: colors.textTertiary,
              ),
              const SizedBox(height: 8),
              Text(
                l10n.notificationsAllQuiet,
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                l10n.notificationsEmptyDescription,
                style: TextStyle(
                  color: colors.textTertiary,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
