import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:t_aidy/core/privacy/network_policy.dart';
import 'package:t_aidy/core/sync/models/sync_outbox_item.dart';
import 'package:t_aidy/core/sync/outbox_service.dart';
import 'package:t_aidy/core/sync/sync_manager.dart';
import 'package:t_aidy/features/boxes/data/models/box_model.dart';
import 'package:t_aidy/features/evault/data/models/asset_model.dart';
import 'package:t_aidy/features/invoices/data/models/invoice_model.dart';
import 'package:t_aidy/features/receipt_scanning/data/models/receipt_model.dart';

import 'support/fake_supabase.dart';

Map<String, dynamic> _boxRow(String id, String updatedAt, {String? name}) => {
      'id': id,
      'name': name ?? 'Box $id',
      'budget': 100,
      'spent': 0,
      'currency': 'EUR',
      'color_hex': 1,
      'version': 1,
      'updated_at': updatedAt,
      'deleted_at': null,
    };

String _ts(int minute) => DateTime.utc(2020, 1, 1, 0, minute).toIso8601String();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Box<BoxModel> boxesBox;
  late Box settingsBox;
  late SyncManager manager;
  late FakeSupabase client;
  final serverRows = <Map<String, dynamic>>[];

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
    tempDir = await Directory.systemTemp.createTemp('delta_pull_');
    Hive.init(tempDir.path);
    boxesBox = await Hive.openBox<BoxModel>('boxes');
    settingsBox = await Hive.openBox('settings');
    serverRows.clear();
    client = FakeSupabase(rowsByTable: {'boxes': serverRows});
    manager = SyncManager(
      supabase: client,
      outboxService: OutboxService(await Hive.openBox<SyncOutboxItem>('outbox')),
      receiptsBox: await Hive.openBox<ReceiptModel>('receipts'),
      boxesBox: boxesBox,
      invoicesBox: await Hive.openBox<InvoiceModel>('invoices'),
      assetsBox: await Hive.openBox<AssetModel>('assets'),
      settingsBox: settingsBox,
    );
  });

  tearDown(() async {
    manager.dispose();
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('tables larger than the server row cap are read completely', () async {
    client.maxRows = 1000; // PostgREST max-rows on Supabase projects
    final total = 1003;
    for (var i = 0; i < total; i++) {
      serverRows.add(_boxRow('box-${i.toString().padLeft(5, '0')}', _ts(i % 50)));
    }

    await manager.syncAll();

    expect(boxesBox.length, total);
    expect(client.selectCount['boxes'], (total / SyncManager.pullPageSize).ceil());
  });

  test('more rows than a page sharing one timestamp neither stall nor get skipped', () async {
    final total = SyncManager.pullPageSize + 20;
    for (var i = 0; i < total; i++) {
      serverRows.add(_boxRow('box-${i.toString().padLeft(5, '0')}', _ts(0)));
    }

    await manager.syncAll();

    expect(boxesBox.length, total);
    expect(client.selectCount['boxes'], 2);
  });

  test('the watermark follows server timestamps, not the device clock', () async {
    // The server clock is years behind the device clock.
    serverRows.add(_boxRow('box-a', _ts(1)));
    await manager.syncAll();
    expect(settingsBox.get(SyncManager.watermarkKey('boxes')), _ts(1));

    // Another device then writes a row, still long before "now" on this device.
    serverRows.add(_boxRow('box-b', _ts(2)));
    await manager.syncAll();

    expect(boxesBox.containsKey('box-b'), isTrue);
    expect(settingsBox.get(SyncManager.watermarkKey('boxes')), _ts(2));
  });

  test('upgrading from the device-clock watermark re-reads the table once', () async {
    // Earlier versions stored the device time of the last cycle; rows older than
    // it that were skipped or truncated must be backfilled.
    await settingsBox.put('last_synced_at', DateTime.now().toUtc().toIso8601String());
    serverRows.add(_boxRow('box-missed', _ts(5)));

    await manager.syncAll();

    expect(boxesBox.containsKey('box-missed'), isTrue);
  });

  test('isolation mode skips the sync cycle without any request', () async {
    serverRows.add(_boxRow('box-a', _ts(1)));
    await settingsBox.put(NetworkPolicy.isolationModeKey, true);

    await manager.syncAll();

    expect(client.selectCount, isEmpty);
    expect(client.upserts, isEmpty);
    expect(boxesBox.containsKey('box-a'), isFalse);
  });
}
