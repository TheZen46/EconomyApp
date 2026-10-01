import 'package:uuid/uuid.dart';

import '../../features/receipt_scanning/domain/entities/receipt.dart';
import '../utils/date_parser.dart';

/// Maps the JSON produced by the legacy on-device LLM to a [Receipt]. Kept
/// free of platform dependencies so that it can be used and tested on every
/// platform.
class LlmReceiptMapper {
  LlmReceiptMapper._();

  /// Maps the model output to a [Receipt].
  ///
  /// The purchase date comes from `date`; when it is missing or not a valid
  /// purchase date, today is used and the receipt is flagged with
  /// [Receipt.dateUncertain] so that the review screen asks for it.
  static Receipt map(Map<String, dynamic> json, String imagePath, {DateTime? now}) {
    final purchaseDate = ReceiptDateParser.parsePurchaseDate(json['date']?.toString(), now: now);
    final today = now ?? DateTime.now();
    final currency = json['currency']?.toString().trim().toUpperCase() ?? '';
    return Receipt(
      id: const Uuid().v4(),
      merchantName: json['merchantName']?.toString() ?? 'Unknown',
      date: purchaseDate ?? DateTime(today.year, today.month, today.day),
      dateUncertain: purchaseDate == null,
      totalAmount: (json['totalAmount'] is num) ? (json['totalAmount'] as num).toDouble() : 0.0,
      currency: RegExp(r'^[A-Z]{3}$').hasMatch(currency) ? currency : 'EUR',
      items: _mapItems(json['items']),
      imagePath: imagePath,
    );
  }

  static List<ReceiptItem> _mapItems(dynamic itemsJson) {
    if (itemsJson is! List) return [];

    return itemsJson.whereType<Map>().map((item) {
      final desc = item['description']?.toString() ?? 'Unknown Item';
      final qty = (item['quantity'] is num) ? (item['quantity'] as num).toInt() : 1;
      final unitPrice = (item['unitPrice'] is num) ? (item['unitPrice'] as num).toDouble() : 0.0;
      // Keep the printed line total (discounts, weighed goods) when present.
      final totalPrice = (item['totalPrice'] is num) ? (item['totalPrice'] as num).toDouble() : qty * unitPrice;

      return ReceiptItem(
        description: desc,
        quantity: qty,
        unitPrice: unitPrice,
        totalPrice: totalPrice,
      );
    }).toList();
  }
}
