import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/core/data_contracts/remote_dtos.dart';
import 'package:t_aidy/core/data_contracts/ai_receipt_parser.dart';
import 'package:t_aidy/features/receipt_scanning/data/models/receipt_model.dart';
import 'package:t_aidy/features/boxes/data/models/box_model.dart';
import 'package:t_aidy/features/invoices/data/models/invoice_model.dart';
import 'package:t_aidy/features/evault/data/models/asset_model.dart';
import 'package:t_aidy/features/receipt_scanning/domain/entities/receipt.dart';

void main() {
  group('Remote Schema Contract & Data Serialization (Issue #60 / TAIDY-A03)', () {
    test('Remote DTO column sets match Supabase migration definitions exactly', () {
      final migrationFile = File('supabase/migrations/20260828_master_sync_schema.sql');
      expect(migrationFile.existsSync(), isTrue, reason: 'Migration file must exist.');
      final migrationSql = migrationFile.readAsStringSync();

      // Contractual column sets defined in DTOs
      expect(ReceiptRemoteDto.columns, {
        'id',
        'user_id',
        'merchant_name',
        'total_amount',
        'currency',
        'scanned_date',
        'image_path',
        'vat_number',
        'merchant_address',
        'transaction_time',
        'box_id',
        'items',
        'is_synced',
        'version',
        'created_at',
        'updated_at',
        'deleted_at',
      });

      expect(BoxRemoteDto.columns, {
        'id',
        'user_id',
        'name',
        'budget',
        'spent',
        'currency',
        'color_hex',
        'icon_identifier',
        'auto_categorize',
        'keywords',
        'is_private',
        'version',
        'created_at',
        'updated_at',
        'deleted_at',
      });

      expect(InvoiceRemoteDto.columns, {
        'id',
        'user_id',
        'invoice_number',
        'client_name',
        'amount',
        'currency',
        'status',
        'issued_date',
        'due_date',
        'notes',
        'version',
        'created_at',
        'updated_at',
        'deleted_at',
      });

      expect(VaultAssetRemoteDto.columns, {
        'id',
        'user_id',
        'receipt_id',
        'name',
        'merchant_name',
        'purchase_date',
        'warranty_months',
        'price',
        'receipt_image_path',
        'document_path',
        'version',
        'created_at',
        'updated_at',
        'deleted_at',
      });

      // Assert that every DTO column is referenced in the SQL migration
      for (final col in ReceiptRemoteDto.columns) {
        expect(migrationSql.contains(col), isTrue,
            reason: 'Column $col from ReceiptRemoteDto must exist in SQL migration.');
      }
      for (final col in BoxRemoteDto.columns) {
        expect(migrationSql.contains(col), isTrue,
            reason: 'Column $col from BoxRemoteDto must exist in SQL migration.');
      }
      for (final col in InvoiceRemoteDto.columns) {
        expect(migrationSql.contains(col), isTrue,
            reason: 'Column $col from InvoiceRemoteDto must exist in SQL migration.');
      }
      for (final col in VaultAssetRemoteDto.columns) {
        expect(migrationSql.contains(col), isTrue,
            reason: 'Column $col from VaultAssetRemoteDto must exist in SQL migration.');
      }
    });

    test('RemoteSchemaSerializer strictly sanitizes payloads and prevents PGRST204 errors', () {
      final dirtyReceiptPayload = {
        'id': 'rec_100',
        'user_id': 'user_abc',
        'merchant_name': 'Valid Merchant',
        'scanned_date': '2026-10-14T10:00:00.000Z',
        'total_amount': 45.50,
        'currency': 'USD',
        'extraneous_client_field': 'SHOULD_BE_STRIPPED',
        'local_flag': true,
        'date': '2026-10-14', // Legacy key not in SQL column set
      };

      final sanitized = RemoteSchemaSerializer.sanitizeForTable('receipts', dirtyReceiptPayload);
      expect(sanitized.containsKey('extraneous_client_field'), isFalse);
      expect(sanitized.containsKey('local_flag'), isFalse);
      expect(sanitized.containsKey('date'), isFalse);
      expect(sanitized['merchant_name'], 'Valid Merchant');
      expect(sanitized['total_amount'], 45.50);

      // Verify all keys in sanitized payload are valid SQL columns
      for (final key in sanitized.keys) {
        expect(RemoteSchemaSerializer.isValidColumn('receipts', key), isTrue);
      }
    });

    test('Round-trip serialization fidelity between Remote JSON, DTO, and Domain Model', () {
      final now = DateTime.utc(2026, 10, 14, 12, 0, 0);

      // 1. Receipt
      final receiptModel = ReceiptModel(
        id: 'rec_uuid_1',
        merchantName: 'Supermarket',
        date: now,
        totalAmount: 125.75,
        currency: 'EUR',
        items: [
          ReceiptItemModel(
            id: 'item_1',
            description: 'Organic Milk',
            quantity: 2,
            unitPrice: 2.50,
            totalPrice: 5.00,
            necessity: 'essential',
            mainCategory: 'Groceries',
          ),
        ],
        boxId: 'groceries_box',
        userId: 'user_42',
        vatNumber: 'IT12345678901',
        merchantAddress: 'Via Roma 1, Milano',
        time: '12:30',
        version: 3,
        updatedAt: now,
      );

      final receiptDto = ReceiptRemoteDto.fromModel(receiptModel);
      final receiptRemoteJson = receiptDto.toRemoteJson();
      expect(receiptRemoteJson['scanned_date'], now.toIso8601String());
      expect(receiptRemoteJson['merchant_name'], 'Supermarket');
      expect(receiptRemoteJson['items'], isA<List>());

      final parsedReceiptModel = ReceiptRemoteDto.fromRemoteJson(receiptRemoteJson).toModel();
      expect(parsedReceiptModel.id, receiptModel.id);
      expect(parsedReceiptModel.merchantName, receiptModel.merchantName);
      expect(parsedReceiptModel.totalAmount, receiptModel.totalAmount);
      expect(parsedReceiptModel.currency, receiptModel.currency);
      expect(parsedReceiptModel.items.length, 1);
      expect(parsedReceiptModel.items.first.description, 'Organic Milk');

      // 2. Box
      final boxModel = BoxModel(
        id: 'box_uuid_1',
        name: 'Household',
        budget: 500.0,
        spent: 120.0,
        currency: 'EUR',
        color: 0xFF2196F3,
        icon: 'home',
        isPrivate: true,
        autoCategorize: true,
        keywords: 'rent,utilities,groceries',
        version: 2,
        updatedAt: now,
        userId: 'user_42',
      );

      final boxRemoteJson = boxModel.toRemoteJson();
      expect(boxRemoteJson['color_hex'], 0xFF2196F3);
      expect(boxRemoteJson['icon_identifier'], 'home');
      expect(boxRemoteJson['is_private'], isTrue);

      final parsedBoxModel = BoxRemoteDto.fromRemoteJson(boxRemoteJson).toModel();
      expect(parsedBoxModel.id, boxModel.id);
      expect(parsedBoxModel.name, boxModel.name);
      expect(parsedBoxModel.budget, boxModel.budget);
      expect(parsedBoxModel.spent, boxModel.spent);
      expect(parsedBoxModel.color, boxModel.color);
      expect(parsedBoxModel.isPrivate, isTrue);

      // 3. Invoice
      final invoiceModel = InvoiceModel(
        id: 'inv_uuid_1',
        invoiceNumber: 'INV-2026-001',
        clientName: 'Acme Corp',
        amount: 1500.0,
        currency: 'EUR',
        status: InvoiceStatus.sent,
        issuedDate: now,
        dueDate: now.add(const Duration(days: 30)),
        notes: 'Net 30 payment terms',
        version: 1,
        updatedAt: now,
        userId: 'user_42',
      );

      final invoiceRemoteJson = invoiceModel.toRemoteJson();
      expect(invoiceRemoteJson['invoice_number'], 'INV-2026-001');
      expect(invoiceRemoteJson['client_name'], 'Acme Corp');
      expect(invoiceRemoteJson['status'], InvoiceStatus.sent);

      final parsedInvoiceModel = InvoiceRemoteDto.fromRemoteJson(invoiceRemoteJson).toModel();
      expect(parsedInvoiceModel.id, invoiceModel.id);
      expect(parsedInvoiceModel.invoiceNumber, invoiceModel.invoiceNumber);
      expect(parsedInvoiceModel.amount, invoiceModel.amount);
      expect(parsedInvoiceModel.status, invoiceModel.status);

      // 4. Asset
      final assetModel = AssetModel(
        id: 'asset_uuid_1',
        name: 'MacBook Pro 16',
        purchaseDate: now,
        warrantyMonths: 24,
        price: 2499.00,
        receiptImagePath: '/receipts/macbook.jpg',
        merchantName: 'Apple Store',
        receiptId: 'rec_uuid_1',
        documentPath: '/docs/warranty.pdf',
        version: 1,
        updatedAt: now,
        userId: 'user_42',
      );

      final assetRemoteJson = assetModel.toRemoteJson();
      expect(assetRemoteJson['name'], 'MacBook Pro 16');
      expect(assetRemoteJson['warranty_months'], 24);
      expect(assetRemoteJson['price'], 2499.00);

      final parsedAssetModel = VaultAssetRemoteDto.fromRemoteJson(assetRemoteJson).toModel();
      expect(parsedAssetModel.id, assetModel.id);
      expect(parsedAssetModel.name, assetModel.name);
      expect(parsedAssetModel.warrantyMonths, assetModel.warrantyMonths);
      expect(parsedAssetModel.price, assetModel.price);
    });

    test('Unified AiReceiptParser handles Gemini, VLM, and LLM output schemas without drift', () {
      final now = DateTime(2026, 10, 14);

      // 1. Gemini / VLM canonical snake_case format
      final vlmOutput = {
        'merchant_name': 'Cafe Central',
        'merchant_address': 'Herrengasse 14, Wien',
        'vat_number': 'ATU12345678',
        'date': '2026-10-14',
        'time': '10:15',
        'currency': 'EUR',
        'total_amount': 18.50,
        'items': [
          {
            'description': 'Melange Coffee',
            'quantity': 2,
            'unit_price': 4.50,
            'total_price': 9.00,
            'necessity': 'discretional',
            'main_category': 'Food & Dining',
            'sub_category': 'Coffee',
          },
          {
            'raw_name': 'Apfelstrudel',
            'quantity': 1,
            'unit_price': 9.50,
            'necessity': 'discretional',
            'main_category': 'Food & Dining',
            'sub_category': 'Bakery',
          },
        ],
      };

      final parsedVlm = AiReceiptParser.parseToEntity(vlmOutput, imagePath: '/path/cafe.jpg', now: now);
      expect(parsedVlm.merchantName, 'Cafe Central');
      expect(parsedVlm.currency, 'EUR');
      expect(parsedVlm.totalAmount, 18.50);
      expect(parsedVlm.items.length, 2);
      expect(parsedVlm.items[0].description, 'Melange Coffee');
      expect(parsedVlm.items[0].necessity, ItemNecessity.discretional);
      expect(parsedVlm.items[1].description, 'Apfelstrudel');
      expect(parsedVlm.items[1].totalPrice, 9.50); // derived fallback

      // 2. LLM legacy camelCase format
      final llmOutput = {
        'merchantName': 'Tech Store',
        'merchantAddress': 'Tech Blvd 10',
        'vatNumber': 'US987654321',
        'date': '2026-10-14',
        'totalAmount': 29.99,
        'currency': r'$',
        'items': [
          {
            'description': 'USB-C Cable',
            'quantity': 1,
            'unitPrice': 29.99,
            'totalPrice': 29.99,
            'isAsset': true,
          },
        ],
      };

      final parsedLlm = AiReceiptParser.parseToEntity(llmOutput, now: now);
      expect(parsedLlm.merchantName, 'Tech Store');
      expect(parsedLlm.currency, 'USD'); // normalized from '$'
      expect(parsedLlm.totalAmount, 29.99);
      expect(parsedLlm.items.length, 1);
      expect(parsedLlm.items[0].isAsset, isTrue);

      // 3. Nested merchant & transaction envelope
      final nestedOutput = {
        'merchant': {
          'name': 'Boutique Flora',
          'vat_number': 'FR55123456789',
        },
        'transaction': {
          'date': '2026-10-14',
          'total_amount': 45.00,
          'currency': 'eur',
        },
        'items': [],
      };

      final parsedNested = AiReceiptParser.parseToEntity(nestedOutput, now: now);
      expect(parsedNested.merchantName, 'Boutique Flora');
      expect(parsedNested.vatNumber, 'FR55123456789');
      expect(parsedNested.totalAmount, 45.00);
      expect(parsedNested.currency, 'EUR');
    });

    test('AiReceiptParser necessity resolution matches contractual enum mappings', () {
      expect(AiReceiptParser.parseNecessity('essential'), ItemNecessity.essential);
      expect(AiReceiptParser.parseNecessity('ESSENTIAL'), ItemNecessity.essential);
      expect(AiReceiptParser.parseNecessity('discretional'), ItemNecessity.discretional);
      expect(AiReceiptParser.parseNecessity('discretionary'), ItemNecessity.discretional);
      expect(AiReceiptParser.parseNecessity('junk'), ItemNecessity.junk);
      expect(AiReceiptParser.parseNecessity('JUNK'), ItemNecessity.junk);
      expect(AiReceiptParser.parseNecessity('unknown'), ItemNecessity.unknown);
      expect(AiReceiptParser.parseNecessity(null), ItemNecessity.unknown);
      expect(AiReceiptParser.parseNecessity('unrecognized_string'), ItemNecessity.unknown);
    });
  });
}
