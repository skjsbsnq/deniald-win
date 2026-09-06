import 'dart:math' as math;

import 'package:flutter/material.dart' show Colors, Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../localization/denial_localizations.dart';
import '../../state/system_status.dart';
import '../../theme/motion.dart';
import '../../theme/shell_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/shell_backdrop_blur.dart';

/// The popup calendar bubble originating from the clock capsule on the shelf.
class UnifiedCalendarBubble extends ConsumerStatefulWidget {
  const UnifiedCalendarBubble({
    required this.visible,
    this.onDismiss,
    this.shelfHeight = 56.0,
    super.key,
  });

  final bool visible;
  final VoidCallback? onDismiss;
  final double shelfHeight;

  @override
  ConsumerState<UnifiedCalendarBubble> createState() =>
      _UnifiedCalendarBubbleState();
}

class _UnifiedCalendarBubbleState extends ConsumerState<UnifiedCalendarBubble>
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
  void didUpdateWidget(covariant UnifiedCalendarBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible != widget.visible) {
      springTo(
        _controller,
        widget.visible ? 1.0 : 0.0,
        spring: Motion.expressiveSpatialDefault,
        telemetryLabel: 'calendar_bubble_toggle',
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
      builder: (context, child) {
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
        final bubbleWidth = math.min(size.width - 16.0, 360.0);

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
        );
      },
      child: RepaintBoundary(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: _CalendarBubbleContent(onDismiss: widget.onDismiss),
        ),
      ),
    );
  }
}

class _CalendarBubbleContent extends ConsumerStatefulWidget {
  const _CalendarBubbleContent({this.onDismiss});

  final VoidCallback? onDismiss;

  @override
  ConsumerState<_CalendarBubbleContent> createState() =>
      _CalendarBubbleContentState();
}

class _CalendarBubbleContentState
    extends ConsumerState<_CalendarBubbleContent> {
  late DateTime _displayedMonth;
  late DateTime _selectedDate;
  int? _hoveredIndex;

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

  void _jumpToToday(DateTime now) {
    setState(() {
      _displayedMonth = DateTime(now.year, now.month, 1);
      _selectedDate = DateTime(now.year, now.month, now.day);
    });
  }

  String _weekdaySymbol(String name, bool isZh) {
    if (isZh) {
      if (name.startsWith('星期') && name.length >= 3) {
        return name.substring(2);
      }
      if (name.startsWith('周') && name.length >= 2) {
        return name.substring(1);
      }
    }
    return name.length >= 2 ? name.substring(0, 2) : name;
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = context.shellColors;
    final l10n = context.l10n;
    final isZh = Localizations.localeOf(context).languageCode == 'zh';

    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final timeStr = localizedTime(context, now);
    final dateStr = localizedLongDate(context, now);

    final isLookingAtCurrentMonth =
        _displayedMonth.year == now.year && _displayedMonth.month == now.month;
    final isTodaySelected =
        _selectedDate.year == today.year &&
        _selectedDate.month == today.month &&
        _selectedDate.day == today.day;

    final monthTitle = isZh
        ? '${_displayedMonth.year}年${_displayedMonth.month}月'
        : '${localizedMonth(l10n, _displayedMonth.month)} ${_displayedMonth.year}';

    // Calendar grid arithmetic (Monday is index 1 in Dart DateTime).
    final firstDayOfMonth = DateTime(
      _displayedMonth.year,
      _displayedMonth.month,
      1,
    );
    final leadingOffset = firstDayOfMonth.weekday - 1;
    final gridStartDate = firstDayOfMonth.subtract(
      Duration(days: leadingOffset),
    );

    // Weekday headers: Monday to Sunday (1 to 7).
    final weekdays = <int>[
      DateTime.monday,
      DateTime.tuesday,
      DateTime.wednesday,
      DateTime.thursday,
      DateTime.friday,
      DateTime.saturday,
      DateTime.sunday,
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header: current time, date, and jump-to-today chip.
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    timeStr,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    dateStr,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.1,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            ),
            if (!isLookingAtCurrentMonth || !isTodaySelected)
              _HeaderActionChip(
                label: isZh ? '今天' : 'Today',
                onPressed: () => _jumpToToday(now),
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12.0),
          child: Container(height: 1.0, color: colors.hairlineSoft),
        ),
        // Month / year navigation.
        Row(
          children: [
            Text(
              monthTitle,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                decoration: TextDecoration.none,
              ),
            ),
            const Spacer(),
            _CircleIconButton(
              icon: Icons.chevron_left_rounded,
              onPressed: _goToPreviousMonth,
            ),
            const SizedBox(width: 4),
            _CircleIconButton(
              icon: Icons.chevron_right_rounded,
              onPressed: _goToNextMonth,
            ),
          ],
        ),
        const SizedBox(height: 10.0),
        // Weekday header row.
        Row(
          children: [
            for (final day in weekdays)
              Expanded(
                child: Center(
                  child: Text(
                    _weekdaySymbol(localizedWeekday(l10n, day), isZh),
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6.0),
        // 42-day calendar matrix (6 rows x 7 days).
        for (int week = 0; week < 6; week++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2.0),
            child: Row(
              children: [
                for (int col = 0; col < 7; col++) ...[
                  () {
                    final index = week * 7 + col;
                    final cellDate = gridStartDate.add(Duration(days: index));
                    final isCurrentMonth =
                        cellDate.month == _displayedMonth.month;
                    final isCellToday =
                        cellDate.year == today.year &&
                        cellDate.month == today.month &&
                        cellDate.day == today.day;
                    final isCellSelected =
                        cellDate.year == _selectedDate.year &&
                        cellDate.month == _selectedDate.month &&
                        cellDate.day == _selectedDate.day;
                    final isHovered = _hoveredIndex == index;

                    Color bg;
                    Color fg;
                    FontWeight weight;

                    if (isCellToday) {
                      bg = theme.accentPalette.primary;
                      fg = theme.accentPalette.onPrimary;
                      weight = FontWeight.w700;
                    } else if (isCellSelected) {
                      bg = theme.accentPalette.container;
                      fg = theme.accentPalette.onContainer;
                      weight = FontWeight.w600;
                    } else if (isHovered) {
                      bg = colors.panelHighlight;
                      fg = colors.textPrimary;
                      weight = FontWeight.w500;
                    } else {
                      bg = Colors.transparent;
                      fg = isCurrentMonth
                          ? colors.textPrimary
                          : colors.textTertiary;
                      weight = isCurrentMonth
                          ? FontWeight.w500
                          : FontWeight.w400;
                    }

                    return Expanded(
                      child: Center(
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          onEnter: (_) => setState(() => _hoveredIndex = index),
                          onExit: (_) => setState(() => _hoveredIndex = null),
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              setState(() {
                                _selectedDate = cellDate;
                                if (cellDate.month != _displayedMonth.month) {
                                  _displayedMonth = DateTime(
                                    cellDate.year,
                                    cellDate.month,
                                    1,
                                  );
                                }
                              });
                            },
                            child: AnimatedContainer(
                              duration: Motion.pill,
                              curve: Curves.easeOut,
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: bg,
                                borderRadius: theme.borderRadius(
                                  ShellShapeScale.full,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  '${cellDate.day}',
                                  style: TextStyle(
                                    color: fg,
                                    fontSize: 13,
                                    fontWeight: weight,
                                    decoration: TextDecoration.none,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }(),
                ],
              ],
            ),
          ),
        const SizedBox(height: 12.0),
        // Selected day agenda summary card.
        _CalendarAgendaCard(
          selectedDate: _selectedDate,
          isToday: isTodaySelected,
          isZh: isZh,
        ),
      ],
    );
  }
}

class _HeaderActionChip extends StatefulWidget {
  const _HeaderActionChip({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  State<_HeaderActionChip> createState() => _HeaderActionChipState();
}

class _HeaderActionChipState extends State<_HeaderActionChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = context.shellColors;

    final bg = _hovered ? colors.panelHighlight : theme.accentPalette.container;
    final fg = _hovered ? colors.textPrimary : theme.accentPalette.onContainer;

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
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: theme.borderRadius(ShellShapeScale.full),
          ),
          child: Center(
            child: Text(
              widget.label,
              style: TextStyle(
                color: fg,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CircleIconButton extends StatefulWidget {
  const _CircleIconButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  State<_CircleIconButton> createState() => _CircleIconButtonState();
}

class _CircleIconButtonState extends State<_CircleIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = context.shellColors;

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
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: _hovered ? colors.panelHighlight : Colors.transparent,
            borderRadius: theme.borderRadius(ShellShapeScale.full),
          ),
          child: Center(
            child: Icon(
              widget.icon,
              size: 20,
              color: _hovered ? colors.textPrimary : colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _CalendarAgendaCard extends StatelessWidget {
  const _CalendarAgendaCard({
    required this.selectedDate,
    required this.isToday,
    required this.isZh,
  });

  final DateTime selectedDate;
  final bool isToday;
  final bool isZh;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = context.shellColors;
    final l10n = context.l10n;

    final dateTitle = isZh
        ? '${selectedDate.month}月${selectedDate.day}日${isToday ? ' · 今天' : ''}'
        : '${localizedMonth(l10n, selectedDate.month)} ${selectedDate.day}${isToday ? ' · Today' : ''}';

    final agendaSubtitle = isZh ? '暂无日程安排' : 'No upcoming events';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
      decoration: BoxDecoration(
        color: theme.panelColor(colors.surfaceContainer),
        borderRadius: theme.borderRadius(ShellShapeScale.large),
        border: Border.all(color: colors.hairlineSoft, width: 1.0),
      ),
      child: Row(
        children: [
          Icon(
            Icons.event_note_rounded,
            size: 22,
            color: theme.accentPalette.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  dateTitle,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.1,
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  agendaSubtitle,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    height: 1.1,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
