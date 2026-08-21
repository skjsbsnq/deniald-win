import 'package:denial_dart_shell/src/desktop/desktop_calendar_month.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUp(CalendarMonthData.clearCacheForTesting);

  setUpAll(() async {
    await initializeDateFormatting('en', null);
    await initializeDateFormatting('zh', null);
  });

  group('CalendarMonthComputation', () {
    test('computes correct days in month for regular and leap years', () {
      // Leap year 2024
      expect(CalendarMonthData.getDaysInMonth(2024, 2), 29);
      // Non-leap year 2025
      expect(CalendarMonthData.getDaysInMonth(2025, 2), 28);
      // Century non-leap year 1900
      expect(CalendarMonthData.getDaysInMonth(1900, 2), 28);
      // 400-year leap year 2000
      expect(CalendarMonthData.getDaysInMonth(2000, 2), 29);

      // Other months
      expect(CalendarMonthData.getDaysInMonth(2026, 1), 31);
      expect(CalendarMonthData.getDaysInMonth(2026, 4), 30);
      expect(CalendarMonthData.getDaysInMonth(2026, 8), 31);
      expect(CalendarMonthData.getDaysInMonth(2026, 12), 31);
    });

    test(
      'computes correct leading empty slots and grid for en_US (Sunday first)',
      () {
        // August 2026: 2026-08-01 is Saturday (weekday = 6).
        // en_US first day of week is Sunday (FIRSTDAYOFWEEK = 6 in intl).
        // Sunday=0, Mon=1, Tue=2, Wed=3, Thu=4, Fri=5, Sat=6.
        // So Saturday is index 6. There should be 6 leading days from July.
        final monthData = CalendarMonthData.compute(
          year: 2026,
          month: 8,
          locale: 'en_US',
        );

        expect(monthData.year, 2026);
        expect(monthData.month, 8);
        expect(monthData.daysInMonth, 31);
        expect(monthData.leadingDaysCount, 6);
        expect(monthData.cells.length, 42); // 6 rows * 7 columns

        // First 6 cells are July 26..31
        expect(monthData.cells[0].date, DateTime(2026, 7, 26));
        expect(monthData.cells[0].isCurrentMonth, false);
        expect(monthData.cells[5].date, DateTime(2026, 7, 31));
        expect(monthData.cells[5].isCurrentMonth, false);

        // Cell 6 is Aug 1
        expect(monthData.cells[6].date, DateTime(2026, 8, 1));
        expect(monthData.cells[6].isCurrentMonth, true);

        // Cell 36 is Aug 31
        expect(monthData.cells[36].date, DateTime(2026, 8, 31));
        expect(monthData.cells[36].isCurrentMonth, true);

        // Cell 37 is Sep 1
        expect(monthData.cells[37].date, DateTime(2026, 9, 1));
        expect(monthData.cells[37].isCurrentMonth, false);
        // Cell 41 is Sep 5
        expect(monthData.cells[41].date, DateTime(2026, 9, 5));
        expect(monthData.cells[41].isCurrentMonth, false);
      },
    );

    test(
      'computes correct leading empty slots and grid for zh_CN (Monday first)',
      () {
        // August 2026: 2026-08-01 is Saturday.
        // zh_CN first day of week is Monday (FIRSTDAYOFWEEK = 0 in intl).
        // Mon=0, Tue=1, Wed=2, Thu=3, Fri=4, Sat=5, Sun=6.
        // So Saturday is index 5. There should be 5 leading days from July.
        final monthData = CalendarMonthData.compute(
          year: 2026,
          month: 8,
          locale: 'zh_CN',
        );

        expect(monthData.year, 2026);
        expect(monthData.month, 8);
        expect(monthData.daysInMonth, 31);
        expect(monthData.leadingDaysCount, 5);
        expect(monthData.cells.length, 42);

        // First 5 cells are July 27..31
        expect(monthData.cells[0].date, DateTime(2026, 7, 27));
        expect(monthData.cells[0].isCurrentMonth, false);
        expect(monthData.cells[4].date, DateTime(2026, 7, 31));
        expect(monthData.cells[4].isCurrentMonth, false);

        // Cell 5 is Aug 1
        expect(monthData.cells[5].date, DateTime(2026, 8, 1));
        expect(monthData.cells[5].isCurrentMonth, true);

        // Cell 35 is Aug 31
        expect(monthData.cells[35].date, DateTime(2026, 8, 31));
        expect(monthData.cells[35].isCurrentMonth, true);

        // Cell 36 is Sep 1
        expect(monthData.cells[36].date, DateTime(2026, 9, 1));
        expect(monthData.cells[36].isCurrentMonth, false);
      },
    );

    test('handles year rollover (Dec -> Jan, Jan -> Dec)', () {
      // December 2025 -> previous month is Nov 2025, next month is Jan 2026
      final decData = CalendarMonthData.compute(
        year: 2025,
        month: 12,
        locale: 'en_US',
      );
      expect(decData.cells.last.date.year, 2026);
      expect(decData.cells.last.date.month, 1);

      // January 2026 -> previous month is Dec 2025
      final janData = CalendarMonthData.compute(
        year: 2026,
        month: 1,
        locale: 'en_US',
      );
      expect(janData.cells.first.date.year, 2025);
      expect(janData.cells.first.date.month, 12);
    });

    test('produces correct weekday headers for both en and zh', () {
      final enData = CalendarMonthData.compute(
        year: 2026,
        month: 8,
        locale: 'en_US',
      );
      expect(enData.weekdayHeaders, ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa']);

      final zhData = CalendarMonthData.compute(
        year: 2026,
        month: 8,
        locale: 'zh_CN',
      );
      expect(zhData.weekdayHeaders, ['一', '二', '三', '四', '五', '六', '日']);
    });

    test('reuses entries with the same normalized day key', () {
      final first = CalendarMonthData.compute(
        year: 2026,
        month: 8,
        locale: 'zh_CN',
        today: DateTime(2026, 8, 21, 8),
        selectedDate: DateTime(2026, 8, 21, 9),
      );
      final second = CalendarMonthData.compute(
        year: 2026,
        month: 8,
        locale: 'zh_CN',
        today: DateTime(2026, 8, 21, 23),
        selectedDate: DateTime(2026, 8, 21, 1),
      );
      final changedSelection = CalendarMonthData.compute(
        year: 2026,
        month: 8,
        locale: 'zh_CN',
        today: DateTime(2026, 8, 21),
        selectedDate: DateTime(2026, 8, 22),
      );

      expect(identical(first, second), isTrue);
      expect(identical(first, changedSelection), isFalse);
    });
  });
}
