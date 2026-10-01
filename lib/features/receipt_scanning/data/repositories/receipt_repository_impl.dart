import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/services/ai_service.dart';
import '../../domain/entities/receipt.dart';
import '../../domain/repositories/receipt_repository.dart';
import '../datasources/hive_receipt_data_source.dart';
import '../datasources/receipt_image_store.dart';
import '../datasources/supabase_data_source.dart';
import '../models/receipt_model.dart';
import '../datasources/sync_service.dart';

import 'package:hive/hive.dart'; // Add Hive import
// Add Drive Service import
import '../../../settings/data/datasources/webhook_service.dart'; // Webhook Import

import '../../../../core/constants/taxonomy_constants.dart';
import '../../../evault/data/models/asset_model.dart';
import 'package:uuid/uuid.dart'; // UUID
import '../../../../core/sync/outbox_service.dart';

class ReceiptRepositoryImpl implements ReceiptRepository {
  final LocalReceiptDataSource localDataSource;
  final AIService aiService;
  final SupabaseDataSource supabaseDataSource;
  final Box settingsBox;
  final SyncService syncService;
  final WebhookService webhookService;
  final Box<AssetModel> assetsBox; // New injection
  final OutboxService? outboxService;
  final ReceiptImageStore imageStore;

  ReceiptRepositoryImpl({
    required this.localDataSource,
    required this.aiService,
    required this.supabaseDataSource,
    required this.settingsBox,
    required this.syncService,
    required this.webhookService,
    required this.assetsBox,
    this.outboxService,
    ReceiptImageStore? imageStore,
  }) : imageStore = imageStore ?? ReceiptImageStore();

  @override
  Future<Either<Failure, List<Receipt>>> getReceipts() async {
    try {
      final receiptModels = await localDataSource.getReceipts();
      final entities = receiptModels.map((e) => e.toEntity()).toList();
      return Right(entities);
    } catch (e) {
      return const Left(CacheFailure());
    }
  }

  @override
  Future<Either<Failure, Receipt>> processReceiptImage(String imagePath, {Map<String, Map<String, List<TaxonomyItem>>>? taxonomy}) async {
    return await aiService.extractReceiptData(imagePath, taxonomy: taxonomy);
  }

  @override
  Future<Either<Failure, void>> saveReceipt(Receipt receipt) async {
    try {
      // 0. Keep the image: picker files live in a directory the OS may purge.
      final originalImagePath = receipt.imagePath ?? '';
      final storedImagePath = await imageStore.persist(receipt.id, originalImagePath);
      if (storedImagePath != originalImagePath) {
        receipt = receipt.copyWith(imagePath: storedImagePath);
      }

      // 1. Save Locally
      final model = ReceiptModel.fromEntity(receipt);
      await localDataSource.saveReceipt(model);

      // 2. Enqueue mutation in OutboxService for Dual-Tier Sync & Offline Resiliency
      if (outboxService != null) {
        await outboxService!.enqueue(
          entityType: 'receipt',
          entityId: model.id,
          mutationType: 'upsert',
          payload: model.toRemoteJson(),
        );
      }

      // 3. Schedule Background Upload (Auto-Retry)
      // Fire and forget, SyncService handles upload of image (if present) and receipt data to Supabase
      unawaited(syncService.scheduleUpload(receipt.id, receipt.imagePath ?? ''));

      // 4. Trigger Webhook (Fire & Forget)
      // We don't await this to keep UI snappy
      unawaited(webhookService.sendWebhook(receipt).catchError((e) {
        debugPrint('Webhook failed: $e');
      }));

      // 5. Update Digital Vault
      try {
        for (final item in receipt.items) {
          if (item.isAsset) {
             final alreadyExists = assetsBox.values.any((a) => a.receiptId == receipt.id && a.name == item.description);
             if (!alreadyExists) {
               final nowUtc = DateTime.now().toUtc();
               final asset = AssetModel(
                  id: const Uuid().v4(),
                  name: item.description,
                  purchaseDate: receipt.date,
                  warrantyMonths: 24,
                  price: item.unitPrice,
                  receiptImagePath: receipt.imagePath ?? '',
                  merchantName: receipt.merchantName,
                  receiptId: receipt.id,
                  createdAt: nowUtc,
                  updatedAt: nowUtc,
               );
               await assetsBox.put(asset.id, asset);
               if (outboxService != null) {
                 await outboxService!.enqueue(
                   entityType: 'asset',
                   entityId: asset.id,
                   mutationType: 'upsert',
                   payload: asset.toJson(),
                 );
               }
               debugPrint('Vault: Added ${item.description}');
             }
          }
        }
      } catch (e) {
         debugPrint('Vault Error: $e');
      }

      return const Right(null);
    } catch (e) {
      return const Left(CacheFailure());
    }
  }

  @override
  Future<Either<Failure, void>> syncCorrectedReceipt(Receipt receipt, String imagePath) async {
    try {
      unawaited(syncService.scheduleUpload(receipt.id, imagePath));
      return const Right(null);
    } catch (e) {
      return const Right(null); 
    }
  }


  @override
  Future<Either<Failure, void>> clearAllData({bool includeCloud = false}) async {
    try {
      final receiptModels = await localDataSource.getReceipts();
      final ids = receiptModels.map((e) => e.id).toList();

      if (includeCloud) {
        if (ids.isNotEmpty) {
          await supabaseDataSource.deleteData(ids);
          await supabaseDataSource.deleteReceipts(ids);
        }

        // Tombstones propagate the deletion to other devices and supersede any
        // upsert for the same receipt that is still queued ahead of them.
        if (outboxService != null) {
          for (final id in ids) {
            await outboxService!.enqueue(
              entityType: 'receipt',
              entityId: id,
              mutationType: 'delete',
              payload: {'id': id},
            );
          }
        }
      }
      // Device-only clearing enqueues nothing: synchronized copies stay in the
      // cloud, and queued upserts still deliver receipts that have not reached
      // it yet, so the cleared data remains restorable via "Replicate Cloud Data".

      // Always clear local
      await localDataSource.clearAll();
      for (final model in receiptModels) {
        await _deleteStoredImage(model.imagePath);
      }
      
      return const Right(null);
    } catch (e) {
      return const Left(CacheFailure());
    }
  }

  @override
  Future<Either<Failure, void>> deleteReceipt(String id) async {
    try {
      final existing = await localDataSource.getReceipt(id);

      // 1. Delete from Local first to ensure transactional consistency
      await localDataSource.deleteReceipt(id);
      await _deleteStoredImage(existing?.imagePath);

      // 2. Enqueue deletion tombstone in OutboxService to propagate soft-delete to cloud replicas
      if (outboxService != null) {
        await outboxService!.enqueue(
          entityType: 'receipt',
          entityId: id,
          mutationType: 'delete',
          payload: {'id': id},
        );
      }

      // 3. Delete binary training image/data from storage (Best effort)
      try {
        await supabaseDataSource.deleteData([id]);
      } catch (e) {
        // Ignore storage error; outbox tombstone guarantees eventual DB consistency
      }
      
      return const Right(null);
    } catch (e) {
      return const Left(CacheFailure());
    }
  }

  /// Deletes a receipt's stored image unless a vault asset still uses it as
  /// warranty evidence.
  Future<void> _deleteStoredImage(String? path) async {
    if (path == null || path.isEmpty) return;
    if (assetsBox.values.any((asset) => asset.receiptImagePath == path)) return;
    await imageStore.delete(path);
  }
}
