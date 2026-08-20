import 'dart:math' as math;

import 'package:flutter/material.dart' show Icons, Tooltip;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../l10n/generated/app_localizations.dart';
import '../localization/denial_localizations.dart';
import '../models/desktop_notification.dart';
import '../models/display_layout.dart';
import '../state/desktop_notifications.dart';
import '../state/system_status.dart';
import '../theme/motion.dart';
import '../theme/shell_theme.dart';
import '../theme/tokens.dart';
import '../widgets/shell_surface_host.dart';
import 'desktop_calendar_month.dart';

/// Displays the transient desktop calendar popup panel.
///
/// Uses [shellSurfaceControllerProvider] to present a frosted panel anchored
/// beside the system bar clock, featuring a monthly calendar view and a
/// notification summary (Option C) with full keyboard, mouse, and touch interaction.
ShellSurfaceHandle showDesktopCalendarPanel({
  required WidgetRef ref,
  VoidCallback? onOpenNotifications,
  SystemBarSide side = SystemBarSide.bottom,
}) {
  return ref
      .read(shellSurfaceControllerProvider.notifier)
      .show(
        keyName: 'desktop-calendar-panel',
        debugLabel: 'Desktop calendar panel',
        barrierColor: const Color(0x00000000),
        dismissPolicy: ShellDismissPolicy.outsideTapAndEscape,
        transitionDuration: Motion.desktopPanelOpen,
        builder: (context, handle) => DesktopCalendarPanel(
          handle: handle,
          onClose: handle.close,
          onOpenNotifications: onOpenNotifications,
          side: side,
        ),
      );
}

/// The calendar and notification summary popup panel widget.
class DesktopCalendarPanel extends ConsumerStatefulWidget {
  const DesktopCalendarPanel({
    super.key,
    this.handle,
    this.onClose,
    this.onEnter,
    this.onExit,
    this.onOpenNotifications,
    this.side = SystemBarSide.bottom,
  });

  final ShellSurfaceHandle? handle;
  final VoidCallback? onClose;
  final VoidCallback? onEnter;
  final VoidCallback? onExit;
  final VoidCallback? onOpenNotifications;
  final SystemBarSide side;

  static const double panelWidth = 360.0;
  static const double panelHeight = 560.0;

  @override
  ConsumerState<DesktopCalendarPanel> createState() =>
      _DesktopCalendarPanelState();
}

class _DesktopCalendarPanelState extends ConsumerState<DesktopCalendarPanel> {
  late DateTime _displayedMonth;
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _displayedMonth = DateTime(now.year, now.month, 1);
    _selectedDate = DateTime(now.year, now.month, now.day);
  }

  void _goToPreviousMonth() {
    setState(() {
      _displayedMonth = DateTime(
        _displayedMonth.year,
        _displayedMonth.month - 1,
        1,
      );
    });
  }

  void _goToNextMonth() {
    setState(() {
      _displayedMonth = DateTime(
        _displayedMonth.year,
        _displayedMonth.month + 1,
        1,
      );
    });
  }

  void _goToToday(DateTime now) {
    setState(() {
      _displayedMonth = DateTime(now.year, now.month, 1);
      _selectedDate = DateTime(now.year, now.month, now.day);
    });
  }

  void _close() {
    widget.handle?.close();
    widget.onClose?.call();
  }

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final theme = ShellTheme.of(context);
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context).toString();

    final isDifferentMonth =
        _displayedMonth.year != now.year || _displayedMonth.month != now.month;

    return MouseRegion(
      onEnter: (_) {
        if (mounted) {
          widget.onEnter?.call();
        }
      },
      onExit: (_) {
        if (mounted) {
          widget.onExit?.call();
        }
      },
      child: FocusTraversalGroup(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.panelColor(ShellColors.panelBackground),
            borderRadius: BorderRadius.circular(theme.panelRadius),
            border: Border.all(color: ShellColors.hairline),
            boxShadow: const [
              BoxShadow(
                color: ShellColors.shadow,
                blurRadius: 36,
                spreadRadius: 3,
                offset: Offset(0, 16),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header: Time & Date display + Close button
                _PanelHeader(
                  now: now,
                  onClose: _close,
                  accentColor: theme.accent,
                  locale: locale,
                ),
                const SizedBox(height: 12),
                // Month navigation bar (Month name, Today button, Prev/Next buttons)
                _MonthNavigationBar(
                  displayedMonth: _displayedMonth,
                  showTodayButton: isDifferentMonth,
                  locale: locale,
                  l10n: l10n,
                  onPrevious: _goToPreviousMonth,
                  onNext: _goToNextMonth,
                  onToday: () => _goToToday(now),
                ),
                const SizedBox(height: 8),
                // Month calendar view
                DesktopCalendarMonthView(
                  displayedMonth: _displayedMonth,
                  today: now,
                  selectedDate: _selectedDate,
                  locale: locale,
                  onDateSelected: (date) {
                    setState(() {
                      _selectedDate = date;
                      if (date.year != _displayedMonth.year ||
                          date.month != _displayedMonth.month) {
                        _displayedMonth = DateTime(date.year, date.month, 1);
                      }
                    });
                  },
                ),
                const SizedBox(height: 10),
                Container(height: 1, color: ShellColors.hairlineSoft),
                const SizedBox(height: 10),
                // Notification summary (Option C)
                Expanded(
                  child: _NotificationSummarySection(
                    l10n: l10n,
                    onViewAll: () {
                      _close();
                      widget.onOpenNotifications?.call();
                    },
                    onClose: _close,
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

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({
    required this.now,
    required this.onClose,
    required this.accentColor,
    required this.locale,
  });

  final DateTime now;
  final VoidCallback onClose;
  final Color accentColor;
  final String locale;

  String _formatLongDate(DateTime date, String loc) {
    try {
      final formatter = DateFormat.yMMMMEEEEd(loc);
      return formatter.format(date);
    } catch (_) {
      return DateFormat.yMMMMEEEEd().format(date);
    }
  }

  @override
  Widget build(BuildContext context) {
    final timeStr = localizedTime(context, now);
    final dateStr = _formatLongDate(now, locale);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                timeStr,
                style: ShellText.statusClock.copyWith(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                dateStr,
                style: ShellText.cardTitle.copyWith(
                  color: accentColor,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        _PanelIconButton(
          icon: Icons.close_rounded,
          semanticLabel: context.l10n.notificationsCloseCenter,
          onTap: onClose,
        ),
      ],
    );
  }
}

class _MonthNavigationBar extends StatelessWidget {
  const _MonthNavigationBar({
    required this.displayedMonth,
    required this.showTodayButton,
    required this.locale,
    required this.l10n,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
  });

  final DateTime displayedMonth;
  final bool showTodayButton;
  final String locale;
  final AppLocalizations l10n;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToday;

  String _formatMonthYear(DateTime date, String loc) {
    try {
      return DateFormat.yMMMM(loc).format(date);
    } catch (_) {
      return DateFormat.yMMMM().format(date);
    }
  }

  @override
  Widget build(BuildContext context) {
    final monthYearText = _formatMonthYear(displayedMonth, locale);
    final theme = ShellTheme.of(context);

    return Row(
      children: [
        Expanded(
          child: Text(
            monthYearText,
            style: ShellText.cardTitle.copyWith(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: ShellColors.textPrimary,
            ),
          ),
        ),
        if (showTodayButton) ...[
          _PillButton(
            label: l10n.desktopCalendarToday,
            accentColor: theme.accent,
            onTap: onToday,
          ),
          const SizedBox(width: 4),
        ],
        _PanelIconButton(
          icon: Icons.keyboard_arrow_up_rounded,
          semanticLabel: l10n.desktopCalendarPreviousMonth,
          onTap: onPrevious,
        ),
        const SizedBox(width: 2),
        _PanelIconButton(
          icon: Icons.keyboard_arrow_down_rounded,
          semanticLabel: l10n.desktopCalendarNextMonth,
          onTap: onNext,
        ),
      ],
    );
  }
}

class _PillButton extends StatefulWidget {
  const _PillButton({
    required this.label,
    required this.accentColor,
    required this.onTap,
  });

  final String label;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  State<_PillButton> createState() => _PillButtonState();
}

class _PillButtonState extends State<_PillButton> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    Color bg = const Color(0x00000000);
    if (_pressed) {
      bg = widget.accentColor.withValues(alpha: 0.28);
    } else if (_hovered || _focused) {
      bg = widget.accentColor.withValues(alpha: 0.16);
    }

    return Semantics(
      button: true,
      label: widget.label,
      child: Focus(
        onFocusChange: (focused) => setState(() => _focused = focused),
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.enter ||
                  event.logicalKey == LogicalKeyboardKey.space)) {
            widget.onTap();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => setState(() => _pressed = true),
            onTapUp: (_) => setState(() => _pressed = false),
            onTapCancel: () => setState(() => _pressed = false),
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: Motion.pill,
              curve: Motion.standard,
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: _focused
                      ? widget.accentColor
                      : widget.accentColor.withValues(alpha: 0.4),
                  width: _focused ? 1.5 : 1.0,
                ),
              ),
              child: Text(
                widget.label,
                style: ShellText.cardTitle.copyWith(
                  color: widget.accentColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PanelIconButton extends StatefulWidget {
  const _PanelIconButton({
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  State<_PanelIconButton> createState() => _PanelIconButtonState();
}

class _PanelIconButtonState extends State<_PanelIconButton> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    Color bg = const Color(0x00000000);
    if (_pressed) {
      bg = ShellColors.surfaceContainerHighest;
    } else if (_hovered || _focused) {
      bg = ShellColors.surfaceContainerHigh;
    }

    final accent = ShellTheme.of(context).accent;

    return Tooltip(
      message: widget.semanticLabel,
      waitDuration: const Duration(milliseconds: 500),
      child: Semantics(
        button: true,
        label: widget.semanticLabel,
        child: Focus(
          onFocusChange: (focused) => setState(() => _focused = focused),
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                (event.logicalKey == LogicalKeyboardKey.enter ||
                    event.logicalKey == LogicalKeyboardKey.space)) {
              widget.onTap();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (_) => setState(() => _pressed = true),
              onTapUp: (_) => setState(() => _pressed = false),
              onTapCancel: () => setState(() => _pressed = false),
              onTap: widget.onTap,
              child: AnimatedContainer(
                duration: Motion.pill,
                curve: Motion.standard,
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(14),
                  border: _focused
                      ? Border.all(color: accent, width: 1.5)
                      : null,
                ),
                alignment: Alignment.center,
                child: Icon(
                  widget.icon,
                  size: 17,
                  color: ShellColors.textPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationSummarySection extends ConsumerWidget {
  const _NotificationSummarySection({
    required this.l10n,
    required this.onViewAll,
    this.onClose,
  });

  final AppLocalizations l10n;
  final VoidCallback onViewAll;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(desktopNotificationsProvider);
    final theme = ShellTheme.of(context);
    final history = state.history;
    final unreadCount = state.unreadCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Section header
        Row(
          children: [
            Icon(
              unreadCount > 0
                  ? Icons.notifications_active_rounded
                  : Icons.notifications_none_rounded,
              size: 16,
              color: unreadCount > 0 ? theme.accent : ShellColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                l10n.notificationsTitle,
                style: ShellText.cardTitle.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: ShellColors.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (unreadCount > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: theme.accent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  unreadCount.toString(),
                  style: ShellText.systemBarValue.copyWith(
                    color: ShellColors.onAccent,
                    fontSize: 10.5,
                  ),
                ),
              ),
            ],
            const Spacer(),
            _TextLinkButton(
              label: l10n.desktopCalendarViewAllNotifications,
              accentColor: theme.accent,
              onTap: onViewAll,
            ),
          ],
        ),
        const SizedBox(height: 6),
        // Snippet or empty state
        Expanded(
          child: history.isEmpty
              ? Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.notifications_off_outlined,
                        size: 16,
                        color: ShellColors.textTertiary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        l10n.desktopCalendarNoNotifications,
                        style: ShellText.systemBarCaption.copyWith(
                          color: ShellColors.textTertiary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  physics: const ClampingScrollPhysics(),
                  padding: EdgeInsets.zero,
                  itemCount: math.min(2, history.length),
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final record = history[index];
                    final notif = record.notification;
                    return _NotificationSummaryCard(
                      notification: notif,
                      onTap: () {
                        if (record.active) {
                          ref
                              .read(desktopNotificationsProvider.notifier)
                              .invokeDefaultAction(notif.id);
                        }
                        onClose?.call();
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _NotificationSummaryCard extends StatefulWidget {
  const _NotificationSummaryCard({
    required this.notification,
    required this.onTap,
  });

  final DesktopNotification notification;
  final VoidCallback onTap;

  @override
  State<_NotificationSummaryCard> createState() =>
      _NotificationSummaryCardState();
}

class _NotificationSummaryCardState extends State<_NotificationSummaryCard> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final notification = widget.notification;
    final accent = ShellTheme.of(context).accent;

    return Semantics(
      button: true,
      label:
          '${notification.appName}: ${notification.summary}. ${notification.body}',
      child: Focus(
        onFocusChange: (focused) => setState(() => _focused = focused),
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.enter ||
                  event.logicalKey == LogicalKeyboardKey.space)) {
            widget.onTap();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: _hovered || _focused
                    ? ShellColors.surfaceContainerHigh
                    : ShellColors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _focused ? accent : ShellColors.hairlineSoft,
                  width: _focused ? 1.5 : 1.0,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          notification.appName.isNotEmpty
                              ? notification.appName
                              : notification.summary,
                          style: ShellText.cardTitle.copyWith(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: ShellColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (notification.appName.isNotEmpty &&
                      notification.summary.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      notification.summary,
                      style: ShellText.systemBarCaption.copyWith(
                        fontSize: 11.5,
                        color: ShellColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (notification.body.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      notification.body,
                      style: ShellText.systemBarCaption.copyWith(
                        fontSize: 11,
                        color: ShellColors.textTertiary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TextLinkButton extends StatefulWidget {
  const _TextLinkButton({
    required this.label,
    required this.accentColor,
    required this.onTap,
  });

  final String label;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  State<_TextLinkButton> createState() => _TextLinkButtonState();
}

class _TextLinkButtonState extends State<_TextLinkButton> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.label,
      child: Focus(
        onFocusChange: (focused) => setState(() => _focused = focused),
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.enter ||
                  event.logicalKey == LogicalKeyboardKey.space)) {
            widget.onTap();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: _focused
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: widget.accentColor, width: 1.5),
                    )
                  : null,
              child: Text(
                widget.label,
                style: ShellText.cardTitle.copyWith(
                  color: _hovered || _focused
                      ? widget.accentColor
                      : ShellColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  decoration: _hovered || _focused
                      ? TextDecoration.underline
                      : TextDecoration.none,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
