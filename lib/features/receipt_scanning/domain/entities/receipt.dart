import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:t_aidy/core/financial/money.dart';
import 'package:t_aidy/core/financial/price_basis.dart';

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
    // True when the extraction found no valid purchase date and [date] is a
    // placeholder; the review screen asks the user to confirm it. Not stored.
    @Default(false) bool dateUncertain,
    @Default(PriceBasis.gross) PriceBasis priceBasis,
    @Default(false) bool isUserCorrected,
  }) = _Receipt;

  const Receipt._();

  /// Converts the total amount to an exact fixed-point Money representation.
  Money get totalMoney => Money.fromDecimal(totalAmount, currency: currency);

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
  Money get essentialTotalMoney => items
      .where((i) => i.necessity == ItemNecessity.essential)
      .fold(Money.zero(currency), (sum, i) => sum + i.totalPriceMoney(currency));

  Money get junkTotalMoney => items
      .where((i) => i.necessity == ItemNecessity.junk)
      .fold(Money.zero(currency), (sum, i) => sum + i.totalPriceMoney(currency));

  double get essentialTotal => essentialTotalMoney.toDouble;
      
  double get junkTotal => junkTotalMoney.toDouble;
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
    @Default('') String id,
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
    @Default(PriceBasis.gross) PriceBasis priceBasis,
    @Default(false) bool isUserCorrected,
    
    @Deprecated('Use subCategory or mainCategory instead')
    String? category, // Keeping for backward compatibility temporarily
  }) = _ReceiptItem;
}

/// Extension providing exact fixed-point [Money] representation for [ReceiptItem].
extension ReceiptItemMoneyExtension on ReceiptItem {
  /// Line item total in fixed-point Money.
  Money totalPriceMoney([String currency = 'EUR']) =>
      Money.fromDecimal(totalPrice, currency: currency);

  /// Unit price in fixed-point Money.
  Money unitPriceMoney([String currency = 'EUR']) =>
      Money.fromDecimal(unitPrice, currency: currency);
}

