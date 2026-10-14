import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'outbox_service.dart';
import 'sync_coordinator.dart';
import 'sync_manager.dart';
import '../providers/supabase_providers.dart';
import '../providers/storage_providers.dart';
import '../crdt/crdt_providers.dart';

export '../providers/storage_providers.dart' show outboxHiveBoxProvider;

/// Optional service responsible for queueing, executing, and deduplicating offline mutations.
///
/// **Lifetime:** App-scoped singleton.
/// Returns null if [outboxHiveBoxNullableProvider] is null.
final outboxServiceNullableProvider = Provider<OutboxService?>((ref) {
  final box = ref.watch(outboxHiveBoxNullableProvider);
  if (box == null) return null;
  return OutboxService(box);
});

/// Service responsible for queueing, executing, and deduplicating offline mutations.
///
/// **Lifetime:** App-scoped singleton.
/// **Override:** Inherits from [outboxHiveBoxProvider].
/// **Dependencies:** `outboxHiveBoxProvider`.
final outboxServiceProvider = Provider<OutboxService>((ref) {
  final box = ref.watch(outboxHiveBoxProvider);
  return OutboxService(box);
});

/// Bidirectional synchronization orchestrator connecting local Hive storage to Supabase.
///
/// **Lifetime:** App-scoped singleton with registered disposal cleanup via `ref.onDispose`.
/// **Override:** None required. Returns `null` if Supabase credentials are missing or the app runs offline.
/// **Dependencies:**
/// - `supabaseClientProvider`: Supabase client or null if offline.
/// - `outboxServiceProvider`: Outbox queue service.
/// - `hiveBoxProvider`: Receipts local box.
/// - `boxesHiveBoxProvider`: Budget boxes local box.
/// - `invoicesHiveBoxProvider`: Invoices local box.
/// - `assetsBoxProvider`: EVault asset inventory local box.
/// - `settingsBoxProvider`: General settings and encryption metadata box.
final syncManagerProvider = Provider<SyncManager?>((ref) {
  // Without an initialized client the app runs local-only.
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return null;

  // Supabase is configured; all required dependencies for bidirectional sync must be present.
  final outbox = ref.watch(outboxServiceProvider);
  final receipts = ref.watch(hiveBoxProvider);
  final boxes = ref.watch(boxesHiveBoxProvider);
  final invoices = ref.watch(invoicesHiveBoxProvider);
  final assets = ref.watch(assetsBoxProvider);
  final settings = ref.watch(settingsBoxProvider);
  final coordinator = ref.watch(syncCoordinatorProvider);

  final manager = SyncManager(
    supabase: client,
    outboxService: outbox,
    receiptsBox: receipts,
    boxesBox: boxes,
    invoicesBox: invoices,
    assetsBox: assets,
    settingsBox: settings,
    coordinator: coordinator,
    onSyncCompleted: coordinator.notifySyncCompleted,
    crdtEngine: ref.watch(crdtSyncEngineProvider),
  );
  ref.onDispose(manager.dispose);
  return manager;
});

/// Streams the count of dead-lettered outbox mutations (status `permanently_failed`),
/// updating reactively whenever the local outbox Hive box changes.
///
/// **Lifetime:** Auto-updating stream provider.
/// **Dependencies:** `outboxHiveBoxNullableProvider`.
final deadLetteredMutationCountProvider = StreamProvider<int>((ref) async* {
  final box = ref.watch(outboxHiveBoxNullableProvider);
  if (box == null) {
    yield 0;
    return;
  }
  int count() => box.values.where((item) => item.status == 'permanently_failed').length;
  yield count();
  yield* box.watch().map((_) => count());
});
