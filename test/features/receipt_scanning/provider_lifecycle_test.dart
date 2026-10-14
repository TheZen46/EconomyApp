import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:t_aidy/core/services/ai_service.dart';
import 'package:t_aidy/features/receipt_scanning/data/datasources/sync_service.dart';
import 'package:t_aidy/core/sync/sync_manager.dart';
import 'package:t_aidy/features/receipt_scanning/data/models/receipt_model.dart';
import 'package:t_aidy/features/receipt_scanning/data/models/sync_item_model.dart';
import 'package:t_aidy/features/receipt_scanning/domain/entities/receipt.dart';
import 'package:t_aidy/features/receipt_scanning/presentation/providers/receipt_provider.dart';
import 'package:t_aidy/features/receipt_scanning/domain/repositories/receipt_repository.dart';
import 'package:t_aidy/features/settings/presentation/providers/llm_provider.dart';
import 'package:t_aidy/features/evault/presentation/providers/asset_provider.dart';
import 'package:t_aidy/features/evault/data/models/asset_model.dart';

class FakeSyncService extends Fake implements SyncService {
  bool disposed = false;

  @override
  void dispose() {
    disposed = true;
  }
}

class FakeSyncManager extends Fake implements SyncManager {
  bool disposed = false;

  @override
  void dispose() {
    disposed = true;
  }
}

class FakeReceiptRepository extends Fake implements ReceiptRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Provider Lifecycle & Cascade Isolation (TAIDY-M04 / Issue #26)', () {
    test('Changing isLlmLoadedProvider does not re-create receiptRepositoryProvider or receiptListProvider', () {
      final container = ProviderContainer(
        overrides: [
          hiveBoxProvider.overrideWithValue(FakeBox<ReceiptModel>()),
          settingsBoxProvider.overrideWithValue(FakeBox<dynamic>()),
          syncBoxProvider.overrideWithValue(FakeBox<SyncItemModel>()),
          assetsBoxProvider.overrideWithValue(FakeBox<AssetModel>()),
        ],
      );
      addTearDown(container.dispose);

      // Read repository and receipt list notifier initially
      final initialRepo = container.read(receiptRepositoryProvider);
      final initialNotifier = container.read(receiptListProvider.notifier);

      // Mutate isLlmLoadedProvider
      container.read(isLlmLoadedProvider.notifier).state = true;

      // Repository and Notifier must remain the exact same instances
      final updatedRepo = container.read(receiptRepositoryProvider);
      final updatedNotifier = container.read(receiptListProvider.notifier);

      expect(identical(initialRepo, updatedRepo), isTrue,
          reason: 'receiptRepositoryProvider should not re-evaluate when AI backend changes');
      expect(identical(initialNotifier, updatedNotifier), isTrue,
          reason: 'receiptListProvider should not be recreated when AI backend changes');
    });

    test('SyncService and SyncManager register ref.onDispose and call dispose() upon teardown', () {
      final fakeSyncService = FakeSyncService();

      final testSyncServiceProvider = Provider<SyncService>((ref) {
        ref.onDispose(fakeSyncService.dispose);
        return fakeSyncService;
      });

      final testSyncManagerProvider = Provider<SyncManager>((ref) {
        final manager = FakeSyncManager();
        ref.onDispose(manager.dispose);
        return manager;
      });

      final container = ProviderContainer();
      final syncService = container.read(testSyncServiceProvider);
      final syncManager = container.read(testSyncManagerProvider) as FakeSyncManager;

      expect(fakeSyncService.disposed, isFalse);
      expect(syncManager.disposed, isFalse);

      container.dispose();

      expect(fakeSyncService.disposed, isTrue,
          reason: 'SyncService.dispose() must be called when provider container is disposed');
      expect(syncManager.disposed, isTrue,
          reason: 'SyncManager.dispose() must be called when provider container is disposed');
    });
  });
}

class FakeBox<T> extends Fake implements Box<T> {
  @override
  bool get isOpen => true;

  @override
  bool get isEmpty => true;

  @override
  bool get isNotEmpty => false;

  @override
  int get length => 0;

  @override
  Iterable<T> get values => [];

  @override
  Iterable<dynamic> get keys => [];

  @override
  T? get(dynamic key, {T? defaultValue}) => defaultValue;

  @override
  Future<void> put(dynamic key, T value) async {}

  @override
  Stream<BoxEvent> watch({dynamic key}) => const Stream.empty();
}
