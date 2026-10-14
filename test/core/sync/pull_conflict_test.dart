import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:t_aidy/core/sync/models/sync_outbox_item.dart';
import 'package:t_aidy/core/sync/outbox_service.dart';
import 'package:t_aidy/core/sync/sync_manager.dart';
import 'package:t_aidy/features/boxes/data/models/box_model.dart';
import 'package:t_aidy/features/evault/data/models/asset_model.dart';
import 'package:t_aidy/features/invoices/data/models/invoice_model.dart';
import 'package:t_aidy/features/receipt_scanning/data/models/receipt_model.dart';

import 'support/fake_supabase.dart';

/// Push failure followed by pull: a local change that has not reached the
/// server must survive the pull for every synchronized entity type.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Box<ReceiptModel> receiptsBox;
  late Box<BoxModel> boxesBox;
  late Box<InvoiceModel> invoicesBox;
  late Box<AssetModel> assetsBox;
  late Box<SyncOutboxItem> outboxBox;
  late OutboxService outbox;

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
    tempDir = await Directory.systemTemp.createTemp('pull_conflict_');
    Hive.init(tempDir.path);
    receiptsBox = await Hive.openBox<ReceiptModel>('receipts');
    boxesBox = await Hive.openBox<BoxModel>('boxes');
    invoicesBox = await Hive.openBox<InvoiceModel>('invoices');
    assetsBox = await Hive.openBox<AssetModel>('assets');
    outboxBox = await Hive.openBox<SyncOutboxItem>('outbox');
    outbox = OutboxService(outboxBox);
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<void> sync(FakeSupabase client) async {
    final manager = SyncManager(
      supabase: client,
      outboxService: outbox,
      receiptsBox: receiptsBox,
      boxesBox: boxesBox,
      invoicesBox: invoicesBox,
      assetsBox: assetsBox,
      settingsBox: await Hive.openBox('settings'),
    );
    await manager.syncAll();
    manager.dispose();
  }

  Future<SyncOutboxItem> enqueueEdit(String type, String id) {
    return outbox.enqueue(entityType: type, entityId: id, mutationType: 'upsert', payload: {'id': id});
  }

  /// Server copy that is newer by version and timestamp than the local one.
  Map<String, dynamic> staleServerRow(String id, Map<String, dynamic> fields) => {
        'id': id,
        'version': 7,
        'updated_at': '2026-09-30T12:00:00.000Z',
        'deleted_at': null,
        ...fields,
      };

  test('a receipt edit waiting in the outbox is not overwritten', () async {
    await receiptsBox.put('rec-1', ReceiptModel(
      id: 'rec-1', merchantName: 'Edited locally', date: DateTime.utc(2026, 9, 1),
      totalAmount: 10, currency: 'EUR', items: [ReceiptItemModel(description: 'Bread', unitPrice: 10, quantity: 1)],
    ));
    await enqueueEdit('receipt', 'rec-1');
    final client = FakeSupabase(rowsByTable: {
      'receipts': [staleServerRow('rec-1', {'merchant_name': 'Stale server copy', 'scanned_date': '2026-09-01T00:00:00Z'})],
    })..writeErrors['receipts'] = const SocketException('connection reset');

    await sync(client);

    expect(receiptsBox.get('rec-1')!.merchantName, 'Edited locally');
    expect(receiptsBox.get('rec-1')!.items.single.description, 'Bread');
  });

  test('a box edit waiting in the outbox is not overwritten', () async {
    await boxesBox.put('box-1', BoxModel(id: 'box-1', name: 'Edited locally', budget: 100, spent: 0, currency: 'EUR', color: 1));
    await enqueueEdit('box', 'box-1');
    final client = FakeSupabase(rowsByTable: {
      'boxes': [staleServerRow('box-1', {'name': 'Stale server copy', 'budget': 50, 'spent': 0, 'currency': 'EUR'})],
    })..writeErrors['boxes'] = const SocketException('connection reset');

    await sync(client);

    expect(boxesBox.get('box-1')!.name, 'Edited locally');
  });

  test('an invoice edit waiting in the outbox is not overwritten', () async {
    await invoicesBox.put('inv-1', InvoiceModel(
      id: 'inv-1', invoiceNumber: 'INV-1', clientName: 'Edited locally', amount: 100,
      status: 'Draft', issuedDate: DateTime.utc(2026, 9, 1),
    ));
    await enqueueEdit('invoice', 'inv-1');
    final client = FakeSupabase(rowsByTable: {
      'invoices': [staleServerRow('inv-1', {
        'invoice_number': 'INV-1', 'client_name': 'Stale server copy', 'amount': 100,
        'status': 'Draft', 'issued_date': '2026-09-01T00:00:00Z',
      })],
    })..writeErrors['invoices'] = const SocketException('connection reset');

    await sync(client);

    expect(invoicesBox.get('inv-1')!.clientName, 'Edited locally');
  });

  test('an asset edit waiting in the outbox is not overwritten', () async {
    await assetsBox.put('asset-1', AssetModel(
      id: 'asset-1', name: 'Edited locally', purchaseDate: DateTime.utc(2026, 9, 1),
      warrantyMonths: 24, price: 99, receiptImagePath: '', merchantName: 'Store',
    ));
    await enqueueEdit('asset', 'asset-1');
    final client = FakeSupabase(rowsByTable: {
      'vault_assets': [staleServerRow('asset-1', {
        'name': 'Stale server copy', 'purchase_date': '2026-09-01T00:00:00Z',
        'warranty_months': 24, 'price': 99, 'merchant_name': 'Store',
      })],
    })..writeErrors['vault_assets'] = const SocketException('connection reset');

    await sync(client);

    expect(assetsBox.get('asset-1')!.name, 'Edited locally');
  });

  test('a remote tombstone does not delete an entity with an unsynced edit', () async {
    await boxesBox.put('box-1', BoxModel(id: 'box-1', name: 'Edited locally', budget: 100, spent: 0, currency: 'EUR', color: 1));
    await enqueueEdit('box', 'box-1');
    final client = FakeSupabase(rowsByTable: {
      'boxes': [staleServerRow('box-1', {'name': 'Deleted elsewhere', 'deleted_at': '2026-09-30T12:00:00.000Z'})],
    })..writeErrors['boxes'] = const SocketException('connection reset');

    await sync(client);

    expect(boxesBox.get('box-1')?.name, 'Edited locally');
  });

  test('a dead-lettered edit is also protected until it is retried or discarded', () async {
    await boxesBox.put('box-1', BoxModel(id: 'box-1', name: 'Edited locally', budget: 100, spent: 0, currency: 'EUR', color: 1));
    final item = await enqueueEdit('box', 'box-1');
    await outbox.markFailed(item.id, 'rejected', permanent: true);
    final client = FakeSupabase(rowsByTable: {
      'boxes': [staleServerRow('box-1', {'name': 'Stale server copy'})],
    });

    await sync(client);

    expect(boxesBox.get('box-1')!.name, 'Edited locally');
  });

  test('remote changes still apply to entities without unsynced edits', () async {
    await boxesBox.put('box-1', BoxModel(id: 'box-1', name: 'Old local copy', budget: 100, spent: 0, currency: 'EUR', color: 1));
    final client = FakeSupabase(rowsByTable: {
      'boxes': [staleServerRow('box-1', {'name': 'Renamed on another device'})],
    });

    await sync(client);

    expect(boxesBox.get('box-1')!.name, 'Renamed on another device');
  });
}
