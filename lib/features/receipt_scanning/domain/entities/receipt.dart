import 'package:freezed_annotation/freezed_annotation.dart';

part 'receipt.freezed.dart';

@freezed
class Receipt with _$Receipt {
  const factory Receipt({
    required String id,
    required String merchantName,
    @Default('') String vatNumber,
    @Default('') String merchantAddress,
    required DateTime date,
    @Default('') String time,
    required double totalAmount,
    required String currency,
    // required String category, // Removed as per user request
    @Default([]) List<ReceiptItem> items,
    String? imagePath,
    @Default('main') String? boxId,
  }) = _Receipt;

  const Receipt._();

  String get category {
    if (items.isEmpty) return 'Uncategorized';
    
    // Most frequent category
    final catCounts = <String, int>{};
    for (final item in items) {
      if (item.mainCategory != null) {
        catCounts[item.mainCategory!] = (catCounts[item.mainCategory!] ?? 0) + 1;
      }
    }
    
    if (catCounts.isEmpty) return 'Mixed';
    
    // Sort by count
    final sorted = catCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return sorted.first.key;
  }
  
  // Helpers for analysis
  double get essentialTotal => items
      .where((i) => i.necessity == ItemNecessity.essential)
      .fold(0, (sum, i) => sum + i.totalPrice);
      
  double get junkTotal => items
      .where((i) => i.necessity == ItemNecessity.junk)
      .fold(0, (sum, i) => sum + i.totalPrice);
}

enum ItemNecessity {
  essential,    // Primary goods (Water, Bread, Medicine)
  discretional, // Fun but optional (Coffee, Nice clothes)
  junk,         // Unhealthy/Wasteful (Chips, Soda, Gambling)
  unknown
}

@freezed
class ReceiptItem with _$ReceiptItem {
  const factory ReceiptItem({
    required String description,
    required double unitPrice,
    @Default(1) int quantity,
    required double totalPrice,
    
    // New Taxonomy Fields
    @Default(ItemNecessity.unknown) ItemNecessity necessity,
    String? mainCategory, // e.g. "Food & Drink"
    String? subCategory,  // e.g. "Beverages (Sugary)"
    @Default(false) bool isAsset,
    @Default('main') String? boxId,
    
    @Deprecated('Use subCategory or mainCategory instead')
    String? category, // Keeping for backward compatibility temporarily
  }) = _ReceiptItem;
}
