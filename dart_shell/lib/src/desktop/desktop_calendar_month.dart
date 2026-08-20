import 'package:flutter/material.dart' show Tooltip;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/date_symbols.dart';
import 'package:intl/intl.dart';

import '../localization/denial_localizations.dart';
import '../theme/motion.dart';
import '../theme/shell_theme.dart';
import '../theme/tokens.dart';

/// Represents a single day cell in the monthly calendar grid.
class CalendarMonthCell {
  const CalendarMonthCell({
    required this.date,
    required this.isCurrentMonth,
    this.isToday = false,
    this.isSelected = false,
  });

  final DateTime date;
  final bool isCurrentMonth;
  final bool isToday;
  final bool isSelected;
}

/// Computed calendar grid model for a given month and locale.
class CalendarMonthData {
  CalendarMonthData({
    required this.year,
    required this.month,
    required this.daysInMonth,
    required this.leadingDaysCount,
    required this.weekdayHeaders,
    required this.cells,
  });

  final int year;
  final int month;
  final int daysInMonth;
  final int leadingDaysCount;
  final List<String> weekdayHeaders;
  final List<CalendarMonthCell> cells;

  /// Returns total number of days in the specified year and month,
  /// accurately handling leap years and century boundaries.
  static int getDaysInMonth(int year, int month) =>
      DateTime(year, month + 1, 0).day;

  /// Computes the complete 42-cell (6 rows x 7 columns) calendar grid.
  static CalendarMonthData compute({
    required int year,
    required int month,
    String? locale,
    DateTime? today,
    DateTime? selectedDate,
  }) {
    final effectiveLocale = locale ?? Intl.getCurrentLocale();
    final dateSymbols = _resolveDateSymbols(effectiveLocale);

    // In intl DateSymbols: FIRSTDAYOFWEEK is 0 for Monday, 6 for Sunday, 5 for Saturday.
    final firstDayOfWeekIndex = dateSymbols.FIRSTDAYOFWEEK % 7;

    final daysInCurrentMonth = getDaysInMonth(year, month);
    final firstDayOfMonth = DateTime(year, month, 1);

    // DateTime.weekday: 1=Mon, 2=Tue, ..., 7=Sun.
    // Map to 0-indexed where 0=Mon, 1=Tue, ..., 6=Sun:
    final firstDayIsoZeroBased = (firstDayOfMonth.weekday - 1) % 7;
    final leadingDaysCount =
        (firstDayIsoZeroBased - firstDayOfWeekIndex + 7) % 7;

    // Weekday headers
    final weekdayHeaders = <String>[];
    for (var i = 0; i < 7; i++) {
      final weekdayIndex = (firstDayOfWeekIndex + i) % 7; // 0=Mon..6=Sun
      final header = _formatWeekdayHeader(effectiveLocale, weekdayIndex);
      weekdayHeaders.add(header);
    }

    final cells = <CalendarMonthCell>[];

    // Previous month trailing days
    final prevMonthDate = DateTime(year, month - 1, 1);
    final prevYear = prevMonthDate.year;
    final prevMonth = prevMonthDate.month;
    final daysInPrevMonth = getDaysInMonth(prevYear, prevMonth);

    for (var i = leadingDaysCount - 1; i >= 0; i--) {
      final day = daysInPrevMonth - i;
      final date = DateTime(prevYear, prevMonth, day);
      cells.add(
        CalendarMonthCell(
          date: date,
          isCurrentMonth: false,
          isToday: _isSameDay(date, today),
          isSelected: _isSameDay(date, selectedDate),
        ),
      );
    }

    // Current month days
    for (var day = 1; day <= daysInCurrentMonth; day++) {
      final date = DateTime(year, month, day);
      cells.add(
        CalendarMonthCell(
          date: date,
          isCurrentMonth: true,
          isToday: _isSameDay(date, today),
          isSelected: _isSameDay(date, selectedDate),
        ),
      );
    }

    // Next month leading days to complete 42 cells (6 rows * 7 columns)
    final nextMonthDate = DateTime(year, month + 1, 1);
    final nextYear = nextMonthDate.year;
    final nextMonth = nextMonthDate.month;
    var nextMonthDay = 1;

    while (cells.length < 42) {
      final date = DateTime(nextYear, nextMonth, nextMonthDay++);
      cells.add(
        CalendarMonthCell(
          date: date,
          isCurrentMonth: false,
          isToday: _isSameDay(date, today),
          isSelected: _isSameDay(date, selectedDate),
        ),
      );
    }

    return CalendarMonthData(
      year: year,
      month: month,
      daysInMonth: daysInCurrentMonth,
      leadingDaysCount: leadingDaysCount,
      weekdayHeaders: List<String>.unmodifiable(weekdayHeaders),
      cells: List<CalendarMonthCell>.unmodifiable(cells),
    );
  }

  static DateSymbols _resolveDateSymbols(String locale) {
    try {
      final symbolsMap = dateTimeSymbolMap();
      final normalized = Intl.canonicalizedLocale(locale);
      if (symbolsMap.containsKey(normalized)) {
        return symbolsMap[normalized] as DateSymbols;
      }
      final lang = normalized.split('_').first;
      if (symbolsMap.containsKey(lang)) {
        return symbolsMap[lang] as DateSymbols;
      }
      return (symbolsMap['en'] ?? symbolsMap['en_US']) as DateSymbols;
    } catch (_) {
      return DateFormat(null, locale).dateSymbols;
    }
  }

  static String _formatWeekdayHeader(String locale, int weekdayIndex) {
    final lang = locale.toLowerCase();
    if (lang.startsWith('zh')) {
      const zhWeekdays = ['一', '二', '三', '四', '五', '六', '日'];
      return zhWeekdays[weekdayIndex % 7];
    }
    const enWeekdays = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];
    return enWeekdays[weekdayIndex % 7];
  }

  static bool _isSameDay(DateTime a, DateTime? b) {
    if (b == null) return false;
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

/// Pure month view widget displaying weekday headers and the 7x6 day grid.
class DesktopCalendarMonthView extends StatelessWidget {
  const DesktopCalendarMonthView({
    super.key,
    required this.displayedMonth,
    this.today,
    this.selectedDate,
    this.onDateSelected,
    this.locale,
  });

  final DateTime displayedMonth;
  final DateTime? today;
  final DateTime? selectedDate;
  final ValueChanged<DateTime>? onDateSelected;
  final String? locale;

  static const double _cellGap = 3.0;

  @override
  Widget build(BuildContext context) {
    final effectiveToday = today ?? DateTime.now();
    final effectiveLocale =
        locale ?? Localizations.localeOf(context).toString();

    final data = CalendarMonthData.compute(
      year: displayedMonth.year,
      month: displayedMonth.month,
      locale: effectiveLocale,
      today: effectiveToday,
      selectedDate: selectedDate,
    );

    final theme = ShellTheme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Weekday header row
        Padding(
          padding: const EdgeInsets.only(bottom: 6.0),
          child: Row(
            children: [
              for (final header in data.weekdayHeaders)
                Expanded(
                  child: Center(
                    child: Text(
                      header,
                      style: ShellText.cardTitle.copyWith(
                        color: ShellColors.textSecondary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        // Day grid (6 rows of 7 cells)
        for (var row = 0; row < 6; row++) ...[
          if (row > 0) const SizedBox(height: _cellGap),
          Row(
            children: [
              for (var col = 0; col < 7; col++) ...[
                if (col > 0) const SizedBox(width: _cellGap),
                Expanded(
                  child: _CalendarDayCell(
                    cell: data.cells[row * 7 + col],
                    accentColor: theme.accent,
                    onTap: () =>
                        onDateSelected?.call(data.cells[row * 7 + col].date),
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

class _CalendarDayCell extends StatefulWidget {
  const _CalendarDayCell({
    required this.cell,
    required this.accentColor,
    required this.onTap,
  });

  final CalendarMonthCell cell;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  State<_CalendarDayCell> createState() => _CalendarDayCellState();
}

class _CalendarDayCellState extends State<_CalendarDayCell> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final cell = widget.cell;
    final isToday = cell.isToday;
    final isSelected = cell.isSelected;
    final isCurrentMonth = cell.isCurrentMonth;

    Color backgroundColor;
    Color textColor;
    Border? border;

    if (isToday) {
      backgroundColor = widget.accentColor;
      textColor = ShellColors.onAccent;
      if (isSelected) {
        border = Border.all(color: ShellColors.textPrimary, width: 2);
      }
    } else if (isSelected) {
      backgroundColor = widget.accentColor.withValues(alpha: 0.24);
      textColor = widget.accentColor;
      border = Border.all(color: widget.accentColor, width: 1.5);
    } else if (_pressed) {
      backgroundColor = ShellColors.surfaceContainerHigh;
      textColor = isCurrentMonth
          ? ShellColors.textPrimary
          : ShellColors.textSecondary.withValues(alpha: 0.4);
    } else if (_hovered || _focused) {
      backgroundColor = ShellColors.surfaceContainer;
      textColor = isCurrentMonth
          ? ShellColors.textPrimary
          : ShellColors.textSecondary.withValues(alpha: 0.6);
      if (_focused) {
        border = Border.all(color: widget.accentColor, width: 1.5);
      }
    } else {
      backgroundColor = const Color(0x00000000);
      textColor = isCurrentMonth
          ? ShellColors.textPrimary
          : ShellColors.textSecondary.withValues(alpha: 0.35);
    }

    final dateStr =
        '${cell.date.year}-${cell.date.month.toString().padLeft(2, '0')}-${cell.date.day.toString().padLeft(2, '0')}';
    final l10n = context.l10n;
    final tooltipMessage = isToday
        ? '$dateStr · ${l10n.desktopCalendarToday}'
        : dateStr;

    return Tooltip(
      message: tooltipMessage,
      waitDuration: const Duration(milliseconds: 600),
      child: Semantics(
        button: true,
        selected: isSelected,
        label: isToday ? '$dateStr, ${l10n.desktopCalendarToday}' : dateStr,
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
                height: 34,
                decoration: BoxDecoration(
                  color: backgroundColor,
                  borderRadius: BorderRadius.circular(17),
                  border: border,
                ),
                alignment: Alignment.center,
                child: Text(
                  cell.date.day.toString(),
                  style: ShellText.systemBarValue.copyWith(
                    color: textColor,
                    fontSize: 13,
                    fontWeight: isToday || isSelected
                        ? FontWeight.w700
                        : FontWeight.normal,
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
