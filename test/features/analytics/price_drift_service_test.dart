import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/features/analytics/data/price_drift_service.dart';
import 'package:t_aidy/features/receipt_scanning/domain/entities/receipt.dart';

void main() {
  group('PriceDriftService Semantic Clustering & Inflation Tests', () {
    final receipts = [
      Receipt(
        id: 'r1',
        merchantName: 'Trader Joes',
        date: DateTime(2026, 1, 10),
        totalAmount: 10.0,
        currency: 'USD',
        items: const [
          ReceiptItem(description: 'Organic Oat Milk 1L', unitPrice: 3.49, quantity: 1, totalPrice: 3.49, mainCategory: 'Groceries'),
        ],
      ),
      Receipt(
        id: 'r2',
        merchantName: 'Whole Foods Market',
        date: DateTime(2026, 2, 15),
        totalAmount: 15.0,
        currency: 'USD',
        items: const [
          ReceiptItem(description: 'OAT MILK 1000ML ORGANIC', unitPrice: 4.19, quantity: 1, totalPrice: 4.19, mainCategory: 'Groceries'),
        ],
      ),
      Receipt(
        id: 'r3',
        merchantName: 'Target',
        date: DateTime(2026, 3, 20),
        totalAmount: 20.0,
        currency: 'USD',
        items: const [
          ReceiptItem(description: 'Organic Oatmilk 1 Liter', unitPrice: 3.89, quantity: 1, totalPrice: 3.89, mainCategory: 'Groceries'),
        ],
      ),
    ];

    test('semantically clusters typo-variant descriptions into single canonical SKU', () {
      final clusters = PriceDriftService.analyzePriceDrift(receipts);

      expect(clusters.length, 1);
      final sku = clusters.first;
      expect(sku.count, 3);
      expect(sku.initialPrice, 3.49);
      expect(sku.latestPrice, 3.89);
      expect(sku.minPrice, 3.49);
      expect(sku.maxPrice, 4.19);
      expect(sku.cheapestMerchant, 'Trader Joes');
      expect(sku.lowestPrice, 3.49);
      expect(sku.highestMerchant, 'Whole Foods Market');
      expect(sku.highestPrice, 4.19);
      expect(sku.priceDriftPercent, greaterThan(0.0));
    });

    test('evaluates price trend for individual item correctly', () {
      final trend = PriceDriftService.getPriceTrendForItem('Oat Milk Organic', 4.50, receipts);
      expect(trend, isNotNull);
      expect(trend!, greaterThan(0.0)); // 4.50 is higher than historical average ~3.85
    });
  });
}
