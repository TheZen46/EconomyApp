// ignore_for_file: deprecated_member_use, deprecated_member_use_from_same_package, unused_local_variable, unnecessary_underscores, invalid_annotation_target, unused_element, non_constant_identifier_names, use_build_context_synchronously
import 'package:hive/hive.dart';
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

final webhookServiceProvider = Provider<WebhookService>((ref) {
  final settingsBox = ref.watch(settingsBoxProvider);
  return WebhookService(settingsBox);
});

final aiServiceProvider = Provider<AIService>((ref) {
  // 1. Check Local LLM
  final isLlmReady = ref.watch(isLlmLoadedProvider);
  if (isLlmReady) {
    return ref.watch(llmServiceProvider);
  }

  // 2. Check Cloud Gemini
  final box = ref.watch(settingsBoxProvider);
  final apiKey = box.get('gemini_api_key', defaultValue: '') as String;
  final isEnabled = box.get('enable_gemini_ai', defaultValue: false) as bool;
  
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

class ReceiptListNotifier extends StateNotifier<AsyncValue<List<Receipt>>> {
  final ReceiptRepository _repository;

  ReceiptListNotifier(this._repository) : super(const AsyncValue.loading()) {
    loadReceipts();
  }

  Future<void> loadReceipts() async {
    state = const AsyncValue.loading();
    final result = await _repository.getReceipts();
    result.fold(
      (failure) => state = AsyncValue.error(failure, StackTrace.current),
      (receipts) => state = AsyncValue.data(receipts),
    );
  }

  Future<void> addReceipt(Receipt receipt) async {
    final result = await _repository.saveReceipt(receipt);
    result.fold(
      (failure) { /* Handle error if needed, or expose via state */ },
      (_) => loadReceipts(), // Refresh list
    );
  }

  Future<void> clearAll({bool includeCloud = false}) async {
    final result = await _repository.clearAllData(includeCloud: includeCloud);
    result.fold(
      (failure) { /* Handle error */ },
      (_) => loadReceipts(), // Refresh list (should be empty)
    );
  }

  Future<void> deleteReceipt(String id) async {
    final result = await _repository.deleteReceipt(id);
    result.fold(
      (failure) { /* Handle error */ },
      (_) => loadReceipts(), // Refresh list
    );
  }

  Future<int> importCsvTransactions(String csvString, CsvParserService parser) async {
    state = const AsyncValue.loading();
    try {
      final receipts = parser.parseBankCsv(csvString);
      int addedCount = 0;
      for (final r in receipts) {
        await _repository.saveReceipt(r);
        addedCount++;
      }
      await loadReceipts();
      return addedCount;
    } catch (e) {
      await loadReceipts();
      return 0;
    }
  }

}

// --- User Prefs Providers ---

final monthlyBudgetProvider = StateNotifierProvider<BudgetNotifier, double>((ref) {
  final box = ref.watch(settingsBoxProvider);
  return BudgetNotifier(box);
});

class BudgetNotifier extends StateNotifier<double> {
  final Box _box;
  static const _key = 'monthly_budget_limit';

  BudgetNotifier(this._box) : super(_box.get(_key, defaultValue: 500.0) as double);

  Future<void> setBudget(double newLimit) async {
    await _box.put(_key, newLimit);
    state = newLimit;
  }
}
