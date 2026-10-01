import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/core/utils/date_parser.dart';

void main() {
  group('ReceiptDateParser.parse', () {
    test('reads ISO-8601 and year-first dates', () {
      expect(ReceiptDateParser.parse('2024-01-15'), DateTime(2024, 1, 15));
      expect(ReceiptDateParser.parse('2024-01-15T18:22:00Z'), DateTime(2024, 1, 15));
      expect(ReceiptDateParser.parse('2024/1/5'), DateTime(2024, 1, 5));
      expect(ReceiptDateParser.parse('2024.01.15'), DateTime(2024, 1, 15));
    });

    test('reads day-first dates, and month-first only when unambiguous', () {
      expect(ReceiptDateParser.parse('15/01/2024'), DateTime(2024, 1, 15));
      expect(ReceiptDateParser.parse('05.03.24'), DateTime(2024, 3, 5));
      expect(ReceiptDateParser.parse('05-03-2024'), DateTime(2024, 3, 5));
      expect(ReceiptDateParser.parse('01/15/2024'), DateTime(2024, 1, 15));
    });

    test('rejects dates that do not exist and text that is not a date', () {
      expect(ReceiptDateParser.parse('31/02/2024'), isNull);
      expect(ReceiptDateParser.parse('2024-13-01'), isNull);
      expect(ReceiptDateParser.parse('2024-02-30'), isNull);
      expect(ReceiptDateParser.parse('13/13/2024'), isNull);
      expect(ReceiptDateParser.parse('1/2/345'), isNull);
      expect(ReceiptDateParser.parse('Total 12.50'), isNull);
      expect(ReceiptDateParser.parse(''), isNull);
      expect(ReceiptDateParser.parse(null), isNull);
    });
  });

  group('ReceiptDateParser.detectDayFirst', () {
    test('follows the unambiguous dates and reads ambiguous ones accordingly', () {
      expect(ReceiptDateParser.detectDayFirst(['03/04/2026', '25/04/2026']), isTrue);
      expect(ReceiptDateParser.detectDayFirst(['03/04/2026', '04/25/2026']), isFalse);
      expect(ReceiptDateParser.detectDayFirst(['03/04/2026', '2026-04-25', 'Coffee']), isNull);
      expect(ReceiptDateParser.parse('03/04/2026', dayFirst: false), DateTime(2026, 3, 4));
      expect(ReceiptDateParser.parse('25/04/2026', dayFirst: false), DateTime(2026, 4, 25));
    });
  });

  group('ReceiptDateParser.parsePurchaseDate', () {
    final now = DateTime(2026, 10, 1);

    test('rejects future dates and dates before 2000', () {
      expect(ReceiptDateParser.parsePurchaseDate('2026-10-01', now: now), DateTime(2026, 10, 1));
      expect(ReceiptDateParser.parsePurchaseDate('2026-10-02', now: now), DateTime(2026, 10, 2));
      expect(ReceiptDateParser.parsePurchaseDate('2026-10-05', now: now), isNull);
      expect(ReceiptDateParser.parsePurchaseDate('1999-12-31', now: now), isNull);
    });
  });
}
