import 'package:flutter/material.dart' show Colors, Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../localization/denial_localizations.dart';
import '../../../../state/system_status.dart';
import '../../../../theme/shell_theme.dart';
import '../../../../theme/tokens.dart';
import '../../../../widgets/shell_hover_pill.dart';

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

  // The 42-cell grid is cached and only rebuilt when one of its inputs
  // changes; the per-minute clock tick then costs nothing and hover lives
  // inside each cell, so neither rebuilds the whole grid.
  ({
    DateTime gridStart,
    DateTime today,
    DateTime selected,
    DateTime displayedMonth,
  })?
  _gridCacheKey;
  late List<Widget> _gridCache;

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

  @override
  Widget build(BuildContext context) {
    final colors = context.shellColors;
    final l10n = context.l10n;

    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final isLookingAtCurrentMonth =
        _displayedMonth.year == now.year && _displayedMonth.month == now.month;
    final isTodaySelected =
        _selectedDate.year == today.year &&
        _selectedDate.month == today.month &&
        _selectedDate.day == today.day;

    final monthTitle =
        '${localizedMonth(l10n, _displayedMonth.month)} ${_displayedMonth.year}';

    // Calendar grid arithmetic (Monday is index 1 in Dart DateTime). Day
    // offsets go through the DateTime constructor, never Duration math: a
    // 23- or 25-hour DST day would otherwise shift a cell's wall date.
    final firstDayOfMonth = DateTime(
      _displayedMonth.year,
      _displayedMonth.month,
      1,
    );
    final leadingOffset = firstDayOfMonth.weekday - 1;
    final gridStartDate = DateTime(
      _displayedMonth.year,
      _displayedMonth.month,
      1 - leadingOffset,
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
                  style: context.shellTheme.text.titleSmallEmphasized.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            if (!isLookingAtCurrentMonth || !isTodaySelected) ...[
              _CalendarTodayChip(
                label: l10n.commonToday,
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
                    localizedWeekdaySymbol(l10n, day),
                    style: context.shellTheme.text.labelMedium.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4.0),
        // 42-day calendar matrix (6 rows x 7 days).
        for (final row in _cachedGridRows(gridStartDate, today)) row,
      ],
    );
  }

  List<Widget> _cachedGridRows(DateTime gridStartDate, DateTime today) {
    final cacheKey = (
      gridStart: gridStartDate,
      today: today,
      selected: _selectedDate,
      displayedMonth: _displayedMonth,
    );
    if (_gridCacheKey == cacheKey) {
      return _gridCache;
    }

    DateTime cellAt(int index) => DateTime(
      gridStartDate.year,
      gridStartDate.month,
      gridStartDate.day + index,
    );

    // The selected day's whole week row rides on a continuous
    // primaryContainer band — the M3E "week pill" from the reference
    // calendar — instead of an isolated dot.
    // Located by wall-date comparison, not Duration math: a 23/25-hour DST
    // day inside the grid would skew a difference().inDays lookup.
    var selectedWeek = -1;
    for (var i = 0; i < 42; i++) {
      if (_sameMonth(cellAt(i), _selectedDate) &&
          cellAt(i).day == _selectedDate.day) {
        selectedWeek = i ~/ 7;
        break;
      }
    }

    final rows = <Widget>[
      for (int week = 0; week < 6; week++)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2.0),
          child: _WeekBandRow(
            highlighted: week == selectedWeek,
            child: Row(
              children: [
                for (int col = 0; col < 7; col++)
                  () {
                    final index = week * 7 + col;
                    final cellDate = cellAt(index);
                    return _CalendarDayCell(
                      key: ValueKey('calendar-cell-$gridStartDate-$index'),
                      cellDate: cellDate,
                      isCurrentMonth: _sameMonth(cellDate, _displayedMonth),
                      isToday:
                          _sameMonth(cellDate, today) &&
                          cellDate.day == today.day,
                      isSelected:
                          _sameMonth(cellDate, _selectedDate) &&
                          cellDate.day == _selectedDate.day,
                      onTap: () => _selectCell(gridStartDate, index),
                    );
                  }(),
              ],
            ),
          ),
        ),
    ];
    _gridCacheKey = cacheKey;
    _gridCache = rows;
    return rows;
  }

  void _selectCell(DateTime gridStartDate, int index) {
    setState(() {
      _selectedDate = DateTime(
        gridStartDate.year,
        gridStartDate.month,
        gridStartDate.day + index,
      );
      if (_selectedDate.month != _displayedMonth.month) {
        _displayedMonth = DateTime(_selectedDate.year, _selectedDate.month, 1);
      }
    });
  }

  static bool _sameMonth(DateTime date, DateTime month) =>
      date.year == month.year && date.month == month.month;
}

/// The week row carrying the selected date, drawn as a continuous
/// `primaryContainer` band behind the day cells.
class _WeekBandRow extends StatelessWidget {
  const _WeekBandRow({required this.highlighted, required this.child});

  final bool highlighted;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    if (!highlighted) {
      return child;
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.accentPalette.container,
        borderRadius: theme.borderRadius(ShellShapeScale.full),
      ),
      child: child,
    );
  }
}

/// One calendar day. Hover state is local so sweeping the grid repaints
/// single cells instead of the whole 42-cell matrix.
class _CalendarDayCell extends StatelessWidget {
  const _CalendarDayCell({
    required this.cellDate,
    required this.isCurrentMonth,
    required this.isToday,
    required this.isSelected,
    required this.onTap,
    super.key,
  });

  final DateTime cellDate;
  final bool isCurrentMonth;
  final bool isToday;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = context.shellColors;

    // The selected day is the filled dot on the week band; today drops to an
    // accent-colored label so the two never compete as twin solid circles.
    final Color bg = isSelected
        ? theme.accentPalette.primary
        : Colors.transparent;
    final Color hoverBg = isSelected
        ? theme.accentPalette.primary
        : colors.panelHighlight;

    return Expanded(
      child: Center(
        child: ShellHoverPill.builder(
          onTap: onTap,
          width: 32,
          height: 32,
          color: bg,
          hoverColor: hoverBg,
          childBuilder: (context, hovered, focused) {
            final Color fg;
            final FontWeight weight;
            if (isSelected) {
              fg = theme.accentPalette.onPrimary;
              weight = FontWeight.w700;
            } else if (isToday) {
              fg = theme.accentPalette.primary;
              weight = FontWeight.w700;
            } else if (hovered) {
              fg = colors.textPrimary;
              weight = FontWeight.w500;
            } else {
              fg = isCurrentMonth ? colors.textPrimary : colors.textTertiary;
              weight = isCurrentMonth ? FontWeight.w500 : FontWeight.w400;
            }
            return Text(
              '${cellDate.day}',
              style: theme.text.bodyMedium.copyWith(
                color: fg,
                fontWeight: weight,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CalendarTodayChip extends StatelessWidget {
  const _CalendarTodayChip({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = context.shellColors;

    return ShellHoverPill.builder(
      onTap: onPressed,
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      color: theme.accentPalette.container,
      hoverColor: colors.panelHighlight,
      childBuilder: (context, hovered, focused) => Text(
        label,
        style: theme.text.labelSmall.copyWith(
          color: hovered ? colors.textPrimary : theme.accentPalette.onContainer,
        ),
      ),
    );
  }
}

class _CalendarNavButton extends StatelessWidget {
  const _CalendarNavButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.shellColors;

    return ShellHoverPill.builder(
      onTap: onPressed,
      width: 28,
      height: 28,
      color: Colors.transparent,
      hoverColor: colors.panelHighlight,
      childBuilder: (context, hovered, focused) => Icon(
        icon,
        size: 18,
        color: hovered ? colors.textPrimary : colors.textSecondary,
      ),
    );
  }
}
