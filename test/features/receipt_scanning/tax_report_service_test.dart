import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/features/receipt_scanning/data/datasources/tax_report_service.dart';
import 'package:t_aidy/features/receipt_scanning/domain/entities/receipt.dart';

void main() {
  group('TaxReportService VAT & Tax Export Tests', () {
    final sampleReceipts = [
      Receipt(
        id: 'rec-vat-001',
        merchantName: 'Esselunga Supermercato',
        vatNumber: 'IT01234567890',
        date: DateTime(2026, 9, 10, 14, 0),
        totalAmount: 52.0,
        currency: 'EUR',
        items: const [
          // 4% basic food VAT
          ReceiptItem(
            description: 'Pane Fresco 1kg',
            unitPrice: 2.00,
            quantity: 1,
            totalPrice: 2.00,
            mainCategory: 'Fresh Produce',
            subCategory: 'Bread',
            necessity: ItemNecessity.essential,
          ),
          // 10% intermediate food VAT
          ReceiptItem(
            description: 'Petto di Pollo 500g',
            unitPrice: 10.00,
            quantity: 1,
            totalPrice: 10.00,
            mainCategory: 'Proteins & Dairy',
            subCategory: 'Poultry',
            necessity: ItemNecessity.essential,
          ),
          // 22% standard VAT
          ReceiptItem(
            description: 'Detersivo Lavatrice',
            unitPrice: 40.00,
            quantity: 1,
            totalPrice: 40.00,
            mainCategory: 'Household & Living',
            subCategory: 'Cleaning',
            necessity: ItemNecessity.essential,
          ),
        ],
      ),
      Receipt(
        id: 'rec-vat-002',
        merchantName: 'Farmacia Comunale',
        vatNumber: 'IT98765432100',
        date: DateTime(2026, 9, 12, 10, 30),
        totalAmount: 20.0,
        currency: 'EUR',
        items: const [
          // 10% health VAT
          ReceiptItem(
            description: 'Tachipirina 500mg',
            unitPrice: 20.00,
            quantity: 1,
            totalPrice: 20.00,
            mainCategory: 'Personal Care',
            subCategory: 'Health & Medicine',
            necessity: ItemNecessity.essential,
          ),
        ],
      ),
    ];

    test('generates accurate VAT brackets and taxable base calculations', () {
      final report = TaxReportService.generateTaxReport(
        receipts: sampleReceipts,
        startDate: DateTime(2026, 9, 1),
        endDate: DateTime(2026, 9, 30),
      );

      expect(report.totalReceipts, equals(2));
      expect(report.totalGrossAmount, equals(72.0)); // 2 + 10 + 40 + 20

      // Check brackets
      final rate4 = report.bracketSummaries.firstWhere((b) => b.ratePercentage == 4.0);
      expect(rate4.grossTotal, equals(2.00));
      expect(rate4.taxableBase, closeTo(2.00 / 1.04, 0.01));
      expect(rate4.vatAmount, closeTo(2.00 - (2.00 / 1.04), 0.01));

      final rate10 = report.bracketSummaries.firstWhere((b) => b.ratePercentage == 10.0);
      expect(rate10.grossTotal, equals(30.00)); // 10 + 20
      expect(rate10.taxableBase, closeTo(30.00 / 1.10, 0.01));
      expect(rate10.vatAmount, closeTo(30.00 - (30.00 / 1.10), 0.01));

      final rate22 = report.bracketSummaries.firstWhere((b) => b.ratePercentage == 22.0);
      expect(rate22.grossTotal, equals(40.00));
      expect(rate22.taxableBase, closeTo(40.00 / 1.22, 0.01));
      expect(rate22.vatAmount, closeTo(40.00 - (40.00 / 1.22), 0.01));

      expect(report.totalTaxableBase + report.totalVatAmount, closeTo(report.totalGrossAmount, 0.01));
    });

    test('exports formatted CSV report matching accounting standards', () {
      final report = TaxReportService.generateTaxReport(receipts: sampleReceipts);
      final csvString = TaxReportService.exportToCsv(report);

      expect(csvString, contains('tAIdy - Tax & VAT Summary Report'));
      expect(csvString, contains('=== VAT BRACKET SUMMARY ==='));
      expect(csvString, contains('4.0%'));
      expect(csvString, contains('10.0%'));
      expect(csvString, contains('22.0%'));
      expect(csvString, contains('=== ITEMIZED TRANSACTION LOG ==='));
      expect(csvString, contains('Esselunga Supermercato'));
      expect(csvString, contains('Farmacia Comunale'));
      expect(csvString, contains('IT01234567890'));
    });

    test('exports valid PDF document payload', () {
      final report = TaxReportService.generateTaxReport(receipts: sampleReceipts);
      final pdfBytes = TaxReportService.exportToPdfBytes(report);

      expect(pdfBytes, isNotEmpty);
      final pdfString = utf8.decode(pdfBytes, allowMalformed: true);
      expect(pdfString, startsWith('%PDF-1.4'));
      expect(pdfString, contains('tAIdy Tax & VAT Summary Report'));
      expect(pdfString, contains('%%EOF'));
    });
  });
}
