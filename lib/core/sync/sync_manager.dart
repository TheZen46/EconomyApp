import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:synchronized/synchronized.dart';

import 'conflict_policy.dart';
import 'outbox_service.dart';
import 'sync_error_policy.dart';
import '../../features/boxes/data/models/box_model.dart';
import '../../features/invoices/data/models/invoice_model.dart';
import '../../features/evault/data/models/asset_model.dart';
import '../../features/receipt_scanning/data/models/receipt_model.dart';

/// Bidirectional, offline-first sync coordinator for the RLS-protected user
/// entity tables (receipts, boxes, invoices, assets).
///
/// It does not write the training corpus: receipt_training_labels is filled
/// server-side and readable only by the service role, and training uploads are
/// consent-gated in SyncService.
class SyncManager {
  final SupabaseClient supabase;
  final OutboxService outboxService;
  final Box<ReceiptModel> receiptsBox;
  final Box<BoxModel> boxesBox;
  final Box<InvoiceModel> invoicesBox;
  final Box<AssetModel> assetsBox;
  final Box settingsBox;
  final VoidCallback? onSyncCompleted;

  final Lock _syncLock = Lock();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _isSyncing = false;

  SyncManager({
    required this.supabase,
    required this.outboxService,
    required this.receiptsBox,
    required this.boxesBox,
    required this.invoicesBox,
    required this.assetsBox,
    required this.settingsBox,
    this.onSyncCompleted,
  }) {
    _initAutoSync();
  }

  void _initAutoSync() {
    try {
      _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
        if (!results.contains(ConnectivityResult.none)) {
          syncAll();
        }
      });
    } catch (e) {
      debugPrint('SyncManager: Connectivity listener notice: $e');
    }
  }

  void dispose() {
    _connectivitySub?.cancel();
  }

  /// Full bidirectional synchronization cycle:
  /// 1. Push all pending outbox mutations to Supabase.
  /// 2. Pull remote updates since last sync (Delta Sync) with LWW conflict resolution.
  Future<void> syncAll() async {
    await _syncLock.synchronized(() async {
      if (_isSyncing) return;
      _isSyncing = true;

      try {
        final user = supabase.auth.currentUser;
        if (user == null) {
          debugPrint('SyncManager: No active authenticated user, skipping cloud sync.');
          return;
        }

        debugPrint('SyncManager: Starting bidirectional sync cycle for user ${user.id}...');

        // ── STEP 1: Flush Outbox (Push) ──────────────────────────────────────
        await _flushOutbox(user.id);

        // ── STEP 2: Pull Deltas (Pull) ───────────────────────────────────────
        await _pullDeltas(user.id);

        // Time of the last completed cycle, for display only; the pull itself
        // uses the per-table server watermarks (see _pullTable).
        await settingsBox.put('last_synced_at', DateTime.now().toUtc().toIso8601String());
        debugPrint('SyncManager: Synchronization cycle completed successfully.');
        onSyncCompleted?.call();
      } catch (e, stack) {
        debugPrint('SyncManager: Error during sync cycle: $e\n$stack');
      } finally {
        _isSyncing = false;
      }
    });
  }

  /// Flushes pending outbox items to Supabase.
  ///
  /// Mutations of one entity are applied in creation order. A mutation that fails,
  /// or is still waiting out its retry backoff, holds back the later mutations of
  /// the same entity only, so unrelated entities keep synchronizing. Errors that
  /// cannot succeed on retry are dead-lettered immediately.
  Future<void> _flushOutbox(String userId) async {
    final queued = outboxService.getPendingMutations();
    if (queued.isEmpty) {
      debugPrint('SyncManager: Outbox is empty.');
      return;
    }

    debugPrint('SyncManager: Processing ${queued.length} pending outbox items...');

    final now = DateTime.now();
    final heldEntities = <String>{};

    for (final item in queued) {
      final entityKey = OutboxService.entityKey(item.entityType, item.entityId);
      if (heldEntities.contains(entityKey)) continue;
      if (outboxService.isBackingOff(item, now)) {
        heldEntities.add(entityKey);
        continue;
      }

      final table = _mapEntityTypeToTable(item.entityType);
      if (table == null) {
        await outboxService.markFailed(
          item.id,
          'Unknown entity type "${item.entityType}"',
          permanent: true,
        );
        continue;
      }

      try {
        var payload = Map<String, dynamic>.from(item.payload);
        // user_profiles is keyed by the user id itself and has no user_id column.
        if (item.entityType != 'profile') {
          payload['user_id'] = userId;
        }
        if (item.entityType == 'receipt') {
          payload = ReceiptModel.sanitizeRemotePayload(payload);
        }

        if (item.mutationType == 'delete') {
          // Soft-delete tombstone
          await supabase.from(table).update({
            'deleted_at': DateTime.now().toUtc().toIso8601String(),
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          }).eq('id', item.entityId).eq('user_id', userId);
        } else {
          // Insert / Update (Upsert)
          await supabase.from(table).upsert(payload);
        }

        await outboxService.markCompleted(item.id);
      } catch (e) {
        debugPrint('SyncManager: Failed to sync outbox item ${item.id}: $e');
        await outboxService.markFailed(item.id, e.toString(), permanent: isPermanentSyncError(e));
        heldEntities.add(entityKey);
      }
    }
  }

  /// Resets dead-lettered mutations and runs a synchronization cycle, for use
  /// after the cause (for example a missing migration) has been corrected.
  Future<void> retryDeadLettered() async {
    await outboxService.retryPermanentlyFailed();
    await syncAll();
  }

  /// Rows requested per page during the delta pull.
  static const int pullPageSize = 500;

  /// The first page of a pull starts this far before the stored watermark, so
  /// that a row whose transaction committed after a later one was read (its
  /// updated_at is the transaction start time) is still picked up. Re-applying
  /// a row is idempotent.
  static const Duration pullOverlap = Duration(minutes: 1);

  /// Settings key holding the delta-pull watermark of [table]: the largest
  /// server-assigned updated_at already applied from it.
  static String watermarkKey(String table) => 'sync_watermark_$table';

  /// Pulls remote delta updates from Supabase and applies them with Last-Write-Wins (LWW).
  ///
  /// Entities that still have a mutation in the outbox keep their local state:
  /// the server has not seen that change yet, so a remote row (including a
  /// tombstone) must neither overwrite nor delete it. The change wins once its
  /// push succeeds.
  Future<void> _pullDeltas(String userId) async {
    final unsynced = outboxService.entitiesWithUnsyncedChanges();

    await _pullTable('receipts', 'receipt', userId, unsynced, _applyReceiptDelta);
    await _pullTable('boxes', 'box', userId, unsynced, _applyBoxDelta);
    await _pullTable('invoices', 'invoice', userId, unsynced, _applyInvoiceDelta);
    await _pullTable('vault_assets', 'asset', userId, unsynced, _applyAssetDelta);
  }

  /// Reads the rows of [table] changed since its watermark, page by page.
  ///
  /// The watermark comes from the server timestamps of the rows actually
  /// applied, never from the device clock, and is saved after each page.
  /// Pages are ordered by (updated_at, id) and each continues strictly after
  /// the last (updated_at, id) seen, so rows updated during the pull cannot
  /// shift a page boundary and many rows sharing one timestamp cannot stall it.
  /// A table without a watermark (first pull, or after upgrading from the
  /// device-clock watermark) is read in full, which also backfills rows that
  /// earlier versions skipped or truncated.
  Future<void> _pullTable(
    String table,
    String entityType,
    String userId,
    Set<String> unsynced,
    Future<void> Function(Map<String, dynamic> row) apply,
  ) async {
    final stored = DateTime.tryParse(settingsBox.get(watermarkKey(table)) as String? ?? '');
    final since = stored?.subtract(pullOverlap).toUtc().toIso8601String();

    String? cursorUpdatedAt;
    String? cursorId;
    while (true) {
      var query = supabase.from(table).select().eq('user_id', userId);
      if (cursorUpdatedAt != null && cursorId != null) {
        final ts = _filterValue(cursorUpdatedAt);
        query = query.or('updated_at.gt.$ts,and(updated_at.eq.$ts,id.gt.${_filterValue(cursorId)})');
      } else if (since != null) {
        query = query.gte('updated_at', since);
      }
      final page = await query
          .order('updated_at', ascending: true)
          .order('id', ascending: true)
          .limit(pullPageSize);

      for (final row in page) {
        if (!unsynced.contains(OutboxService.entityKey(entityType, row['id'] as String))) {
          await apply(row);
        }
      }
      if (page.isEmpty) break;

      cursorUpdatedAt = page.last['updated_at'] as String?;
      cursorId = page.last['id'] as String?;
      if (cursorUpdatedAt == null || cursorId == null) break; // cannot paginate without a key
      await settingsBox.put(watermarkKey(table), cursorUpdatedAt);
      if (page.length < pullPageSize) break;
    }
  }

  /// Quotes a value for a PostgREST logical filter, where `,.:()` are reserved.
  static String _filterValue(String value) =>
      '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';

  Future<void> _applyReceiptDelta(Map<String, dynamic> row) async {
    final id = row['id'] as String;
    final deletedAt = row['deleted_at'] != null ? DateTime.tryParse(row['deleted_at'] as String) : null;

    if (deletedAt != null) {
      await receiptsBox.delete(id);
      return;
    }

    var remoteModel = ReceiptModel.fromJson(row);
    final localModel = receiptsBox.get(id);

    // A row without an items array (written before the column existed, or by
    // another tool) carries no information about line items; keep the local ones.
    if (localModel != null && row['items'] is! List) {
      remoteModel = remoteModel.copyWith(items: localModel.items);
    }

    if (localModel == null || _shouldRemoteOverwrite(localModel.updatedAt, localModel.version, remoteModel.updatedAt, remoteModel.version)) {
      await receiptsBox.put(id, remoteModel);
    }
  }

  Future<void> _applyBoxDelta(Map<String, dynamic> row) async {
    final id = row['id'] as String;
    final deletedAt = row['deleted_at'] != null ? DateTime.tryParse(row['deleted_at'] as String) : null;

    if (deletedAt != null) {
      await boxesBox.delete(id);
      return;
    }

    final remoteModel = BoxModel.fromJson(row);
    final localModel = boxesBox.get(id);

    if (localModel == null || _shouldRemoteOverwrite(localModel.updatedAt, localModel.version, remoteModel.updatedAt, remoteModel.version)) {
      await boxesBox.put(id, remoteModel);
    }
  }

  Future<void> _applyInvoiceDelta(Map<String, dynamic> row) async {
    final id = row['id'] as String;
    final deletedAt = row['deleted_at'] != null ? DateTime.tryParse(row['deleted_at'] as String) : null;

    if (deletedAt != null) {
      await invoicesBox.delete(id);
      return;
    }

    final remoteModel = InvoiceModel.fromJson(row);
    final localModel = invoicesBox.get(id);

    if (localModel == null || _shouldRemoteOverwrite(localModel.updatedAt, localModel.version, remoteModel.updatedAt, remoteModel.version)) {
      await invoicesBox.put(id, remoteModel);
    }
  }

  Future<void> _applyAssetDelta(Map<String, dynamic> row) async {
    final id = row['id'] as String;
    final deletedAt = row['deleted_at'] != null ? DateTime.tryParse(row['deleted_at'] as String) : null;

    if (deletedAt != null) {
      await assetsBox.delete(id);
      return;
    }

    final remoteModel = AssetModel.fromJson(row);
    final localModel = assetsBox.get(id);

    if (localModel == null || _shouldRemoteOverwrite(localModel.updatedAt, localModel.version, remoteModel.updatedAt, remoteModel.version)) {
      await assetsBox.put(id, remoteModel);
    }
  }

  /// Conflict Resolution (Last-Write-Wins with monotonic version validation)
  bool _shouldRemoteOverwrite(DateTime? localUpdated, int localVersion, DateTime? remoteUpdated, int remoteVersion) {
    return shouldRemoteOverwrite(
      localUpdatedAt: localUpdated,
      localVersion: localVersion,
      remoteUpdatedAt: remoteUpdated,
      remoteVersion: remoteVersion,
    );
  }

  /// Remote table for [entityType], or null when the type is not synchronized.
  String? _mapEntityTypeToTable(String entityType) {
    switch (entityType) {
      case 'receipt':
        return 'receipts';
      case 'box':
        return 'boxes';
      case 'invoice':
        return 'invoices';
      case 'asset':
        return 'vault_assets';
      case 'profile':
        return 'user_profiles';
      case 'taxonomy':
        return 'taxonomies';
      default:
        return null;
    }
  }
}
