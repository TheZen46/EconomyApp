import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/asset_model.dart';
import '../../../receipt_scanning/domain/entities/receipt.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/sync/outbox_service.dart';
import '../../../../core/sync/sync_providers.dart';

final assetsBoxProvider = Provider<Box<AssetModel>>((ref) {
  throw UnimplementedError('Assets Box must be overridden in main');
});

final assetListProvider = StateNotifierProvider<AssetNotifier, List<AssetModel>>((ref) {
  Box<AssetModel>? box;
  try {
    box = ref.watch(assetsBoxProvider);
  } catch (_) {}

  OutboxService? outbox;
  try {
    outbox = ref.watch(outboxServiceProvider);
  } catch (_) {}

  return AssetNotifier(box, outbox);
});

class AssetNotifier extends StateNotifier<List<AssetModel>> {
  final Box<AssetModel>? _box;
  final OutboxService? _outboxService;

  AssetNotifier([this._box, this._outboxService]) : super(_box?.values.toList() ?? []);

  /// Reloads state from Hive box to synchronize with background sync deltas.
  void reload() {
    state = _box?.values.toList() ?? [];
  }

  Future<void> addAssetFromReceiptItem(ReceiptItem item, Receipt receipt, {int warrantyMonths = 24}) async {
    final previous = state;
    final nowUtc = DateTime.now().toUtc();
    final asset = AssetModel(
      id: const Uuid().v4(),
      name: item.description,
      purchaseDate: receipt.date,
      warrantyMonths: warrantyMonths,
      price: item.unitPrice,
      receiptImagePath: receipt.imagePath ?? '', 
      merchantName: receipt.merchantName,
      receiptId: receipt.id,
      createdAt: nowUtc,
      updatedAt: nowUtc,
    );
    
    try {
      await _box?.put(asset.id, asset);
      state = _box?.values.toList() ?? [asset, ...state];

      if (_outboxService != null) {
        await _outboxService.enqueue(
          entityType: 'asset',
          entityId: asset.id,
          mutationType: 'upsert',
          payload: asset.toJson(),
        );
      }
    } catch (e) {
      debugPrint('AssetNotifier: Error adding asset: $e');
      state = previous;
      rethrow;
    }
  }

  Future<void> deleteAsset(String id) async {
    final previous = state;
    try {
      await _box?.delete(id);
      state = state.where((a) => a.id != id).toList();

      if (_outboxService != null) {
        await _outboxService.enqueue(
          entityType: 'asset',
          entityId: id,
          mutationType: 'delete',
          payload: {'id': id},
        );
      }
    } catch (e) {
      debugPrint('AssetNotifier: Error deleting asset: $e');
      state = previous;
      rethrow;
    }
  }
}
