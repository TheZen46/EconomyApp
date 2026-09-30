import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/core/financial/invoice_aging_engine.dart';
import 'package:t_aidy/features/invoices/data/models/invoice_model.dart';

void main() {
  group('InvoiceAgingEngine Tests', () {
    final asOfDate = DateTime(2026, 4, 1);

    final testInvoices = [
      InvoiceModel(
        id: 'inv-1',
        invoiceNumber: 'INV-001',
        clientName: 'Alpha Corp',
        issuedDate: DateTime(2026, 3, 20), // 12 days old -> current
        dueDate: DateTime(2026, 4, 5),
        amount: 2500.0,
        status: InvoiceStatus.sent,
      ),
      InvoiceModel(
        id: 'inv-2',
        invoiceNumber: 'INV-002',
        clientName: 'Beta LLC',
        issuedDate: DateTime(2026, 2, 15), // 45 days old -> overdue30
        dueDate: DateTime(2026, 3, 1), // 31 days overdue
        amount: 1500.0,
        status: InvoiceStatus.sent,
      ),
      InvoiceModel(
        id: 'inv-3',
        invoiceNumber: 'INV-003',
        clientName: 'Gamma Systems',
        issuedDate: DateTime(2025, 12, 1), // 121 days old -> critical90
        dueDate: DateTime(2025, 12, 31), // 91 days overdue
        amount: 4000.0,
        status: InvoiceStatus.sent,
      ),
      InvoiceModel(
        id: 'inv-4',
        invoiceNumber: 'INV-004',
        clientName: 'Delta Media',
        issuedDate: DateTime(2026, 1, 10),
        dueDate: DateTime(2026, 1, 31),
        amount: 3000.0,
        status: InvoiceStatus.settled, // Paid -> should be ignored in aging report
      ),
    ];

    test('analyzes aging buckets and uncollected balances correctly', () {
      final report = InvoiceAgingEngine.analyzeInvoices(testInvoices, asOfDate: asOfDate);

      expect(report.totalUnpaidCount, 3);
      expect(report.totalOutstanding, 8000.0); // 2500 + 1500 + 4000
      expect(report.currentAmount, 2500.0);
      expect(report.overdue30Amount, 1500.0);
      expect(report.overdue60Amount, 0.0);
      expect(report.critical90Amount, 4000.0);
      expect(report.overdueCount, 2); // Beta & Gamma are past due
      expect(report.totalLateFeesAccrued, greaterThan(0.0));
    });

    test('generates tailored dunning reminders with correct amounts and late fees', () {
      final report = InvoiceAgingEngine.analyzeInvoices(testInvoices, asOfDate: asOfDate);
      final urgentItem = report.agingItems.firstWhere((i) => i.invoice.id == 'inv-3');

      final msg = InvoiceAgingEngine.generateDunningMessage(urgentItem);
      expect(msg.contains('URGENT'), true);
      expect(msg.contains('INV-003'), true);
      expect(msg.contains('Gamma Systems'), true);
      expect(msg.contains('4000.00'), true);
    });
  });
}
