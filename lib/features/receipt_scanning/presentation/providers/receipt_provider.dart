import 'package:flutter/foundation.dart';
import 'package:dartz/dartz.dart';
import 'package:hive/hive.dart';
import '../../../../core/services/secure_storage_service.dart';
import '../../../../core/error/failures.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/model_repository.dart';
import 'model_update_provider.dart';

import '../../../../core/services/ai_service.dart';
import '../../../../core/services/export_service.dart';
import '../../data/datasources/hive_receipt_data_source.dart';
import '../../data/datasources/mock_ai_service.dart';
import '../../data/datasources/supabase_data_source.dart';
import '../../data/datasources/gemini_ai_service.dart';
import '../../data/models/receipt_model.dart';
import '../../data/repositories/receipt_repository_impl.dart';
import '../../domain/entities/receipt.dart';
import '../../domain/repositories/receipt_repository.dart';

// --- Data Source Providers ---

import '../../data/models/sync_item_model.dart';
import '../../data/datasources/sync_service.dart';
import '../../../../core/services/google_drive_service.dart'; // Ensure global access or provider
import '../../../settings/data/datasources/webhook_service.dart';
import '../../../evault/presentation/providers/asset_provider.dart';
import '../../../settings/presentation/providers/llm_provider.dart';
import '../../../boxes/data/providers/boxes_provider.dart';
import '../../data/datasources/csv_parser_service.dart';

final csvParserServiceProvider = Provider<CsvParserService>((ref) => CsvParserService());

final hiveBoxProvider = Provider<Box<ReceiptModel>>((ref) {
  throw UnimplementedError('Hive box must be overridden in main');
});
final settingsBoxProvider = Provider<Box>((ref) {
  throw UnimplementedError('Settings Hive box must be overridden in main');
});
final syncBoxProvider = Provider<Box<SyncItemModel>>((ref) {
  throw UnimplementedError('Sync Queue Hive box must be overridden in main');
});

final localDataSourceProvider = Provider<LocalReceiptDataSource>((ref) {
  final box = ref.watch(hiveBoxProvider);
  return HiveReceiptDataSourceImpl(box);
});

final syncServiceProvider = Provider<SyncService>((ref) {
  final queueBox = ref.watch(syncBoxProvider);
  final localDS = ref.watch(localDataSourceProvider);
  final supabaseDS = ref.watch(supabaseDataSourceProvider);
  final settingsBox = ref.watch(settingsBoxProvider);
  
  return SyncService(
    queueBox: queueBox,
    localDataSource: localDS,
    supabaseDataSource: supabaseDS,
    settingsBox: settingsBox,
    googleDriveService: googleDriveService,
  );
});

final syncQueueStreamProvider = StreamProvider<List<SyncItemModel>>((ref) async* {
  final box = ref.watch(syncBoxProvider);
  yield box.values.toList();
  yield* box.watch().map((_) => box.values.toList());
});

final permanentlyFailedSyncItemsProvider = Provider<List<SyncItemModel>>((ref) {
  final items = ref.watch(syncQueueStreamProvider).valueOrNull ?? [];
  return items.where((item) => item.status == SyncStatus.permanentlyFailed).toList();
});

final webhookServiceProvider = Provider<WebhookService>((ref) {
  final settingsBox = ref.watch(settingsBoxProvider);
  return WebhookService(settingsBox);
});

/// Async provider that reads the Gemini API key from secure storage.
final geminiApiKeyProvider = FutureProvider<String>((ref) async {
  return await SecureStorageService.readSecret(SecretKeys.geminiApiKey) ?? '';
});

final aiServiceProvider = Provider<AIService>((ref) {
  // 1. Check Local LLM
  final isLlmReady = ref.watch(isLlmLoadedProvider);
  if (isLlmReady) {
    return ref.watch(llmServiceProvider);
  }

  // 2. Check Cloud Gemini — read key from async provider (empty string while loading)
  final box = ref.watch(settingsBoxProvider);
  final isEnabled = box.get('enable_gemini_ai', defaultValue: false) as bool;
  final apiKeyAsync = ref.watch(geminiApiKeyProvider);
  final apiKey = apiKeyAsync.valueOrNull ?? '';

  if (isEnabled && apiKey.isNotEmpty) {
    return GeminiAIService(apiKey);
  }

  // 3. Fallback
  return MockAIService();
});


final exportServiceProvider = Provider<ExportService>((ref) {
  return ExportService();
});

final supabaseDataSourceProvider = Provider<SupabaseDataSource>((ref) {
   return SupabaseDataSourceImpl(Supabase.instance.client);
});

final storageUsageProvider = FutureProvider<int>((ref) async {
  final dataSource = ref.watch(supabaseDataSourceProvider);
  return await dataSource.getStorageUsage();
});


// --- OTA Model Providers ---
// --- OTA Model Providers ---

final modelRepositoryProvider = Provider<ModelRepository>((ref) {
  // Assuming Supabase is initialized
  return SupabaseModelRepository(Supabase.instance.client);
});

final modelUpdateServiceProvider = StateNotifierProvider<ModelUpdateService, UpdateState>((ref) {
  final repo = ref.watch(modelRepositoryProvider);
  return ModelUpdateService(repo);
});

// --- Repository Provider ---

final receiptRepositoryProvider = Provider<ReceiptRepository>((ref) {
  final localDS = ref.watch(localDataSourceProvider);
  final aiService = ref.watch(aiServiceProvider);
  final supabaseDS = ref.watch(supabaseDataSourceProvider);
  final settingsBox = ref.watch(settingsBoxProvider);
  final syncService = ref.watch(syncServiceProvider);
  final webhookService = ref.watch(webhookServiceProvider);
  final assetsBox = ref.watch(assetsBoxProvider);
  
  return ReceiptRepositoryImpl(
    localDataSource: localDS, 
    aiService: aiService,
    supabaseDataSource: supabaseDS,
    settingsBox: settingsBox,
    syncService: syncService,
    webhookService: webhookService,
    assetsBox: assetsBox,
  );
});

// --- Logic / State Providers ---

final receiptListProvider = StateNotifierProvider<ReceiptListNotifier, AsyncValue<List<Receipt>>>((ref) {
  final repository = ref.watch(receiptRepositoryProvider);
  return ReceiptListNotifier(repository);
});

final filteredReceiptsByActiveBoxProvider = Provider<AsyncValue<List<Receipt>>>((ref) {
  final receiptsAsync = ref.watch(receiptListProvider);
  final activeBoxId = ref.watch(activeBoxIdProvider);

  return receiptsAsync.whenData((receipts) {
    if (activeBoxId == 'main') {
      return receipts.where((r) => (r.boxId ?? 'main') == 'main').toList();
    }
    return receipts.where((r) => r.boxId == activeBoxId).toList();
  });
});

class ReceiptListNotifier extends StateNotifier<AsyncValue<List<Receipt>>> {
  final ReceiptRepository _repository;

  ReceiptListNotifier(this._repository) : super(const AsyncValue.loading()) {
    loadReceipts();
  }

  Future<void> loadReceipts() async {
    if (!state.hasValue) {
      state = const AsyncValue.loading();
    }
    final result = await _repository.getReceipts();
    result.fold(
      (failure) => state = AsyncValue.error(failure, StackTrace.current),
      (receipts) => state = AsyncValue.data(receipts),
    );
  }

  Future<void> addReceipt(Receipt receipt) async {
    final current = state.valueOrNull ?? [];
    final updated = current.any((r) => r.id == receipt.id)
        ? current.map((r) => r.id == receipt.id ? receipt : r).toList()
        : [receipt, ...current];
    state = AsyncValue.data(updated);

    final result = await _repository.saveReceipt(receipt);
    result.fold(
      (failure) {
        debugPrint('Error saving receipt: ${failure.message}');
      },
      (_) {},
    );
  }

  Future<void> clearAll({bool includeCloud = false}) async {
    state = const AsyncValue.data([]);
    final result = await _repository.clearAllData(includeCloud: includeCloud);
    result.fold(
      (failure) {
        debugPrint('Error clearing receipts: ${failure.message}');
      },
      (_) {},
    );
  }

  Future<void> deleteReceipt(String id) async {
    final current = state.valueOrNull ?? [];
    state = AsyncValue.data(current.where((r) => r.id != id).toList());

    final result = await _repository.deleteReceipt(id);
    result.fold(
      (failure) {
        debugPrint('Error deleting receipt: ${failure.message}');
      },
      (_) {},
    );
  }

  Future<Either<Failure, CsvImportReport>> importCsvTransactions(String csvString, CsvParserService parser) async {
    try {
      final parseResult = parser.importCsv(csvString);
      return await parseResult.fold(
        (failure) async => Left(failure),
        (report) async {
          if (report.successfulReceipts.isEmpty) {
            return Right(report);
          }

          final current = state.valueOrNull ?? [];
          final List<Receipt> newlyAdded = [];
          for (final r in report.successfulReceipts) {
            final saveResult = await _repository.saveReceipt(r);
            saveResult.fold(
              (failure) => debugPrint('Error saving CSV receipt: ${failure.message}'),
              (_) => newlyAdded.add(r),
            );
          }
          state = AsyncValue.data([...newlyAdded, ...current]);
          return Right(report);
        },
      );
    } catch (e) {
      return Left(CacheFailure('Failed to import CSV: $e'));
    }
  }
}

// --- User Prefs Providers ---

final monthlyBudgetProvider = StateNotifierProvider<BudgetNotifier, double>((ref) {
  try {
    final box = ref.watch(settingsBoxProvider);
    return BudgetNotifier(box);
  } catch (_) {
    return BudgetNotifier(null);
  }
});

class BudgetNotifier extends StateNotifier<double> {
  final Box? _box;
  static const _key = 'monthly_budget_limit';

  BudgetNotifier([this._box]) : super((_box?.get(_key, defaultValue: 500.0) as num?)?.toDouble() ?? 500.0);

  Future<void> setBudget(double newLimit) async {
    await _box?.put(_key, newLimit);
    state = newLimit;
  }
}

final currentBalanceProvider = StateNotifierProvider<CurrentBalanceNotifier, double>((ref) {
  try {
    final box = ref.watch(settingsBoxProvider);
    return CurrentBalanceNotifier(box);
  } catch (_) {
    return CurrentBalanceNotifier(null);
  }
});

class CurrentBalanceNotifier extends StateNotifier<double> {
  final Box? _box;
  static const _key = 'current_balance';

  CurrentBalanceNotifier([this._box]) : super((_box?.get(_key, defaultValue: 0.0) as num?)?.toDouble() ?? 0.0);

  Future<void> setBalance(double newBalance) async {
    await _box?.put(_key, newBalance);
    state = newBalance;
  }
}

final projectedIncomeProvider = StateNotifierProvider<ProjectedIncomeNotifier, double>((ref) {
  try {
    final box = ref.watch(settingsBoxProvider);
    return ProjectedIncomeNotifier(box);
  } catch (_) {
    return ProjectedIncomeNotifier(null);
  }
});

class ProjectedIncomeNotifier extends StateNotifier<double> {
  final Box? _box;
  static const _key = 'projected_income';

  ProjectedIncomeNotifier([this._box]) : super((_box?.get(_key, defaultValue: 0.0) as num?)?.toDouble() ?? 0.0);

  Future<void> setIncome(double newIncome) async {
    await _box?.put(_key, newIncome);
    state = newIncome;
  }
}
