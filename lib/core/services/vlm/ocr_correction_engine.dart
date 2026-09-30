import 'dart:math' as math;
import '../../../features/receipt_scanning/domain/entities/receipt.dart';

/// Arithmetic or semantic issue detected in raw OCR/VLM receipt extraction.
class OcrDiscrepancy {
  final String field;
  final String description;
  final dynamic originalValue;
  final dynamic correctedValue;
  final double confidence;

  const OcrDiscrepancy({
    required this.field,
    required this.description,
    required this.originalValue,
    required this.correctedValue,
    this.confidence = 1.0,
  });
}

/// Result of OCR and VLM receipt auto-correction and verification.
class OcrCorrectionResult {
  final Receipt correctedReceipt;
  final List<OcrDiscrepancy> discrepanciesFixed;
  final bool hasLineItemArithmeticParity;
  final double discrepancyDelta;

  const OcrCorrectionResult({
    required this.correctedReceipt,
    required this.discrepanciesFixed,
    required this.hasLineItemArithmeticParity,
    this.discrepancyDelta = 0.0,
  });
}

/// High-precision on-device engine for detecting and correcting OCR line-item arithmetic errors,
/// decimal point shifts, and noisy merchant name normalization.
class OcrCorrectionEngine {
  OcrCorrectionEngine._();

  /// Evaluates and auto-corrects extraction errors in a raw scanned [Receipt].
  static OcrCorrectionResult autoCorrectReceipt({
    required Receipt rawReceipt,
    List<String> knownMerchants = const [],
    double tolerance = 0.02,
  }) {
    final discrepancies = <OcrDiscrepancy>[];
    String correctedMerchant = rawReceipt.merchantName.trim();

    // 1. Normalize Merchant Name via Fuzzy Matching against Known Database Merchants
    if (knownMerchants.isNotEmpty && correctedMerchant.isNotEmpty) {
      final bestMatch = _findBestMerchantMatch(correctedMerchant, knownMerchants);
      if (bestMatch != null && bestMatch != correctedMerchant) {
        discrepancies.add(OcrDiscrepancy(
          field: 'merchantName',
          description: 'Fuzzy-matched merchant name to known entity',
          originalValue: correctedMerchant,
          correctedValue: bestMatch,
          confidence: 0.95,
        ));
        correctedMerchant = bestMatch;
      }
    }

    // 2. Validate and Fix Line Item Math (quantity * unitPrice == totalPrice)
    final correctedItems = <ReceiptItem>[];
    double computedItemsSum = 0.0;

    for (int i = 0; i < rawReceipt.items.length; i++) {
      final item = rawReceipt.items[i];
      double unitPrice = item.unitPrice;
      double totalPrice = item.totalPrice;
      int quantity = item.quantity > 0 ? item.quantity : 1;

      final expectedTotal = quantity * unitPrice;

      // Case A: totalPrice is 0 or wildly off, but unitPrice and quantity are valid
      if ((totalPrice <= 0 || (totalPrice - expectedTotal).abs() > tolerance) && expectedTotal > 0) {
        discrepancies.add(OcrDiscrepancy(
          field: 'items[$i].totalPrice',
          description: 'Recalculated line item total ($quantity x \$${unitPrice.toStringAsFixed(2)})',
          originalValue: totalPrice,
          correctedValue: expectedTotal,
        ));
        totalPrice = expectedTotal;
      }
      // Case B: unitPrice is 0, but totalPrice and quantity are valid
      else if (unitPrice <= 0 && totalPrice > 0 && quantity > 0) {
        final calcUnitPrice = totalPrice / quantity;
        discrepancies.add(OcrDiscrepancy(
          field: 'items[$i].unitPrice',
          description: 'Inferred unit price from line item total and quantity',
          originalValue: unitPrice,
          correctedValue: calcUnitPrice,
        ));
        unitPrice = calcUnitPrice;
      }

      computedItemsSum += totalPrice;
      correctedItems.add(item.copyWith(
        unitPrice: unitPrice,
        totalPrice: totalPrice,
        quantity: quantity,
      ));
    }

    // 3. Reconcile Receipt Total with Sum of Line Items
    double correctedTotal = rawReceipt.totalAmount;

    if (correctedItems.isNotEmpty) {
      final diff = (computedItemsSum - correctedTotal).abs();

      // Case C: Subtotal decimal shift (e.g. 15.00 OCR'd as 1500 or 1.50)
      if (diff > tolerance) {
        if ((computedItemsSum * 100 - correctedTotal).abs() <= tolerance * 100) {
          // Total was missing decimal point
          discrepancies.add(OcrDiscrepancy(
            field: 'totalAmount',
            description: 'Fixed decimal scale error on total amount',
            originalValue: correctedTotal,
            correctedValue: computedItemsSum,
          ));
          correctedTotal = computedItemsSum;
        } else if (computedItemsSum > 0 && (correctedTotal <= 0 || diff > tolerance)) {
          // Adjust total amount to match verified line-item sum
          discrepancies.add(OcrDiscrepancy(
            field: 'totalAmount',
            description: 'Synchronized receipt total with verified line-item sum',
            originalValue: correctedTotal,
            correctedValue: computedItemsSum,
          ));
          correctedTotal = computedItemsSum;
        }
      }
    }

    final delta = (computedItemsSum - correctedTotal).abs();
    final isParity = correctedItems.isEmpty || delta <= tolerance;

    final correctedReceipt = rawReceipt.copyWith(
      merchantName: correctedMerchant,
      totalAmount: correctedTotal,
      items: correctedItems,
    );

    return OcrCorrectionResult(
      correctedReceipt: correctedReceipt,
      discrepanciesFixed: discrepancies,
      hasLineItemArithmeticParity: isParity,
      discrepancyDelta: delta,
    );
  }

  static String? _findBestMerchantMatch(String target, List<String> candidates, {double similarityThreshold = 0.75}) {
    String? bestCandidate;
    double highestScore = 0.0;
    final lowerTarget = target.toLowerCase();

    for (final candidate in candidates) {
      final lowerCandidate = candidate.toLowerCase();
      if (lowerTarget == lowerCandidate) return candidate;

      final dist = _levenshteinDistance(lowerTarget, lowerCandidate);
      final maxLen = math.max(lowerTarget.length, lowerCandidate.length);
      if (maxLen == 0) continue;

      final similarity = 1.0 - (dist / maxLen);
      if (similarity > highestScore && similarity >= similarityThreshold) {
        highestScore = similarity;
        bestCandidate = candidate;
      }
    }

    return bestCandidate;
  }

  static int _levenshteinDistance(String s, String t) {
    if (s == t) return 0;
    if (s.isEmpty) return t.length;
    if (t.isEmpty) return s.length;

    List<int> v0 = List<int>.filled(t.length + 1, 0);
    List<int> v1 = List<int>.filled(t.length + 1, 0);

    for (int i = 0; i <= t.length; i++) {
      v0[i] = i;
    }

    for (int i = 0; i < s.length; i++) {
      v1[0] = i + 1;
      for (int j = 0; j < t.length; j++) {
        final cost = (s.codeUnitAt(i) == t.codeUnitAt(j)) ? 0 : 1;
        v1[j + 1] = math.min(v1[j] + 1, math.min(v0[j + 1] + 1, v0[j] + cost));
      }
      for (int j = 0; j <= t.length; j++) {
        v0[j] = v1[j];
      }
    }

    return v1[t.length];
  }
}
