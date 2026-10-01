import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/core/error/failures.dart';
import 'package:t_aidy/features/receipt_scanning/data/datasources/csv_parser_service.dart';
import 'package:t_aidy/features/receipt_scanning/domain/entities/receipt.dart';

void main() {
  late CsvParserService parser;

  setUp(() {
    parser = CsvParserService();
  });

  group('CsvParserService - Amount Parsing Edge Cases', () {
    test('parses single-digit dollar amounts (e.g. \$5, \$1)', () {
      const csv = '''Date,Description,Amount
2024-05-01,Coffee Shop,\$5
2024-05-02,Newspaper,\$1
''';
      final receipts = parser.parseBankCsv(csv);
      expect(receipts.length, 2);
      expect(receipts[0].totalAmount, 5.0);
      expect(receipts[1].totalAmount, 1.0);
    });

    test('parses negative single-digit amounts as positive expenditures', () {
      const csv = '''Date,Description,Amount
2024-05-01,Espresso,-\$5
2024-05-02,Tea,-3
''';
      final receipts = parser.parseBankCsv(csv);
      expect(receipts.length, 2);
      expect(receipts[0].totalAmount, 5.0);
      expect(receipts[1].totalAmount, 3.0);
    });

    test('parses standard decimal amounts with currency symbols and signs', () {
      const csv = '''Date,Description,Amount
2024-05-01,Supermarket,-\$125.75
2024-05-02,Bookstore,-\$42.00
2024-05-03,Bakery,-7.50
''';
      final receipts = parser.parseBankCsv(csv);
      expect(receipts.length, 3);
      expect(receipts[0].totalAmount, 125.75);
      expect(receipts[1].totalAmount, 42.00);
      expect(receipts[2].totalAmount, 7.50);
      expect(receipts[0].currency, 'USD');
    });
  });

  group('CsvParserService - Date Parsing Across Varying Formats', () {
    test('parses ISO format YYYY-MM-DD', () {
      const csv = '''Date,Description,Amount
2024-08-15,Grocery Store,\$50.00
''';
      final receipts = parser.parseBankCsv(csv);
      expect(receipts.length, 1);
      expect(receipts[0].date.year, 2024);
      expect(receipts[0].date.month, 8);
      expect(receipts[0].date.day, 15);
    });

    test('parses US format MM/DD/YYYY', () {
      const csv = '''Date,Description,Amount
08/15/2024,Tech Outlet,\$99.99
''';
      final receipts = parser.parseBankCsv(csv);
      expect(receipts.length, 1);
      expect(receipts[0].date.year, 2024);
      expect(receipts[0].date.month, 8);
      expect(receipts[0].date.day, 15);
    });

    test('parses slash format YYYY/MM/DD', () {
      const csv = '''Date,Description,Amount
2024/11/28,Department Store,\$210.00
''';
      final receipts = parser.parseBankCsv(csv);
      expect(receipts.length, 1);
      expect(receipts[0].date.year, 2024);
      expect(receipts[0].date.month, 11);
      expect(receipts[0].date.day, 28);
    });

    test('parses dot format YYYY.MM.DD', () {
      const csv = '''Date,Description,Amount
2024.04.10,Pharmacy,\$18.25
''';
      final receipts = parser.parseBankCsv(csv);
      expect(receipts.length, 1);
      expect(receipts[0].date.year, 2024);
      expect(receipts[0].date.month, 4);
      expect(receipts[0].date.day, 10);
    });

    test('parses dash format MM-DD-YYYY', () {
      const csv = '''Date,Description,Amount
06-21-2024,Gas Station,\$45.00
''';
      final receipts = parser.parseBankCsv(csv);
      expect(receipts.length, 1);
      expect(receipts[0].date.year, 2024);
      expect(receipts[0].date.month, 6);
      expect(receipts[0].date.day, 21);
    });

    test('parses international format DD/MM/YYYY without date rollover (e.g. 25/12/2024)', () {
      const csv = '''Date,Description,Amount
25/12/2024,Holiday Dinner,\$150.00
31/01/2024,New Year Party,\$80.00
''';
      final receipts = parser.parseBankCsv(csv);
      expect(receipts.length, 2);
      expect(receipts[0].date.year, 2024);
      expect(receipts[0].date.month, 12);
      expect(receipts[0].date.day, 25);
      expect(receipts[1].date.year, 2024);
      expect(receipts[1].date.month, 1);
      expect(receipts[1].date.day, 31);
    });
  });

  group('CsvParserService - General Behavior & Edge Cases', () {
    test('returns empty list for empty or header-only CSV', () {
      expect(parser.parseBankCsv(''), isEmpty);
      expect(parser.parseBankCsv('Date,Description,Amount\n'), isEmpty);
    });

    test('correctly maps merchant description and line items', () {
      const csv = '''Date,Merchant,Amount
2024-07-04,Starbucks Coffee,\$5.75
''';
      final receipts = parser.parseBankCsv(csv);
      expect(receipts.length, 1);
      expect(receipts[0].merchantName, contains('Starbucks'));
      expect(receipts[0].items.length, 1);
      expect(receipts[0].items.first.totalPrice, 5.75);
    });

    test('handles CRLF line endings', () {
      const csv = "Date,Description,Amount\r\n2024-01-15,Metro Pass,\$5\r\n2024-01-16,Lunch,\$12\r\n";
      final receipts = parser.parseBankCsv(csv);
      expect(receipts.length, 2);
      expect(receipts[0].totalAmount, 5.0);
      expect(receipts[1].totalAmount, 12.0);
    });
  });

  group('CsvParserService - importCsv Structured Reports & Line Validation', () {
    test('returns Left(CsvParsingFailure) on empty or whitespace-only CSV', () {
      final emptyResult = parser.importCsv('');
      expect(emptyResult.isLeft(), isTrue);
      expect(emptyResult.fold((f) => f, (r) => null), isA<CsvParsingFailure>());

      final whitespaceResult = parser.importCsv('   \n  \t  \n');
      expect(whitespaceResult.isLeft(), isTrue);
      expect(whitespaceResult.fold((f) => f, (r) => null), isA<CsvParsingFailure>());
    });

    test('returns structured report for clean batch with 100% success', () {
      const csv = '''Date,Description,Amount
2026-08-01,Groceries,\$84.50
2026-08-02,Gas Station,\$45.00
2026-08-03,Restaurant,\$62.30
''';

      final result = parser.importCsv(csv);
      expect(result.isRight(), isTrue);

      final report = result.getOrElse(() => const CsvImportReport(totalRows: 0, successfulReceipts: [], failedRows: []));
      expect(report.totalRows, 3);
      expect(report.successCount, 3);
      expect(report.failureCount, 0);
      expect(report.hasErrors, isFalse);
      expect(report.isFullSuccess, isTrue);
      expect(report.successfulReceipts.length, 3);
    });

    test('collects line-by-line validation errors without aborting valid rows in batch', () {
      const csv = '''Date,Description,Amount
2026-08-01,Valid Market,\$25.00
InvalidDateText,Broken Item,\$15.00
2026-08-03,No Amount Row,NotAnAmount
JustSomeRandomTextWithoutAnyColumns
2026-08-05,Second Valid Market,\$105.50
''';

      final result = parser.importCsv(csv);
      expect(result.isRight(), isTrue);

      final report = result.getOrElse(() => const CsvImportReport(totalRows: 0, successfulReceipts: [], failedRows: []));
      expect(report.totalRows, 5);
      expect(report.successCount, 2);
      expect(report.failureCount, 3);
      expect(report.hasErrors, isTrue);
      expect(report.isFullSuccess, isFalse);

      // Verify successful receipts
      expect(report.successfulReceipts[0].merchantName, contains('Valid Market'));
      expect(report.successfulReceipts[0].totalAmount, 25.00);
      expect(report.successfulReceipts[1].merchantName, contains('Second Valid Market'));
      expect(report.successfulReceipts[1].totalAmount, 105.50);

      // Verify line-by-line error reports
      expect(report.failedRows[0].lineNumber, 3);
      expect(report.failedRows[0].reason, contains('date'));

      expect(report.failedRows[1].lineNumber, 4);
      expect(report.failedRows[1].reason, contains('amount'));

      expect(report.failedRows[2].lineNumber, 5);
      expect(report.failedRows[2].reason, contains('Missing both'));
    });

    test('header row is identified and not counted as a failed row', () {
      const csv = '''Transaction Date,Merchant Details,Debit Amount,Account Balance
2026-08-10,Online Subscription,\$14.99,\$2,450.00
''';

      final result = parser.importCsv(csv);
      expect(result.isRight(), isTrue);

      final report = result.getOrElse(() => const CsvImportReport(totalRows: 0, successfulReceipts: [], failedRows: []));
      expect(report.totalRows, 1);
      expect(report.successCount, 1);
      expect(report.failureCount, 0);
    });
  });

  group('CsvParserService - European statements, direction, currency and duplicates', () {
    CsvImportReport report(String csv, {List<Receipt> existing = const []}) =>
        parser.importCsv(csv, existing: existing).getOrElse(() => throw StateError('import failed'));

    test('reads semicolon-separated files with decimal commas', () {
      const csv = '''Data;Descrizione;Importo
05/09/2026;Esselunga;-12,50
06/09/2026;Ikea;-1.234,56
07/09/2026;Bar;-0,90
08/09/2026;Ferramenta;-1.250
''';
      final r = report(csv);
      expect(r.failureCount, 0);
      expect(r.successfulReceipts.map((e) => e.totalAmount), [12.5, 1234.56, 0.9, 1250.0]);
      expect(r.successfulReceipts.first.date, DateTime(2026, 9, 5));
    });

    test('reads European amounts in quoted cells', () {
      const csv = '''Data,Descrizione,Importo
05/09/2026,Esselunga,"-12,50"
06/09/2026,Ikea,"-1.234,56"
07/09/2026,Bar,"-0,90"
08/09/2026,Ferramenta,"-1.250"
''';
      final r = report(csv);
      expect(r.failureCount, 0);
      expect(r.successfulReceipts.map((e) => e.totalAmount), [12.5, 1234.56, 0.9, 1250.0]);
    });

    test('a dot with three decimals follows the decimal point when the file uses one', () {
      const csv = '''Date,Description,Amount
2026-09-05,Hardware,-1.250
2026-09-06,Coffee,-3.75
''';
      expect(report(csv).successfulReceipts.first.totalAmount, 1.25);
    });

    test('ambiguous dates follow the unambiguous ones in the file', () {
      const dayFirst = '''Date,Description,Amount
03/04/2026,Pharmacy,-10
25/04/2026,Bakery,-5
''';
      expect(report(dayFirst).successfulReceipts.first.date, DateTime(2026, 4, 3));

      const monthFirst = '''Date,Description,Amount
03/04/2026,Pharmacy,-10
04/25/2026,Bakery,-5
''';
      expect(report(monthFirst).successfulReceipts.first.date, DateTime(2026, 3, 4));
    });

    test('dates that do not exist are rejected instead of rolling over', () {
      const csv = '''Date,Description,Amount
31/02/2026,Pharmacy,-10
''';
      final r = report(csv);
      expect(r.successCount, 0);
      expect(r.failedRows.single.reason, contains('date'));
    });

    test('incoming transactions are skipped, not imported as expenses', () {
      const csv = '''Date,Description,Amount
2026-09-01,Supermarket,-50.00
2026-09-02,Salary,2000.00
2026-09-03,Restaurant,-30.00
2026-09-04,Refund Shop,15.00
2026-09-05,Fuel,-60.00
''';
      final r = report(csv);
      expect(r.successfulReceipts.map((e) => e.merchantName), ['Supermarket', 'Restaurant', 'Fuel']);
      expect(r.skippedRows.map((e) => e.lineNumber), [3, 5]);
      expect(r.skippedRows.first.reason, contains('Incoming'));
    });

    test('explicit debit and credit columns are honoured', () {
      const csv = '''Data operazione,Descrizione,Addebiti,Accrediti,Saldo
01/09/2026,Supermercato,"45,20",,"1.954,80"
02/09/2026,Stipendio,,"2.000,00","3.954,80"
''';
      final r = report(csv);
      expect(r.successfulReceipts.single.totalAmount, 45.2);
      expect(r.successfulReceipts.single.merchantName, 'Supermercato');
      expect(r.skippedCount, 1);
    });

    test('the currency comes from a currency column or the amount, else EUR', () {
      const csv = '''Date,Description,Amount,Currency
2026-09-01,London Cafe,-4.50,GBP
2026-09-02,Shop,€ -9.99,
2026-09-03,Kiosk,-2.00,
''';
      final r = report(csv);
      expect(r.successfulReceipts.map((e) => e.currency), ['GBP', 'EUR', 'EUR']);
    });

    test('importing the same rows again skips them as duplicates', () {
      const csv = '''Date,Description,Amount
2026-09-01,Coffee,-2.00
2026-09-01,Coffee,-2.00
2026-09-02,Lunch,-12.00
''';
      final first = report(csv);
      expect(first.successCount, 3);

      // One of the two identical coffees was already imported.
      final second = report(csv, existing: first.successfulReceipts.take(1).toList());
      expect(second.successfulReceipts.map((e) => e.merchantName), ['Coffee', 'Lunch']);
      expect(second.skippedRows.single.reason, contains('Already imported'));

      final third = report(csv, existing: first.successfulReceipts);
      expect(third.successCount, 0);
      expect(third.skippedCount, 3);
    });

    test('text containing digits is not mistaken for an amount', () {
      const csv = '''2026-09-01,Pharmacy 24h,7-Eleven,-8.40
''';
      final r = report(csv);
      expect(r.successfulReceipts.single.totalAmount, 8.4);
      expect(r.successfulReceipts.single.merchantName, 'Pharmacy 24h 7-Eleven');
    });
  });
}
