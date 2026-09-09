import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../localization/denial_localizations.dart';
import '../../../../models/desktop_notification.dart';
import '../../../../state/desktop_notifications.dart';
import '../../../../theme/motion.dart';
import '../../../../theme/shell_theme.dart';
import '../../../../theme/tokens.dart';
import '../../../../widgets/shell_hover_pill.dart';
import '../../../../widgets/notification_banner.dart';
import '../../../../widgets/notification_media.dart';
import '../unified_dashboard_panel.dart';

/// Notification center for the dashboard Info view. History is grouped by
/// application with collapsible groups, an elastic swipe-to-dismiss gesture,
/// a do-not-disturb capsule, and a clear-all action.
class DashboardNotificationList extends ConsumerStatefulWidget {
  const DashboardNotificationList({super.key});

  @override
  ConsumerState<DashboardNotificationList> createState() =>
      _DashboardNotificationListState();
}

class _DashboardNotificationListState
    extends ConsumerState<DashboardNotificationList> {
  bool _markReadScheduled = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

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

    // Seeing the list consumes the unread markers, matching the classic
    // notification center: the badge clears the moment this page is shown.
    // The panel's closing spring keeps this subtree mounted briefly after it
    // stops being visible; notifications landing in that window must keep
    // their unread state for the shelf badge instead of being silently
    // consumed.
    final unreadCount = ref.watch(
      desktopNotificationsProvider.select((state) => state.unreadCount),
    );
    if (unreadCount > 0 &&
        DashboardPanelVisibility.of(context) &&
        !_markReadScheduled) {
      _markReadScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _markReadScheduled = false;
        if (mounted) {
          ref.read(desktopNotificationsProvider.notifier).markAllRead();
        }
      });
    }

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

  // Expanded groups render in chunks so a pathological group (a hundred
  // piled-up notifications from one app) inflates progressively instead of
  // materializing every card in one frame.
  static const int _expandedChunk = 25;

  bool _expanded = false;
  int _visibleCount = _expandedChunk;
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
    } else if (MediaQuery.disableAnimationsOf(context)) {
      // Reduce-motion users get the resting offset directly; the settle
      // spring is decorative overshoot.
      _drag.value = 0.0;
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
              onTap: () => setState(() {
                _expanded = !_expanded;
                if (_expanded) {
                  _visibleCount = _expandedChunk;
                }
              }),
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
                                    fontSize: 13,
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
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    _GroupCountCapsule(
                      label: widget.records.length == 1
                          ? context.l10n.notificationsOneNotification
                          : context.l10n.notificationsGroupCount(
                              widget.records.length,
                            ),
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
                          index < widget.records.length &&
                              index < _visibleCount;
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
                        if (widget.records.length > _visibleCount) ...[
                          const SizedBox(height: 6),
                          _ShowMoreCapsule(
                            label: context.l10n.notificationsShowAll(
                              widget.records.length,
                            ),
                            onPressed: () =>
                                setState(() => _visibleCount += _expandedChunk),
                          ),
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
              fontSize: 11,
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

/// Centered capsule that raises a capped group's visible card count.
class _ShowMoreCapsule extends StatelessWidget {
  const _ShowMoreCapsule({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.shellColors;

    return Center(
      child: ShellHoverPill(
        onTap: onPressed,
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        color: colors.surfaceContainerHighest,
        hoverColor: colors.panelHighlight,
        child: Text(
          label,
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }
}

class _NotificationListStatusBar extends StatelessWidget {
  const _NotificationListStatusBar({
    required this.doNotDisturb,
    required this.policyLoaded,
    required this.count,
    required this.onToggleDoNotDisturb,
    required this.onClearAll,
  });

  final bool doNotDisturb;
  final bool policyLoaded;
  final int count;
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
          semanticsLabel: doNotDisturb
              ? l10n.notificationsDisableDoNotDisturb
              : l10n.notificationsEnableDoNotDisturb,
          onToggle: onToggleDoNotDisturb,
        ),
        Expanded(
          child: Center(
            child: Text(
              count == 1
                  ? l10n.notificationsOneNotification
                  : l10n.notificationsGroupCount(count),
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

class _DoNotDisturbCapsule extends StatelessWidget {
  const _DoNotDisturbCapsule({
    required this.active,
    required this.enabled,
    required this.semanticsLabel,
    required this.onToggle,
  });

  final bool active;
  final bool enabled;
  final String semanticsLabel;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = context.shellColors;

    return ShellHoverPill.builder(
      onTap: onToggle,
      enabled: enabled,
      semanticLabel: semanticsLabel,
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 11),
      color: !enabled
          ? colors.tileOff
          : active
          ? theme.accentPalette.container
          : colors.surfaceContainerHighest,
      hoverColor: colors.panelHighlight,
      childBuilder: (context, hovered, focused) {
        final fg = !enabled
            ? colors.glyphInactive
            : active
            ? theme.accentPalette.onContainer
            : colors.textPrimary;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              active
                  ? Icons.notifications_off_rounded
                  : Icons.notifications_active_rounded,
              size: 15,
              color: fg,
            ),
            const SizedBox(width: 6),
            Text(
              context.l10n.notificationsDndShort,
              style: TextStyle(
                color: fg,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ClearAllButton extends StatelessWidget {
  const _ClearAllButton({
    required this.enabled,
    required this.semanticsLabel,
    required this.onPressed,
  });

  final bool enabled;
  final String semanticsLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.shellColors;

    return ShellHoverPill(
      onTap: onPressed,
      enabled: enabled,
      semanticLabel: semanticsLabel,
      width: 30,
      height: 30,
      color: enabled ? colors.surfaceContainerHighest : colors.tileOff,
      hoverColor: colors.panelHighlight,
      child: Icon(
        Icons.delete_sweep_rounded,
        size: 16,
        color: enabled ? colors.textPrimary : colors.glyphInactive,
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
                  fontSize: 13,
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
