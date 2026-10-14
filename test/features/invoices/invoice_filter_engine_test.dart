import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/features/invoices/data/models/invoice_model.dart';
import 'package:t_aidy/features/invoices/domain/invoice_filter_engine.dart';

void main() {
  group('InvoiceFilterEngine', () {
    final date = DateTime(2026, 9, 15);

    final invoices = [
      InvoiceModel(
        id: '1',
        invoiceNumber: 'INV-202609-0001',
        clientName: 'Acme Corp',
        amount: 1500.0,
        status: InvoiceStatus.sent,
        issuedDate: DateTime(2026, 9, 10),
      ),
      InvoiceModel(
        id: '2',
        invoiceNumber: 'INV-202609-0002',
        clientName: 'Globex Inc',
        amount: 2500.0,
        status: InvoiceStatus.settled,
        issuedDate: DateTime(2026, 9, 5),
      ),
      InvoiceModel(
        id: '3',
        invoiceNumber: 'INV-202608-0001',
        clientName: 'Wayne Enterprises',
        amount: 4000.0,
        status: InvoiceStatus.overdue,
        issuedDate: DateTime(2026, 8, 1),
      ),
      InvoiceModel(
        id: '4',
        invoiceNumber: 'INV-202607-0001',
        clientName: 'Stark Industries',
        amount: 500.0,
        status: InvoiceStatus.draft,
        issuedDate: DateTime(2026, 7, 20),
      ),
    ];

    test('filters by status correctly', () {
      final all = InvoiceFilterEngine.filterInvoices(invoices, statusFilter: 'All');
      expect(all.length, 4);

      final sent = InvoiceFilterEngine.filterInvoices(invoices, statusFilter: InvoiceStatus.sent);
      expect(sent.length, 1);
      expect(sent.first.id, '1');

      final overdue = InvoiceFilterEngine.filterInvoices(invoices, statusFilter: InvoiceStatus.overdue);
      expect(overdue.length, 1);
      expect(overdue.first.id, '3');
    });

    test('filters by search query matching client name or invoice number', () {
      final byClient = InvoiceFilterEngine.filterInvoices(invoices, searchQuery: 'wayne');
      expect(byClient.length, 1);
      expect(byClient.first.clientName, 'Wayne Enterprises');

      final byNumber = InvoiceFilterEngine.filterInvoices(invoices, searchQuery: '202608');
      expect(byNumber.length, 1);
      expect(byNumber.first.id, '3');

      final none = InvoiceFilterEngine.filterInvoices(invoices, searchQuery: 'nonexistent');
      expect(none.isEmpty, true);
    });

    test('computes monthly velocity for 6 trailing months', () {
      final velocity = InvoiceFilterEngine.computeMonthlyVelocity(
        invoices,
        asOfDate: date,
        monthCount: 6,
      );

      expect(velocity.length, 6);
      // Trailing 6 months end in September 2026
      final sep = velocity.last;
      expect(sep.month.month, 9);
      expect(sep.month.year, 2026);
      // In September: 1500 (sent) + 2500 (settled) = 4000 invoiced, 2500 settled
      expect(sep.invoicedAmount, 4000.0);
      expect(sep.settledAmount, 2500.0);

      // In August (month - 1): Wayne Enterprises (4000 overdue)
      final aug = velocity[4];
      expect(aug.month.month, 8);
      expect(aug.invoicedAmount, 4000.0);
      expect(aug.settledAmount, 0.0);
    });

    test('computes portfolio summary statistics accurately', () {
      final stats = InvoiceFilterEngine.computeSummaryStats(invoices);

      // Sent (1500) + Overdue (4000) = 5500
      expect(stats.totalOutstanding, 5500.0);
      expect(stats.totalOverdue, 4000.0);
      expect(stats.totalDraft, 500.0);
      expect(stats.awaitingCount, 2);
    });
  });
}
