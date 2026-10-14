import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:t_aidy/core/sync/models/sync_outbox_item.dart';
import 'package:t_aidy/core/sync/outbox_service.dart';
import 'package:t_aidy/core/sync/sync_error_policy.dart';
import 'package:t_aidy/core/sync/sync_manager.dart';
import 'package:t_aidy/features/boxes/data/models/box_model.dart';
import 'package:t_aidy/features/evault/data/models/asset_model.dart';
import 'package:t_aidy/features/invoices/data/models/invoice_model.dart';
import 'package:t_aidy/features/receipt_scanning/data/models/receipt_model.dart';

import 'support/fake_supabase.dart';

const _schemaError = PostgrestException(
  message: "Could not find the 'date' column of 'receipts' in the schema cache",
  code: 'PGRST204',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('isPermanentSyncError', () {
    test('classifies request, schema, data and access errors as permanent', () {
      for (final code in ['PGRST204', 'PGRST205', 'PGRST102', '23505', '22P02', '42501', '42703', '400', '403', '404']) {
        expect(isPermanentSyncError(PostgrestException(message: 'x', code: code)), isTrue, reason: code);
      }
    });

    test('classifies connection, authentication, rate-limit and server errors as transient', () {
      for (final code in ['PGRST000', 'PGRST301', '08006', '40001', '40P01', '53300', '401', '408', '429', '500', '503']) {
        expect(isPermanentSyncError(PostgrestException(message: 'x', code: code)), isFalse, reason: code);
      }
      expect(isPermanentSyncError(const PostgrestException(message: 'x')), isFalse);
      expect(isPermanentSyncError(const SocketException('offline')), isFalse);
    });
  });

  group('SyncManager outbox processing', () {
    late Directory tempDir;
    late Box<SyncOutboxItem> outboxBox;
    late OutboxService outbox;
    late FakeSupabase client;
    late SyncManager manager;

    setUpAll(() {
      if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ReceiptModelAdapter());
      if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(ReceiptItemModelAdapter());
      if (!Hive.isAdapterRegistered(7)) Hive.registerAdapter(AssetModelAdapter());
      if (!Hive.isAdapterRegistered(10)) Hive.registerAdapter(BoxModelAdapter());
      if (!Hive.isAdapterRegistered(11)) Hive.registerAdapter(InvoiceModelAdapter());
      if (!Hive.isAdapterRegistered(12)) Hive.registerAdapter(SyncOutboxItemAdapter());
    });

    setUp(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/connectivity'),
        (MethodCall methodCall) async => ['wifi'],
      );
      tempDir = await Directory.systemTemp.createTemp('outbox_flush_');
      Hive.init(tempDir.path);
      outboxBox = await Hive.openBox<SyncOutboxItem>('outbox');
      outbox = OutboxService(outboxBox);
      client = FakeSupabase();
      manager = SyncManager(
        supabase: client,
        outboxService: outbox,
        receiptsBox: await Hive.openBox<ReceiptModel>('receipts'),
        boxesBox: await Hive.openBox<BoxModel>('boxes'),
        invoicesBox: await Hive.openBox<InvoiceModel>('invoices'),
        assetsBox: await Hive.openBox<AssetModel>('assets'),
        settingsBox: await Hive.openBox('settings'),
      );
    });

    tearDown(() async {
      manager.dispose();
      await Hive.close();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    Future<SyncOutboxItem> enqueue(String type, String id, {String mutation = 'upsert'}) {
      return outbox.enqueue(
        entityType: type,
        entityId: id,
        mutationType: mutation,
        payload: {'id': id},
      );
    }

    test('a failing entity does not block mutations of other entities', () async {
      client.writeErrors['receipts'] = const SocketException('connection reset');
      await enqueue('receipt', 'rec-1');
      await enqueue('box', 'box-1');

      await manager.syncAll();

      expect(client.upserts.map((u) => u.table), ['receipts', 'boxes']);
      expect(outboxBox.values.map((i) => i.entityId), ['rec-1']);
    });

    test('later mutations of a failing entity are held back to preserve order', () async {
      client.writeErrors['receipts'] = const SocketException('connection reset');
      await enqueue('receipt', 'rec-1');
      await enqueue('receipt', 'rec-1', mutation: 'delete');

      await manager.syncAll();

      expect(client.upserts, hasLength(1));
      expect(client.updates, isEmpty);
      expect(outboxBox.length, 2);
    });

    test('permanent errors are dead-lettered at once, transient ones are retried', () async {
      client.writeErrors['receipts'] = _schemaError;
      client.writeErrors['boxes'] = const SocketException('connection reset');
      final receipt = await enqueue('receipt', 'rec-1');
      final box = await enqueue('box', 'box-1');

      await manager.syncAll();

      expect(outboxBox.get(receipt.id)!.status, 'permanently_failed');
      expect(outboxBox.get(box.id)!.status, 'failed');
      expect(outboxBox.get(box.id)!.retryCount, 1);
    });

    test('items in their backoff window are not retried and hold their entity', () async {
      client.writeErrors['receipts'] = const SocketException('connection reset');
      await enqueue('receipt', 'rec-1');
      await manager.syncAll();
      client.writeErrors.clear();
      await enqueue('receipt', 'rec-1', mutation: 'delete');

      await manager.syncAll(); // immediately afterwards, inside the 2 s backoff window

      expect(client.upserts, hasLength(1));
      expect(client.updates, isEmpty);
    });

    test('unknown entity types are dead-lettered instead of being written to receipts', () async {
      final item = await enqueue('receipt_item', 'item-1');

      await manager.syncAll();

      expect(client.upserts, isEmpty);
      expect(outboxBox.get(item.id)!.status, 'permanently_failed');
    });

    test('profile payloads are not given a user_id column', () async {
      await enqueue('profile', 'user-1');

      await manager.syncAll();

      final body = client.upserts.single.values as Map<String, dynamic>;
      expect(client.upserts.single.table, 'user_profiles');
      expect(body.containsKey('user_id'), isFalse);
    });

    test('retryDeadLettered resubmits dead-lettered mutations', () async {
      client.writeErrors['receipts'] = _schemaError;
      await enqueue('receipt', 'rec-1');
      await manager.syncAll();
      expect(outbox.getPermanentlyFailed(), hasLength(1));

      client.writeErrors.clear(); // e.g. the missing migration has been applied
      await manager.retryDeadLettered();

      expect(client.upserts, hasLength(2));
      expect(outboxBox.isEmpty, isTrue);
    });

    test('pushing a receipt does not write to the training corpus', () async {
      await outbox.enqueue(
        entityType: 'receipt',
        entityId: 'rec-1',
        mutationType: 'upsert',
        payload: {
          'id': 'rec-1',
          'merchant_name': 'Pharmacy',
          'items': [
            {'description': 'Insulin pen', 'unit_price': 30.0, 'quantity': 1},
          ],
        },
      );

      await manager.syncAll();

      expect(client.upserts.single.table, 'receipts');
      expect(client.inserts.where((w) => w.table == 'receipt_training_labels'), isEmpty);
    });
  });
}
