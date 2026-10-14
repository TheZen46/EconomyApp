import 'package:uuid/uuid.dart';

import '../../features/receipt_scanning/data/models/receipt_model.dart';
import '../../features/receipt_scanning/domain/entities/receipt.dart';
import '../financial/price_basis.dart';
import '../utils/currency_codes.dart';
import '../utils/date_parser.dart';

/// Unified receipt extraction parser shared across Gemini, local VLM, and on-device LLM backends.
///
/// Enforces a single AI output contract, eliminating field drift (`date` vs `scanned_date`,
/// `merchantName` vs `merchant_name`), default discrepancies (`USD` vs `EUR`), and necessity parsing divergence.
class AiReceiptParser {
  AiReceiptParser._();

  /// Parses raw AI extraction JSON into a domain [Receipt] entity.
  static Receipt parseToEntity(
    Map<String, dynamic> json, {
    String? imagePath,
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    final transactionMap = json['transaction'] as Map<String, dynamic>? ?? {};
    final rawDateStr = (json['date'] as String?) ??
        (json['scanned_date'] as String?) ??
        (transactionMap['date'] as String?);
    final purchaseDate = ReceiptDateParser.parsePurchaseDate(rawDateStr, now: today);

    final model = parseToModel(json, imagePath: imagePath, now: now);
    return model.toEntity().copyWith(
      dateUncertain: purchaseDate == null,
    );
  }

  /// Parses raw AI extraction JSON into a [ReceiptModel].
  static ReceiptModel parseToModel(
    Map<String, dynamic> json, {
    String? imagePath,
    DateTime? now,
    String? id,
  }) {
    final today = now ?? DateTime.now();

    // 1. Merchant Extraction (Handles flat snake_case, camelCase, or nested {merchant: {...}})
    final merchantMap = json['merchant'] as Map<String, dynamic>? ?? {};
    final merchantName = (json['merchant_name'] as String?) ??
        (json['merchantName'] as String?) ??
        (merchantMap['name'] as String?) ??
        'Unknown Merchant';

    final vatNumber = (json['vat_number'] as String?) ??
        (json['vatNumber'] as String?) ??
        (merchantMap['vat_number'] as String?) ??
        (merchantMap['vatNumber'] as String?) ??
        '';

    final merchantAddress = (json['merchant_address'] as String?) ??
        (json['merchantAddress'] as String?) ??
        (merchantMap['address'] as String?) ??
        '';

    // 2. Transaction Extraction (Handles flat snake_case, camelCase, or nested {transaction: {...}})
    final transactionMap = json['transaction'] as Map<String, dynamic>? ?? {};

    final rawDateStr = (json['date'] as String?) ??
        (json['scanned_date'] as String?) ??
        (transactionMap['date'] as String?);

    final purchaseDate = ReceiptDateParser.parsePurchaseDate(rawDateStr, now: today);
    final effectiveDate = purchaseDate ?? DateTime(today.year, today.month, today.day);

    final timeStr = (json['time'] as String?) ??
        (json['transaction_time'] as String?) ??
        (transactionMap['time'] as String?) ??
        '';

    final rawCurrency = (json['currency'] as String?) ??
        (transactionMap['currency'] as String?) ??
        'USD';
    final normalizedCurrency = CurrencyCodes.normalize(rawCurrency);

    final rawTotal = json['total_amount'] ??
        json['totalAmount'] ??
        json['total'] ??
        transactionMap['total_amount'] ??
        transactionMap['total'];
    final totalAmount = (rawTotal is num) ? rawTotal.toDouble() : 0.0;

    final boxId = (json['box_id'] as String?) ??
        (json['boxId'] as String?) ??
        'main';

    final priceBasis = PriceBasis.fromString(
      (json['price_basis'] as String?) ?? (json['priceBasis'] as String?),
    );

    // 3. Line Items Extraction
    final itemsRaw = json['items'];
    final List<ReceiptItemModel> items;
    if (itemsRaw is List) {
      items = itemsRaw
          .whereType<Map>()
          .map((item) => _parseItem(Map<String, dynamic>.from(item)))
          .toList();
    } else {
      items = const [];
    }

    return ReceiptModel(
      id: id ?? (json['id'] as String?) ?? const Uuid().v4(),
      merchantName: merchantName.trim().isNotEmpty ? merchantName.trim() : 'Unknown Merchant',
      date: effectiveDate,
      totalAmount: totalAmount,
      currency: normalizedCurrency,
      items: items,
      imagePath: imagePath ?? (json['image_path'] as String?),
      vatNumber: vatNumber.trim(),
      merchantAddress: merchantAddress.trim(),
      time: timeStr.trim(),
      boxId: boxId,
      userId: json['user_id'] as String?,
      version: (json['version'] as num?)?.toInt() ?? 1,
      priceBasis: priceBasis,
    );
  }

  static ReceiptItemModel _parseItem(Map<String, dynamic> item) {
    final rawName = (item['description'] as String?) ??
        (item['raw_name'] as String?) ??
        (item['normalized_name'] as String?) ??
        (item['name'] as String?) ??
        'Item';

    final qty = (item['quantity'] is num) ? (item['quantity'] as num).toInt() : 1;
    final unitPrice = (item['unit_price'] is num)
        ? (item['unit_price'] as num).toDouble()
        : ((item['unitPrice'] is num) ? (item['unitPrice'] as num).toDouble() : 0.0);

    final rawTotal = item['total_price'] ?? item['totalPrice'];
    final totalPrice = (rawTotal is num) ? rawTotal.toDouble() : (qty * unitPrice);

    final mainCategory = (item['main_category'] as String?) ??
        (item['mainCategory'] as String?) ??
        (item['category'] as String?);

    final subCategory = (item['sub_category'] as String?) ??
        (item['subCategory'] as String?);

    final necessityStr = (item['necessity'] as String?) ?? 'unknown';

    final isAsset = item['is_asset'] == true || item['isAsset'] == true;
    final isUserCorrected = item['is_user_corrected'] == true || item['isUserCorrected'] == true;

    final rawScore = item['confidence_score'] ?? item['confidenceScore'];
    final confidenceScore = (rawScore is num) ? rawScore.toDouble() : 1.0;

    final priceBasis = PriceBasis.fromString(
      (item['price_basis'] as String?) ?? (item['priceBasis'] as String?),
    );

    return ReceiptItemModel(
      id: (item['id'] as String?) ?? const Uuid().v4(),
      description: rawName.trim().isNotEmpty ? rawName.trim() : 'Item',
      unitPrice: unitPrice,
      quantity: qty,
      totalPrice: totalPrice,
      category: mainCategory,
      mainCategory: mainCategory,
      subCategory: subCategory,
      necessity: necessityStr,
      isAsset: isAsset,
      isUserCorrected: isUserCorrected,
      confidenceScore: confidenceScore,
      priceBasis: priceBasis,
    );
  }

  /// Parses necessity string to contractual [ItemNecessity] enum.
  static ItemNecessity parseNecessity(dynamic value) {
    if (value == null) return ItemNecessity.unknown;
    final str = value.toString().toLowerCase().trim();
    switch (str) {
      case 'essential':
        return ItemNecessity.essential;
      case 'discretional':
      case 'discretionary':
        return ItemNecessity.discretional;
      case 'junk':
        return ItemNecessity.junk;
      default:
        return ItemNecessity.unknown;
    }
  }
}
