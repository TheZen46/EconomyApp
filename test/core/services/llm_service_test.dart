import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/core/error/failures.dart';
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
}
