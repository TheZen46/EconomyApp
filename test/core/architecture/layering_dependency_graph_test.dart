import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/core/entities/syncable_entity.dart';
import 'package:t_aidy/features/receipt_scanning/data/models/receipt_model.dart';
import 'package:t_aidy/features/boxes/data/models/box_model.dart';
import 'package:t_aidy/features/invoices/data/models/invoice_model.dart';
import 'package:t_aidy/features/evault/data/models/asset_model.dart';

void main() {
  group('Layering & Dependency Graph Verification (Issue #59)', () {
    test('All primary domain entities implement SyncableEntity contract', () {
      final now = DateTime.now();

      final receipt = ReceiptModel(
        id: 'rec_123',
        userId: 'user_1',
        merchantName: 'Store',
        date: now,
        totalAmount: 10.0,
        currency: 'EUR',
        items: [],
        version: 1,
        updatedAt: now,
      );
      expect(receipt, isA<SyncableEntity>());
      expect(receipt.id, 'rec_123');
      expect(receipt.userId, 'user_1');
      expect(receipt.version, 1);
      expect(receipt.updatedAt, now);
      expect(receipt.deletedAt, isNull);

      final box = BoxModel(
        id: 'box_123',
        name: 'Entity 1',
        budget: 1000.0,
        spent: 250.0,
        currency: 'EUR',
        color: 0xFF123456,
        version: 2,
        updatedAt: now,
        userId: 'user_1',
      );
      expect(box, isA<SyncableEntity>());
      expect(box.id, 'box_123');
      expect(box.userId, 'user_1');
      expect(box.version, 2);
      expect(box.updatedAt, now);

      final invoice = InvoiceModel(
        id: 'inv_123',
        invoiceNumber: 'INV-001',
        clientName: 'Client',
        amount: 120.0,
        issuedDate: now,
        status: InvoiceStatus.draft,
        version: 3,
        updatedAt: now,
        userId: 'user_1',
      );
      expect(invoice, isA<SyncableEntity>());
      expect(invoice.id, 'inv_123');
      expect(invoice.userId, 'user_1');
      expect(invoice.version, 3);
      expect(invoice.updatedAt, now);

      final asset = AssetModel(
        id: 'ast_123',
        name: 'Document',
        purchaseDate: now,
        warrantyMonths: 12,
        price: 99.99,
        receiptImagePath: '/path/doc.jpg',
        merchantName: 'Store',
        version: 4,
        updatedAt: now,
        userId: 'user_1',
      );
      expect(asset, isA<SyncableEntity>());
      expect(asset.id, 'ast_123');
      expect(asset.userId, 'user_1');
      expect(asset.version, 4);
      expect(asset.updatedAt, now);
    });

    test('Core non-routing modules do not import feature presentation providers', () {
      final coreDir = Directory('lib/core');
      final forbiddenFileNames = [
        'receipt_provider.dart',
        'boxes_provider.dart',
        'invoices_provider.dart',
        'asset_provider.dart',
      ];

      final violations = <String>[];

      for (final entity in coreDir.listSync(recursive: true)) {
        if (entity is File && entity.path.endsWith('.dart')) {
          final normalizedPath = entity.path.replaceAll(r'\', '/');
          // Exclude app router since it is the top-level composition root for page routing
          if (normalizedPath.contains('core/routes/app_router.dart')) {
            continue;
          }
          final lines = entity.readAsLinesSync();
          for (var i = 0; i < lines.length; i++) {
            final line = lines[i];
            if (line.trim().startsWith('import ') || line.trim().startsWith('export ')) {
              for (final forbidden in forbiddenFileNames) {
                if (line.contains(forbidden)) {
                  violations.add('${entity.path}:${i + 1}: $line');
                }
              }
            }
          }
        }
      }

      expect(violations, isEmpty,
          reason: 'Core modules must not depend on feature presentation providers:\n${violations.join('\n')}');
    });
  });
}
