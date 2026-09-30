import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/core/financial/audit_risk_score_engine.dart';
import 'package:t_aidy/features/invoices/data/models/invoice_model.dart';
import 'package:t_aidy/features/receipt_scanning/domain/entities/receipt.dart';

void main() {
  group('AuditRiskScoreEngine Tests', () {
    test('computes low risk score for healthy ledger with verifiable receipts and invoices', () {
      final sampleInvoices = [
        InvoiceModel(
          id: 'inv-1',
          invoiceNumber: 'INV-001',
          clientName: 'Acme Corp',
          amount: 20000.0,
          status: InvoiceStatus.settled,
          issuedDate: DateTime(2026, 2, 1),
        ),
      ];

      final sampleReceipts = [
        Receipt(
          id: 'r1',
          merchantName: 'Apple Store',
          totalAmount: 1243.82, // Non-round figure with exact cents
          date: DateTime(2026, 2, 10),
          currency: 'USD',
          items: const [
            ReceiptItem(description: 'MacBook Monitor', unitPrice: 1243.82, quantity: 1, totalPrice: 1243.82, mainCategory: 'Equipment'),
          ],
        ),
        Receipt(
          id: 'r2',
          merchantName: 'FedEx Shipping',
          totalAmount: 43.17, // Non-round figure
          date: DateTime(2026, 2, 15),
          currency: 'USD',
          items: const [
            ReceiptItem(description: 'Postage', unitPrice: 43.17, quantity: 1, totalPrice: 43.17, mainCategory: 'Office Supplies'),
          ],
        ),
      ];

      final assessment = AuditRiskScoreEngine.evaluateAuditRisk(
        receipts: sampleReceipts,
        invoices: sampleInvoices,
        fiscalYear: 2026,
      );

      expect(assessment.overallRiskScore, lessThanOrEqualTo(25));
      expect(assessment.riskLevel, 'Low');
      expect(assessment.hasDefensibleAuditReadiness, true);
    });

    test('flags high audit risk for contractor payments over \$600 missing Form W-9', () {
      final sampleInvoices = [
        InvoiceModel(
          id: 'inv-1',
          invoiceNumber: 'INV-001',
          clientName: 'Client LLC',
          amount: 15000.0,
          status: InvoiceStatus.settled,
          issuedDate: DateTime(2026, 2, 1),
        ),
      ];

      final sampleReceipts = [
        // Subcontractor paid $1,500 with no TIN/W-9 on file
        Receipt(
          id: 'r-contractor',
          merchantName: 'Jane Subcontractor Dev',
          totalAmount: 1500.0,
          date: DateTime(2026, 2, 20),
          currency: 'USD',
          items: const [
            ReceiptItem(description: 'Custom React Development', unitPrice: 1500.0, quantity: 1, totalPrice: 1500.0, mainCategory: 'Professional Services'),
          ],
        ),
      ];

      final assessment = AuditRiskScoreEngine.evaluateAuditRisk(
        receipts: sampleReceipts,
        invoices: sampleInvoices,
        fiscalYear: 2026,
      );

      expect(assessment.contractorsMissingW9Count, greaterThan(0));
      expect(assessment.riskFactors.any((f) => f.title.contains('Subcontractors Paid')), true);
      expect(assessment.overallRiskScore, greaterThanOrEqualTo(15));
    });
  });
}
