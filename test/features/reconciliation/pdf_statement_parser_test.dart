import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/features/reconciliation/data/datasources/pdf_statement_parser.dart';

void main() {
  group('PdfStatementParser Tests', () {
    const sampleStatementText = '''
CHASE BANKING STATEMENT
Statement Period: 03/01/2026 to 03/31/2026
Page 1 of 2

03/05/2026 APPLE STORE ONLINE PURCHASE -1,299.00
03/12/2026 UBER TRIP SAN FRANCISCO -34.50
03/18/2026 STARBUCKS COFFEE CO -6.75
Mar 22, 2026 GITHUB SUBSCRIPTION -20.00
2026-03-25 AWS EMEA AMAZON WEB SERVICES -154.20

Total Debits: \$1,514.45
Balance Forward: \$8,450.00
''';

    test('extracts all debit transactions with dates, descriptions, and amounts from statement text', () {
      final transactions = PdfStatementParser.parsePdfText(sampleStatementText);

      expect(transactions.length, 5);

      // Check Apple Store line
      expect(transactions[0].description, 'APPLE STORE ONLINE PURCHASE');
      expect(transactions[0].amount, 1299.00);
      expect(transactions[0].date.year, 2026);
      expect(transactions[0].date.month, 3);
      expect(transactions[0].date.day, 5);

      // Check Uber
      expect(transactions[1].description, 'UBER TRIP SAN FRANCISCO');
      expect(transactions[1].amount, 34.50);

      // Check Starbucks
      expect(transactions[2].description, 'STARBUCKS COFFEE CO');
      expect(transactions[2].amount, 6.75);

      // Check Alpha Date (GitHub)
      expect(transactions[3].description, 'GITHUB SUBSCRIPTION');
      expect(transactions[3].amount, 20.00);
      expect(transactions[3].date.day, 22);

      // Check ISO Date (AWS)
      expect(transactions[4].description, 'AWS EMEA AMAZON WEB SERVICES');
      expect(transactions[4].amount, 154.20);
      expect(transactions[4].date.day, 25);
    });

    test('handles empty text gracefully', () {
      final res = PdfStatementParser.parsePdfText('');
      expect(res.isEmpty, true);
    });
  });
}
