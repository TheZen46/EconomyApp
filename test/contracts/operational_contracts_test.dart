import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:t_aidy/features/receipt_scanning/data/models/receipt_model.dart';
import 'package:t_aidy/features/receipt_scanning/data/models/dashboard_config.dart';
import 'package:t_aidy/features/settings/data/models/taxonomy_model.dart';
import 'package:t_aidy/features/receipt_scanning/data/models/sync_item_model.dart';
import 'package:t_aidy/features/evault/data/models/asset_model.dart';
import 'package:t_aidy/features/boxes/data/models/box_model.dart';
import 'package:t_aidy/features/invoices/data/models/invoice_model.dart';
import 'package:t_aidy/core/sync/models/sync_outbox_item.dart';
import 'package:t_aidy/features/settings/data/models/user_profile_model.dart';

void main() {
  group('Operational Contracts Verification', () {
    test('Hive TypeId Registry satisfies contractual uniqueness and numeric constraints', () {
      final List<TypeAdapter<dynamic>> adapters = [
        ReceiptModelAdapter(),
        ReceiptItemModelAdapter(),
        DashboardWidgetTypeAdapter(),
        DashboardItemAdapter(),
        TaxonomyItemModelAdapter(),
        TaxonomyConfigModelAdapter(),
        SyncItemModelAdapter(),
        AssetModelAdapter(),
        BoxModelAdapter(),
        InvoiceModelAdapter(),
        SyncOutboxItemAdapter(),
        UserProfileModelAdapter(),
      ];

      final expectedRegistry = <int, String>{
        0: 'ReceiptModelAdapter',
        1: 'ReceiptItemModelAdapter',
        2: 'DashboardWidgetTypeAdapter',
        3: 'DashboardItemAdapter',
        4: 'TaxonomyItemModelAdapter',
        5: 'TaxonomyConfigModelAdapter',
        6: 'SyncItemModelAdapter',
        7: 'AssetModelAdapter',
        10: 'BoxModelAdapter',
        11: 'InvoiceModelAdapter',
        12: 'SyncOutboxItemAdapter',
        13: 'UserProfileModelAdapter',
      };

      // 1. Verify every registered adapter matches its contractual typeId
      for (final adapter in adapters) {
        final adapterName = adapter.runtimeType.toString();
        expect(
          expectedRegistry.containsKey(adapter.typeId),
          isTrue,
          reason: 'Adapter $adapterName has unexpected or uncontracted typeId: ${adapter.typeId}',
        );
        expect(
          expectedRegistry[adapter.typeId],
          adapterName,
          reason: 'typeId ${adapter.typeId} mismatch: expected ${expectedRegistry[adapter.typeId]}, got $adapterName',
        );
      }

      // 2. Verify absolute uniqueness across all registered typeIds
      final seenIds = <int>{};
      for (final adapter in adapters) {
        expect(
          seenIds.contains(adapter.typeId),
          isFalse,
          reason: 'Collision detected: typeId ${adapter.typeId} is shared by multiple adapters!',
        );
        seenIds.add(adapter.typeId);
      }
    });

    test('Sync Outbox state machine lifecycle supports contractual statuses', () {
      const contractualStatuses = [
        'pending',
        'processing',
        'synced',
        'failed',
        'permanently_failed',
      ];

      for (final status in contractualStatuses) {
        final item = SyncOutboxItem(
          id: 'test-id',
          entityType: 'receipt',
          entityId: 'rec-1',
          mutationType: 'upsert',
          payload: {'test': true},
          status: status,
        );
        expect(item.status, status);
        final json = item.toJson();
        expect(json['status'], status);
        final roundTrip = SyncOutboxItem.fromJson(json);
        expect(roundTrip.status, status);
      }
    });

    test('Contract markdown specifications exist and are documented', () {
      const requiredDocs = [
        'docs/contracts/hive_registry.md',
        'docs/contracts/sync_outbox_contract.md',
        'docs/contracts/remote_schema_mapping.md',
        'docs/contracts/personal_data_inventory.md',
      ];

      for (final docPath in requiredDocs) {
        final file = File(docPath);
        expect(
          file.existsSync(),
          isTrue,
          reason: 'Contract specification $docPath is missing!',
        );
        final content = file.readAsStringSync();
        expect(content.isNotEmpty, isTrue, reason: '$docPath must not be empty.');
      }
    });
  });
}
