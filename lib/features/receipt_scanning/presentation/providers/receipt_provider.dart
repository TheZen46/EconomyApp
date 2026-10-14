import 'package:flutter/foundation.dart';
import 'package:dartz/dartz.dart';
import 'package:hive/hive.dart';
import '../../../../core/privacy/network_policy.dart';
import '../../../../core/providers/supabase_providers.dart';
import '../../../../core/services/secure_storage_service.dart';
import '../../../../core/error/failures.dart';
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
import '../../../../core/constants/app_constants.dart';

// --- Data Source Providers ---

import '../../data/models/sync_item_model.dart';
import '../../data/datasources/sync_service.dart';
import '../../../../core/services/google_drive_service.dart'; // Ensure global access or provider
import '../../../settings/data/datasources/webhook_service.dart';
import '../../../evault/presentation/providers/asset_provider.dart';
import '../../../settings/presentation/providers/llm_provider.dart';
import '../../../boxes/data/models/box_model.dart';
import '../../../boxes/data/providers/boxes_provider.dart';
import '../../data/datasources/csv_parser_service.dart';
import '../../../../core/sync/outbox_service.dart';
import '../../../../core/sync/sync_coordinator.dart';
import '../../../../core/sync/sync_providers.dart';

/// Service for parsing CSV bank and card statement exports.
///
/// **Lifetime:** App-scoped singleton.
/// **Dependencies:** None.
final csvParserServiceProvider = Provider<CsvParserService>((ref) => CsvParserService());

/// Hive box storing persisted [ReceiptModel] records (`receipts_v3`).
///
/// **Lifetime:** App-scoped singleton.
/// **Override:** Required. Must be overridden with an encrypted box instance in `main()`.
/// **Dependencies:** None.
final hiveBoxProvider = Provider<Box<ReceiptModel>>((ref) {
  throw UnimplementedError('Hive box must be overridden in main');
});

/// Shared Hive box storing user preferences and application configuration (`settings`).
///
/// **Lifetime:** App-scoped singleton.
/// **Override:** Required. Must be overridden with an encrypted box instance in `main()`.
/// **Dependencies:** None.
final settingsBoxProvider = Provider<Box>((ref) {
  throw UnimplementedError('Settings Hive box must be overridden in main');
});

/// Legacy Hive box storing queued sync mutations (`sync_queue`).
///
/// **Lifetime:** App-scoped singleton.
/// **Override:** Required. Must be overridden with an encrypted box instance in `main()`.
/// **Dependencies:** None.
final syncBoxProvider = Provider<Box<SyncItemModel>>((ref) {
  throw UnimplementedError('Sync Queue Hive box must be overridden in main');
});

/// Local Hive data source for reading and writing receipt records.
///
/// **Lifetime:** App-scoped singleton.
/// **Dependencies:** `hiveBoxProvider`.
final localDataSourceProvider = Provider<LocalReceiptDataSource>((ref) {
  final box = ref.watch(hiveBoxProvider);
  return HiveReceiptDataSourceImpl(box);
});

/// Legacy synchronization service coordinating queue items with remote storage.
///
/// **Lifetime:** App-scoped singleton with registered disposal cleanup via `ref.onDispose`.
/// **Dependencies:** `syncBoxProvider`, `localDataSourceProvider`, `supabaseDataSourceProvider`, `settingsBoxProvider`, `boxesHiveBoxProvider`.
final syncServiceProvider = Provider<SyncService>((ref) {
  final queueBox = ref.watch(syncBoxProvider);
  final localDS = ref.watch(localDataSourceProvider);
  final supabaseDS = ref.watch(supabaseDataSourceProvider);
  final settingsBox = ref.watch(settingsBoxProvider);
  
  Box<BoxModel>? boxes;
  try {
    boxes = ref.watch(boxesHiveBoxProvider);
  } catch (_) {}

  final service = SyncService(
    queueBox: queueBox,
    localDataSource: localDS,
    supabaseDataSource: supabaseDS,
    settingsBox: settingsBox,
    googleDriveService: googleDriveService,
    isPrivateBox: (boxId) => boxId != null && (boxes?.get(boxId)?.isPrivate ?? false),
    coordinator: ref.watch(syncCoordinatorProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

/// Reactive stream of all items currently in the sync queue box.
///
/// **Lifetime:** Auto-updating stream provider.
/// **Dependencies:** `syncBoxProvider`.
final syncQueueStreamProvider = StreamProvider<List<SyncItemModel>>((ref) async* {
  final box = ref.watch(syncBoxProvider);
  yield box.values.toList();
  yield* box.watch().map((_) => box.values.toList());
});

/// Filtered list of sync queue mutations that have permanently failed retry limits.
///
/// **Lifetime:** Dependent on `syncQueueStreamProvider`.
/// **Dependencies:** `syncQueueStreamProvider`.
final permanentlyFailedSyncItemsProvider = Provider<List<SyncItemModel>>((ref) {
  final items = ref.watch(syncQueueStreamProvider).valueOrNull ?? [];
  return items.where((item) => item.status == SyncStatus.permanentlyFailed).toList();
});

/// Dispatches JSON webhook notifications upon receipt modifications if configured.
///
/// **Lifetime:** App-scoped singleton.
/// **Dependencies:** `settingsBoxProvider`.
final webhookServiceProvider = Provider<WebhookService>((ref) {
  final settingsBox = ref.watch(settingsBoxProvider);
  return WebhookService(settingsBox);
});

/// Async provider that reads the Gemini API key from secure storage.
///
/// **Lifetime:** Async cached future provider.
/// **Dependencies:** None.
final geminiApiKeyProvider = FutureProvider<String>((ref) async {
  return await SecureStorageService.readSecret(SecretKeys.geminiApiKey) ?? '';
});

/// Resolves the active [AIService] according to user settings and model readiness:
/// 1. Native on-device VLM engine (if loaded and ready)
/// 2. Legacy local LLM (if loaded)
/// 3. Google Gemini Cloud API (if configured and cloud allowed by [NetworkPolicy])
/// 4. Local heuristic mock extractor (fallback)
///
/// **Lifetime:** App-scoped provider.
/// **Dependencies:** `isVlmReadyProvider`, `vlmEngineServiceProvider`, `isLlmLoadedProvider`, `llmServiceProvider`, `settingsBoxProvider`, `geminiApiKeyProvider`.
final aiServiceProvider = Provider<AIService>((ref) {
  // 1. Check Next-Gen On-Device VLM Engine
  final isVlmReady = ref.watch(isVlmReadyProvider);
  if (isVlmReady) {
    return ref.watch(vlmEngineServiceProvider);
  }

  // 2. Check Legacy Local LLM
  final isLlmReady = ref.watch(isLlmLoadedProvider);
  if (isLlmReady) {
    return ref.watch(llmServiceProvider);
  }

  // 3. Check Cloud Gemini — read key from async provider (empty string while loading)
  final box = ref.watch(settingsBoxProvider);
  final isEnabled = box.get('enable_gemini_ai', defaultValue: false) as bool;
  final apiKeyAsync = ref.watch(geminiApiKeyProvider);
  final apiKey = apiKeyAsync.valueOrNull ?? '';

  // Isolation mode keeps receipt images on the device.
  if (isEnabled && apiKey.isNotEmpty && NetworkPolicy.isCloudAllowed(box)) {
    return GeminiAIService(apiKey, model: box.get(GeminiAIService.modelSettingKey) as String?);
  }

  // 4. Fallback
  return MockAIService();
});


/// Service handling CSV, JSON, and PDF report exports.
///
/// **Lifetime:** App-scoped singleton.
/// **Dependencies:** None.
final exportServiceProvider = Provider<ExportService>((ref) {
  return ExportService();
});

/// Remote Supabase storage and database data source.
///
/// **Lifetime:** App-scoped singleton.
/// **Dependencies:** `supabaseClientOrOfflineProvider`.
final supabaseDataSourceProvider = Provider<SupabaseDataSource>((ref) {
  return SupabaseDataSourceImpl(ref.watch(supabaseClientOrOfflineProvider));
});

/// Computes the user's remote cloud storage consumption in bytes.
///
/// **Lifetime:** Async future provider.
/// **Dependencies:** `supabaseDataSourceProvider`.
final storageUsageProvider = FutureProvider<int>((ref) async {
  final dataSource = ref.watch(supabaseDataSourceProvider);
  return await dataSource.getStorageUsage();
});


// ── OTA Model Providers ─────────────────────────────────────────────────────

/// Remote repository tracking available on-device model weight manifests and SHA-256 digests.
///
/// **Lifetime:** App-scoped singleton.
/// **Dependencies:** `supabaseClientOrOfflineProvider`.
final modelRepositoryProvider = Provider<ModelRepository>((ref) {
  return SupabaseModelRepository(ref.watch(supabaseClientOrOfflineProvider));
});

/// State notifier managing over-the-air model updates and downloads.
///
/// **Lifetime:** App-scoped state notifier.
/// **Dependencies:** `modelRepositoryProvider`, `settingsBoxProvider`.
final modelUpdateServiceProvider = StateNotifierProvider<ModelUpdateService, UpdateState>((ref) {
  final repo = ref.watch(modelRepositoryProvider);
  return ModelUpdateService(repo, isCloudAllowed: () => _cloudAllowed(ref));
});

/// Whether cloud requests are allowed (see [NetworkPolicy]).
bool _cloudAllowed(Ref ref) {
  try {
    return NetworkPolicy.isCloudAllowed(ref.read(settingsBoxProvider));
  } catch (_) {
    return true;
  }
}

// ── Repository Provider ─────────────────────────────────────────────────────

/// Primary repository aggregating local Hive storage, cloud sync, webhooks, and AI extraction.
///
/// **Lifetime:** App-scoped singleton.
/// **Dependencies:**
/// - `localDataSourceProvider`: Local encrypted Hive receipts storage.
/// - `supabaseDataSourceProvider`: Remote Supabase receipts storage.
/// - `settingsBoxProvider`: Application configuration and privacy toggles.
/// - `syncServiceProvider`: Legacy queue sync service.
/// - `webhookServiceProvider`: Outgoing webhooks dispatcher.
/// - `assetsBoxProvider`: EVault asset inventory box.
/// - `outboxServiceProvider`: Offline-first CRDT outbox queue.
/// - `aiServiceProvider`: Dynamic AI extraction backend resolver.
final receiptRepositoryProvider = Provider<ReceiptRepository>((ref) {
  final localDS = ref.watch(localDataSourceProvider);
  final supabaseDS = ref.watch(supabaseDataSourceProvider);
  final settingsBox = ref.watch(settingsBoxProvider);
  final syncService = ref.watch(syncServiceProvider);
  final webhookService = ref.watch(webhookServiceProvider);
  final assetsBox = ref.watch(assetsBoxProvider);

  OutboxService? outbox;
  try {
    outbox = ref.watch(outboxServiceProvider);
  } catch (_) {}
  
  return ReceiptRepositoryImpl(
    localDataSource: localDS, 
    supabaseDataSource: supabaseDS,
    settingsBox: settingsBox,
    syncService: syncService,
    webhookService: webhookService,
    assetsBox: assetsBox,
    outboxService: outbox,
    aiServiceResolver: () => ref.read(aiServiceProvider),
  );
});

// ── Logic / State Providers ─────────────────────────────────────────────────

/// State notifier provider managing the active list of user receipts.
///
/// **Lifetime:** App-scoped state notifier.
/// **Dependencies:** `receiptRepositoryProvider`.
final receiptListProvider = StateNotifierProvider<ReceiptListNotifier, AsyncValue<List<Receipt>>>((ref) {
  final repository = ref.watch(receiptRepositoryProvider);
  return ReceiptListNotifier(repository);
});

/// Projects the list of receipts filtered by the currently active budget box.
///
/// **Lifetime:** Auto-updating dependent projection provider.
/// **Dependencies:** `receiptListProvider`, `activeBoxIdProvider`.
final filteredReceiptsByActiveBoxProvider = Provider<AsyncValue<List<Receipt>>>((ref) {
  final receiptsAsync = ref.watch(receiptListProvider);
  final activeBoxId = ref.watch(activeBoxIdProvider);

  return receiptsAsync.whenData((receipts) {
    return receipts.where((r) {
      final parentMatches = (r.boxId ?? 'main') == activeBoxId;
      final childMatches = r.items.any((i) => (i.boxId ?? r.boxId ?? 'main') == activeBoxId);
      return parentMatches || childMatches;
    }).toList();
  });
});

/// Family provider calculating the aggregated currency expenditure for a specific budget box ID.
///
/// **Lifetime:** Parameterized family provider.
/// **Dependencies:** `receiptListProvider`.
final boxSpentAmountProvider = Provider.family<double, String>((ref, boxId) {
  final receipts = ref.watch(receiptListProvider).valueOrNull ?? [];
  double total = 0.0;
  for (final receipt in receipts) {
    if (receipt.items.isEmpty) {
      if ((receipt.boxId ?? 'main') == boxId) {
        total += receipt.totalAmount;
      }
    } else {
      for (final item in receipt.items) {
        final itemBox = item.boxId ?? receipt.boxId ?? 'main';
        if (itemBox == boxId) {
          total += item.totalPrice;
        }
      }
    }
  }
  return total;
});

/// State notifier maintaining the reactive list of loaded [Receipt] entities.
class ReceiptListNotifier extends StateNotifier<AsyncValue<List<Receipt>>> {
  final ReceiptRepository _repository;

  /// Creates a [ReceiptListNotifier] backed by [ReceiptRepository] and initiates initial load.
  ReceiptListNotifier(this._repository) : super(const AsyncValue.loading()) {
    loadReceipts();
  }

  /// Reloads all receipt entities asynchronously from the underlying repository.
  Future<void> loadReceipts() async {
    if (!state.hasValue) {
      state = const AsyncValue.loading();
    }
    final result = await _repository.getReceipts();
    if (!mounted) return;
    result.fold(
      (failure) => state = AsyncValue.error(failure, StackTrace.current),
      (receipts) => state = AsyncValue.data(receipts),
    );
  }

  /// Saves [receipt], updating the list optimistically. On failure the list
  /// is restored and the failure returned, so that callers can report it.
  Future<Either<Failure, void>> addReceipt(Receipt receipt) async {
    final previous = state;
    final current = state.valueOrNull ?? [];
    final updated = current.any((r) => r.id == receipt.id)
        ? current.map((r) => r.id == receipt.id ? receipt : r).toList()
        : [receipt, ...current];
    state = AsyncValue.data(updated);

    final result = await _repository.saveReceipt(receipt);
    if (!mounted) return result;
    result.fold(
      (failure) {
        debugPrint('Error saving receipt: ${failure.message}');
        state = previous;
      },
      (_) {},
    );
    return result;
  }

  /// Clears all stored receipts from local storage, and optionally purges remote cloud records.
  Future<void> clearAll({bool includeCloud = false}) async {
    final previous = state;
    state = const AsyncValue.data([]);
    final result = await _repository.clearAllData(includeCloud: includeCloud);
    if (!mounted) return;
    result.fold(
      (failure) {
        debugPrint('Error clearing receipts: ${failure.message}');
        state = previous;
      },
      (_) {},
    );
  }

  /// Optimistically deletes the receipt matching [id].
  Future<void> deleteReceipt(String id) async {
    final previous = state;
    final current = state.valueOrNull ?? [];
    state = AsyncValue.data(current.where((r) => r.id != id).toList());

    final result = await _repository.deleteReceipt(id);
    if (!mounted) return;
    result.fold(
      (failure) {
        debugPrint('Error deleting receipt: ${failure.message}');
        state = previous;
      },
      (_) {},
    );
  }

  /// Parses and imports bank statement rows from [csvString], skipping transactions that exist.
  Future<Either<Failure, CsvImportReport>> importCsvTransactions(String csvString, CsvParserService parser) async {
    try {
      final current = state.valueOrNull ?? [];
      // Rows already imported from an earlier copy of the file are skipped.
      final parseResult = parser.importCsv(csvString, existing: current);
      return await parseResult.fold(
        (failure) async => Left(failure),
        (report) async {
          if (report.successfulReceipts.isEmpty) {
            return Right(report);
          }

          final List<Receipt> newlyAdded = [];
          for (final r in report.successfulReceipts) {
            final saveResult = await _repository.saveReceipt(r);
            saveResult.fold(
              (failure) => debugPrint('Error saving CSV receipt: ${failure.message}'),
              (_) => newlyAdded.add(r),
            );
          }
          if (mounted) {
            state = AsyncValue.data([...newlyAdded, ...current]);
          }
          return Right(report);
        },
      );
    } catch (e) {
      return Left(CacheFailure('Failed to import CSV: $e'));
    }
  }
}

// ── User Prefs Providers ────────────────────────────────────────────────────

/// Manages the monthly discretionary spending budget ceiling.
///
/// **Lifetime:** App-scoped state notifier provider.
/// **Dependencies:** `settingsBoxProvider`.
final monthlyBudgetProvider = StateNotifierProvider<BudgetNotifier, double>((ref) {
  try {
    final box = ref.watch(settingsBoxProvider);
    return BudgetNotifier(box);
  } catch (_) {
    return BudgetNotifier(null);
  }
});

/// State notifier persisting the monthly spending ceiling under `monthly_budget_limit`.
class BudgetNotifier extends StateNotifier<double> {
  final Box? _box;
  static const _key = 'monthly_budget_limit';

  /// Creates a [BudgetNotifier] with an initial budget default of 500.0.
  BudgetNotifier([this._box]) : super((_box?.get(_key, defaultValue: 500.0) as num?)?.toDouble() ?? 500.0);

  /// Updates and persists the budget ceiling to [newLimit].
  Future<void> setBudget(double newLimit) async {
    await _box?.put(_key, newLimit);
    if (!mounted) return;
    state = newLimit;
  }
}

/// Tracks the user's primary bank account balance.
///
/// **Lifetime:** App-scoped state notifier provider.
/// **Dependencies:** `settingsBoxProvider`.
final currentBalanceProvider = StateNotifierProvider<CurrentBalanceNotifier, double>((ref) {
  try {
    final box = ref.watch(settingsBoxProvider);
    return CurrentBalanceNotifier(box);
  } catch (_) {
    return CurrentBalanceNotifier(null);
  }
});

/// State notifier persisting the bank balance under `current_balance`.
class CurrentBalanceNotifier extends StateNotifier<double> {
  final Box? _box;
  static const _key = 'current_balance';

  /// Creates a [CurrentBalanceNotifier] initialized from persistent settings.
  CurrentBalanceNotifier([this._box]) : super((_box?.get(_key, defaultValue: 0.0) as num?)?.toDouble() ?? 0.0);

  /// Updates and persists the current bank balance to [newBalance].
  Future<void> setBalance(double newBalance) async {
    await _box?.put(_key, newBalance);
    if (!mounted) return;
    state = newBalance;
  }
}

/// Tracks estimated recurring monthly revenue or salary.
///
/// **Lifetime:** App-scoped state notifier provider.
/// **Dependencies:** `settingsBoxProvider`.
final projectedIncomeProvider = StateNotifierProvider<ProjectedIncomeNotifier, double>((ref) {
  try {
    final box = ref.watch(settingsBoxProvider);
    return ProjectedIncomeNotifier(box);
  } catch (_) {
    return ProjectedIncomeNotifier(null);
  }
});

/// State notifier persisting estimated monthly income under `projected_income`.
class ProjectedIncomeNotifier extends StateNotifier<double> {
  final Box? _box;
  static const _key = 'projected_income';

  /// Creates a [ProjectedIncomeNotifier] initialized from persistent settings.
  ProjectedIncomeNotifier([this._box]) : super((_box?.get(_key, defaultValue: 0.0) as num?)?.toDouble() ?? 0.0);

  /// Updates and persists projected monthly revenue to [newIncome].
  Future<void> setIncome(double newIncome) async {
    await _box?.put(_key, newIncome);
    if (!mounted) return;
    state = newIncome;
  }
}

/// Toggles whether financial amounts are blurred or obscured in the presentation layer.
///
/// **Lifetime:** App-scoped state notifier provider.
/// **Dependencies:** `settingsBoxProvider`.
final privacyModeProvider = StateNotifierProvider<PrivacyModeNotifier, bool>((ref) {
  try {
    final box = ref.watch(settingsBoxProvider);
    return PrivacyModeNotifier(box);
  } catch (_) {
    return PrivacyModeNotifier(null);
  }
});

/// State notifier persisting privacy obscuration mode under `privacy_mode_enabled`.
class PrivacyModeNotifier extends StateNotifier<bool> {
  final Box? _box;
  static const _key = 'privacy_mode_enabled';

  /// Creates a [PrivacyModeNotifier] initialized to false if unset.
  PrivacyModeNotifier([this._box]) : super((_box?.get(_key, defaultValue: false) as bool?) ?? false);

  /// Inverts the current privacy obscuration state.
  Future<void> toggle() async {
    final next = !state;
    await _box?.put(_key, next);
    if (!mounted) return;
    state = next;
  }

  /// Sets whether privacy obscuration is [enabled].
  Future<void> setEnabled(bool enabled) async {
    await _box?.put(_key, enabled);
    if (!mounted) return;
    state = enabled;
  }
}

/// Provides the user's estimated marginal tax withholding rate (e.g. 0.25 for 25%).
///
/// **Lifetime:** App-scoped state notifier provider.
/// **Dependencies:** `settingsBoxProvider`.
final taxNestRateProvider = StateNotifierProvider<TaxNestRateNotifier, double>((ref) {
  try {
    final box = ref.watch(settingsBoxProvider);
    return TaxNestRateNotifier(box);
  } catch (_) {
    return TaxNestRateNotifier(null);
  }
});

/// State notifier persisting the estimated tax withholding fraction under `tax_nest_rate`.
class TaxNestRateNotifier extends StateNotifier<double> {
  final Box? _box;
  static const _key = 'tax_nest_rate';

  /// Creates a [TaxNestRateNotifier] with default fallback to [AppConstants.defaultTaxRate].
  TaxNestRateNotifier([this._box])
      : super((_box?.get(_key, defaultValue: AppConstants.defaultTaxRate) as num?)?.toDouble() ??
            AppConstants.defaultTaxRate);

  /// Updates and persists the marginal tax withholding rate to [rate].
  Future<void> setRate(double rate) async {
    await _box?.put(_key, rate);
    if (!mounted) return;
    state = rate;
  }
}

/// Provides the statutory tax liability savings target amount.
///
/// **Lifetime:** App-scoped state notifier provider.
/// **Dependencies:** `settingsBoxProvider`.
final taxNestGoalProvider = StateNotifierProvider<TaxNestGoalNotifier, double>((ref) {
  try {
    final box = ref.watch(settingsBoxProvider);
    return TaxNestGoalNotifier(box);
  } catch (_) {
    return TaxNestGoalNotifier(null);
  }
});

/// State notifier persisting the statutory tax reserve target under `tax_nest_goal`.
class TaxNestGoalNotifier extends StateNotifier<double> {
  final Box? _box;
  static const _key = 'tax_nest_goal';

  /// Creates a [TaxNestGoalNotifier] with default fallback to [AppConstants.defaultTaxNestGoal].
  TaxNestGoalNotifier([this._box])
      : super((_box?.get(_key, defaultValue: AppConstants.defaultTaxNestGoal) as num?)?.toDouble() ??
            AppConstants.defaultTaxNestGoal);

  /// Updates and persists the tax nest reserve goal to [goal].
  Future<void> setGoal(double goal) async {
    await _box?.put(_key, goal);
    if (!mounted) return;
    state = goal;
  }
}

