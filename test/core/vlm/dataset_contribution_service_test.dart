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
      date: DateTime(2026, 9, 9, 14, 30),
      totalAmount: 45.90,
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
  });
}
