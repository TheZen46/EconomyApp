import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/core/services/receipt_deduplication_service.dart';
import 'package:t_aidy/features/receipt_scanning/domain/entities/receipt.dart';

void main() {
  group('ReceiptDeduplicationService Tests', () {
    final originalReceipt = Receipt(
      id: 'rec-orig-1',
      merchantName: 'Trader Joe\'s',
      totalAmount: 48.50,
      date: DateTime(2026, 4, 10, 14, 30),
      items: [
        ReceiptItem(description: 'Oat Milk', unitPrice: 4.50, quantity: 1, totalPrice: 4.50),
        ReceiptItem(description: 'Greek Yogurt', unitPrice: 5.00, quantity: 2, totalPrice: 10.00),
        ReceiptItem(description: 'Avocados', unitPrice: 4.00, quantity: 1, totalPrice: 4.00),
      ],
      currency: 'USD',
    );

    final exactDuplicate = Receipt(
      id: 'rec-dup-1',
      merchantName: 'Trader Joes Inc.',
      totalAmount: 48.50,
      date: DateTime(2026, 4, 10, 14, 32),
      items: [
        ReceiptItem(description: 'Oat Milk', unitPrice: 4.50, quantity: 1, totalPrice: 4.50),
        ReceiptItem(description: 'Greek Yogurt', unitPrice: 5.00, quantity: 2, totalPrice: 10.00),
      ],
      currency: 'USD',
    );

    final distinctReceipt = Receipt(
      id: 'rec-diff-1',
      merchantName: 'Shell Gas Station',
      totalAmount: 55.00,
      date: DateTime(2026, 4, 12, 10, 0),
      items: [
        ReceiptItem(description: 'Regular Gasoline', unitPrice: 55.00, quantity: 1, totalPrice: 55.00),
      ],
      currency: 'USD',
    );

    test('flags exact duplicate with high confidence score (> 0.85)', () {
      final match = ReceiptDeduplicationService.compareReceipts(exactDuplicate, originalReceipt);

      expect(match.isPotentialDuplicate, true);
      expect(match.confidenceScore, greaterThan(0.85));
      expect(match.matchingReasons.isNotEmpty, true);
      expect(match.matchingReasons.any((r) => r.contains('Identical total amount')), true);
    });

    test('correctly rejects completely distinct receipt', () {
      final match = ReceiptDeduplicationService.compareReceipts(distinctReceipt, originalReceipt);

      expect(match.isPotentialDuplicate, false);
      expect(match.confidenceScore, lessThan(0.30));
    });

    test('findDuplicate finds candidate in collection of historical receipts', () {
      final duplicate = ReceiptDeduplicationService.findDuplicate(
        candidate: exactDuplicate,
        existingReceipts: [distinctReceipt, originalReceipt],
      );

      expect(duplicate, isNotNull);
      expect(duplicate!.existingReceipt.id, originalReceipt.id);
      expect(duplicate.isPotentialDuplicate, true);
    });
  });
}
