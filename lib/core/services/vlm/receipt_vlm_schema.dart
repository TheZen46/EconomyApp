import '../../financial/money.dart';
import '../../financial/tax_engine.dart';
import '../../privacy/pii_scrubber_service.dart';
import '../../../features/receipt_scanning/domain/entities/receipt.dart';

/// Single source of truth for VLM receipt extraction schema, GBNF grammar rules,
/// and training dataset serialization.
///
/// Ensures training data ground truth matches what the constrained decoder can produce,
/// eliminating placeholder VAT numbers, fabricated tax splits, and schema discrepancies.
class ReceiptVlmSchema {
  ReceiptVlmSchema._();

  // Root JSON keys
  static const String keyMerchantName = 'merchant_name';
  static const String keyMerchantAddress = 'merchant_address';
  static const String keyVatNumber = 'vat_number';
  static const String keyDate = 'date';
  static const String keyTime = 'time';
  static const String keyCurrency = 'currency';
  static const String keyItems = 'items';
  static const String keyTaxBreakdown = 'tax_breakdown';
  static const String keyTotalAmount = 'total_amount';
  static const String keyConfidenceScore = 'confidence_score';

  // Line item JSON keys
  static const String keyRawName = 'raw_name';
  static const String keyNormalizedName = 'normalized_name';
  static const String keyMainCategory = 'main_category';
  static const String keySubCategory = 'sub_category';
  static const String keyNecessity = 'necessity';
  static const String keyQuantity = 'quantity';
  static const String keyUnitPrice = 'unit_price';
  static const String keyTotalPrice = 'total_price';
  static const String keyIsAsset = 'is_asset';

  // Tax breakdown JSON keys
  static const String keyTaxRate = 'rate';
  static const String keyTaxAmount = 'tax_amount';

  /// Derives non-fabricated, grounded VAT/tax entries from real receipt line items.
  ///
  /// In contrast to placeholder rates and synthetic proportions, this groups items by
  /// resolved VAT rates via [TaxRateResolver], computes real net/tax allocations via
  /// [TaxEngine], and emits canonical GBNF-compliant entries `{"rate": double, "tax_amount": double}`.
  /// If no tax info or items are present, returns an empty list `[]`.
  static List<Map<String, dynamic>> deriveTaxBreakdown(Receipt receipt) {
    if (receipt.items.isEmpty) {
      if (receipt.totalAmount <= 0) return [];
      final ratePercent = TaxRateResolver.inferVatRatePercentage(receipt.category);
      if (ratePercent <= 0) return [];
      final rateRatio = double.parse((ratePercent / 100.0).toStringAsFixed(4));
      final rateBps = (ratePercent * 100).round();
      final baseMoney = Money.fromDecimal(receipt.totalAmount, currency: receipt.currency);
      final netMoney = receipt.priceBasis == PriceBasis.net
          ? baseMoney
          : TaxEngine.computeNetFromGross(baseMoney, rateBps);
      final grossMoney = receipt.priceBasis == PriceBasis.net
          ? TaxEngine.computeGrossFromNet(baseMoney, rateBps)
          : baseMoney;
      final taxAmount = double.parse(((grossMoney.cents - netMoney.cents) / 100.0).toStringAsFixed(2));
      return [
        {
          keyTaxRate: rateRatio,
          keyTaxAmount: taxAmount,
        }
      ];
    }

    final rateToTaxCents = <double, int>{};
    final receiptCurrency = receipt.currency.isNotEmpty ? receipt.currency : 'EUR';

    for (final item in receipt.items) {
      final ratePercent = TaxRateResolver.inferVatRatePercentage(
        item.mainCategory,
        item.subCategory,
      );
      if (ratePercent <= 0) continue;
      final rateRatio = double.parse((ratePercent / 100.0).toStringAsFixed(4));
      final rateBps = (ratePercent * 100).round();
      final itemMoney = Money.fromDecimal(item.totalPrice, currency: receiptCurrency);
      final netMoney = item.priceBasis == PriceBasis.net
          ? itemMoney
          : TaxEngine.computeNetFromGross(itemMoney, rateBps);
      final grossMoney = item.priceBasis == PriceBasis.net
          ? TaxEngine.computeGrossFromNet(itemMoney, rateBps)
          : itemMoney;
      final taxCents = grossMoney.cents - netMoney.cents;

      rateToTaxCents[rateRatio] = (rateToTaxCents[rateRatio] ?? 0) + taxCents;
    }

    if (rateToTaxCents.isEmpty) return [];

    final sortedRates = rateToTaxCents.keys.toList()..sort();
    return sortedRates.map((rate) {
      final taxAmount = double.parse((rateToTaxCents[rate]! / 100.0).toStringAsFixed(2));
      return {
        keyTaxRate: rate,
        keyTaxAmount: taxAmount,
      };
    }).toList();
  }

  /// Converts a [Receipt] into a GBNF-compliant ground truth JSON map for fine-tuning.
  ///
  /// - Strips PII if [anonymize] is true.
  /// - Omits placeholder VAT numbers: uses real `receipt.vatNumber` or empty string if absent.
  /// - Omits placeholder addresses: uses real `receipt.merchantAddress` or empty string if absent.
  /// - Formats time as `HH:mm` matching GBNF `time-string`.
  /// - Computes grounded tax breakdown matching GBNF `tax-entry` schema.
  static Map<String, dynamic> toTrainingJson(Receipt receipt, {bool anonymize = true}) {
    final merchant = anonymize
        ? PiiScrubberService.sanitizeText(receipt.merchantName)
        : receipt.merchantName;
    final address = receipt.merchantAddress.trim().isNotEmpty
        ? (anonymize ? PiiScrubberService.sanitizeText(receipt.merchantAddress) : receipt.merchantAddress.trim())
        : '';
    final vat = receipt.vatNumber.trim();
    final dateStr = receipt.date.toIso8601String().split('T').first;
    final timeStr = formatTime(receipt);
    final currency = receipt.currency.isNotEmpty ? receipt.currency.toUpperCase() : 'USD';

    final itemsList = receipt.items.map((item) {
      final rawDesc = anonymize ? PiiScrubberService.sanitizeText(item.description) : item.description;
      return {
        keyRawName: rawDesc,
        keyNormalizedName: rawDesc,
        keyMainCategory: item.mainCategory ?? 'Miscellaneous',
        keySubCategory: item.subCategory ?? 'General',
        keyNecessity: item.necessity.name,
        keyQuantity: item.quantity,
        keyUnitPrice: item.unitPrice,
        keyTotalPrice: item.totalPrice,
        keyIsAsset: item.isAsset,
      };
    }).toList();

    return {
      keyMerchantName: merchant,
      keyMerchantAddress: address,
      keyVatNumber: vat,
      keyDate: dateStr,
      keyTime: timeStr,
      keyCurrency: currency,
      keyItems: itemsList,
      keyTaxBreakdown: deriveTaxBreakdown(receipt),
      keyTotalAmount: receipt.totalAmount,
      keyConfidenceScore: 1.0,
    };
  }

  /// Formats receipt time conforming to GBNF `time-string` (`HH:mm`).
  static String formatTime(Receipt receipt) {
    if (receipt.time.isNotEmpty) {
      final parts = receipt.time.trim().split(':');
      if (parts.length >= 2) {
        final h = parts[0].padLeft(2, '0');
        final m = parts[1].padLeft(2, '0');
        return '$h:$m';
      }
    }
    final h = receipt.date.hour.toString().padLeft(2, '0');
    final m = receipt.date.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// Compares an original AI prediction with user-saved values to detect genuine corrections.
  static bool hasUserCorrections(Receipt? original, Receipt edited) {
    if (original == null) return false;
    if (original.merchantName.trim() != edited.merchantName.trim()) return true;
    if (original.merchantAddress.trim() != edited.merchantAddress.trim()) return true;
    if (original.vatNumber.trim() != edited.vatNumber.trim()) return true;
    if ((original.totalAmount - edited.totalAmount).abs() > 0.001) return true;
    if (original.currency.toUpperCase() != edited.currency.toUpperCase()) return true;
    if (original.date.year != edited.date.year ||
        original.date.month != edited.date.month ||
        original.date.day != edited.date.day) {
      return true;
    }
    if (original.items.length != edited.items.length) return true;
    return edited.items.any((item) => item.isUserCorrected);
  }
}
