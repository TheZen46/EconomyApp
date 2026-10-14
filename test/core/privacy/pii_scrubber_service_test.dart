import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/core/privacy/pii_scrubber_service.dart';
import 'package:t_aidy/features/receipt_scanning/domain/entities/receipt.dart';

void main() {
  group('PiiScrubberService Unit Tests', () {
    test('redacts email addresses correctly', () {
      const input = 'Invoice sent to alessandro.test@company.io for coffee';
      final sanitized = PiiScrubberService.sanitizeText(input);
      expect(sanitized, contains('[REDACTED_EMAIL]'));
      expect(sanitized, isNot(contains('alessandro.test@company.io')));
    });

    test('redacts credit and debit card numbers', () {
      const input = 'Paid with Card 4532 0150 9988 1234 on terminal';
      final sanitized = PiiScrubberService.sanitizeText(input);
      expect(sanitized, contains('[REDACTED_CARD]'));
      expect(sanitized, isNot(contains('4532 0150 9988 1234')));
    });

    test('redacts international and standard phone numbers', () {
      const input = 'Customer Support: +1-800-555-0199 or (02) 8877 6655';
      final sanitized = PiiScrubberService.sanitizeText(input);
      expect(sanitized, contains('[REDACTED_PHONE]'));
    });

    test('redacts street addresses', () {
      const input = 'Store Location: Via Roma 42, Milan, Italy';
      final sanitized = PiiScrubberService.sanitizeText(input);
      expect(sanitized, contains('[REDACTED_ADDRESS]'));
      expect(sanitized, isNot(contains('Via Roma 42')));
    });

    test('redacts IBAN numbers', () {
      const input = 'Transfer refund to IT60X0542811101000000123456';
      final sanitized = PiiScrubberService.sanitizeText(input);
      expect(sanitized, contains('[REDACTED_IBAN]'));
    });

    test('does not over-redact ordinary terms such as Dr. Pepper or sent via courier', () {
      const input = 'Ordered 2x Dr. Pepper 330ml sent via courier';
      final sanitized = PiiScrubberService.sanitizeText(input);
      expect(sanitized, contains('Dr. Pepper'));
      expect(sanitized, contains('sent via courier'));
      expect(sanitized, isNot(contains('[REDACTED_ADDRESS]')));
    });

    test('redacts personal names from cashier, server and customer labels', () {
      const input1 = 'Cashier: Mario Rossi on Terminal 04';
      final sanitized1 = PiiScrubberService.sanitizeText(input1);
      expect(sanitized1, contains('Cashier: [REDACTED_NAME]'));
      expect(sanitized1, isNot(contains('Mario Rossi')));

      const input2 = 'Served by: Jane Smith';
      final sanitized2 = PiiScrubberService.sanitizeText(input2);
      expect(sanitized2, contains('Served by: [REDACTED_NAME]'));
      expect(sanitized2, isNot(contains('Jane Smith')));

      const input3 = 'Customer Mario Rossi, Cardholder: Alice Johnson';
      final sanitized3 = PiiScrubberService.sanitizeText(input3);
      expect(sanitized3, contains('Customer [REDACTED_NAME]'));
      expect(sanitized3, contains('Cardholder: [REDACTED_NAME]'));
      expect(sanitized3, isNot(contains('Mario Rossi')));
      expect(sanitized3, isNot(contains('Alice Johnson')));

      const input4 = 'Attn: Sig. Marco Bianchi';
      final sanitized4 = PiiScrubberService.sanitizeText(input4);
      expect(sanitized4, contains('[REDACTED_NAME]'));
      expect(sanitized4, isNot(contains('Marco Bianchi')));
    });

    test('redacts number-first Anglo addresses correctly', () {
      const input = 'Store: 123 Main Street, Suite 400, Springfield';
      final sanitized = PiiScrubberService.sanitizeText(input);
      expect(sanitized, contains('[REDACTED_ADDRESS]'));
      expect(sanitized, isNot(contains('123 Main Street')));
    });

    test('sanitizeItemForTraining outputs clean training sample', () {
      const item = ReceiptItem(
        description: 'Organic Milk at Via Dante 10',
        unitPrice: 2.10,
        quantity: 2,
        totalPrice: 4.20,
        necessity: ItemNecessity.essential,
        mainCategory: 'Groceries',
        subCategory: 'Dairy',
      );

      final trainingSample = PiiScrubberService.sanitizeItemForTraining(
        merchantName: 'Supermarket contact@store.com',
        item: item,
        isUserCorrected: true,
      );

      expect(trainingSample['anonymized_merchant'], 'Supermarket [REDACTED_EMAIL]');
      expect(trainingSample['anonymized_description'], contains('Organic Milk at [REDACTED_ADDRESS]'));
      expect(trainingSample['quantity'], 2);
      expect(trainingSample['unit_price'], 2.10);
      expect(trainingSample['main_category'], 'Groceries');
      expect(trainingSample['was_user_corrected'], true);
    });
  });
}
