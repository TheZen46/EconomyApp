import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/core/financial/salt_apportionment_engine.dart';
import 'package:t_aidy/features/invoices/data/models/invoice_model.dart';
import 'package:t_aidy/features/receipt_scanning/domain/entities/receipt.dart';

void main() {
  group('SaltApportionmentEngine Tests', () {
    test('accurately apportions multi-state revenue and calculates state tax liabilities', () {
      final sampleInvoices = [
        // California Client ($20,000)
        InvoiceModel(
          id: 'inv-ca',
          invoiceNumber: 'INV-CA-001',
          clientName: 'Tech Inc (CA)',
          amount: 20000.0,
          status: InvoiceStatus.settled,
          issuedDate: DateTime(2026, 2, 1),
        ),
        // New York Client ($15,000)
        InvoiceModel(
          id: 'inv-ny',
          invoiceNumber: 'INV-NY-001',
          clientName: 'Wall Street Media (NY)',
          amount: 15000.0,
          status: InvoiceStatus.settled,
          issuedDate: DateTime(2026, 3, 1),
        ),
        // Texas Client ($10,000) - No state income tax
        InvoiceModel(
          id: 'inv-tx',
          invoiceNumber: 'INV-TX-001',
          clientName: 'Austin Cloud Co (TX)',
          amount: 10000.0,
          status: InvoiceStatus.settled,
          issuedDate: DateTime(2026, 3, 15),
        ),
      ];

      final sampleReceipts = [
        Receipt(
          id: 'r-ca-1',
          merchantName: 'Apple Store SF',
          totalAmount: 2000.0,
          date: DateTime(2026, 2, 10),
          currency: 'USD',
          items: const [],
        ),
      ];

      final summary = SaltApportionmentEngine.calculateApportionment(
        invoices: sampleInvoices,
        receipts: sampleReceipts,
        primaryHomeState: 'CA',
        fiscalYear: 2026,
      );

      expect(summary.totalApportionedRevenue, 45000.0);
      expect(summary.primaryHomeState, 'CA');

      // Check California apportionment
      final caApportionment = summary.stateApportionments.firstWhere((a) => a.profile.stateCode == 'CA');
      expect(caApportionment.grossRevenue, 20000.0);
      expect(caApportionment.directExpenses, 2000.0);
      expect(caApportionment.apportionmentRatio, closeTo(20000 / 45000, 0.001));
      expect(caApportionment.filingRequired, true);

      // Check Texas apportionment (0% tax rate)
      final txApportionment = summary.stateApportionments.firstWhere((a) => a.profile.stateCode == 'TX');
      expect(txApportionment.grossRevenue, 10000.0);
      expect(txApportionment.estimatedStateTax, 0.0);

      // Check New York apportionment
      final nyApportionment = summary.stateApportionments.firstWhere((a) => a.profile.stateCode == 'NY');
      expect(nyApportionment.grossRevenue, 15000.0);
      expect(nyApportionment.filingRequired, true);

      // State returns should include California and New York
      expect(summary.requiredStateReturns.any((r) => r.contains('California')), true);
      expect(summary.requiredStateReturns.any((r) => r.contains('New York')), true);
    });

    test('supports explicit client state mapping overrides', () {
      final sampleInvoices = [
        InvoiceModel(
          id: 'inv-client1',
          invoiceNumber: 'INV-001',
          clientName: 'Global Design LLC',
          amount: 5000.0,
          status: InvoiceStatus.settled,
          issuedDate: DateTime(2026, 1, 15),
        ),
      ];

      final summary = SaltApportionmentEngine.calculateApportionment(
        invoices: sampleInvoices,
        receipts: const [],
        primaryHomeState: 'CA',
        fiscalYear: 2026,
        clientStateMapping: {'global design llc': 'CO'},
      );

      final coApportionment = summary.stateApportionments.firstWhere((a) => a.profile.stateCode == 'CO');
      expect(coApportionment.grossRevenue, 5000.0);
      expect(coApportionment.estimatedStateTax, closeTo(5000.0 * 0.044, 0.01));
    });
  });
}
