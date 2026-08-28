import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/services/ai_service.dart';
import '../../domain/entities/receipt.dart';
import '../../domain/repositories/receipt_repository.dart';
import '../datasources/hive_receipt_data_source.dart';
import '../datasources/supabase_data_source.dart';
import '../models/receipt_model.dart';
import '../datasources/sync_service.dart';

import 'package:hive/hive.dart'; // Add Hive import
// Add Drive Service import
import '../../../settings/data/datasources/webhook_service.dart'; // Webhook Import

import '../../../../core/constants/taxonomy_constants.dart';

import '../../../evault/data/models/asset_model.dart'; // Asset Model
import 'package:uuid/uuid.dart'; // UUID

class ReceiptRepositoryImpl implements ReceiptRepository {
  final LocalReceiptDataSource localDataSource;
  final AIService aiService;
  final SupabaseDataSource supabaseDataSource;
  final Box settingsBox;
  final SyncService syncService;
  final WebhookService webhookService;
  final Box<AssetModel> assetsBox; // New injection

  ReceiptRepositoryImpl({
    required this.localDataSource,
    required this.aiService,
    required this.supabaseDataSource,
    required this.settingsBox,
    required this.syncService,
    required this.webhookService,
    required this.assetsBox,
  });

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
      // 1. Save Locally
      final model = ReceiptModel.fromEntity(receipt);
      await localDataSource.saveReceipt(model);

      // 2. Schedule Background Upload (Auto-Retry)
      if (receipt.imagePath != null) {
        // Fire and forget, SyncService handles the rest
        unawaited(syncService.scheduleUpload(receipt.id, receipt.imagePath!));
      }

      // 3. Trigger Webhook (Fire & Forget)
      // We don't await this to keep UI snappy
      unawaited(webhookService.sendWebhook(receipt).catchError((e) {
        debugPrint('Webhook failed: $e');
      }));

      // 4. Update Digital Vault
      try {
        for (final item in receipt.items) {
          if (item.isAsset) {
             final alreadyExists = assetsBox.values.any((a) => a.receiptId == receipt.id && a.name == item.description);
             if (!alreadyExists) {
               final asset = AssetModel(
                  id: const Uuid().v4(),
                  name: item.description,
                  purchaseDate: receipt.date,
                  warrantyMonths: 24,
                  price: item.unitPrice,
                  receiptImagePath: receipt.imagePath ?? '',
                  merchantName: receipt.merchantName,
                  receiptId: receipt.id,
               );
               await assetsBox.add(asset);
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
      if (includeCloud) {
        // We need IDs to delete from Supabase
        final receiptModels = await localDataSource.getReceipts();
        final ids = receiptModels.map((e) => e.id).toList();
        
        if (ids.isNotEmpty) {
          await supabaseDataSource.deleteData(ids);
          await supabaseDataSource.deleteReceipts(ids);
        }
      }
      
      // Always clear local
      await localDataSource.clearAll();
      
      return const Right(null);
    } catch (e) {
      return const Left(CacheFailure());
    }
  }

  @override
  Future<Either<Failure, void>> deleteReceipt(String id) async {
    try {
      // 1. Try to delete from Cloud (Best effort)
      try {
        await supabaseDataSource.deleteData([id]);
        await supabaseDataSource.deleteReceipts([id]);
      } catch (e) {
        // Ignore cloud deletion error if offline
      }

      // 2. Delete from Local
      await localDataSource.deleteReceipt(id);
      
      return const Right(null);
    } catch (e) {
      return const Left(CacheFailure());
    }
  }
}
