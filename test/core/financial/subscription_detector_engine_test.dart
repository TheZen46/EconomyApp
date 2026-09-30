import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/core/financial/subscription_detector_engine.dart';
import 'package:t_aidy/features/receipt_scanning/domain/entities/receipt.dart';

void main() {
  group('SubscriptionDetectorEngine Tests', () {
    final recurringAdobe = [
      Receipt(
        id: 'adobe-1',
        merchantName: 'Adobe Creative Cloud',
        totalAmount: 54.99,
        date: DateTime(2026, 1, 15),
        items: [],
        currency: 'USD',
      ),
      Receipt(
        id: 'adobe-2',
        merchantName: 'Adobe Creative Cloud',
        totalAmount: 54.99,
        date: DateTime(2026, 2, 15),
        items: [],
        currency: 'USD',
      ),
      Receipt(
        id: 'adobe-3',
        merchantName: 'Adobe Creative Cloud',
        totalAmount: 59.99, // Price increase!
        date: DateTime(2026, 3, 15),
        items: [],
        currency: 'USD',
      ),
    ];

    final oneOffReceipt = Receipt(
      id: 'target-1',
      merchantName: 'Target Superstore',
      totalAmount: 112.50,
      date: DateTime(2026, 2, 10),
      items: [],
      currency: 'USD',
    );

    test('detects monthly subscription, cadence, and price hike accurately', () {
      final allReceipts = [...recurringAdobe, oneOffReceipt];
      final report = SubscriptionDetectorEngine.analyzeReceipts(allReceipts);

      expect(report.totalSubscriptionCount, 1);
      final adobeSub = report.activeSubscriptions.first;
      expect(adobeSub.merchantName, 'Adobe Creative Cloud');
      expect(adobeSub.cadence, SubscriptionCadence.monthly);
      expect(adobeSub.occurrenceCount, 3);
      expect(adobeSub.latestAmount, 59.99);
      expect(adobeSub.hasPriceIncreased, true);
      expect(adobeSub.priceIncreaseAmount, closeTo(5.00, 0.01));
      expect(adobeSub.estimatedAnnualCost, closeTo(59.99 * 12.0, 0.01));

      expect(report.totalMonthlySaaSExpense, 59.99);
      expect(report.priceHikedSubscriptions.length, 1);
    });

    test('handles empty or one-off receipts gracefully', () {
      final report = SubscriptionDetectorEngine.analyzeReceipts([oneOffReceipt]);
      expect(report.totalSubscriptionCount, 0);
      expect(report.totalMonthlySaaSExpense, 0.0);
    });
  });
}
