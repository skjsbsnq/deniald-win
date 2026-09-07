import 'package:flutter/material.dart' show Colors, Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../localization/denial_localizations.dart';
import '../../../../state/system_status.dart';
import '../../../../theme/motion.dart';
import '../../../../theme/shell_color_scheme.dart';
import '../../../../theme/shell_theme.dart';
import '../../../../theme/tokens.dart';

/// Month calendar for the dashboard tool drawer.
///
/// The grid state machine (Monday-first 42-cell layout, today badge,
/// selection, hover) is lifted from the shelf calendar bubble so both
/// surfaces stay visually identical.
class DrawerCalendarWidget extends ConsumerStatefulWidget {
  const DrawerCalendarWidget({super.key});

  @override
  ConsumerState<DrawerCalendarWidget> createState() =>
      _DrawerCalendarWidgetState();
}

class _DrawerCalendarWidgetState extends ConsumerState<DrawerCalendarWidget> {
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
        // Month / year navigation with the jump-to-today chip.
        Row(
          children: [
            _CalendarNavButton(
              icon: Icons.chevron_left_rounded,
              onPressed: _goToPreviousMonth,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Center(
                child: Text(
                  monthTitle,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ),
            if (!isLookingAtCurrentMonth || !isTodaySelected) ...[
              _CalendarTodayChip(
                label: isZh ? '今天' : 'Today',
                onPressed: () => _jumpToToday(now),
              ),
              const SizedBox(width: 4),
            ],
            _CalendarNavButton(
              icon: Icons.chevron_right_rounded,
              onPressed: _goToNextMonth,
            ),
          ],
        ),
        const SizedBox(height: 8.0),
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
        const SizedBox(height: 4.0),
        // 42-day calendar matrix (6 rows x 7 days).
        for (int week = 0; week < 6; week++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2.0),
            child: Row(
              children: [
                for (int col = 0; col < 7; col++)
                  _buildDayCell(
                    week * 7 + col,
                    gridStartDate,
                    today,
                    theme,
                    colors,
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildDayCell(
    int index,
    DateTime gridStartDate,
    DateTime today,
    ShellThemeData theme,
    ShellColorScheme colors,
  ) {
    final cellDate = gridStartDate.add(Duration(days: index));
    final isCurrentMonth = cellDate.month == _displayedMonth.month;
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
      fg = isCurrentMonth ? colors.textPrimary : colors.textTertiary;
      weight = isCurrentMonth ? FontWeight.w500 : FontWeight.w400;
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
                  _displayedMonth = DateTime(cellDate.year, cellDate.month, 1);
                }
              });
            },
            child: AnimatedContainer(
              duration: Motion.pill,
              curve: Curves.easeOut,
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: theme.borderRadius(ShellShapeScale.full),
              ),
              child: Center(
                child: Text(
                  '${cellDate.day}',
                  style: TextStyle(
                    color: fg,
                    fontSize: 12.5,
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
  }
}

class _CalendarTodayChip extends StatefulWidget {
  const _CalendarTodayChip({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  State<_CalendarTodayChip> createState() => _CalendarTodayChipState();
}

class _CalendarTodayChipState extends State<_CalendarTodayChip> {
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
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: theme.borderRadius(ShellShapeScale.full),
          ),
          child: Center(
            child: Text(
              widget.label,
              style: TextStyle(
                color: fg,
                fontSize: 11,
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

class _CalendarNavButton extends StatefulWidget {
  const _CalendarNavButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  State<_CalendarNavButton> createState() => _CalendarNavButtonState();
}

class _CalendarNavButtonState extends State<_CalendarNavButton> {
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
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: _hovered ? colors.panelHighlight : Colors.transparent,
            borderRadius: theme.borderRadius(ShellShapeScale.full),
          ),
          child: Center(
            child: Icon(
              widget.icon,
              size: 18,
              color: _hovered ? colors.textPrimary : colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
