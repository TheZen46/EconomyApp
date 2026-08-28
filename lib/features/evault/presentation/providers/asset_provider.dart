import 'package:hive/hive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/asset_model.dart';
import '../../../receipt_scanning/domain/entities/receipt.dart';
import 'package:uuid/uuid.dart';

final assetsBoxProvider = Provider<Box<AssetModel>>((ref) {
  throw UnimplementedError('Assets Box must be overridden in main');
});

final assetListProvider = StateNotifierProvider<AssetNotifier, List<AssetModel>>((ref) {
  try {
    final box = ref.watch(assetsBoxProvider);
    return AssetNotifier(box);
  } catch (_) {
    return AssetNotifier(null);
  }
});

class AssetNotifier extends StateNotifier<List<AssetModel>> {
  final Box<AssetModel>? _box;

  AssetNotifier([this._box]) : super(_box?.values.toList() ?? []);

  Future<void> addAssetFromReceiptItem(ReceiptItem item, Receipt receipt, {int warrantyMonths = 24}) async {
    final asset = AssetModel(
      id: const Uuid().v4(),
      name: item.description,
      purchaseDate: receipt.date,
      warrantyMonths: warrantyMonths,
      price: item.unitPrice,
      receiptImagePath: receipt.imagePath ?? '', 
      merchantName: receipt.merchantName,
      receiptId: receipt.id,
    );
    
    await _box?.put(asset.id, asset);
    state = _box?.values.toList() ?? [asset, ...state];
  }

  Future<void> deleteAsset(String id) async {
    await _box?.delete(id);
    state = state.where((a) => a.id != id).toList();
  }
}
