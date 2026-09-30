import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/core/financial/consolidated_statement_service.dart';
import 'package:t_aidy/core/financial/mileage_engine.dart';
import 'package:t_aidy/core/services/audit_dossier_service.dart';
import 'package:t_aidy/features/boxes/data/models/box_model.dart';
import 'package:t_aidy/features/invoices/data/models/invoice_model.dart';
import 'package:t_aidy/features/receipt_scanning/domain/entities/receipt.dart';

void main() {
  group('ConsolidatedStatementService & Merkle Verifier Tests', () {
    test('generates consolidated statement and eliminates inter-entity transfers', () {
      final sampleBoxes = [
        BoxModel(
          id: 'box-consulting',
          name: 'Consulting Ops',
          budget: 20000.0,
          spent: 3000.0,
          currency: 'USD',
          color: 0xFF10B981,
        ),
        BoxModel(
          id: 'box-ecommerce',
          name: 'E-Commerce Store',
          budget: 15000.0,
          spent: 2000.0,
          currency: 'USD',
          color: 0xFF3B82F6,
        ),
      ];

      final sampleInvoices = [
        // External Client Revenue ($10,000)
        InvoiceModel(
          id: 'inv-ext',
          invoiceNumber: 'INV-001',
          clientName: 'External Client LLC',
          amount: 10000.0,
          status: InvoiceStatus.settled,
          issuedDate: DateTime(2026, 2, 1),
        ),
        // Inter-Entity Transfer: E-Commerce Store billed Consulting Ops for design ($2,000)
        InvoiceModel(
          id: 'inv-inter',
          invoiceNumber: 'INV-002',
          clientName: 'Consulting Ops',
          amount: 2000.0,
          status: InvoiceStatus.settled,
          issuedDate: DateTime(2026, 2, 15),
        ),
      ];

      final sampleReceipts = [
        // External Software Expense ($500)
        Receipt(
          id: 'r-ext',
          merchantName: 'AWS Cloud',
          totalAmount: 500.0,
          date: DateTime(2026, 2, 10),
          currency: 'USD',
          boxId: 'box-consulting',
          items: const [
            ReceiptItem(description: 'AWS Hosting', unitPrice: 500.0, quantity: 1, totalPrice: 500.0, mainCategory: 'Technology'),
          ],
        ),
        // Inter-Entity Expense Receipt ($2,000 paid to E-Commerce Store)
        Receipt(
          id: 'r-inter',
          merchantName: 'E-Commerce Store',
          totalAmount: 2000.0,
          date: DateTime(2026, 2, 16),
          currency: 'USD',
          boxId: 'box-consulting',
          items: const [
            ReceiptItem(description: 'Design Services from Store', unitPrice: 2000.0, quantity: 1, totalPrice: 2000.0, mainCategory: 'Inter-Entity'),
          ],
        ),
      ];

      final sampleTrips = [
        MileageTrip(
          id: 'trip-1',
          date: DateTime(2026, 2, 20),
          purpose: 'Client Onsite',
          startLocation: 'Office',
          endLocation: 'Client HQ',
          distance: 100.0,
          unit: DistanceUnit.miles,
          ratePerUnit: 0.67,
          boxId: 'box-consulting',
        ),
      ];

      final statement = ConsolidatedStatementService.generateConsolidatedStatement(
        boxes: sampleBoxes,
        invoices: sampleInvoices,
        receipts: sampleReceipts,
        mileageTrips: sampleTrips,
        fiscalYear: 2026,
      );

      // Gross Revenue = $10,000 + $2,000 = $12,000
      expect(statement.totalGrossRevenue, 12000.0);
      // Inter-entity eliminated revenue = $2,000
      expect(statement.totalInterEntityEliminatedRevenue, 2000.0);
      // Consolidated net revenue = $10,000
      expect(statement.consolidatedNetRevenue, 10000.0);

      // Gross Expenses = $500 (AWS) + $2,000 (Internal) + $67 (Mileage) = $2,567.0
      expect(statement.totalGrossExpenses, 2567.0);
      // Inter-entity eliminated expense = $2,000
      expect(statement.totalInterEntityEliminatedExpenses, 2000.0);
      // Consolidated net expenses = $567.0
      expect(statement.consolidatedNetExpenses, 567.0);

      // Consolidated Operating Profit = $10,000 - $567 = $9,433.0
      expect(statement.consolidatedOperatingProfit, 9433.0);
      expect(statement.consolidatedProfitMargin, closeTo(94.33, 0.01));

      // Table formatting check
      final tableText = statement.toFormattedTable();
      expect(tableText.contains('CONSOLIDATED MULTI-ENTITY FINANCIAL STATEMENT'), true);
      expect(tableText.contains('Inter-Entity Transfer Elimination'), true);
    });

    test('AuditDossierService HTML includes in-browser offline cryptographic verifier widget', () {
      final sampleReceipts = [
        Receipt(
          id: 'rec-test',
          merchantName: 'Acme Hardware',
          totalAmount: 150.0,
          date: DateTime(2026, 3, 1),
          currency: 'USD',
          items: const [
            ReceiptItem(description: 'Tool Set', unitPrice: 150.0, quantity: 1, totalPrice: 150.0, mainCategory: 'Equipment'),
          ],
        ),
      ];

      final html = AuditDossierService.generateAuditDossierHtml(
        receipts: sampleReceipts,
        boxName: 'Consulting Ops',
        fiscalYear: 2026,
      );

      expect(html.contains('Standalone Cryptographic Verifier (Zero-Cloud / Air-Gapped)'), true);
      expect(html.contains('WebCrypto SHA-256'), true);
      expect(html.contains('function verifyLedger()'), true);
    });
  });
}
