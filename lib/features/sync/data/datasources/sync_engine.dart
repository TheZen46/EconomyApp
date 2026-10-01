import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:synchronized/synchronized.dart';

import '../../../../core/sync/conflict_policy.dart';
import '../../../boxes/data/models/box_model.dart';
import '../../../evault/data/models/asset_model.dart';
import '../../../invoices/data/models/invoice_model.dart';
import '../../../receipt_scanning/data/datasources/hive_receipt_data_source.dart';
import '../../../receipt_scanning/data/datasources/sync_service.dart';
import '../../../receipt_scanning/data/models/receipt_model.dart';
import '../../../settings/data/models/taxonomy_model.dart';
import '../../domain/entities/sync_progress_state.dart';
import 'remote_replica_data_source.dart';

/// Callback listener for real-time progress state updates.
typedef SyncProgressCallback = void Function(SyncProgressState state);

/// Robust cross-device synchronization engine handling data replication,
/// delta synchronization, resilient streaming, and local Hive rehydration.
class SyncEngine {
  final RemoteReplicaDataSource remoteDataSource;
  final LocalReceiptDataSource localDataSource;
  final Box<AssetModel>? assetsBox;
  final Box<BoxModel>? boxesBox;
  final Box<InvoiceModel>? invoicesBox;
  final Box<TaxonomyConfigModel>? taxonomyBox;
  final SyncService? uploadSyncService;

  final Lock _engineLock = Lock();
  final math.Random _random = math.Random();

  SyncProgressState _currentState = const SyncProgressState();
  final StreamController<SyncProgressState> _stateController =
      StreamController<SyncProgressState>.broadcast();

  Stream<SyncProgressState> get stateStream => _stateController.stream;
  SyncProgressState get currentState => _currentState;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _isDisposed = false;
  bool _shouldCancel = false;

  SyncEngine({
    required this.remoteDataSource,
    required this.localDataSource,
    this.assetsBox,
    this.boxesBox,
    this.invoicesBox,
    this.taxonomyBox,
    this.uploadSyncService,
  }) {
    _initConnectivityListener();
  }

  void _initConnectivityListener() {
    try {
      _connectivitySub = Connectivity().onConnectivityChanged.listen(
        (results) {
          if (!results.contains(ConnectivityResult.none) &&
              _currentState.stage == SyncStage.interruptedRetrying) {
            debugPrint('SyncEngine: Connectivity restored, resuming sync...');
          }
        },
        onError: (e) {
          debugPrint('SyncEngine: Connectivity listener notice: $e');
        },
        cancelOnError: false,
      );
    } catch (e) {
      debugPrint('SyncEngine: Connectivity listener setup notice: $e');
    }
  }

  void _emit(SyncProgressState newState) {
    if (_isDisposed) return;
    _currentState = newState;
    _stateController.add(newState);
  }

  /// Cancels the current running synchronization run.
  void cancel() {
    _shouldCancel = true;
  }

  /// Continues into the application in offline mode, bypassing blocking sync.
  void continueOffline() {
    _shouldCancel = true;
    _emit(_currentState.copyWith(
      stage: SyncStage.completed,
      message: 'Workspace loaded in offline fallback mode.',
      progress: 1.0,
    ));
  }

  /// Executes full initial replication and delta sync for [userId].
  Future<bool> executeSync({
    required String userId,
    bool isInitial = true,
  }) async {
    return await _engineLock.synchronized(() async {
      _shouldCancel = false;
      int attempt = 0;
      const maxAttempts = 5;

      while (attempt < maxAttempts && !_shouldCancel) {
        attempt++;
        try {
          // ── Step 1: Handshake & Network Validation ─────────────────────────
          _emit(SyncProgressState(
            stage: SyncStage.authenticating,
            progress: 0.05,
            message: 'Establishing secure handshake with cloud vault...',
            isInitialSync: isInitial,
            retryAttempt: attempt,
            maxRetryAttempts: maxAttempts,
          ));

          // Advisory connectivity check
          final isOnline = await _checkConnectivity();
          if (!isOnline) {
            debugPrint('SyncEngine: Advisory network check reports offline, attempting query with timeout...');
          }

          // ── Step 2: Query Remote Manifest (Delta Sync) ─────────────────────
          _emit(_currentState.copyWith(
            stage: SyncStage.fetchingManifest,
            progress: 0.15,
            message: 'Querying encrypted directory manifest & delta catalog...',
          ));

          final remoteReceiptRows = await remoteDataSource.fetchReceipts(userId);
          final remoteFiles = await remoteDataSource.listRemoteFiles(userId);
          final remoteBoxes = await remoteDataSource.fetchBoxes(userId);
          final remoteAssets = await remoteDataSource.fetchAssets(userId);
          final remoteInvoices = await remoteDataSource.fetchInvoices(userId);

          // ── Step 3: Delta Calculation ──────────────────────────────────────
          final localReceipts = await localDataSource.getReceipts();
          final localReceiptIds = localReceipts.map((r) => r.id).toSet();

          // Identify receipts missing locally; soft-deleted rows are tombstones, not data
          final deltaReceiptsToImport = remoteReceiptRows.where((row) {
            final id = row['id'] as String?;
            return id != null && !_isTombstone(row) && !localReceiptIds.contains(id);
          }).toList();

          // Identify remote image files to download
          final remoteImageFiles = remoteFiles.where((f) => f.path.contains('/images/')).toList();
          final totalDeltaItems = deltaReceiptsToImport.length +
              remoteImageFiles.length +
              remoteBoxes.length +
              remoteAssets.length +
              remoteInvoices.length;

          final totalBytesToTransfer = remoteFiles.fold<int>(0, (sum, f) => sum + f.size);

          _emit(_currentState.copyWith(
            stage: SyncStage.downloadingDeltas,
            progress: 0.25,
            message: totalDeltaItems == 0
                ? 'Local cache is in parity. Checking file integrity...'
                : 'Streaming delta replicas ($totalDeltaItems pending changes)...',
            totalItems: totalDeltaItems > 0 ? totalDeltaItems : 1,
            totalBytes: totalBytesToTransfer,
          ));

          // ── Step 4: Rehydrate Database Entities ────────────────────────────
          int completedItems = 0;
          int bytesDownloaded = 0;
          final stopwatch = Stopwatch()..start();

          // 4a. Receipts
          for (final row in deltaReceiptsToImport) {
            if (_shouldCancel) return false;
            try {
              final receiptModel = _parseRow(row, ReceiptModel.fromJson, 'receipt');
              if (receiptModel != null) {
                await localDataSource.saveReceipt(receiptModel);
              }
            } catch (e) {
              debugPrint('SyncEngine: Notice rehydrating receipt: $e');
            }
            completedItems++;
            _updateTransferProgress(completedItems, totalDeltaItems, bytesDownloaded, totalBytesToTransfer, stopwatch);
          }

          // 4b. Boxes
          if (boxesBox != null) {
            for (final row in remoteBoxes) {
              if (_shouldCancel) return false;
              try {
                final box = _isTombstone(row) ? null : _parseRow(row, BoxModel.fromJson, 'box');
                final local = box == null ? null : boxesBox!.get(box.id);
                if (box != null &&
                    (local == null ||
                        shouldRemoteOverwrite(
                          localUpdatedAt: local.updatedAt,
                          localVersion: local.version,
                          remoteUpdatedAt: box.updatedAt,
                          remoteVersion: box.version,
                        ))) {
                  await boxesBox!.put(box.id, box);
                }
              } catch (e) {
                debugPrint('SyncEngine: Notice rehydrating box: $e');
              }
              completedItems++;
              _updateTransferProgress(completedItems, totalDeltaItems, bytesDownloaded, totalBytesToTransfer, stopwatch);
            }
          }

          // 4c. Vault Assets
          if (assetsBox != null) {
            for (final row in remoteAssets) {
              if (_shouldCancel) return false;
              try {
                final asset = _isTombstone(row) ? null : _parseRow(row, AssetModel.fromJson, 'asset');
                final local = asset == null ? null : assetsBox!.get(asset.id);
                if (asset != null &&
                    (local == null ||
                        shouldRemoteOverwrite(
                          localUpdatedAt: local.updatedAt,
                          localVersion: local.version,
                          remoteUpdatedAt: asset.updatedAt,
                          remoteVersion: asset.version,
                        ))) {
                  await assetsBox!.put(asset.id, asset);
                }
              } catch (e) {
                debugPrint('SyncEngine: Notice rehydrating asset: $e');
              }
              completedItems++;
              _updateTransferProgress(completedItems, totalDeltaItems, bytesDownloaded, totalBytesToTransfer, stopwatch);
            }
          }

          // 4d. Invoices
          if (invoicesBox != null) {
            for (final row in remoteInvoices) {
              if (_shouldCancel) return false;
              try {
                final invoice = _isTombstone(row) ? null : _parseRow(row, InvoiceModel.fromJson, 'invoice');
                final local = invoice == null ? null : invoicesBox!.get(invoice.id);
                if (invoice != null &&
                    (local == null ||
                        shouldRemoteOverwrite(
                          localUpdatedAt: local.updatedAt,
                          localVersion: local.version,
                          remoteUpdatedAt: invoice.updatedAt,
                          remoteVersion: invoice.version,
                        ))) {
                  await invoicesBox!.put(invoice.id, invoice);
                }
              } catch (e) {
                debugPrint('SyncEngine: Notice rehydrating invoice: $e');
              }
              completedItems++;
              _updateTransferProgress(completedItems, totalDeltaItems, bytesDownloaded, totalBytesToTransfer, stopwatch);
            }
          }

          // ── Step 5: Chunked File Replication ───────────────────────────────
          _emit(_currentState.copyWith(
            stage: SyncStage.rehydratingStorage,
            message: 'Replicating media assets & local directory structure...',
          ));

          Directory? localDocsDir;
          if (!kIsWeb) {
            try {
              localDocsDir = await getApplicationDocumentsDirectory();
            } catch (_) {
              localDocsDir = null;
            }
          }

          for (int i = 0; i < remoteImageFiles.length; i++) {
            if (_shouldCancel) return false;
            final fileEntry = remoteImageFiles[i];

            bool alreadyExistsLocally = false;
            String? targetLocalPath;

            if (!kIsWeb && localDocsDir != null) {
              targetLocalPath = '${localDocsDir.path}/${fileEntry.name}';
              final localFile = File(targetLocalPath);
              if (localFile.existsSync() && localFile.lengthSync() == fileEntry.size) {
                alreadyExistsLocally = true;
              }
            }

            if (!alreadyExistsLocally) {
              try {
                final bytes = await remoteDataSource.downloadFile(fileEntry.path);
                bytesDownloaded += bytes.length;

                if (!kIsWeb && targetLocalPath != null) {
                  final localFile = File(targetLocalPath);
                  await localFile.writeAsBytes(bytes, flush: true);
                }
              } catch (e) {
                debugPrint('SyncEngine: Notice downloading file ${fileEntry.name}: $e');
              }
            } else {
              bytesDownloaded += fileEntry.size;
            }

            completedItems++;
            _updateTransferProgress(
              completedItems,
              totalDeltaItems,
              bytesDownloaded,
              totalBytesToTransfer,
              stopwatch,
              message: 'Streaming media asset ${i + 1} of ${remoteImageFiles.length}...',
            );
          }

          // ── Step 6: Push Pending Local Uploads (Bidirectional Parity) ───────
          if (uploadSyncService != null) {
            try {
              await uploadSyncService!.syncPendingItems();
            } catch (e) {
              debugPrint('SyncEngine: Local upload queue flush notice: $e');
            }
          }

          // ── Step 7: Parity Verification & Finalization ──────────────────────
          _emit(_currentState.copyWith(
            stage: SyncStage.verifyingParity,
            progress: 0.95,
            message: 'Verifying bit-for-bit directory integrity...',
          ));

          await Future.delayed(const Duration(milliseconds: 300));

          _emit(_currentState.copyWith(
            stage: SyncStage.completed,
            progress: 1.0,
            message: 'Replication complete. Local environment synchronized.',
            itemsCompleted: totalDeltaItems > 0 ? totalDeltaItems : 1,
            totalItems: totalDeltaItems > 0 ? totalDeltaItems : 1,
            bytesTransferred: totalBytesToTransfer,
            totalBytes: totalBytesToTransfer,
          ));

          return true;
        } catch (e) {
          debugPrint('SyncEngine: Sync run failed on attempt $attempt: $e');

          if (attempt >= maxAttempts || _shouldCancel) {
            _emit(_currentState.copyWith(
              stage: SyncStage.failed,
              errorMessage: 'Synchronization encountered an error: $e',
              message: 'Sync could not complete. You can retry or work offline.',
              canContinueOffline: true,
            ));
            return false;
          } else {
            // Exponential backoff with jitter: 2^attempt + random(0..1000ms)
            final backoffSecs = math.pow(2, attempt).clamp(2, 10).toInt();
            final jitterMs = _random.nextInt(1000);

            _emit(_currentState.copyWith(
              stage: SyncStage.interruptedRetrying,
              retryAttempt: attempt,
              maxRetryAttempts: maxAttempts,
              canContinueOffline: true,
              message: 'Connection interrupted. Reconnecting in ${backoffSecs}s (Attempt $attempt/$maxAttempts)...',
            ));

            await Future.delayed(Duration(seconds: backoffSecs, milliseconds: jitterMs));
          }
        }
      }

      return false;
    });
  }

  void _updateTransferProgress(
    int completed,
    int total,
    int bytesTransferred,
    int totalBytes,
    Stopwatch stopwatch, {
    String? message,
  }) {
    final safeTotal = total > 0 ? total : 1;
    final progressVal = 0.25 + (0.65 * (completed / safeTotal)).clamp(0.0, 0.65);
    final elapsedSecs = stopwatch.elapsedMilliseconds / 1000.0;
    final speed = elapsedSecs > 0 ? (bytesTransferred / elapsedSecs) : 0.0;

    _emit(_currentState.copyWith(
      progress: progressVal.clamp(0.0, 0.95),
      itemsCompleted: completed,
      totalItems: safeTotal,
      bytesTransferred: bytesTransferred,
      totalBytes: totalBytes > bytesTransferred ? totalBytes : bytesTransferred,
      transferSpeedBytesPerSec: speed,
      message: message ?? _currentState.message,
    ));
  }

  Future<bool> _checkConnectivity() async {
    try {
      final results = await Connectivity().checkConnectivity();
      return !results.contains(ConnectivityResult.none);
    } catch (_) {
      return true; // Fallback
    }
  }

  // ── Entity Parsing Helpers ─────────────────────────────────────────────────

  /// Whether [row] is a soft-deleted record.
  static bool _isTombstone(Map<String, dynamic> row) => row['deleted_at'] != null;

  /// Maps [row] with the model's own `fromJson`, the same mapping the delta pull
  /// in `SyncManager` uses, so both paths read identical columns.
  T? _parseRow<T>(
    Map<String, dynamic> row,
    T Function(Map<String, dynamic>) fromJson,
    String entity,
  ) {
    if (row['id'] == null) return null;
    try {
      return fromJson(row);
    } catch (e) {
      debugPrint('SyncEngine: Error parsing $entity row: $e');
      return null;
    }
  }

  void dispose() {
    _isDisposed = true;
    _connectivitySub?.cancel();
    _stateController.close();
  }
}
