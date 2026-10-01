import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:dartz/dartz.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:t_aidy/core/error/failures.dart';
import 'package:t_aidy/core/sync/models/sync_outbox_item.dart';
import 'package:t_aidy/core/sync/outbox_service.dart';
import 'package:t_aidy/core/sync/sync_manager.dart';
import 'package:t_aidy/core/crdt/crdt_sync_engine.dart';
import 'package:t_aidy/core/crdt/hlc.dart';
import 'package:t_aidy/core/services/google_drive_service.dart';
import 'package:t_aidy/features/receipt_scanning/domain/entities/receipt.dart';
import 'package:t_aidy/features/receipt_scanning/domain/repositories/receipt_repository.dart';
import 'package:t_aidy/features/receipt_scanning/data/models/receipt_model.dart';
import 'package:t_aidy/features/receipt_scanning/data/repositories/receipt_repository_impl.dart';
import 'package:t_aidy/features/receipt_scanning/presentation/providers/receipt_provider.dart';
import 'package:t_aidy/features/receipt_scanning/data/datasources/hive_receipt_data_source.dart';
import 'package:t_aidy/features/receipt_scanning/data/datasources/receipt_image_store.dart';
import 'package:t_aidy/features/receipt_scanning/data/datasources/supabase_data_source.dart';
import 'package:t_aidy/features/receipt_scanning/data/datasources/sync_service.dart';
import 'package:t_aidy/features/receipt_scanning/data/models/sync_item_model.dart';
import 'package:t_aidy/features/settings/data/datasources/webhook_service.dart';
import 'package:t_aidy/features/evault/data/models/asset_model.dart';
import 'package:t_aidy/features/evault/presentation/providers/asset_provider.dart';
import 'package:t_aidy/features/boxes/data/models/box_model.dart';
import 'package:t_aidy/features/boxes/data/providers/boxes_provider.dart';
import 'package:t_aidy/features/invoices/data/models/invoice_model.dart';
import 'package:t_aidy/features/invoices/data/providers/invoices_provider.dart';
import 'package:t_aidy/core/services/ai_service.dart';

class FakeLocalDataSource implements LocalReceiptDataSource {
  final Map<String, ReceiptModel> store = {};
  bool shouldFail = false;

  @override
  Future<List<ReceiptModel>> getReceipts() async {
    if (shouldFail) throw const CacheFailure();
    return store.values.toList();
  }

  @override
  Future<ReceiptModel?> getReceipt(String id) async {
    if (shouldFail) throw const CacheFailure();
    return store[id];
  }

  @override
  Future<void> saveReceipt(ReceiptModel receipt) async {
    if (shouldFail) throw const CacheFailure();
    store[receipt.id] = receipt;
  }

  @override
  Future<void> clearAll() async {
    if (shouldFail) throw const CacheFailure();
    store.clear();
  }

  @override
  Future<void> deleteReceipt(String id) async {
    if (shouldFail) throw const CacheFailure();
    store.remove(id);
  }
}

class FakeSupabaseDataSource implements SupabaseDataSource {
  final List<String> deletedIds = [];

  @override
  Future<void> deleteData(List<String> ids, {List<String>? imagePaths}) async {
    deletedIds.addAll(ids);
  }

  final List<String> hardDeletedIds = [];

  @override
  Future<void> deleteReceipts(List<String> ids) async {
    hardDeletedIds.addAll(ids);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeAiService implements AIService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeFailingRepository implements ReceiptRepository {
  List<Receipt> receipts;
  bool shouldFailSave = false;
  bool shouldFailDelete = false;
  bool shouldFailClear = false;

  FakeFailingRepository(this.receipts);

  @override
  Future<Either<Failure, List<Receipt>>> getReceipts() async => Right(receipts);

  @override
  Future<Either<Failure, void>> saveReceipt(Receipt receipt) async {
    if (shouldFailSave) return const Left(CacheFailure('Simulated write failure'));
    receipts = [receipt, ...receipts.where((r) => r.id != receipt.id)];
    return const Right(null);
  }

  @override
  Future<Either<Failure, void>> deleteReceipt(String id) async {
    if (shouldFailDelete) return const Left(CacheFailure('Simulated delete failure'));
    receipts = receipts.where((r) => r.id != id).toList();
    return const Right(null);
  }

  @override
  Future<Either<Failure, void>> clearAllData({bool includeCloud = false}) async {
    if (shouldFailClear) return const Left(CacheFailure('Simulated clear failure'));
    receipts = [];
    return const Right(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSyncSupabaseClient extends Fake implements SupabaseClient {
  final User? mockUser;
  final bool Function(String table, Map<String, dynamic> payload)? shouldFailUpsert;
  final List<Map<String, dynamic>> upsertedRows = [];

  FakeSyncSupabaseClient({this.mockUser, this.shouldFailUpsert});

  @override
  GoTrueClient get auth => FakeGoTrueClient(mockUser);

  @override
  SupabaseQueryBuilder from(String table) => FakeSyncQueryBuilder(this, table);
}

class FakeGoTrueClient extends Fake implements GoTrueClient {
  final User? _user;
  FakeGoTrueClient(this._user);

  @override
  User? get currentUser => _user;
}

class FakeSyncQueryBuilder extends Fake implements SupabaseQueryBuilder {
  final FakeSyncSupabaseClient client;
  final String table;
  FakeSyncQueryBuilder(this.client, this.table);

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #upsert) {
      final payload = Map<String, dynamic>.from(invocation.positionalArguments[0] as Map);
      client.upsertedRows.add(payload);
      if (client.shouldFailUpsert != null && client.shouldFailUpsert!(table, payload)) {
        throw Exception('Simulated Supabase 500 Network Failure');
      }
      return FakePostgrestFilterBuilder<List<Map<String, dynamic>>>(client);
    }
    if (invocation.memberName == #select ||
        invocation.memberName == #update ||
        invocation.memberName == #insert) {
      return FakePostgrestFilterBuilder<List<Map<String, dynamic>>>(client);
    }
    return super.noSuchMethod(invocation);
  }
}

class FakePostgrestFilterBuilder<T> extends Fake implements PostgrestFilterBuilder<T> {
  final FakeSyncSupabaseClient client;
  FakePostgrestFilterBuilder(this.client);

  @override
  PostgrestFilterBuilder<T> eq(String column, Object value) => this;

  @override
  PostgrestFilterBuilder<T> gt(String column, Object value) => this;

  @override
  Future<TResult> then<TResult>(FutureOr<TResult> Function(T value) onValue, {Function? onError}) async {
    return onValue(<Map<String, dynamic>>[] as T);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Box<SyncOutboxItem> outboxBox;
  late Box<AssetModel> assetsBox;
  late Box<BoxModel> boxesBox;
  late Box<InvoiceModel> invoicesBox;
  late Box settingsBox;
  late Box<SyncItemModel> syncQueueBox;
  late OutboxService outboxService;

  setUpAll(() {
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ReceiptModelAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(ReceiptItemModelAdapter());
    if (!Hive.isAdapterRegistered(6)) Hive.registerAdapter(SyncItemModelAdapter());
    if (!Hive.isAdapterRegistered(7)) Hive.registerAdapter(AssetModelAdapter());
    if (!Hive.isAdapterRegistered(10)) Hive.registerAdapter(BoxModelAdapter());
    if (!Hive.isAdapterRegistered(11)) Hive.registerAdapter(InvoiceModelAdapter());
    if (!Hive.isAdapterRegistered(12)) Hive.registerAdapter(SyncOutboxItemAdapter());
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('improvements_test_');
    Hive.init(tempDir.path);

    outboxBox = await Hive.openBox<SyncOutboxItem>('outbox_test');
    assetsBox = await Hive.openBox<AssetModel>('assets_test');
    boxesBox = await Hive.openBox<BoxModel>('boxes_test');
    invoicesBox = await Hive.openBox<InvoiceModel>('invoices_test');
    settingsBox = await Hive.openBox('settings_test');
    syncQueueBox = await Hive.openBox<SyncItemModel>('sync_queue_test');

    outboxService = OutboxService(outboxBox);
  });

  tearDown(() async {
    await outboxBox.close();
    await assetsBox.close();
    await boxesBox.close();
    await invoicesBox.close();
    await settingsBox.close();
    await syncQueueBox.close();
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Area 1: Dual-Tier Outbox & Tombstone Enqueueing', () {
    test('ReceiptRepositoryImpl enqueues upsert mutations and delete tombstones in OutboxService', () async {
      final fakeLocal = FakeLocalDataSource();
      final fakeSupabase = FakeSupabaseDataSource();
      final syncService = SyncService(
        queueBox: syncQueueBox,
        localDataSource: fakeLocal,
        supabaseDataSource: fakeSupabase,
        settingsBox: settingsBox,
        googleDriveService: GoogleDriveService(),
      );
      final webhookService = WebhookService(settingsBox);

      final repo = ReceiptRepositoryImpl(
        localDataSource: fakeLocal,
        aiService: FakeAiService(),
        supabaseDataSource: fakeSupabase,
        settingsBox: settingsBox,
        syncService: syncService,
        webhookService: webhookService,
        assetsBox: assetsBox,
        outboxService: outboxService,
      );

      final testReceipt = Receipt(
        id: 'test-rcpt-1',
        merchantName: 'Acme Hardware',
        date: DateTime.utc(2026, 9, 20),
        totalAmount: 129.99,
        currency: 'USD',
        items: [
          ReceiptItem(
            description: 'Cordless Drill',
            unitPrice: 129.99,
            totalPrice: 129.99,
            quantity: 1,
            isAsset: true,
          ),
        ],
      );

      // Save receipt
      final saveResult = await repo.saveReceipt(testReceipt);
      expect(saveResult.isRight(), isTrue);

      final pendingAfterSave = outboxService.getPendingMutations();
      expect(pendingAfterSave.length, greaterThanOrEqualTo(2)); // 1 receipt upsert + 1 asset upsert
      expect(pendingAfterSave.any((item) => item.entityType == 'receipt' && item.entityId == 'test-rcpt-1'), isTrue);
      expect(pendingAfterSave.any((item) => item.entityType == 'asset' && item.mutationType == 'upsert'), isTrue);

      // Delete receipt
      final deleteResult = await repo.deleteReceipt('test-rcpt-1');
      expect(deleteResult.isRight(), isTrue);

      final pendingAfterDelete = outboxService.getPendingMutations();
      expect(pendingAfterDelete.any((item) => item.entityType == 'receipt' && item.entityId == 'test-rcpt-1' && item.mutationType == 'delete'), isTrue);
    });

    group('clearAllData', () {
      late FakeLocalDataSource fakeLocal;
      late FakeSupabaseDataSource fakeSupabase;
      late ReceiptRepositoryImpl repo;

      setUp(() {
        fakeLocal = FakeLocalDataSource()
          ..store['rcpt-a'] = ReceiptModel(
            id: 'rcpt-a',
            merchantName: 'Bakery',
            date: DateTime.utc(2026, 9, 1),
            totalAmount: 4.5,
            currency: 'EUR',
            items: const [],
          );
        fakeSupabase = FakeSupabaseDataSource();
        repo = ReceiptRepositoryImpl(
          localDataSource: fakeLocal,
          aiService: FakeAiService(),
          supabaseDataSource: fakeSupabase,
          settingsBox: settingsBox,
          syncService: SyncService(
            queueBox: syncQueueBox,
            localDataSource: fakeLocal,
            supabaseDataSource: fakeSupabase,
            settingsBox: settingsBox,
            googleDriveService: GoogleDriveService(),
          ),
          webhookService: WebhookService(settingsBox),
          assetsBox: assetsBox,
          outboxService: outboxService,
        );
      });

      test('device-only clearing enqueues no delete mutation and leaves the cloud untouched', () async {
        final result = await repo.clearAllData(includeCloud: false);

        expect(result.isRight(), isTrue);
        expect(fakeLocal.store, isEmpty);
        expect(fakeSupabase.deletedIds, isEmpty);
        expect(outboxService.getPendingMutations().where((m) => m.mutationType == 'delete'), isEmpty);
      });

      test('saving keeps the image in durable storage and deleting the receipt removes it', () async {
        final docs = await Directory.systemTemp.createTemp('repo_images_docs_');
        addTearDown(() => docs.deleteSync(recursive: true));
        final picked = File('${docs.path}/../picked_${DateTime.now().microsecondsSinceEpoch}.jpg')
          ..writeAsBytesSync([9, 9, 9]);
        addTearDown(() {
          if (picked.existsSync()) picked.deleteSync();
        });
        final imageRepo = ReceiptRepositoryImpl(
          localDataSource: fakeLocal,
          aiService: FakeAiService(),
          supabaseDataSource: fakeSupabase,
          settingsBox: settingsBox,
          syncService: SyncService(
            queueBox: syncQueueBox,
            localDataSource: fakeLocal,
            supabaseDataSource: fakeSupabase,
            settingsBox: settingsBox,
            googleDriveService: GoogleDriveService(),
          ),
          webhookService: WebhookService(settingsBox),
          assetsBox: assetsBox,
          outboxService: outboxService,
          imageStore: ReceiptImageStore(documentsDirectory: () async => docs),
        );

        await imageRepo.saveReceipt(Receipt(
          id: 'rcpt-img',
          merchantName: 'Bakery',
          date: DateTime.utc(2026, 9, 1),
          totalAmount: 4.5,
          currency: 'EUR',
          imagePath: picked.path,
        ));

        final storedPath = fakeLocal.store['rcpt-img']!.imagePath!;
        expect(storedPath, startsWith('${docs.path}/${ReceiptImageStore.folderName}/'));
        expect(File(storedPath).existsSync(), isTrue);

        await imageRepo.deleteReceipt('rcpt-img');
        expect(File(storedPath).existsSync(), isFalse);
      });

      test('clearing everywhere deletes remotely and enqueues tombstones', () async {
        final result = await repo.clearAllData(includeCloud: true);

        expect(result.isRight(), isTrue);
        expect(fakeLocal.store, isEmpty);
        expect(fakeSupabase.deletedIds, contains('rcpt-a'));
        // Rows are soft-deleted through the tombstones, never hard-deleted.
        expect(fakeSupabase.hardDeletedIds, isEmpty);
        final deletes = outboxService.getPendingMutations().where((m) => m.mutationType == 'delete').toList();
        expect(deletes.map((m) => m.entityId), ['rcpt-a']);
      });
    });

    test('BoxesNotifier enqueues upsert mutations and delete tombstones', () async {
      final notifier = BoxesNotifier(boxesBox, null, outboxService);

      final newBox = await notifier.createNew(
        name: 'Work Expenses',
        budget: 1200.0,
        currency: 'EUR',
        color: Colors.blue,
      );

      expect(notifier.state.any((b) => b.id == newBox.id), isTrue);

      final pendingUpserts = outboxService.getPendingMutations().where((m) => m.entityType == 'box' && m.mutationType == 'upsert').toList();
      expect(pendingUpserts.length, 1);
      expect(pendingUpserts.first.entityId, newBox.id);

      // Delete box
      await notifier.deleteBox(newBox.id);
      expect(notifier.state.any((b) => b.id == newBox.id), isFalse);

      final pendingDeletes = outboxService.getPendingMutations().where((m) => m.entityType == 'box' && m.mutationType == 'delete').toList();
      expect(pendingDeletes.length, 1);
      expect(pendingDeletes.first.entityId, newBox.id);
    });

    test('InvoicesNotifier enqueues upsert mutations and delete tombstones', () async {
      final notifier = InvoicesNotifier(invoicesBox, settingsBox, outboxService);

      final inv = await notifier.create(
        clientName: 'Global Media Corp',
        amount: 3400.0,
        status: InvoiceStatus.draft,
        issuedDate: DateTime.utc(2026, 9, 21),
      );

      expect(notifier.state.any((i) => i.id == inv.id), isTrue);

      final pendingUpserts = outboxService.getPendingMutations().where((m) => m.entityType == 'invoice' && m.mutationType == 'upsert').toList();
      expect(pendingUpserts.length, 1);
      expect(pendingUpserts.first.entityId, inv.id);

      // Update status
      await notifier.updateInvoiceStatus(inv.id, InvoiceStatus.sent);
      final allUpserts = outboxService.getPendingMutations().where((m) => m.entityType == 'invoice' && m.mutationType == 'upsert').toList();
      expect(allUpserts.length, 2);

      // Delete
      await notifier.delete(inv.id);
      expect(notifier.state.any((i) => i.id == inv.id), isFalse);

      final pendingDeletes = outboxService.getPendingMutations().where((m) => m.entityType == 'invoice' && m.mutationType == 'delete').toList();
      expect(pendingDeletes.length, 1);
      expect(pendingDeletes.first.entityId, inv.id);
    });

    test('AssetNotifier enqueues upsert mutations and delete tombstones', () async {
      final notifier = AssetNotifier(assetsBox, outboxService);

      final receipt = Receipt(
        id: 'rcpt-vault-1',
        merchantName: 'Apple Store',
        date: DateTime.utc(2026, 9, 10),
        totalAmount: 1999.0,
        currency: 'USD',
      );
      final item = ReceiptItem(
        description: 'MacBook Pro M4',
        unitPrice: 1999.0,
        totalPrice: 1999.0,
        quantity: 1,
        isAsset: true,
      );

      await notifier.addAssetFromReceiptItem(item, receipt);
      expect(notifier.state.length, 1);
      final assetId = notifier.state.first.id;

      final pendingUpserts = outboxService.getPendingMutations().where((m) => m.entityType == 'asset' && m.mutationType == 'upsert').toList();
      expect(pendingUpserts.length, 1);
      expect(pendingUpserts.first.entityId, assetId);

      // Delete asset
      await notifier.deleteAsset(assetId);
      expect(notifier.state.isEmpty, isTrue);

      final pendingDeletes = outboxService.getPendingMutations().where((m) => m.entityType == 'asset' && m.mutationType == 'delete').toList();
      expect(pendingDeletes.length, 1);
      expect(pendingDeletes.first.entityId, assetId);
    });

    test('ReceiptRepositoryImpl saves assets via put(asset.id, asset) with timestamps and allows retrieval and deletion by ID', () async {
      final fakeLocal = FakeLocalDataSource();
      final fakeSupabase = FakeSupabaseDataSource();
      final syncService = SyncService(
        queueBox: syncQueueBox,
        localDataSource: fakeLocal,
        supabaseDataSource: fakeSupabase,
        settingsBox: settingsBox,
        googleDriveService: GoogleDriveService(),
      );
      final webhookService = WebhookService(settingsBox);

      final repo = ReceiptRepositoryImpl(
        localDataSource: fakeLocal,
        aiService: FakeAiService(),
        supabaseDataSource: fakeSupabase,
        settingsBox: settingsBox,
        syncService: syncService,
        webhookService: webhookService,
        assetsBox: assetsBox,
        outboxService: outboxService,
      );

      final testReceipt = Receipt(
        id: 'test-rcpt-asset',
        merchantName: 'Best Buy',
        date: DateTime.utc(2026, 9, 22),
        totalAmount: 499.99,
        currency: 'USD',
        items: [
          ReceiptItem(
            description: '4K Monitor',
            unitPrice: 499.99,
            totalPrice: 499.99,
            quantity: 1,
            isAsset: true,
          ),
        ],
      );

      await repo.saveReceipt(testReceipt);

      // Verify asset exists in assetsBox and was keyed by its ID
      expect(assetsBox.values.length, 1);
      final savedAsset = assetsBox.values.first;
      expect(savedAsset.createdAt, isNotNull);
      expect(savedAsset.updatedAt, isNotNull);

      // Verify assetsBox.get(savedAsset.id) returns the asset (proving put vs add)
      final retrieved = assetsBox.get(savedAsset.id);
      expect(retrieved, isNotNull);
      expect(retrieved!.name, '4K Monitor');

      // Verify assetsBox.delete(savedAsset.id) successfully removes it
      await assetsBox.delete(savedAsset.id);
      expect(assetsBox.values.isEmpty, isTrue);
    });

    test('ReceiptRepositoryImpl does not enqueue outbox tombstone if local delete fails', () async {
      final fakeLocal = FakeLocalDataSource()..shouldFail = true;
      final fakeSupabase = FakeSupabaseDataSource();
      final syncService = SyncService(
        queueBox: syncQueueBox,
        localDataSource: fakeLocal,
        supabaseDataSource: fakeSupabase,
        settingsBox: settingsBox,
        googleDriveService: GoogleDriveService(),
      );
      final webhookService = WebhookService(settingsBox);

      final repo = ReceiptRepositoryImpl(
        localDataSource: fakeLocal,
        aiService: FakeAiService(),
        supabaseDataSource: fakeSupabase,
        settingsBox: settingsBox,
        syncService: syncService,
        webhookService: webhookService,
        assetsBox: assetsBox,
        outboxService: outboxService,
      );

      final result = await repo.deleteReceipt('any-id');
      expect(result.isLeft(), isTrue);
      expect(outboxService.getPendingMutations().isEmpty, isTrue);
    });
  });

  group('Area 2: Optimistic State Rollback on Failure', () {
    test('ReceiptListNotifier rolls back state when addReceipt encounters repository failure', () async {
      final initialReceipt = Receipt(
        id: 'initial-1',
        merchantName: 'Coffee Shop',
        date: DateTime.utc(2026, 9, 1),
        totalAmount: 4.50,
        currency: 'USD',
      );
      final failingRepo = FakeFailingRepository([initialReceipt]);
      final notifier = ReceiptListNotifier(failingRepo);

      await notifier.loadReceipts();
      expect(notifier.state.value!.length, 1);

      failingRepo.shouldFailSave = true;

      final newReceipt = Receipt(
        id: 'failing-rcpt',
        merchantName: 'Ghost Store',
        date: DateTime.utc(2026, 9, 2),
        totalAmount: 99.0,
        currency: 'USD',
      );

      await notifier.addReceipt(newReceipt);

      // State MUST roll back to initial state, preventing ghost receipts
      expect(notifier.state.value!.length, 1);
      expect(notifier.state.value!.first.id, 'initial-1');
    });

    test('ReceiptListNotifier rolls back state when deleteReceipt encounters repository failure', () async {
      final initialReceipt = Receipt(
        id: 'initial-1',
        merchantName: 'Coffee Shop',
        date: DateTime.utc(2026, 9, 1),
        totalAmount: 4.50,
        currency: 'USD',
      );
      final failingRepo = FakeFailingRepository([initialReceipt]);
      final notifier = ReceiptListNotifier(failingRepo);

      await notifier.loadReceipts();
      expect(notifier.state.value!.length, 1);

      failingRepo.shouldFailDelete = true;

      await notifier.deleteReceipt('initial-1');

      // State MUST roll back to retain initial-1
      expect(notifier.state.value!.length, 1);
      expect(notifier.state.value!.first.id, 'initial-1');
    });

    test('ReceiptListNotifier rolls back state when clearAll encounters repository failure', () async {
      final initialReceipt = Receipt(
        id: 'initial-1',
        merchantName: 'Coffee Shop',
        date: DateTime.utc(2026, 9, 1),
        totalAmount: 4.50,
        currency: 'USD',
      );
      final failingRepo = FakeFailingRepository([initialReceipt]);
      final notifier = ReceiptListNotifier(failingRepo);

      await notifier.loadReceipts();
      expect(notifier.state.value!.length, 1);

      failingRepo.shouldFailClear = true;

      await notifier.clearAll();

      // State MUST roll back to retain initial-1
      expect(notifier.state.value!.length, 1);
      expect(notifier.state.value!.first.id, 'initial-1');
    });

    test('InvoicesNotifier and AssetNotifier reload state from persistent storage', () async {
      final invoicesNotifier = InvoicesNotifier(invoicesBox, settingsBox, outboxService);
      final assetNotifier = AssetNotifier(assetsBox, outboxService);

      // Seed directly into Hive
      final externalInvoice = InvoiceModel(
        id: 'ext-inv-1',
        invoiceNumber: 'INV-202609-099',
        clientName: 'External Client',
        amount: 500,
        status: InvoiceStatus.draft,
        issuedDate: DateTime.utc(2026, 9, 23),
      );
      await invoicesBox.put(externalInvoice.id, externalInvoice);

      final externalAsset = AssetModel(
        id: 'ext-asset-1',
        name: 'Office Chair',
        purchaseDate: DateTime.utc(2026, 9, 23),
        warrantyMonths: 12,
        price: 150,
        receiptImagePath: '',
        merchantName: 'IKEA',
      );
      await assetsBox.put(externalAsset.id, externalAsset);

      // Verify notifiers reflect the changes after reload()
      invoicesNotifier.reload();
      assetNotifier.reload();

      expect(invoicesNotifier.state.any((i) => i.id == 'ext-inv-1'), isTrue);
      expect(assetNotifier.state.any((a) => a.id == 'ext-asset-1'), isTrue);
    });
  });

  group('Area 3: CRDT Multi-Device Concurrency & Metadata Updates', () {
    test('updateReceiptMetadata updates receipt properties without clobbering line item causality', () {
      final engineA = CrdtSyncEngine(
        nodeId: 'node_alpha',
        initialHlc: Hlc(millis: 1000, counter: 0, nodeId: 'node_alpha'),
      );

      final initialReceipt = ReceiptModel(
        id: 'receipt-crdt-01',
        merchantName: 'Bakery Original',
        date: DateTime.utc(2026, 9, 1),
        totalAmount: 15.00,
        currency: 'EUR',
        boxId: 'main',
        items: [
          ReceiptItemModel(
            description: 'Artisan Bread',
            unitPrice: 5.00,
            quantity: 3,
            category: 'Groceries',
          ),
        ],
      );

      engineA.recordReceipt(initialReceipt);

      // Clone engine state to simulate Replica B
      final engineB = CrdtSyncEngine(
        nodeId: 'node_beta',
        initialHlc: Hlc(millis: 1000, counter: 0, nodeId: 'node_beta'),
      );
      engineB.mergeDeltaPayload(engineA.generateDeltaPayload());

      // Replica A updates top-level metadata: renames merchant and changes boxId
      engineA.updateReceiptMetadata(
        receiptId: 'receipt-crdt-01',
        merchantName: 'Bakery Renamed',
        boxId: 'box_vacation',
      );

      // Replica B concurrently edits the line item price on receipt-crdt-01
      engineB.updateLineItem(
        receiptId: 'receipt-crdt-01',
        itemId: 'receipt-crdt-01_item_0',
        unitPriceCents: 600, // €6.00
      );

      // Merge B into A
      engineA.mergeDeltaPayload(engineB.generateDeltaPayload());

      // Verify BOTH changes survived without clobbering
      final mergedReceipt = engineA.getReceipt('receipt-crdt-01');
      expect(mergedReceipt, isNotNull);
      expect(mergedReceipt!.merchantName, 'Bakery Renamed');
      expect(mergedReceipt.boxId, 'box_vacation');
      expect(mergedReceipt.items.first.unitPrice, 6.00);
      expect(mergedReceipt.items.first.description, 'Artisan Bread');
    });
  });

  group('Area 4: Outbox Fault Tolerance, Backoff & FIFO Causality Preservation', () {
    test('OutboxService respects exponential backoff on retry attempts', () async {
      final item = await outboxService.enqueue(
        entityType: 'box',
        entityId: 'box-backoff',
        mutationType: 'upsert',
        payload: {'name': 'Testing Backoff'},
      );

      // Before failure, item is pending and immediately available
      expect(outboxService.getPendingMutations(respectBackoff: true).length, 1);

      // Mark failed
      await outboxService.markFailed(item.id, 'Simulated Timeout');

      // With respectBackoff == true, recently failed item (lastAttemptAt == now) is delayed
      expect(outboxService.getPendingMutations(respectBackoff: true).isEmpty, isTrue);

      // Manual / force sync ignores backoff
      expect(outboxService.getPendingMutations(respectBackoff: false).length, 1);
    });

    test('OutboxService retryPermanentlyFailed revives dead-lettered mutations', () async {
      final item = await outboxService.enqueue(
        entityType: 'invoice',
        entityId: 'inv-deadletter',
        mutationType: 'upsert',
        payload: {'invoice_number': 'INV-FAIL'},
      );

      // Fail 5 times to push to permanently_failed
      for (int i = 0; i < 5; i++) {
        await outboxService.markFailed(item.id, 'Attempt $i');
      }

      final itemInBox = outboxBox.get(item.id);
      expect(itemInBox?.status, 'permanently_failed');
      expect(outboxService.getPendingMutations().isEmpty, isTrue);

      // Revive permanently failed items
      await outboxService.retryPermanentlyFailed();

      final revivedItem = outboxBox.get(item.id);
      expect(revivedItem?.status, 'pending');
      expect(revivedItem?.retryCount, 0);
      expect(outboxService.getPendingMutations().length, 1);
    });

    test('SyncManager flushes outbox in FIFO order and holds back only the failing entity', () async {
      final mockUser = const User(
        id: 'sync-user-1',
        appMetadata: {},
        userMetadata: {},
        aud: 'authenticated',
        createdAt: '2026-01-01',
      );

      final receiptsBox = await Hive.openBox<ReceiptModel>('receipts_sync_test');

      // Create 4 queued items:
      // Item 1: Box upsert (succeeds)
      // Item 2: Box upsert (fails)
      // Item 3: Upsert of an unrelated box (proceeds despite Item 2 failure)
      // Item 4: Later mutation of the failing box (held back to preserve its order)
      final item1 = await outboxService.enqueue(
        entityType: 'box',
        entityId: 'box-1',
        mutationType: 'upsert',
        payload: {'id': 'box-1', 'name': 'First Box'},
      );
      final item2 = await outboxService.enqueue(
        entityType: 'box',
        entityId: 'box-2',
        mutationType: 'upsert',
        payload: {'id': 'box-2', 'name': 'Failing Box'},
      );
      final item3 = await outboxService.enqueue(
        entityType: 'box',
        entityId: 'box-3',
        mutationType: 'upsert',
        payload: {'id': 'box-3', 'name': 'Unrelated Third Box'},
      );
      final item4 = await outboxService.enqueue(
        entityType: 'box',
        entityId: 'box-2',
        mutationType: 'upsert',
        payload: {'id': 'box-2', 'name': 'Failing Box (renamed)'},
      );

      final fakeSupabase = FakeSyncSupabaseClient(
        mockUser: mockUser,
        shouldFailUpsert: (table, payload) {
          return payload['id'] == 'box-2';
        },
      );

      final syncManager = SyncManager(
        supabase: fakeSupabase,
        outboxService: outboxService,
        receiptsBox: receiptsBox,
        boxesBox: boxesBox,
        invoicesBox: invoicesBox,
        assetsBox: assetsBox,
        settingsBox: settingsBox,
      );

      await syncManager.syncAll();

      // Item 1 succeeded and removed
      expect(outboxBox.containsKey(item1.id), isFalse);

      // Item 2 failed and marked failed
      final item2Status = outboxBox.get(item2.id);
      expect(item2Status?.status, 'failed');
      expect(item2Status?.retryCount, 1);

      // Item 3 belongs to another entity and was not blocked
      expect(outboxBox.containsKey(item3.id), isFalse);

      // Item 4 was NOT processed (preserved causality for box-2, status still pending)
      final item4Status = outboxBox.get(item4.id);
      expect(item4Status?.status, 'pending');
      expect(item4Status?.retryCount, 0);

      await receiptsBox.close();
    });
  });

  group('Area 5: Active Box Lifecycle & Schema Integrity', () {
    test('BoxesNotifier.deleteBox resets activeBoxIdProvider to main when active box is deleted', () async {
      final container = ProviderContainer(
        overrides: [
          boxesProvider.overrideWith((ref) => BoxesNotifier(boxesBox, ref, outboxService)),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(boxesProvider.notifier);
      final newBox = await notifier.createNew(
        name: 'Temporary Project',
        budget: 100,
        currency: 'USD',
        color: Colors.blue,
      );

      container.read(activeBoxIdProvider.notifier).state = newBox.id;
      expect(container.read(activeBoxIdProvider), newBox.id);

      await notifier.deleteBox(newBox.id);
      expect(container.read(activeBoxIdProvider), 'main');
    });

    test('ReceiptModel toJson includes both date and scanned_date for Supabase schema compatibility', () {
      final receipt = Receipt(
        id: 'schema-test',
        merchantName: 'Target',
        date: DateTime.utc(2026, 9, 24, 15, 30),
        totalAmount: 89.50,
        currency: 'USD',
      );
      final model = ReceiptModel.fromEntity(receipt);
      final json = model.toJson();

      expect(json.containsKey('date'), isTrue);
      expect(json.containsKey('scanned_date'), isTrue);
      expect(json['date'], json['scanned_date']);
    });
  });
}
