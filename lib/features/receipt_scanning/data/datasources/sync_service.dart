import 'dart:async';
import 'dart:math' as math;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:synchronized/synchronized.dart';

import '../../../../core/privacy/network_policy.dart';
import '../../../../core/services/google_drive_service.dart';
import '../models/sync_item_model.dart';
import 'hive_receipt_data_source.dart';
import 'supabase_data_source.dart';

class SyncService {
  /// Settings key of the user's consent to contribute receipts (image and
  /// extracted data) to the model-training storage.
  static const String trainingContributionKey = 'ai_dataset_contribution_enabled';

  /// Whether the user has opted in to training contribution. Off unless the
  /// user has explicitly enabled it.
  static bool isTrainingContributionEnabled(Box settingsBox) =>
      settingsBox.get(trainingContributionKey, defaultValue: false) as bool;

  final Box<SyncItemModel> queueBox;
  final LocalReceiptDataSource localDataSource;
  final SupabaseDataSource supabaseDataSource;
  final Box settingsBox;
  final GoogleDriveService googleDriveService;

  /// Whether the box with the given id is private. Receipts in private boxes
  /// are never uploaded for model training.
  final bool Function(String? boxId) isPrivateBox;
  final math.Random _random = math.Random();

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  /// Asynchronous Mutex lock ensuring only 1 sync execution occurs at a time.
  final Lock _syncLock = Lock();

  /// Item-level transaction locks to prevent concurrent workers from processing
  /// the same receipt item simultaneously.
  final Set<String> _inFlightItemIds = <String>{};

  SyncService({
    required this.queueBox,
    required this.localDataSource,
    required this.supabaseDataSource,
    required this.settingsBox,
    required this.googleDriveService,
    bool Function(String? boxId)? isPrivateBox,
  }) : isPrivateBox = isPrivateBox ?? _noPrivateBoxes {
    // Listen to network changes (v6.0 API returns List)
    try {
      _connectivitySubscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
        // If we have any connection that is NOT none
        if (!results.contains(ConnectivityResult.none)) {
          syncPendingItems();
        }
      });
    } catch (e) {
      debugPrint('SyncService: Connectivity listener failed to start: $e');
    }

    // Initial check
    syncPendingItems();
  }

  static bool _noPrivateBoxes(String? boxId) => false;

  /// Add item to upload queue
  Future<void> scheduleUpload(String receiptId, String imagePath) async {
    await _syncLock.synchronized(() async {
      if (_inFlightItemIds.contains(receiptId)) return;

      final item = SyncItemModel(
        receiptId: receiptId,
        imagePath: imagePath,
        addedAt: DateTime.now(),
      );
      for (final key in queueBox.keys) {
        final existing = queueBox.get(key);
        if (existing == null || existing.receiptId != receiptId) continue;
        // A pending entry reads the receipt when it is uploaded, so it already
        // covers this save. A dead-lettered entry is never retried on its own;
        // saving the receipt again starts over with a fresh entry.
        if (existing.isDeadLettered) {
          await queueBox.put(key, item);
        }
        return;
      }
      await queueBox.add(item);
    });

    // Try immediate sync (will queue behind the lock and execute safely)
    await syncPendingItems();
  }

  /// Safely processes the sync queue with an asynchronous Mutex lock.
  ///
  /// Concurrent calls will be queued through [_syncLock] and executed sequentially,
  /// preventing overlapping network calls or duplicate uploads to Supabase.
  Future<void> syncPendingItems() async {
    await _syncLock.synchronized(() async {
      if (queueBox.isEmpty) return;

      // Isolation mode: items stay queued until it is turned off.
      if (!NetworkPolicy.isCloudAllowed(settingsBox)) {
        debugPrint('SyncService: Isolation mode is on - skipping syncPendingItems.');
        return;
      }

      // Check network connectivity before processing
      try {
        final connectivity = await Connectivity().checkConnectivity();
        if (connectivity.contains(ConnectivityResult.none)) {
          debugPrint('SyncService: Offline - skipping syncPendingItems.');
          return;
        }
      } catch (e) {
        debugPrint('SyncService: Error checking connectivity: $e');
      }

      debugPrint('SyncService: Starting safe synchronized sync of ${queueBox.length} items...');

      // Snapshot keys so we can mutate the box while iterating
      final keys = queueBox.keys.toList();

      for (var key in keys) {
        final item = queueBox.get(key);
        if (item == null) continue;

        // ── Item-Level Transaction Lock ──────────────────────────────────────
        if (_inFlightItemIds.contains(item.receiptId)) {
          debugPrint('SyncService: Item ${item.receiptId} is already in-flight. Skipping.');
          continue;
        }

        // ── Permanently Failed / Dead-letter check ───────────────────────────
        if (item.status == SyncStatus.permanentlyFailed || item.retryCount >= SyncItemModel.maxRetries) {
          debugPrint('SyncService: Item ${item.receiptId} is marked permanently failed '
              'after ${item.retryCount} attempts. Manual retry required.');
          continue;
        }

        // ── Exponential backoff check ────────────────────────────────────────
        // Skip this item if we haven't waited long enough since the last failure.
        if (!item.isReadyForRetry) {
          debugPrint('SyncService: Skipping ${item.receiptId} — backoff active '
              '(retry ${item.retryCount}, next at ${item.nextRetryTimestamp})');
          continue;
        }

        // Acquire item-level transaction lock
        _inFlightItemIds.add(item.receiptId);

        try {
          await _uploadItem(item);
          // Success: remove from queue
          await queueBox.delete(key);
          debugPrint('SyncService: Synced receipt ${item.receiptId}');
        } catch (e) {
          // ── Exponential Backoff with Jitter ────────────────────────────────
          final jitterMs = _random.nextInt(250);
          final updated = item.withFailedAttempt(
            error: e.toString(),
            jitterMs: jitterMs,
          );
          await queueBox.put(key, updated);

          if (updated.status == SyncStatus.permanentlyFailed) {
            debugPrint('SyncService: Receipt ${item.receiptId} permanently failed '
                'after ${updated.retryCount} attempts: $e');
          } else {
            debugPrint('SyncService: Failed to sync ${item.receiptId} '
                '(attempt ${updated.retryCount}/${SyncItemModel.maxRetries}, '
                'next retry at ${updated.nextRetryTimestamp}): $e');
          }
        } finally {
          // Release item-level transaction lock
          _inFlightItemIds.remove(item.receiptId);
        }
      }
    });
  }

  /// Resets a permanently failed item to pending for a manual retry.
  Future<void> retryFailedItem(String receiptId) async {
    await _syncLock.synchronized(() async {
      for (var key in queueBox.keys) {
        final item = queueBox.get(key);
        if (item != null && item.receiptId == receiptId) {
          final reset = item.forManualRetry();
          await queueBox.put(key, reset);
          debugPrint('SyncService: Reset receipt $receiptId for manual retry');
          break;
        }
      }
    });
    await syncPendingItems();
  }

  /// Resets all permanently failed items for manual retry.
  Future<void> retryAllFailed() async {
    await _syncLock.synchronized(() async {
      for (var key in queueBox.keys) {
        final item = queueBox.get(key);
        if (item != null && item.status == SyncStatus.permanentlyFailed) {
          await queueBox.put(key, item.forManualRetry());
        }
      }
    });
    await syncPendingItems();
  }

  /// Deletes all permanently failed items from the queue.
  Future<void> clearFailedItems() async {
    await _syncLock.synchronized(() async {
      final keysToDelete = <dynamic>[];
      for (var key in queueBox.keys) {
        final item = queueBox.get(key);
        if (item != null && item.status == SyncStatus.permanentlyFailed) {
          keysToDelete.add(key);
        }
      }
      for (var key in keysToDelete) {
        await queueBox.delete(key);
      }
    });
  }

  /// Alias for [syncPendingItems] to maintain backward compatibility.
  Future<void> processQueue() => syncPendingItems();

  Future<void> _uploadItem(SyncItemModel item) async {
    // 1. Load Receipt from Local
    final receiptModel = await localDataSource.getReceipt(item.receiptId);
    if (receiptModel == null) {
      // Receipt deleted locally - safe to remove from queue.
      // We assume local deletion is authoritative.
      debugPrint('SyncService: Receipt not found locally, skipping upload.');
      return;
    }
    final receipt = receiptModel.toEntity();

    // 2. Upload to Configured Provider
    final useDrive = settingsBox.get('use_google_drive_storage', defaultValue: false);
    if (useDrive) {
      // The user's own Google Drive: a personal backup, not the training corpus.
      await googleDriveService.uploadReceiptData(receiptModel.toJson(), receipt.id, item.imagePath);
    } else if (isPrivateBox(receiptModel.boxId)) {
      debugPrint('SyncService: ${item.receiptId} is in a private box, not uploading it for training.');
    } else if (isTrainingContributionEnabled(settingsBox)) {
      await supabaseDataSource.uploadTrainingData(receipt, item.imagePath);
    } else {
      // Without consent nothing is uploaded; evaluated per item, so turning the
      // setting off also stops uploads that are already queued.
      debugPrint('SyncService: Training contribution is off, not uploading ${item.receiptId}.');
    }
  }

  void dispose() {
    _connectivitySubscription?.cancel();
  }
}
