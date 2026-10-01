import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:t_aidy/core/sync/models/sync_outbox_item.dart';
import 'package:t_aidy/core/sync/outbox_service.dart';
import 'package:t_aidy/core/sync/sync_manager.dart';
import 'package:t_aidy/features/boxes/data/models/box_model.dart';
import 'package:t_aidy/features/evault/data/models/asset_model.dart';
import 'package:t_aidy/features/invoices/data/models/invoice_model.dart';
import 'package:t_aidy/features/receipt_scanning/data/models/receipt_model.dart';

/// Collects the column names of [table] from every migration in `supabase/migrations/`,
/// from both its `CREATE TABLE` block and its `ADD COLUMN IF NOT EXISTS` statements.
Set<String> _migrationColumns(String table) {
  final columns = <String>{};
  final files = Directory('supabase/migrations')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.sql'));

  final createBlock = RegExp(
    'CREATE TABLE IF NOT EXISTS public\\.$table \\((.*?)\\n\\);',
    dotAll: true,
  );
  final columnLine = RegExp(r'^\s*([a-z_]+)\s+[A-Z]', multiLine: true);
  final addColumn = RegExp(
    'ALTER TABLE public\\.$table ADD COLUMN IF NOT EXISTS ([a-z_]+)',
  );

  for (final file in files) {
    final sql = file.readAsStringSync();
    for (final block in createBlock.allMatches(sql)) {
      for (final line in columnLine.allMatches(block.group(1)!)) {
        columns.add(line.group(1)!);
      }
    }
    for (final match in addColumn.allMatches(sql)) {
      columns.add(match.group(1)!);
    }
  }
  return columns;
}

ReceiptModel _receipt({String id = 'rec-1', List<ReceiptItemModel>? items, int version = 1}) {
  return ReceiptModel(
    id: id,
    merchantName: 'Merchant',
    date: DateTime.utc(2026, 9, 30, 12),
    totalAmount: 12.5,
    currency: 'EUR',
    items: items ??
        [ReceiptItemModel(description: 'Bread', unitPrice: 2.5, quantity: 5)],
    version: version,
  );
}

class _FakeAuth extends Fake implements GoTrueClient {
  @override
  User? get currentUser => User(
        id: 'user-1',
        appMetadata: const {},
        userMetadata: const {},
        aud: 'authenticated',
        createdAt: '2026-01-01T00:00:00Z',
      );
}

/// Records writes and serves canned rows for selects.
class _FakeSupabase extends Fake implements SupabaseClient {
  final Map<String, List<Map<String, dynamic>>> rowsByTable;
  final List<MapEntry<String, Object>> upserts = [];

  _FakeSupabase({this.rowsByTable = const {}});

  @override
  GoTrueClient get auth => _FakeAuth();

  @override
  SupabaseQueryBuilder from(String table) => _FakeQueryBuilder(this, table);
}

class _FakeQueryBuilder extends Fake implements SupabaseQueryBuilder {
  final _FakeSupabase client;
  final String table;

  _FakeQueryBuilder(this.client, this.table);

  @override
  PostgrestFilterBuilder<dynamic> upsert(
    Object values, {
    String? onConflict,
    bool ignoreDuplicates = false,
    bool defaultToNull = true,
  }) {
    client.upserts.add(MapEntry(table, values));
    return _FakeFilterBuilder<dynamic>(null);
  }

  @override
  PostgrestFilterBuilder<dynamic> insert(Object values, {bool defaultToNull = true}) {
    return _FakeFilterBuilder<dynamic>(null);
  }

  @override
  PostgrestFilterBuilder<PostgrestList> select([String columns = '*']) {
    return _FakeFilterBuilder<PostgrestList>(client.rowsByTable[table] ?? <Map<String, dynamic>>[]);
  }
}

class _FakeFilterBuilder<T> extends Fake implements PostgrestFilterBuilder<T> {
  final Object? result;

  _FakeFilterBuilder(this.result);

  @override
  PostgrestFilterBuilder<T> eq(String column, Object value) => this;

  @override
  PostgrestFilterBuilder<T> gt(String column, Object value) => this;

  @override
  Future<R> then<R>(FutureOr<R> Function(T value) onValue, {Function? onError}) async {
    return onValue(result as T);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('public.receipts wire contract', () {
    test('every remote column exists in the migrations', () {
      final schemaColumns = _migrationColumns('receipts');

      expect(schemaColumns, contains('scanned_date'));
      expect(ReceiptModel.remoteColumns.difference(schemaColumns), isEmpty);
    });

    test('toRemoteJson emits only schema columns and keeps line items', () {
      final json = _receipt().toRemoteJson();

      expect(json.keys.toSet().difference(_migrationColumns('receipts')), isEmpty);
      expect(json.containsKey('date'), isFalse);
      expect(json['scanned_date'], '2026-09-30T12:00:00.000Z');
      expect(json['items'], hasLength(1));
    });

    test('sanitizeRemotePayload removes keys enqueued by earlier versions', () {
      final legacy = _receipt().toJson()..['image_url'] = 'https://example.invalid/x.jpg';

      final sanitized = ReceiptModel.sanitizeRemotePayload(legacy);

      expect(sanitized.containsKey('date'), isFalse);
      expect(sanitized.containsKey('image_url'), isFalse);
      expect(sanitized['merchant_name'], 'Merchant');
    });
  });

  group('SyncManager receipt synchronization', () {
    late Directory tempDir;
    late Box<ReceiptModel> receiptsBox;
    late Box<BoxModel> boxesBox;
    late Box<InvoiceModel> invoicesBox;
    late Box<AssetModel> assetsBox;
    late Box<SyncOutboxItem> outboxBox;
    late Box settingsBox;
    late OutboxService outboxService;

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
      tempDir = await Directory.systemTemp.createTemp('receipt_contract_');
      Hive.init(tempDir.path);
      receiptsBox = await Hive.openBox<ReceiptModel>('receipts');
      boxesBox = await Hive.openBox<BoxModel>('boxes');
      invoicesBox = await Hive.openBox<InvoiceModel>('invoices');
      assetsBox = await Hive.openBox<AssetModel>('assets');
      outboxBox = await Hive.openBox<SyncOutboxItem>('outbox');
      settingsBox = await Hive.openBox('settings');
      outboxService = OutboxService(outboxBox);
    });

    tearDown(() async {
      await Hive.close();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    SyncManager createManager(_FakeSupabase client) {
      return SyncManager(
        supabase: client,
        outboxService: outboxService,
        receiptsBox: receiptsBox,
        boxesBox: boxesBox,
        invoicesBox: invoicesBox,
        assetsBox: assetsBox,
        settingsBox: settingsBox,
      );
    }

    test('push sends only schema columns, including for legacy payloads', () async {
      await outboxService.enqueue(
        entityType: 'receipt',
        entityId: 'rec-1',
        mutationType: 'upsert',
        payload: _receipt().toJson(), // pre-fix payload shape, still containing `date`
      );
      final client = _FakeSupabase();
      final manager = createManager(client);

      await manager.syncAll();
      manager.dispose();

      final receiptUpserts = client.upserts.where((u) => u.key == 'receipts').toList();
      expect(receiptUpserts, hasLength(1));
      final body = receiptUpserts.single.value as Map<String, dynamic>;
      expect(body.keys.toSet().difference(ReceiptModel.remoteColumns), isEmpty);
      expect(body['user_id'], 'user-1');
      expect(body['items'], hasLength(1));
      expect(outboxBox.isEmpty, isTrue);
    });

    test('pull keeps local line items when the remote row has no items array', () async {
      await receiptsBox.put('rec-1', _receipt());
      final remoteRow = _receipt(version: 2).toRemoteJson()..remove('items');
      final client = _FakeSupabase(rowsByTable: {'receipts': [remoteRow]});
      final manager = createManager(client);

      await manager.syncAll();
      manager.dispose();

      final stored = receiptsBox.get('rec-1')!;
      expect(stored.version, 2);
      expect(stored.items.map((i) => i.description), ['Bread']);
    });

    test('pull applies remote line items when the row carries them', () async {
      await receiptsBox.put('rec-1', _receipt());
      final remoteRow = _receipt(
        version: 2,
        items: [ReceiptItemModel(description: 'Milk', unitPrice: 1.2, quantity: 1)],
      ).toRemoteJson();
      final client = _FakeSupabase(rowsByTable: {'receipts': [remoteRow]});
      final manager = createManager(client);

      await manager.syncAll();
      manager.dispose();

      expect(receiptsBox.get('rec-1')!.items.map((i) => i.description), ['Milk']);
    });
  });
}
