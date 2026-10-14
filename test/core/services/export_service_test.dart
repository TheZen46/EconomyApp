import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/core/services/export_service.dart';
import 'package:t_aidy/features/receipt_scanning/domain/entities/receipt.dart';
import 'package:t_aidy/features/invoices/data/models/invoice_model.dart';

void main() {
  group('ExportService Tests', () {
    test('sanitizeCsvCell prepends single quote to formula injection triggers', () {
      // Equals
      expect(ExportService.sanitizeCsvCell('=1+1'), "'=1+1");
      expect(ExportService.sanitizeCsvCell('=cmd|\' /C calc\'!A0'), "'=cmd|' /C calc'!A0");

      // Plus
      expect(ExportService.sanitizeCsvCell('+123'), "'+123");

      // At symbol
      expect(ExportService.sanitizeCsvCell('@SUM(A1:B10)'), "'@SUM(A1:B10)");

      // Tab and carriage return
      expect(ExportService.sanitizeCsvCell('\ttext'), "'\ttext");
      expect(ExportService.sanitizeCsvCell('\rtext'), "'\rtext");

      // Minus followed by formula / text
      expect(ExportService.sanitizeCsvCell('-2+3+cmd|...'), "'-2+3+cmd|...");
    });

    test('sanitizeCsvCell preserves valid numbers and benign text', () {
      // Benign text
      expect(ExportService.sanitizeCsvCell('Apple Store'), 'Apple Store');
      expect(ExportService.sanitizeCsvCell('Consulting fee'), 'Consulting fee');

      // Valid negative numeric strings
      expect(ExportService.sanitizeCsvCell('-45.50'), '-45.50');
      expect(ExportService.sanitizeCsvCell('-100'), '-100');

      // Actual number types
      expect(ExportService.sanitizeCsvCell(123), 123);
      expect(ExportService.sanitizeCsvCell(-99.99), -99.99);
      expect(ExportService.sanitizeCsvCell(0.0), 0.0);

      // Empty string
      expect(ExportService.sanitizeCsvCell(''), '');
    });

    test('receiptsToCsv sanitizes cells to protect against spreadsheet formula injection', () {
      final receipt = Receipt(
        id: 'r-1',
        merchantName: '=cmd|\' /C calc\'!A0',
        date: DateTime(2026, 1, 15),
        totalAmount: 120.0,
        currency: 'EUR',
        items: [
          const ReceiptItem(
            description: '+123 Malicious Item',
            unitPrice: 120.0,
            quantity: 1,
            totalPrice: 120.0,
          ),
        ],
      );

      final csv = ExportService.receiptsToCsv([receipt]);
      expect(csv.contains("'+123 Malicious Item"), isTrue);
    });

    test('invoicesToCsv serializes invoice rows and sanitizes dangerous text', () {
      final invoice = InvoiceModel(
        id: 'inv-1',
        invoiceNumber: '@SUM(A1:B10)',
        clientName: 'ACME Corp',
        amount: 5000.0,
        status: InvoiceStatus.sent,
        issuedDate: DateTime(2026, 2, 1),
        notes: '-2+3+cmd|...',
      );

      final csv = ExportService.invoicesToCsv([invoice]);
      expect(csv.contains("'@SUM(A1:B10)"), isTrue);
      expect(csv.contains("ACME Corp"), isTrue);
      expect(csv.contains("5000"), isTrue);
      expect(csv.contains("'-2+3+cmd|..."), isTrue);
    });
  });
}
