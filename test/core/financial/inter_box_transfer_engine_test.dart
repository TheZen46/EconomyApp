import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/core/financial/inter_box_transfer_engine.dart';

void main() {
  group('InterBoxTransferEngine Tests', () {
    test('creates cryptographically sealed transfer record with valid SHA-256 digest', () {
      final transfer = InterBoxTransferEngine.createTransfer(
        sourceBoxId: 'box_agency',
        sourceBoxName: 'Digital Agency LLC',
        targetBoxId: 'box_ecommerce',
        targetBoxName: 'E-Commerce Store',
        amount: 3500.0,
        transferType: InterBoxTransferType.internalServiceBilling,
        memo: 'Q1 Web Development and SEO Optimization',
        isTaxNeutral: true,
        timestamp: DateTime(2026, 3, 1),
      );

      expect(transfer.transferId.startsWith('XFER-'), true);
      expect(transfer.amount, 3500.0);
      expect(transfer.auditDigestSha256.length, 64);
      expect(transfer.isTaxNeutral, true);
    });

    test('consolidates transfers and computes net balances with tax neutrality neutralization', () {
      final t1 = InterBoxTransferEngine.createTransfer(
        sourceBoxId: 'box_agency',
        sourceBoxName: 'Agency',
        targetBoxId: 'box_ecommerce',
        targetBoxName: 'E-Commerce',
        amount: 2000.0,
        transferType: InterBoxTransferType.capitalContribution,
        memo: 'Seed working capital',
        isTaxNeutral: true,
      );

      final t2 = InterBoxTransferEngine.createTransfer(
        sourceBoxId: 'box_ecommerce',
        sourceBoxName: 'E-Commerce',
        targetBoxId: 'box_agency',
        targetBoxName: 'Agency',
        amount: 500.0,
        transferType: InterBoxTransferType.sharedCostApportionment,
        memo: 'Figma license shared cost',
        isTaxNeutral: true,
      );

      final summary = InterBoxTransferEngine.consolidateTransfers([t1, t2], baselineTaxRate: 0.25);

      expect(summary.totalTransfersCount, 2);
      expect(summary.totalTransfersAmount, 2500.0);

      // Agency net: -2000 + 500 = -1500
      expect(summary.netBoxAdjustments['box_agency'], -1500.0);
      // E-Commerce net: +2000 - 500 = +1500
      expect(summary.netBoxAdjustments['box_ecommerce'], 1500.0);

      // Eliminated tax variance: 2500 * 0.25 = 625.0
      expect(summary.eliminatedTaxShieldVariance, 625.0);
    });

    test('rejects transfer when source and target boxes are identical', () {
      expect(
        () => InterBoxTransferEngine.createTransfer(
          sourceBoxId: 'same_box',
          sourceBoxName: 'Same',
          targetBoxId: 'same_box',
          targetBoxName: 'Same',
          amount: 100.0,
          transferType: InterBoxTransferType.capitalContribution,
          memo: 'Invalid circular transfer',
        ),
        throwsArgumentError,
      );
    });
  });
}
