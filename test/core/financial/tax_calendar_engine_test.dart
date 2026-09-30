import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/core/financial/tax_calendar_engine.dart';

void main() {
  group('TaxCalendarEngine Tests', () {
    final refDate = DateTime(2026, 3, 15);

    test('generates 4 quarterly estimated tax deadlines for USA jurisdiction', () {
      final calendar = TaxCalendarEngine.generateFiscalCalendar(
        year: 2026,
        jurisdiction: 'USA',
        annualLockedTaxReserve: 8000.0,
        referenceDate: refDate,
      );

      expect(calendar.length, 4);
      expect(calendar[0].title, 'IRS Q1 Estimated Tax Due');
      expect(calendar[0].dueDate, DateTime(2026, 4, 15));
      expect(calendar[0].estimatedPaymentAmount, 2000.0); // 8000 / 4
      expect(calendar[0].daysRemaining, inInclusiveRange(30, 31));
      expect(calendar[0].isOverdue, false);

      expect(calendar[1].title, 'IRS Q2 Estimated Tax Due');
      expect(calendar[1].dueDate, DateTime(2026, 6, 15));
    });

    test('generates valid iCalendar (.ics) export string with alarm triggers', () {
      final calendar = TaxCalendarEngine.generateFiscalCalendar(
        year: 2026,
        jurisdiction: 'USA',
        annualLockedTaxReserve: 8000.0,
        referenceDate: refDate,
      );

      final ics = calendar.first.toIcsFormat();
      expect(ics.contains('BEGIN:VCALENDAR'), true);
      expect(ics.contains('BEGIN:VEVENT'), true);
      expect(ics.contains('SUMMARY:IRS Q1 Estimated Tax Due'), true);
      expect(ics.contains('TRIGGER:-P7D'), true);
      expect(ics.contains('END:VCALENDAR'), true);
    });

    test('generates UK HMRC Self Assessment schedule', () {
      final calendar = TaxCalendarEngine.generateFiscalCalendar(
        year: 2026,
        jurisdiction: 'GBR',
        annualLockedTaxReserve: 6000.0,
        referenceDate: refDate,
      );

      expect(calendar.length, 2);
      expect(calendar.any((e) => e.title.contains('Payment on Account')), true);
    });
  });
}
