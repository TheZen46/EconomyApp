import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:synchronized/synchronized.dart';

import '../privacy/pii_scrubber_service.dart';
import 'outbox_service.dart';
import '../../features/boxes/data/models/box_model.dart';
import '../../features/invoices/data/models/invoice_model.dart';
import '../../features/evault/data/models/asset_model.dart';
import '../../features/receipt_scanning/data/models/receipt_model.dart';

/// Bidirectional, offline-first sync coordinator.
/// Enforces Dual-Tier Privacy:
/// - Tier 1 (AI Training Corpus): Anonymized receipt labels pushed to receipt_training_labels.
/// - Tier 2 (Confidential Vault): RLS-protected user entity tables (receipts, boxes, invoices, assets).
class SyncManager {
  final SupabaseClient supabase;
  final OutboxService outboxService;
  final Box<ReceiptModel> receiptsBox;
  final Box<BoxModel> boxesBox;
  final Box<InvoiceModel> invoicesBox;
  final Box<AssetModel> assetsBox;
  final Box settingsBox;

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

        // Update last synced timestamp
        await settingsBox.put('last_synced_at', DateTime.now().toUtc().toIso8601String());
        debugPrint('SyncManager: Synchronization cycle completed successfully.');
      } catch (e, stack) {
        debugPrint('SyncManager: Error during sync cycle: $e\n$stack');
      } finally {
        _isSyncing = false;
      }
    });
  }

  /// Flushes pending outbox items to Supabase.
  Future<void> _flushOutbox(String userId) async {
    final pending = outboxService.getPendingMutations();
    if (pending.isEmpty) {
      debugPrint('SyncManager: Outbox is empty.');
      return;
    }

    debugPrint('SyncManager: Processing ${pending.length} pending outbox items...');

    for (final item in pending) {
      try {
        final payload = Map<String, dynamic>.from(item.payload);
        payload['user_id'] = userId;

        final table = _mapEntityTypeToTable(item.entityType);

        if (item.mutationType == 'delete') {
          // Soft-delete tombstone
          await supabase.from(table).update({
            'deleted_at': DateTime.now().toUtc().toIso8601String(),
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          }).eq('id', item.entityId).eq('user_id', userId);
        } else {
          // Insert / Update (Upsert)
          await supabase.from(table).upsert(payload);

          // If this is a receipt, also push anonymized Tier 1 training data
          if (item.entityType == 'receipt') {
            await _stageTier1TrainingLabels(payload);
          }
        }

        await outboxService.markCompleted(item.id);
      } catch (e) {
        debugPrint('SyncManager: Failed to sync outbox item ${item.id}: $e');
        await outboxService.markFailed(item.id, e.toString());
      }
    }
  }

  /// Staging anonymized training data to Tier 1 tables.
  Future<void> _stageTier1TrainingLabels(Map<String, dynamic> receiptPayload) async {
    try {
      final merchant = receiptPayload['merchant_name'] as String? ?? 'Merchant';
      final items = receiptPayload['items'] as List<dynamic>? ?? [];

      for (final itemMap in items) {
        if (itemMap is Map<String, dynamic>) {
          final scrubbedSample = {
            'receipt_id': receiptPayload['id'],
            'anonymized_merchant': PiiScrubberService.sanitizeText(merchant),
            'anonymized_description': PiiScrubberService.sanitizeText(itemMap['description'] as String?),
            'quantity': itemMap['quantity'] ?? 1,
            'unit_price': itemMap['unit_price'] ?? 0.0,
            'total_price': itemMap['total_price'] ?? 0.0,
            'main_category': itemMap['main_category'],
            'sub_category': itemMap['sub_category'],
            'necessity': itemMap['necessity'] ?? 'unknown',
            'was_user_corrected': itemMap['is_user_corrected'] ?? false,
            'created_at': DateTime.now().toUtc().toIso8601String(),
          };

          await supabase.from('receipt_training_labels').insert(scrubbedSample);
        }
      }
    } catch (e) {
      debugPrint('SyncManager: Notice staging Tier 1 training label: $e');
    }
  }

  /// Pulls remote delta updates from Supabase and applies them with Last-Write-Wins (LWW).
  Future<void> _pullDeltas(String userId) async {
    final lastSyncedStr = settingsBox.get('last_synced_at') as String?;
    final lastSyncedAt = lastSyncedStr != null ? DateTime.tryParse(lastSyncedStr) : null;

    // 1. Pull Receipts
    var receiptsQuery = supabase.from('receipts').select().eq('user_id', userId);
    if (lastSyncedAt != null) {
      receiptsQuery = receiptsQuery.gt('updated_at', lastSyncedAt.toUtc().toIso8601String());
    }
    final remoteReceipts = await receiptsQuery;
    for (final row in remoteReceipts) {
      _applyReceiptDelta(row);
    }

    // 2. Pull Boxes
    var boxesQuery = supabase.from('boxes').select().eq('user_id', userId);
    if (lastSyncedAt != null) {
      boxesQuery = boxesQuery.gt('updated_at', lastSyncedAt.toUtc().toIso8601String());
    }
    final remoteBoxes = await boxesQuery;
    for (final row in remoteBoxes) {
      _applyBoxDelta(row);
    }

    // 3. Pull Invoices
    var invoicesQuery = supabase.from('invoices').select().eq('user_id', userId);
    if (lastSyncedAt != null) {
      invoicesQuery = invoicesQuery.gt('updated_at', lastSyncedAt.toUtc().toIso8601String());
    }
    final remoteInvoices = await invoicesQuery;
    for (final row in remoteInvoices) {
      _applyInvoiceDelta(row);
    }

    // 4. Pull Assets
    var assetsQuery = supabase.from('vault_assets').select().eq('user_id', userId);
    if (lastSyncedAt != null) {
      assetsQuery = assetsQuery.gt('updated_at', lastSyncedAt.toUtc().toIso8601String());
    }
    final remoteAssets = await assetsQuery;
    for (final row in remoteAssets) {
      _applyAssetDelta(row);
    }
  }

  void _applyReceiptDelta(Map<String, dynamic> row) {
    final id = row['id'] as String;
    final deletedAt = row['deleted_at'] != null ? DateTime.tryParse(row['deleted_at'] as String) : null;

    if (deletedAt != null) {
      receiptsBox.delete(id);
      return;
    }

    final remoteModel = ReceiptModel.fromJson(row);
    final localModel = receiptsBox.get(id);

    if (localModel == null || _shouldRemoteOverwrite(localModel.updatedAt, localModel.version, remoteModel.updatedAt, remoteModel.version)) {
      receiptsBox.put(id, remoteModel);
    }
  }

  void _applyBoxDelta(Map<String, dynamic> row) {
    final id = row['id'] as String;
    final deletedAt = row['deleted_at'] != null ? DateTime.tryParse(row['deleted_at'] as String) : null;

    if (deletedAt != null) {
      boxesBox.delete(id);
      return;
    }

    final remoteModel = BoxModel.fromJson(row);
    final localModel = boxesBox.get(id);

    if (localModel == null || _shouldRemoteOverwrite(localModel.updatedAt, localModel.version, remoteModel.updatedAt, remoteModel.version)) {
      boxesBox.put(id, remoteModel);
    }
  }

  void _applyInvoiceDelta(Map<String, dynamic> row) {
    final id = row['id'] as String;
    final deletedAt = row['deleted_at'] != null ? DateTime.tryParse(row['deleted_at'] as String) : null;

    if (deletedAt != null) {
      invoicesBox.delete(id);
      return;
    }

    final remoteModel = InvoiceModel.fromJson(row);
    final localModel = invoicesBox.get(id);

    if (localModel == null || _shouldRemoteOverwrite(localModel.updatedAt, localModel.version, remoteModel.updatedAt, remoteModel.version)) {
      invoicesBox.put(id, remoteModel);
    }
  }

  void _applyAssetDelta(Map<String, dynamic> row) {
    final id = row['id'] as String;
    final deletedAt = row['deleted_at'] != null ? DateTime.tryParse(row['deleted_at'] as String) : null;

    if (deletedAt != null) {
      assetsBox.delete(id);
      return;
    }

    final remoteModel = AssetModel.fromJson(row);
    final localModel = assetsBox.get(id);

    if (localModel == null || _shouldRemoteOverwrite(localModel.updatedAt, localModel.version, remoteModel.updatedAt, remoteModel.version)) {
      assetsBox.put(id, remoteModel);
    }
  }

  /// Conflict Resolution (Last-Write-Wins with monotonic version validation)
  bool _shouldRemoteOverwrite(DateTime? localUpdated, int localVersion, DateTime? remoteUpdated, int remoteVersion) {
    if (remoteVersion > localVersion) return true;
    if (remoteVersion < localVersion) return false;
    if (localUpdated == null) return true;
    if (remoteUpdated == null) return false;
    return remoteUpdated.isAfter(localUpdated);
  }

  String _mapEntityTypeToTable(String entityType) {
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
        return 'receipts';
    }
  }
}
