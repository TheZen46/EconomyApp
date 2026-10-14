import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:t_aidy/core/privacy/network_policy.dart';
import 'package:t_aidy/core/services/google_drive_service.dart';
import 'package:t_aidy/features/receipt_scanning/data/datasources/hive_receipt_data_source.dart';
import 'package:t_aidy/features/receipt_scanning/data/datasources/supabase_data_source.dart';
import 'package:t_aidy/features/receipt_scanning/data/datasources/sync_service.dart';
import 'package:t_aidy/features/receipt_scanning/data/models/receipt_model.dart';
import 'package:t_aidy/features/receipt_scanning/data/models/sync_item_model.dart';
import 'package:t_aidy/features/receipt_scanning/domain/entities/receipt.dart';

class FakeLocalReceiptDataSource implements LocalReceiptDataSource {
  final Map<String, ReceiptModel> receipts = {};
  int fullScanCount = 0;

  @override
  Future<List<ReceiptModel>> getReceipts() async {
    fullScanCount++;
    return receipts.values.toList();
  }

  @override
  Future<ReceiptModel?> getReceipt(String id) async => receipts[id];

  @override
  Future<void> saveReceipt(ReceiptModel receipt) async {
    receipts[receipt.id] = receipt;
  }

  @override
  Future<void> clearAll() async => receipts.clear();

  @override
  Future<void> deleteReceipt(String id) async {
    receipts.remove(id);
  }
}

class FakeSupabaseDataSource implements SupabaseDataSource {
  int uploadCallCount = 0;
  int activeConcurrentUploads = 0;
  int peakConcurrentUploads = 0;
  final List<String> uploadedReceiptIds = [];
  bool shouldFail = false;
  Object? errorToThrow;

  @override
  Future<void> uploadTrainingData(Receipt receipt, String imagePath) async {
    if (errorToThrow != null) {
      uploadCallCount++;
      throw errorToThrow!;
    }
    if (shouldFail) {
      uploadCallCount++;
      throw Exception('Simulated network failure');
    }

    activeConcurrentUploads++;
    if (activeConcurrentUploads > peakConcurrentUploads) {
      peakConcurrentUploads = activeConcurrentUploads;
    }
    uploadCallCount++;
    uploadedReceiptIds.add(receipt.id);

    // Simulate network delay to expose race conditions
    await Future.delayed(const Duration(milliseconds: 30));

    activeConcurrentUploads--;
  }

  @override
  Future<int> getStorageUsage() async => 0;

  @override
  Future<void> deleteData(List<String> ids, {List<String>? imagePaths}) async {}

  @override
  Future<void> deleteReceipts(List<String> ids) async {}

  @override
  Future<List<Map<String, dynamic>>> fetchAllReceipts({
    int pageSize = 100,
    String tableName = 'receipts',
  }) async => [];
}

class FakeGoogleDriveService extends GoogleDriveService {
  int uploadCallCount = 0;

  @override
  Future<void> uploadReceiptData(Map<String, dynamic> jsonData, String receiptId, String imagePath) async {
    uploadCallCount++;
    await Future.delayed(const Duration(milliseconds: 30));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Box<SyncItemModel> queueBox;
  late Box settingsBox;
  late FakeLocalReceiptDataSource localDataSource;
  late FakeSupabaseDataSource supabaseDataSource;
  late FakeGoogleDriveService googleDriveService;
  late SyncService syncService;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sync_test_dir_');
    Hive.init(tempDir.path);

    if (!Hive.isAdapterRegistered(6)) {
      Hive.registerAdapter(SyncItemModelAdapter());
    }

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (MethodCall methodCall) async {
        return ['wifi'];
      },
    );

    queueBox = await Hive.openBox<SyncItemModel>('test_sync_queue');
    settingsBox = await Hive.openBox('test_settings_box');
    // Upload mechanics are exercised with training contribution consented to;
    // the consent gate itself is covered by its own group below.
    await settingsBox.put(SyncService.trainingContributionKey, true);
    localDataSource = FakeLocalReceiptDataSource();
    supabaseDataSource = FakeSupabaseDataSource();
    googleDriveService = FakeGoogleDriveService();

    syncService = SyncService(
      queueBox: queueBox,
      localDataSource: localDataSource,
      supabaseDataSource: supabaseDataSource,
      settingsBox: settingsBox,
      googleDriveService: googleDriveService,
    );
  });

  tearDown(() async {
    syncService.dispose();
    await queueBox.close();
    await settingsBox.close();
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('SyncService - Mutex Lock & Safe Sequential Sync', () {
    test('single item sync completes successfully and clears queue', () async {
      final receiptModel = ReceiptModel(
        id: 'rec-001',
        merchantName: 'Store A',
        totalAmount: 49.99,
        date: DateTime.now(),
        items: [],
        currency: 'USD',
      );
      await localDataSource.saveReceipt(receiptModel);

      await syncService.scheduleUpload('rec-001', '/images/rec-001.jpg');
      await syncService.syncPendingItems();

      expect(supabaseDataSource.uploadCallCount, 1);
      expect(supabaseDataSource.uploadedReceiptIds, ['rec-001']);
      expect(queueBox.isEmpty, isTrue);
    });

    test('rapid concurrent invocations of syncPendingItems execute sequentially with peak concurrency 1', () async {
      // 1. Prepare 3 receipts
      for (int i = 1; i <= 3; i++) {
        final rec = ReceiptModel(
          id: 'concurrent-rec-$i',
          merchantName: 'Store $i',
          totalAmount: i * 10.0,
          date: DateTime.now(),
          items: [],
          currency: 'USD',
        );
        await localDataSource.saveReceipt(rec);
        await queueBox.add(SyncItemModel(
          receiptId: 'concurrent-rec-$i',
          imagePath: '/images/$i.jpg',
          addedAt: DateTime.now(),
        ));
      }

      expect(queueBox.length, 3);

      // 2. Trigger 10 concurrent sync invocations simultaneously
      await Future.wait([
        syncService.syncPendingItems(),
        syncService.syncPendingItems(),
        syncService.syncPendingItems(),
        syncService.processQueue(),
        syncService.syncPendingItems(),
        syncService.processQueue(),
        syncService.syncPendingItems(),
        syncService.syncPendingItems(),
        syncService.processQueue(),
        syncService.syncPendingItems(),
      ]);

      // 3. Peak concurrency must be exactly 1 (Mutex lock guarantees no overlap)
      expect(supabaseDataSource.peakConcurrentUploads, 1);

      // 4. Exactly 3 items were uploaded, zero duplicates
      expect(supabaseDataSource.uploadCallCount, 3);
      expect(supabaseDataSource.uploadedReceiptIds.length, 3);
      expect(supabaseDataSource.uploadedReceiptIds.toSet().length, 3);
      expect(queueBox.isEmpty, isTrue);
    });

    test('scheduleUpload does not insert duplicate queue items for same receiptId', () async {
      final rec = ReceiptModel(
        id: 'dup-rec-001',
        merchantName: 'Duplicate Test',
        totalAmount: 100.0,
        date: DateTime.now(),
        items: [],
        currency: 'USD',
      );
      await localDataSource.saveReceipt(rec);

      // Rapidly schedule the same receipt 5 times
      await Future.wait([
        syncService.scheduleUpload('dup-rec-001', '/img1.jpg'),
        syncService.scheduleUpload('dup-rec-001', '/img1.jpg'),
        syncService.scheduleUpload('dup-rec-001', '/img1.jpg'),
        syncService.scheduleUpload('dup-rec-001', '/img1.jpg'),
        syncService.scheduleUpload('dup-rec-001', '/img1.jpg'),
      ]);

      expect(supabaseDataSource.uploadCallCount, 1);
      expect(queueBox.isEmpty, isTrue);
    });

    test('exponential backoff computes exact delays (2s, 4s, 8s, 16s, 32s)', () {
      expect(SyncItemModel.computeBackoff(0).inSeconds, 2);
      expect(SyncItemModel.computeBackoff(1).inSeconds, 4);
      expect(SyncItemModel.computeBackoff(2).inSeconds, 8);
      expect(SyncItemModel.computeBackoff(3).inSeconds, 16);
      expect(SyncItemModel.computeBackoff(4).inSeconds, 32);
      expect(SyncItemModel.computeBackoff(5).inSeconds, 32); // Capped at maxDelaySeconds
    });

    test('failed sync attempts back off exponentially and cease after 5 attempts marking item permanentlyFailed', () async {
      final rec = ReceiptModel(
        id: 'failing-rec-001',
        merchantName: 'Fail Store',
        totalAmount: 20.0,
        date: DateTime.now(),
        items: [],
        currency: 'USD',
      );
      await localDataSource.saveReceipt(rec);

      // Make upload always throw
      supabaseDataSource.shouldFail = true;

      await queueBox.add(SyncItemModel(
        receiptId: 'failing-rec-001',
        imagePath: '/fail.jpg',
        addedAt: DateTime.now(),
      ));

      // Attempt 1: retryCount becomes 1, nextRetryTimestamp set ~2s in future
      await syncService.syncPendingItems();
      var item = queueBox.values.first;
      expect(item.retryCount, 1);
      expect(item.status, SyncStatus.pending);
      expect(item.nextRetryTimestamp, isNotNull);
      expect(item.isReadyForRetry, isFalse);

      // Attempt 2 (simulate waiting past backoff): retryCount becomes 2
      item = item.copyWith(nextRetryTimestamp: DateTime.now().subtract(const Duration(seconds: 1)));
      await queueBox.put(queueBox.keys.first, item);
      await syncService.syncPendingItems();
      item = queueBox.values.first;
      expect(item.retryCount, 2);

      // Attempt 3
      item = item.copyWith(nextRetryTimestamp: DateTime.now().subtract(const Duration(seconds: 1)));
      await queueBox.put(queueBox.keys.first, item);
      await syncService.syncPendingItems();
      item = queueBox.values.first;
      expect(item.retryCount, 3);

      // Attempt 4
      item = item.copyWith(nextRetryTimestamp: DateTime.now().subtract(const Duration(seconds: 1)));
      await queueBox.put(queueBox.keys.first, item);
      await syncService.syncPendingItems();
      item = queueBox.values.first;
      expect(item.retryCount, 4);

      // Attempt 5 -> reaches 5 attempts, transitions to permanentlyFailed
      item = item.copyWith(nextRetryTimestamp: DateTime.now().subtract(const Duration(seconds: 1)));
      await queueBox.put(queueBox.keys.first, item);
      await syncService.syncPendingItems();
      item = queueBox.values.first;
      expect(item.retryCount, 5);
      expect(item.status, SyncStatus.permanentlyFailed);
      expect(item.isDeadLettered, isTrue);

      // Subsequent sync runs skip permanently failed items
      final callsBefore = supabaseDataSource.uploadCallCount;
      await syncService.syncPendingItems();
      expect(supabaseDataSource.uploadCallCount, callsBefore);
    });

    test('manual retry resets permanently failed item and allows immediate synchronization', () async {
      final rec = ReceiptModel(
        id: 'manual-retry-rec',
        merchantName: 'Manual Store',
        totalAmount: 15.0,
        date: DateTime.now(),
        items: [],
        currency: 'USD',
      );
      await localDataSource.saveReceipt(rec);

      // Add a permanently failed item
      final failedItem = SyncItemModel(
        receiptId: 'manual-retry-rec',
        imagePath: '/manual.jpg',
        addedAt: DateTime.now().subtract(const Duration(hours: 2)),
        retryCount: 5,
        status: SyncStatus.permanentlyFailed,
        errorMessage: 'Network timeout',
      );
      await queueBox.add(failedItem);

      // Fix network
      supabaseDataSource.shouldFail = false;

      // Invoke manual retry
      await syncService.retryFailedItem('manual-retry-rec');

      // Item should have succeeded and been removed from queue
      expect(supabaseDataSource.uploadCallCount, 1);
      expect(supabaseDataSource.uploadedReceiptIds, contains('manual-retry-rec'));
      expect(queueBox.isEmpty, isTrue);
    });

    test('uploads to Google Drive when use_google_drive_storage setting is true', () async {
      await settingsBox.put('use_google_drive_storage', true);

      final rec = ReceiptModel(
        id: 'drive-rec-001',
        merchantName: 'Drive Store',
        totalAmount: 99.0,
        date: DateTime.now(),
        items: [],
        currency: 'USD',
      );
      await localDataSource.saveReceipt(rec);

      await syncService.scheduleUpload('drive-rec-001', '/images/drive-001.jpg');
      await syncService.syncPendingItems();

      expect(googleDriveService.uploadCallCount, 1);
      expect(queueBox.isEmpty, isTrue);
    });

    test('saving a receipt whose upload was dead-lettered queues it again', () async {
      await localDataSource.saveReceipt(ReceiptModel(
        id: 'dead-rec',
        merchantName: 'Store',
        totalAmount: 12.0,
        date: DateTime.now(),
        items: [],
        currency: 'USD',
      ));
      await queueBox.add(SyncItemModel(
        receiptId: 'dead-rec',
        imagePath: '/old.jpg',
        addedAt: DateTime.now().subtract(const Duration(days: 1)),
        retryCount: SyncItemModel.maxRetries,
        status: SyncStatus.permanentlyFailed,
        errorMessage: 'Network timeout',
      ));

      await syncService.scheduleUpload('dead-rec', '/new.jpg');

      expect(supabaseDataSource.uploadedReceiptIds, ['dead-rec']);
      expect(queueBox.isEmpty, isTrue);
    });

    test('a pending entry is kept when the same receipt is scheduled again', () async {
      supabaseDataSource.shouldFail = true;
      await localDataSource.saveReceipt(ReceiptModel(
        id: 'pending-rec',
        merchantName: 'Store',
        totalAmount: 12.0,
        date: DateTime.now(),
        items: [],
        currency: 'USD',
      ));

      await syncService.scheduleUpload('pending-rec', '/a.jpg');
      await syncService.scheduleUpload('pending-rec', '/a.jpg');

      expect(queueBox.length, 1);
      expect(queueBox.values.single.retryCount, 1);
    });

    test('uploads look receipts up by key instead of loading all of them', () async {
      for (var i = 0; i < 3; i++) {
        await localDataSource.saveReceipt(ReceiptModel(
          id: 'keyed-$i',
          merchantName: 'Store',
          totalAmount: 1.0,
          date: DateTime.now(),
          items: [],
          currency: 'USD',
        ));
        await queueBox.add(SyncItemModel(receiptId: 'keyed-$i', imagePath: '', addedAt: DateTime.now()));
      }

      await syncService.syncPendingItems();

      expect(supabaseDataSource.uploadCallCount, 3);
      expect(localDataSource.fullScanCount, 0);
    });

    test('retryAllFailed and clearFailedItems properly manage dead-lettered items', () async {
      final item1 = SyncItemModel(
        receiptId: 'failed-1',
        imagePath: '/fail1.jpg',
        addedAt: DateTime.now(),
        retryCount: 5,
        status: SyncStatus.permanentlyFailed,
      );
      final item2 = SyncItemModel(
        receiptId: 'failed-2',
        imagePath: '/fail2.jpg',
        addedAt: DateTime.now(),
        retryCount: 5,
        status: SyncStatus.permanentlyFailed,
      );
      await queueBox.add(item1);
      await queueBox.add(item2);

      expect(queueBox.length, 2);

      // Reset all failed items for retry
      await syncService.retryAllFailed();
      for (var item in queueBox.values) {
        expect(item.status, SyncStatus.pending);
        expect(item.retryCount, 0);
      }

      // Mark again and clear
      await queueBox.clear();
      await queueBox.add(item1);
      await queueBox.add(item2);
      await syncService.clearFailedItems();
      expect(queueBox.isEmpty, isTrue);
    });
  });

  group('SyncService - training contribution consent', () {
    Future<void> queueReceipt(String id) async {
      await localDataSource.saveReceipt(ReceiptModel(
        id: id,
        merchantName: 'Store',
        totalAmount: 10.0,
        date: DateTime.utc(2026, 9, 1),
        items: const [],
        currency: 'EUR',
      ));
      await syncService.scheduleUpload(id, '/images/$id.jpg');
    }

    test('nothing is uploaded unless the user opted in', () async {
      await settingsBox.delete(SyncService.trainingContributionKey);
      expect(SyncService.isTrainingContributionEnabled(settingsBox), isFalse);

      await queueReceipt('rec-no-consent');
      await syncService.syncPendingItems();

      expect(supabaseDataSource.uploadCallCount, 0);
      expect(queueBox.isEmpty, isTrue);
    });

    test('revoking consent stops uploads that are already queued', () async {
      await settingsBox.put(SyncService.trainingContributionKey, false);

      await queueReceipt('rec-revoked');
      await syncService.syncPendingItems();

      expect(supabaseDataSource.uploadCallCount, 0);
    });

    test('the personal Google Drive backup does not depend on training consent', () async {
      await settingsBox.put(SyncService.trainingContributionKey, false);
      await settingsBox.put('use_google_drive_storage', true);

      await queueReceipt('rec-drive');
      await syncService.syncPendingItems();

      expect(googleDriveService.uploadCallCount, 1);
      expect(supabaseDataSource.uploadCallCount, 0);
    });

    test('a StateError raised by the upload is retried, not treated as a deleted receipt', () async {
      supabaseDataSource.errorToThrow = StateError('Bad state from storage client');

      await queueReceipt('rec-state-error');
      await syncService.syncPendingItems();

      expect(supabaseDataSource.uploadCallCount, 1);
      expect(queueBox.values.single.retryCount, 1);
    });
  });

  group('SyncService - isolation mode and private boxes', () {
    Future<void> saveReceipt(String id, {String boxId = 'main'}) => localDataSource.saveReceipt(ReceiptModel(
          id: id,
          merchantName: 'Store',
          totalAmount: 10.0,
          date: DateTime.utc(2026, 9, 1),
          items: const [],
          currency: 'EUR',
          boxId: boxId,
        ));

    test('nothing is uploaded while isolation mode is on, and the item stays queued', () async {
      await settingsBox.put(NetworkPolicy.isolationModeKey, true);
      await saveReceipt('rec-isolated');

      await syncService.scheduleUpload('rec-isolated', '/images/rec-isolated.jpg');
      await syncService.syncPendingItems();

      expect(supabaseDataSource.uploadCallCount, 0);
      expect(queueBox.length, 1);

      await settingsBox.put(NetworkPolicy.isolationModeKey, false);
      await syncService.syncPendingItems();
      expect(supabaseDataSource.uploadedReceiptIds, ['rec-isolated']);
    });

    test('receipts in private boxes are never uploaded for training', () async {
      final service = SyncService(
        queueBox: queueBox,
        localDataSource: localDataSource,
        supabaseDataSource: supabaseDataSource,
        settingsBox: settingsBox,
        googleDriveService: googleDriveService,
        isPrivateBox: (boxId) => boxId == 'secret',
      );
      addTearDown(service.dispose);
      await saveReceipt('rec-private', boxId: 'secret');
      await saveReceipt('rec-public');

      await service.scheduleUpload('rec-private', '');
      await service.scheduleUpload('rec-public', '');

      expect(supabaseDataSource.uploadedReceiptIds, ['rec-public']);
      expect(queueBox.isEmpty, isTrue);
    });
  });
}
