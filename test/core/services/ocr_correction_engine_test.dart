import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/core/services/vlm/ocr_correction_engine.dart';
import 'package:t_aidy/features/receipt_scanning/domain/entities/receipt.dart';

void main() {
  group('OcrCorrectionEngine Tests', () {
    test('corrects arithmetic discrepancies between unit price, quantity, and line item total', () {
      final rawReceipt = Receipt(
        id: 'r1',
        merchantName: 'Home Depot',
        totalAmount: 0.0, // Missing or zero total
        date: DateTime(2026, 3, 1),
        currency: 'USD',
        items: const [
          // 3 items at $12.50 = $37.50, but OCR extracted totalPrice as 0.0
          ReceiptItem(description: 'Plywood Board', unitPrice: 12.50, quantity: 3, totalPrice: 0.0, mainCategory: 'Materials'),
          // 2 items at $5.00 = $10.00, but OCR extracted unitPrice as 0.0 and totalPrice as $10.00
          ReceiptItem(description: 'Screws Pack', unitPrice: 0.0, quantity: 2, totalPrice: 10.0, mainCategory: 'Hardware'),
        ],
      );

      final result = OcrCorrectionEngine.autoCorrectReceipt(rawReceipt: rawReceipt);

      expect(result.correctedReceipt.items[0].totalPrice, 37.50);
      expect(result.correctedReceipt.items[1].unitPrice, 5.00);
      expect(result.correctedReceipt.totalAmount, 47.50); // 37.50 + 10.00
      expect(result.hasLineItemArithmeticParity, true);
      expect(result.discrepanciesFixed.length, greaterThanOrEqualTo(2));
    });

    test('fixes missing decimal point scale in receipt total amount (e.g. 4750 instead of 47.50)', () {
      final rawReceipt = Receipt(
        id: 'r2',
        merchantName: 'Office Max',
        totalAmount: 4750.0, // Scaled 100x
        date: DateTime(2026, 3, 1),
        currency: 'USD',
        items: const [
          ReceiptItem(description: 'Binder', unitPrice: 47.50, quantity: 1, totalPrice: 47.50, mainCategory: 'Supplies'),
        ],
      );

      final result = OcrCorrectionEngine.autoCorrectReceipt(rawReceipt: rawReceipt);

      expect(result.correctedReceipt.totalAmount, 47.50);
      expect(result.hasLineItemArithmeticParity, true);
      expect(result.discrepanciesFixed.any((d) => d.field == 'totalAmount'), true);
    });

    test('normalizes noisy merchant names using fuzzy Levenshtein distance', () {
      final rawReceipt = Receipt(
        id: 'r3',
        merchantName: 'Starbuckks Coffe', // Typo/noisy OCR
        totalAmount: 6.50,
        date: DateTime(2026, 3, 1),
        currency: 'USD',
        items: const [
          ReceiptItem(description: 'Latte', unitPrice: 6.50, quantity: 1, totalPrice: 6.50, mainCategory: 'Meals'),
        ],
      );

      final result = OcrCorrectionEngine.autoCorrectReceipt(
        rawReceipt: rawReceipt,
        knownMerchants: ['Starbucks Coffee', 'Apple Store', 'Office Depot'],
      );

      expect(result.correctedReceipt.merchantName, 'Starbucks Coffee');
      expect(result.discrepanciesFixed.any((d) => d.field == 'merchantName'), true);
    });
  });
}
