import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive/hive.dart';

import '../../../../core/services/google_drive_service.dart';
import '../models/sync_item_model.dart';
import 'hive_receipt_data_source.dart';
import 'supabase_data_source.dart';

class SyncService {
  final Box<SyncItemModel> queueBox;
  final LocalReceiptDataSource localDataSource;
  final SupabaseDataSource supabaseDataSource;
  final Box settingsBox;
  final GoogleDriveService googleDriveService;
  
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _isSyncing = false;

  SyncService({
    required this.queueBox,
    required this.localDataSource,
    required this.supabaseDataSource,
    required this.settingsBox,
    required this.googleDriveService,
  }) {
    // Listen to network changes (v6.0 API returns List)
    // Listen to network changes (v6.0 API returns List)
    try {
      _connectivitySubscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
        // If we have any connection that is NOT none
        if (!results.contains(ConnectivityResult.none)) {
          processQueue();
        }
      });
    } catch (e) {
      print('SyncService: Connectivity listener failed to start: $e');
    }

    // Initial check
    processQueue();
  }

  /// Add item to upload queue
  Future<void> scheduleUpload(String receiptId, String imagePath) async {
    // Avoid duplicates
    if (queueBox.values.any((item) => item.receiptId == receiptId)) {
      return;
    }

    final item = SyncItemModel(
      receiptId: receiptId,
      imagePath: imagePath,
      addedAt: DateTime.now(),
    );
    await queueBox.add(item);
    
    // Try immediate sync (will fail fast if offline)
    processQueue();
  }

  /// Attempt to upload pending items
  Future<void> processQueue() async {
    if (_isSyncing || queueBox.isEmpty) return;

    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity.contains(ConnectivityResult.none)) return;

    _isSyncing = true;
    print('SyncService: Starting sync of ${queueBox.length} items...');

    try {
      // Iterate keys so we can delete by key
      final keys = queueBox.keys.toList();
      
      for (var key in keys) {
        final item = queueBox.get(key);
        if (item == null) continue;

        try {
          await _uploadItem(item);
          // Success: remove from queue
          await queueBox.delete(key);
          print('SyncService: Synced receipt ${item.receiptId}');
        } catch (e) {
          print('SyncService: Failed to sync ${item.receiptId}: $e');
          // Keep in queue for retry later
        }
      }
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _uploadItem(SyncItemModel item) async {
    // 1. Load Receipt from Local
    final receiptModels = await localDataSource.getReceipts();
    try {
      final receiptModel = receiptModels.firstWhere((r) => r.id == item.receiptId);
      final receipt = receiptModel.toEntity();

      // 2. Check Image
      if (!File(item.imagePath).existsSync()) {
        throw Exception('Image file not found: ${item.imagePath}');
      }

      // 3. Upload to Configured Provider
      final useDrive = settingsBox.get('use_google_drive_storage', defaultValue: false);
      if (useDrive) {
         await googleDriveService.uploadReceiptData(receiptModel.toJson(), receipt.id, item.imagePath);
      } else {
         await supabaseDataSource.uploadTrainingData(receipt, item.imagePath);
      }
    } catch (e) {
      // If receipt not found locally, maybe it was deleted?
      if (e is StateError) {
         // Receipt deleted locally - safe to remove from queue?
         // Yes, we assume local deletion is authoritative.
         print('SyncService: Receipt not found locally, skipping upload.');
         return; 
      }
      rethrow;
    }
  }

  void dispose() {
    _connectivitySubscription?.cancel();
  }
}
