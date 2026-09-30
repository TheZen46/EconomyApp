import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/core/financial/contractor_compliance_engine.dart';
import 'package:t_aidy/features/receipt_scanning/domain/entities/receipt.dart';

void main() {
  group('ContractorComplianceEngine Tests', () {
    final receipts2026 = [
      Receipt(
        id: 'rec-c1',
        merchantName: 'DevFlow Consulting',
        totalAmount: 400.0,
        date: DateTime(2026, 2, 1),
        items: [
          ReceiptItem(description: 'Software Subcontracting', unitPrice: 400.0, quantity: 1, totalPrice: 400.0, mainCategory: 'Subcontractors'),
        ],
        currency: 'USD',
      ),
      Receipt(
        id: 'rec-c2',
        merchantName: 'DevFlow Consulting',
        totalAmount: 350.0, // Total = 750.0 >= $600 threshold
        date: DateTime(2026, 3, 1),
        items: [
          ReceiptItem(description: 'Backend Engineering', unitPrice: 350.0, quantity: 1, totalPrice: 350.0, mainCategory: 'Subcontractors'),
        ],
        currency: 'USD',
      ),
      Receipt(
        id: 'rec-c3',
        merchantName: 'PixelCraft Design Studio',
        totalAmount: 250.0, // Total = $250 < $600 threshold
        date: DateTime(2026, 3, 10),
        items: [
          ReceiptItem(description: 'Brand Assets', unitPrice: 250.0, quantity: 1, totalPrice: 250.0, mainCategory: 'Professional Services'),
        ],
        currency: 'USD',
      ),
    ];

    test('flags vendors crossing 600 threshold requiring Form 1099-NEC and W-9', () {
      final report = ContractorComplianceEngine.analyzeReceipts(
        receipts: receipts2026,
        fiscalYear: 2026,
      );

      expect(report.totalVendorsRequiring1099, 1);
      expect(report.missingW9Vendors.length, 1);
      expect(report.missingW9Vendors.first.vendorName, 'DevFlow Consulting');
      expect(report.missingW9Vendors.first.totalPaidInYear, 750.0);
      expect(report.missingW9Vendors.first.status, Contractor1099Status.requires1099);

      final pixelCraft = report.vendors.firstWhere((v) => v.vendorName.contains('PixelCraft'));
      expect(pixelCraft.status, Contractor1099Status.underThreshold);
      expect(pixelCraft.distanceToThreshold, 350.0); // 600 - 250
    });

    test('marks vendor as w9Collected when TIN/EIN is present in records', () {
      final report = ContractorComplianceEngine.analyzeReceipts(
        receipts: receipts2026,
        fiscalYear: 2026,
        knownVendorTins: {'devflowconsulting': 'XX-XXXXXXX'},
      );

      final devFlow = report.vendors.firstWhere((v) => v.normalizedName == 'devflowconsulting');
      expect(devFlow.status, Contractor1099Status.w9Collected);
      expect(devFlow.isW9OnFile, true);
      expect(report.missingW9Vendors.isEmpty, true);
    });
  });
}
