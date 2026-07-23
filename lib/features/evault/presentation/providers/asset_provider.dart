// ignore_for_file: deprecated_member_use, deprecated_member_use_from_same_package, unused_local_variable, unnecessary_underscores, invalid_annotation_target, unused_element, non_constant_identifier_names, use_build_context_synchronously
import 'package:hive/hive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/asset_model.dart';
import '../../../receipt_scanning/domain/entities/receipt.dart';
import 'package:uuid/uuid.dart';

final assetsBoxProvider = Provider<Box<AssetModel>>((ref) {
  throw UnimplementedError('Assets Box must be overridden in main');
});

final assetListProvider = StateNotifierProvider<AssetNotifier, List<AssetModel>>((ref) {
  final box = ref.watch(assetsBoxProvider);
  return AssetNotifier(box);
});

class AssetNotifier extends StateNotifier<List<AssetModel>> {
  final Box<AssetModel> _box;

  AssetNotifier(this._box) : super(_box.values.toList());

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
    
    await _box.add(asset);
    state = _box.values.toList();
  }

  Future<void> deleteAsset(String key) async {
    // Hive keys can be int or string. We should handle the key properly.
    // If using auto-increment int keys (default for box.add), we need the index or key.
    // AssetModel has an 'id' field, but Hive stores by 'key'.
    // Faster way: find key by ID.
    final map = _box.toMap();
    final entry = map.entries.firstWhere((e) => e.value.id == key, orElse: () => throw Exception('Asset not found'));
    await _box.delete(entry.key);
    state = _box.values.toList();
  }
}
