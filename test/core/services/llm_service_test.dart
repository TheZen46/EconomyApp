import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/core/error/failures.dart';
import 'package:t_aidy/core/services/llm_receipt_mapper.dart';
import 'package:t_aidy/core/services/llm_service.dart';
import 'package:t_aidy/core/utils/json_parser_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LLMService Tests', () {
    test('initial model state is uninitialized', () {
      final service = LLMService();
      expect(service.isModelLoaded, isFalse);
    });

    test('extractReceiptData fails safely with CacheFailure when model is not loaded', () async {
      final service = LLMService();
      final result = await service.extractReceiptData('/fake/path.jpg');

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect(failure, isA<CacheFailure>()),
        (_) => fail('Expected CacheFailure'),
      );
    });

    test('JsonParserUtils correctly extracts structured receipt JSON from noisy LLM output', () {
      const noisyResponse = '''
Here is the extracted receipt data:
```json
{
  "merchantName": "Trader Joe's",
  "date": "2026-08-25",
  "totalAmount": 18.75,
  "currency": "USD",
  "items": [
    {"description": "Organic Bananas", "quantity": 1, "unitPrice": 2.25},
    {"description": "Almond Milk", "quantity": 2, "unitPrice": 3.50}
  ]
}
```
Hope this helps!
''';

      final jsonMap = JsonParserUtils.extractJsonMap(noisyResponse);
      expect(jsonMap, isNotNull);
      expect(jsonMap!['merchantName'], "Trader Joe's");
      expect(jsonMap['totalAmount'], 18.75);
      expect((jsonMap['items'] as List).length, 2);
    });

    test('unload resets model loaded state', () {
      final service = LLMService();
      service.unload();
      expect(service.isModelLoaded, isFalse);
    });
  });

  group('LLMService.generate', () {
    late Directory docs;

    setUp(() async {
      docs = await Directory.systemTemp.createTemp('llm_generate_');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (MethodCall call) async => docs.path,
      );
      // A file that exists but cannot be loaded as a model.
      final models = Directory('${docs.path}/models')..createSync();
      File('${models.path}/gemma-2b-it.Q4_K_M.gguf').writeAsStringSync('not a model');
    });

    tearDown(() {
      if (docs.existsSync()) docs.deleteSync(recursive: true);
    });

    test('completes with an error token when the model cannot be loaded', () async {
      final service = LLMService();
      await service.initialize();
      expect(service.isModelLoaded, isTrue);

      final tokens = await service
          .generate('Hello')
          .toList()
          .timeout(const Duration(seconds: 20), onTimeout: () => fail('generate() never completed'));

      expect(tokens, isNotEmpty);
      expect(tokens.last, startsWith('Error'));
    });
  });

  group('LlmReceiptMapper.map', () {
    final now = DateTime(2026, 10, 1, 15, 30);

    test('uses the purchase date from the model output', () {
      final receipt = LlmReceiptMapper.map(
        {'merchantName': 'Walmart', 'date': '2024-01-15', 'totalAmount': 25.5, 'currency': 'usd'},
        '/img.jpg',
        now: now,
      );

      expect(receipt.date, DateTime(2024, 1, 15));
      expect(receipt.dateUncertain, isFalse);
      expect(receipt.currency, 'USD');
    });

    test('flags the date when it is missing, invalid or in the future', () {
      for (final date in [null, '', 'yesterday', '2026-02-30', '2027-01-01']) {
        final receipt = LlmReceiptMapper.map({'merchantName': 'X', 'date': date}, '', now: now);
        expect(receipt.dateUncertain, isTrue, reason: '$date');
        expect(receipt.date, DateTime(2026, 10, 1), reason: '$date');
      }
    });

    test('assigns UUID v4 identifiers that do not collide', () {
      final ids = {
        for (var i = 0; i < 50; i++) LlmReceiptMapper.map({'merchantName': 'X'}, '', now: now).id,
      };

      expect(ids, hasLength(50));
      expect(
        ids.first,
        matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')),
      );
    });

    test('keeps a printed line total and skips malformed items', () {
      final receipt = LlmReceiptMapper.map({
        'merchantName': 'X',
        'items': [
          {'description': 'Cheese 0.43 kg', 'quantity': 1, 'unitPrice': 18.9, 'totalPrice': 8.13},
          {'description': 'Bread', 'quantity': 2, 'unitPrice': 1.5},
          'not an item',
        ],
      }, '', now: now);

      expect(receipt.items, hasLength(2));
      expect(receipt.items[0].totalPrice, 8.13);
      expect(receipt.items[1].totalPrice, 3.0);
    });
  });
}
