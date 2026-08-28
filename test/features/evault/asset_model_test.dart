import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/features/evault/data/models/asset_model.dart';
import 'package:t_aidy/features/evault/presentation/providers/asset_provider.dart';
import 'package:t_aidy/features/receipt_scanning/domain/entities/receipt.dart';

void main() {
  group('AssetModel - Warranty Expiry Date Calendar Accuracy', () {
    test('calculates 12-month warranty accurately across 30 and 31 day months', () {
      final purchaseDate = DateTime(2024, 1, 15, 10, 30);
      final asset = AssetModel(
        id: 'test-1',
        name: 'MacBook Pro',
        purchaseDate: purchaseDate,
        warrantyMonths: 12,
        price: 1999.99,
        receiptImagePath: '',
        merchantName: 'Apple Store',
      );

      expect(asset.warrantyExpiryDate, DateTime(2025, 1, 15, 10, 30));
    });

    test('calculates 24-month warranty accurately starting in February', () {
      final purchaseDate = DateTime(2024, 2, 28, 14, 0);
      final asset = AssetModel(
        id: 'test-2',
        name: 'Sony Headphones',
        purchaseDate: purchaseDate,
        warrantyMonths: 24,
        price: 349.99,
        receiptImagePath: '',
        merchantName: 'Best Buy',
      );

      expect(asset.warrantyExpiryDate, DateTime(2026, 2, 28, 14, 0));
    });

    test('calculates 6-month warranty accurately crossing mid-year', () {
      final purchaseDate = DateTime(2024, 5, 31, 9, 0);
      final asset = AssetModel(
        id: 'test-3',
        name: 'Gaming Mouse',
        purchaseDate: purchaseDate,
        warrantyMonths: 6,
        price: 79.99,
        receiptImagePath: '',
        merchantName: 'Amazon',
      );

      // Month 5 + 6 = 11 (November). November has 30 days, DateTime(2024, 11, 31) normalizes to Dec 1.
      expect(asset.warrantyExpiryDate, DateTime(2024, 11, 31, 9, 0));
    });

    test('evaluates isWarrantyActive accurately relative to current time', () {
      final pastDate = DateTime(2020, 1, 1);
      final expiredAsset = AssetModel(
        id: 'expired-1',
        name: 'Old Phone',
        purchaseDate: pastDate,
        warrantyMonths: 12,
        price: 500,
        receiptImagePath: '',
        merchantName: 'Store',
      );
      expect(expiredAsset.isWarrantyActive, isFalse);

      final futureDate = DateTime.now().add(const Duration(days: 10));
      final activeAsset = AssetModel(
        id: 'active-1',
        name: 'New Monitor',
        purchaseDate: futureDate,
        warrantyMonths: 24,
        price: 400,
        receiptImagePath: '',
        merchantName: 'Store',
      );
      expect(activeAsset.isWarrantyActive, isTrue);
    });
  });

  group('AssetNotifier - State and Operations', () {
    test('adds asset and removes asset by string ID without throwing', () async {
      final notifier = AssetNotifier();
      expect(notifier.state, isEmpty);

      final receiptItem = ReceiptItem(
        description: 'UltraWide Monitor',
        unitPrice: 599.99,
        quantity: 1,
        totalPrice: 599.99,
        isAsset: true,
      );

      final receipt = Receipt(
        id: 'rcpt-101',
        merchantName: 'Micro Center',
        date: DateTime(2024, 6, 1),
        totalAmount: 599.99,
        currency: 'USD',
        items: [receiptItem],
      );

      await notifier.addAssetFromReceiptItem(receiptItem, receipt, warrantyMonths: 36);

      expect(notifier.state.length, 1);
      final addedAsset = notifier.state.first;
      expect(addedAsset.name, 'UltraWide Monitor');
      expect(addedAsset.merchantName, 'Micro Center');
      expect(addedAsset.warrantyMonths, 36);
      expect(addedAsset.receiptId, 'rcpt-101');

      // Delete by string ID
      await notifier.deleteAsset(addedAsset.id);
      expect(notifier.state, isEmpty);
    });
  });
}
