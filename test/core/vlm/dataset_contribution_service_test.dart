import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/core/services/vlm/dataset_contribution_service.dart';
import 'package:t_aidy/core/privacy/pii_scrubber_service.dart';
import 'package:t_aidy/features/receipt_scanning/domain/entities/receipt.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DatasetContributionService & PII Scrubber Tests', () {
    late Directory tempDir;
    late DatasetContributionService service;

    final testReceipt = Receipt(
      id: 'rec-contrib-001',
      merchantName: 'Esselunga Milano Via Roma 12',
      merchantAddress: 'Via Roma 12, Milano',
      vatNumber: 'IT98765432101',
      date: DateTime(2026, 9, 9, 14, 30),
      totalAmount: 172.90,
      currency: 'EUR',
      items: const [
        ReceiptItem(
          description: 'Latte Intero 1L user@example.com',
          unitPrice: 1.50,
          quantity: 2,
          totalPrice: 3.00,
          necessity: ItemNecessity.essential,
          mainCategory: 'Proteins & Dairy',
          subCategory: 'Dairy',
        ),
        ReceiptItem(
          description: 'SSD Samsung 990 Pro 2TB',
          unitPrice: 169.90,
          quantity: 1,
          totalPrice: 169.90,
          necessity: ItemNecessity.discretional,
          mainCategory: 'Electronics & Hardware',
          subCategory: 'Storage',
          isAsset: true,
        ),
      ],
    );

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('dataset_contrib_test_');
      service = DatasetContributionService(baseDirectory: tempDir);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('PiiScrubberService strips emails, addresses, cards, and IBANs', () {
      const sensitiveText = 'Customer Mario Rossi, Via Roma 45, email test@mail.com, Card 4111 2222 3333 4444, IBAN IT60X0542811101000000123456';
      final sanitized = PiiScrubberService.sanitizeText(sensitiveText);

      expect(sanitized, isNot(contains('test@mail.com')));
      expect(sanitized, isNot(contains('4111 2222 3333 4444')));
      expect(sanitized, isNot(contains('IT60X0542811101000000123456')));
      expect(sanitized, contains('[REDACTED_EMAIL]'));
      expect(sanitized, contains('[REDACTED_CARD]'));
      expect(sanitized, contains('[REDACTED_IBAN]'));
    });

    test('DatasetContributionService stages verified receipt into JSONL format', () async {
      final success = await service.stageVerifiedReceipt(receipt: testReceipt);
      expect(success, isTrue);

      final count = await service.getSampleCount();
      expect(count, greaterThan(0));

      final jsonl = await service.exportJsonlContent();
      expect(jsonl, isNotEmpty);

      // Verify JSONL line parses properly as HuggingFace chat format
      final firstLine = jsonl.split('\n').firstWhere((l) => l.trim().isNotEmpty);
      final parsed = jsonDecode(firstLine) as Map<String, dynamic>;

      expect(parsed['source'], equals('user_verified_ground_truth'));
      expect(parsed['messages'], isA<List>());
      final messages = parsed['messages'] as List<dynamic>;
      expect(messages.length, equals(2));
      expect(messages[0]['role'], equals('user'));
      expect(messages[1]['role'], equals('assistant'));

      // Clean up
      await service.clearStagedData();
      final countAfter = await service.getSampleCount();
      expect(countAfter, equals(0));
    });

    test('TAIDY-M22 Issue #44: Ground truth JSON contains real VAT, no fabricated placeholder, and valid schema', () async {
      final success = await service.stageVerifiedReceipt(receipt: testReceipt);
      expect(success, isTrue);

      final jsonl = await service.exportJsonlContent();
      final parsed = jsonDecode(jsonl.split('\n').first) as Map<String, dynamic>;
      final assistantMsg = parsed['messages'][1]['content'] as String;
      final groundTruth = jsonDecode(assistantMsg) as Map<String, dynamic>;

      // 1. VAT number must be the real one, NOT fabricated 'IT12345678901'
      expect(groundTruth['vat_number'], equals('IT98765432101'));

      // 2. Tax breakdown must use 'rate' and 'tax_amount' (not 'rate_percent' or 'taxable_amount')
      final taxes = groundTruth['tax_breakdown'] as List<dynamic>;
      expect(taxes, isNotEmpty);
      for (final t in taxes) {
        final taxMap = t as Map<String, dynamic>;
        expect(taxMap.containsKey('rate'), isTrue);
        expect(taxMap.containsKey('tax_amount'), isTrue);
        expect(taxMap.containsKey('rate_percent'), isFalse);
        expect(taxMap.containsKey('taxable_amount'), isFalse);
      }

      // 3. Tax breakdown reflects real rates for Dairy (10%) and Electronics (22%)
      final rates = taxes.map((t) => (t as Map<String, dynamic>)['rate'] as double).toList();
      expect(rates, containsAll([0.10, 0.22]));

      // 4. Time format matches GBNF time-string ("HH:MM")
      final timeStr = groundTruth['time'] as String;
      expect(RegExp(r'^\d{2}:\d{2}$').hasMatch(timeStr), isTrue);
    });

    test('TAIDY-M22 Issue #44: Omit or set empty string for missing VAT number without fabricating placeholders', () async {
      final receiptWithoutVat = testReceipt.copyWith(vatNumber: '', merchantAddress: '');
      final success = await service.stageVerifiedReceipt(receipt: receiptWithoutVat);
      expect(success, isTrue);

      final jsonl = await service.exportJsonlContent();
      final parsed = jsonDecode(jsonl.split('\n').first) as Map<String, dynamic>;
      final groundTruth = jsonDecode(parsed['messages'][1]['content'] as String) as Map<String, dynamic>;

      // Must be empty string, never 'IT12345678901'
      expect(groundTruth['vat_number'], equals(''));
      expect(groundTruth['vat_number'], isNot(equals('IT12345678901')));
      expect(groundTruth['merchant_address'], equals(''));
      expect(groundTruth['merchant_address'], isNot(equals('[REDACTED_ADDRESS]')));
    });

    test('TAIDY-M22 Issue #44: Correction flags reflect actual comparison between AI output and saved values', () async {
      // 1. Unchanged receipt -> is_user_corrected = false, original_ai_prediction_was_wrong = false
      await service.stageVerifiedReceipt(
        receipt: testReceipt,
        originalAiReceipt: testReceipt,
      );

      final lines = (await service.exportJsonlContent()).split('\n').where((l) => l.trim().isNotEmpty).toList();
      final record1 = jsonDecode(lines.first) as Map<String, dynamic>;
      expect(record1['is_user_corrected'], isFalse);
      expect(record1['original_ai_prediction_was_wrong'], isFalse);

      await service.clearStagedData();

      // 2. Changed receipt -> is_user_corrected = true, original_ai_prediction_was_wrong = true
      final correctedReceipt = testReceipt.copyWith(
        merchantName: 'Esselunga Superstore',
        items: [
          testReceipt.items[0].copyWith(isUserCorrected: true, description: 'Latte Intero 1L'),
          testReceipt.items[1],
        ],
        isUserCorrected: true,
      );

      await service.stageVerifiedReceipt(
        receipt: correctedReceipt,
        originalAiReceipt: testReceipt,
      );

      final lines2 = (await service.exportJsonlContent()).split('\n').where((l) => l.trim().isNotEmpty).toList();
      final record2 = jsonDecode(lines2.first) as Map<String, dynamic>;
      expect(record2['is_user_corrected'], isTrue);
      expect(record2['original_ai_prediction_was_wrong'], isTrue);
    });
  });
}
