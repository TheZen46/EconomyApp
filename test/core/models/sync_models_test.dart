import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/features/boxes/data/models/box_model.dart';
import 'package:t_aidy/features/evault/data/models/asset_model.dart';
import 'package:t_aidy/features/invoices/data/models/invoice_model.dart';
import 'package:t_aidy/features/receipt_scanning/data/models/receipt_model.dart';
import 'package:t_aidy/features/settings/data/models/user_profile_model.dart';

void main() {
  group('Sync Metadata & Serialization Tests', () {
    test('ReceiptModel serializes and deserializes sync metadata accurately', () {
      final now = DateTime.now();
      final model = ReceiptModel(
        id: 'rec-sync-01',
        merchantName: 'Apple Store',
        date: now,
        totalAmount: 1499.00,
        currency: 'USD',
        items: [
          ReceiptItemModel(
            description: 'MacBook Pro M3',
            unitPrice: 1499.00,
            quantity: 1,
            totalPrice: 1499.00,
            necessity: 'essential',
            isUserCorrected: true,
            confidenceScore: 0.98,
          ),
        ],
        userId: 'usr-uuid-1234',
        createdAt: now,
        updatedAt: now,
        version: 2,
      );

      final json = model.toJson();
      expect(json['user_id'], 'usr-uuid-1234');
      expect(json['version'], 2);
      expect(json['items'][0]['is_user_corrected'], true);
      expect(json['items'][0]['confidence_score'], 0.98);

      final restored = ReceiptModel.fromJson(json);
      expect(restored.id, 'rec-sync-01');
      expect(restored.merchantName, 'Apple Store');
      expect(restored.userId, 'usr-uuid-1234');
      expect(restored.version, 2);
      expect(restored.items[0].isUserCorrected, true);
    });

    test('BoxModel serializes and deserializes sync metadata', () {
      final box = BoxModel(
        id: 'box-001',
        name: 'Work Expenses',
        budget: 500.0,
        spent: 120.0,
        currency: 'EUR',
        color: 0xFF002FA7,
        userId: 'usr-uuid-5678',
        version: 3,
      );

      final json = box.toJson();
      expect(json['name'], 'Work Expenses');
      expect(json['user_id'], 'usr-uuid-5678');
      expect(json['version'], 3);

      final restored = BoxModel.fromJson(json);
      expect(restored.name, 'Work Expenses');
      expect(restored.userId, 'usr-uuid-5678');
      expect(restored.version, 3);
    });

    test('InvoiceModel serializes and deserializes sync metadata', () {
      final invoice = InvoiceModel(
        id: 'inv-999',
        invoiceNumber: 'INV-2026-042',
        clientName: 'Google Cloud',
        amount: 8500.00,
        status: InvoiceStatus.sent,
        issuedDate: DateTime.now(),
        userId: 'usr-uuid-9999',
        version: 1,
      );

      final json = invoice.toJson();
      expect(json['invoice_number'], 'INV-2026-042');
      expect(json['user_id'], 'usr-uuid-9999');

      final restored = InvoiceModel.fromJson(json);
      expect(restored.invoiceNumber, 'INV-2026-042');
      expect(restored.clientName, 'Google Cloud');
      expect(restored.userId, 'usr-uuid-9999');
    });

    test('AssetModel serializes and deserializes sync metadata', () {
      final asset = AssetModel(
        id: 'asset-777',
        name: 'Sony Headphones',
        purchaseDate: DateTime.now(),
        warrantyMonths: 24,
        price: 349.99,
        receiptImagePath: 'user/images/asset-777.jpg',
        merchantName: 'Sony Store',
        documentPath: 'user/docs/warranty.pdf',
        userId: 'usr-uuid-1111',
        version: 2,
      );

      final json = asset.toJson();
      expect(json['document_path'], 'user/docs/warranty.pdf');
      expect(json['user_id'], 'usr-uuid-1111');

      final restored = AssetModel.fromJson(json);
      expect(restored.name, 'Sony Headphones');
      expect(restored.documentPath, 'user/docs/warranty.pdf');
      expect(restored.userId, 'usr-uuid-1111');
      expect(restored.version, 2);
    });

    test('UserProfileModel serializes and deserializes correctly', () {
      final profile = UserProfileModel(
        id: 'usr-uuid-0000',
        monthlyBudget: 3500.0,
        defaultCurrency: 'GBP',
        themeMode: 'dark',
        biometricEnabled: true,
        gamificationXp: 1450,
        gamificationStreak: 14,
        version: 4,
      );

      final json = profile.toJson();
      expect(json['monthly_budget'], 3500.0);
      expect(json['gamification_xp'], 1450);
      expect(json['biometric_enabled'], true);

      final restored = UserProfileModel.fromJson(json);
      expect(restored.monthlyBudget, 3500.0);
      expect(restored.defaultCurrency, 'GBP');
      expect(restored.themeMode, 'dark');
      expect(restored.gamificationXp, 1450);
      expect(restored.gamificationStreak, 14);
      expect(restored.version, 4);
    });
  });
}
