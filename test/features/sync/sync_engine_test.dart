import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/features/receipt_scanning/data/datasources/hive_receipt_data_source.dart';
import 'package:t_aidy/features/receipt_scanning/data/models/receipt_model.dart';
import 'package:t_aidy/features/sync/data/datasources/remote_replica_data_source.dart';
import 'package:t_aidy/features/sync/data/datasources/sync_engine.dart';
import 'package:t_aidy/features/sync/domain/entities/sync_progress_state.dart';

class FakeRemoteReplicaDataSource implements RemoteReplicaDataSource {
  final List<Map<String, dynamic>> mockReceipts;
  final List<RemoteFileEntry> mockFiles;
  final List<Map<String, dynamic>> mockBoxes;
  final List<Map<String, dynamic>> mockAssets;
  final List<Map<String, dynamic>> mockInvoices;
  final List<Map<String, dynamic>> mockTaxonomies;
  bool shouldThrowOnDownload;

  FakeRemoteReplicaDataSource({
    this.mockReceipts = const [],
    this.mockFiles = const [],
    this.mockBoxes = const [],
    this.mockAssets = const [],
    this.mockInvoices = const [],
    this.mockTaxonomies = const [],
    this.shouldThrowOnDownload = false,
  });

  @override
  Future<List<RemoteFileEntry>> listRemoteFiles(String userId) async => mockFiles;

  @override
  Future<Uint8List> downloadFile(String path) async {
    if (shouldThrowOnDownload) {
      throw Exception('Simulated download failure');
    }
    return Uint8List.fromList(List.generate(1024, (i) => i % 256));
  }

  @override
  Future<List<Map<String, dynamic>>> fetchReceipts(String userId) async => mockReceipts;

  @override
  Future<List<Map<String, dynamic>>> fetchBoxes(String userId) async => mockBoxes;

  @override
  Future<List<Map<String, dynamic>>> fetchAssets(String userId) async => mockAssets;

  @override
  Future<List<Map<String, dynamic>>> fetchInvoices(String userId) async => mockInvoices;

  @override
  Future<List<Map<String, dynamic>>> fetchTaxonomies(String userId) async => mockTaxonomies;
}

class FakeLocalReceiptDataSource implements LocalReceiptDataSource {
  final Map<String, ReceiptModel> receipts = {};

  @override
  Future<List<ReceiptModel>> getReceipts() async => receipts.values.toList();

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SyncProgressState', () {
    test('formats speed, bytes, and ETA accurately', () {
      final state = SyncProgressState(
        stage: SyncStage.downloadingDeltas,
        progress: 0.5,
        bytesTransferred: 5 * 1024 * 1024,
        totalBytes: 10 * 1024 * 1024,
        transferSpeedBytesPerSec: 2.5 * 1024 * 1024,
      );

      expect(state.formattedSpeed, '2.5 MB/s');
      expect(state.formattedBytes, '5.0 MB');
      expect(state.estimatedSecondsRemaining, 2.0);
      expect(state.formattedEta, '2.0s');
    });

    test('stage completion and retry flags', () {
      const completed = SyncProgressState(stage: SyncStage.completed);
      expect(completed.isCompleted, isTrue);
      expect(completed.isRunning, isFalse);

      const retrying = SyncProgressState(stage: SyncStage.interruptedRetrying);
      expect(retrying.isRetrying, isTrue);
      expect(retrying.isRunning, isTrue);
    });
  });

  group('SyncEngine - Replication and Delta Syncing', () {
    late FakeLocalReceiptDataSource localDS;
    late FakeRemoteReplicaDataSource remoteDS;

    setUp(() {
      localDS = FakeLocalReceiptDataSource();
    });

    test('replicates missing remote receipts to local storage upon login', () async {
      remoteDS = FakeRemoteReplicaDataSource(
        mockReceipts: [
          {
            'id': 'remote-rec-001',
            'merchant_name': 'Apple Store',
            'total_amount': 1299.0,
            'currency': 'USD',
            'date': '2026-08-28T10:00:00.000Z',
            'items': [
              {
                'description': 'MacBook Pro M3',
                'unit_price': 1299.0,
                'quantity': 1,
                'is_asset': true,
              }
            ],
          },
          {
            'id': 'remote-rec-002',
            'merchant_name': 'Whole Foods',
            'total_amount': 45.50,
            'currency': 'USD',
            'date': '2026-08-28T12:00:00.000Z',
            'items': [],
          },
        ],
        mockFiles: [
          const RemoteFileEntry(
            name: 'remote-rec-001.jpg',
            path: 'user-123/images/remote-rec-001.jpg',
            size: 2048,
          ),
        ],
      );

      final engine = SyncEngine(
        remoteDataSource: remoteDS,
        localDataSource: localDS,
      );

      final states = <SyncProgressState>[];
      final sub = engine.stateStream.listen(states.add);

      final success = await engine.executeSync(userId: 'user-123', isInitial: true);

      expect(success, isTrue);
      expect(engine.currentState.isCompleted, isTrue);

      final localList = await localDS.getReceipts();
      expect(localList.length, 2);
      expect(localList.any((r) => r.id == 'remote-rec-001'), isTrue);
      expect(localList.any((r) => r.id == 'remote-rec-002'), isTrue);

      await sub.cancel();
      engine.dispose();
    });

    test('skips receipts that already exist locally (delta parity)', () async {
      final existingReceipt = ReceiptModel(
        id: 'rec-existing-001',
        merchantName: 'Existing Store',
        totalAmount: 100.0,
        currency: 'USD',
        date: DateTime.now(),
        items: [],
      );
      await localDS.saveReceipt(existingReceipt);

      remoteDS = FakeRemoteReplicaDataSource(
        mockReceipts: [
          {
            'id': 'rec-existing-001',
            'merchant_name': 'Existing Store',
            'total_amount': 100.0,
          },
          {
            'id': 'rec-new-002',
            'merchant_name': 'New Store',
            'total_amount': 50.0,
          },
        ],
      );

      final engine = SyncEngine(
        remoteDataSource: remoteDS,
        localDataSource: localDS,
      );

      final success = await engine.executeSync(userId: 'user-123');

      expect(success, isTrue);
      final localList = await localDS.getReceipts();
      expect(localList.length, 2);

      engine.dispose();
    });

    test('continueOffline transitions immediately to completed state', () async {
      remoteDS = FakeRemoteReplicaDataSource();
      final engine = SyncEngine(
        remoteDataSource: remoteDS,
        localDataSource: localDS,
      );

      engine.continueOffline();
      expect(engine.currentState.isCompleted, isTrue);
      expect(engine.currentState.message.contains('offline fallback mode'), isTrue);

      engine.dispose();
    });
  });
}
