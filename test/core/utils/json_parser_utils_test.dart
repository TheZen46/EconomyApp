import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/core/error/failures.dart';
import 'package:t_aidy/core/utils/json_parser_utils.dart';

void main() {
  group('JsonParserUtils - Robust JSON Extraction & Repair Tests', () {
    test('extracts clean JSON wrapped in markdown fences and conversational text', () {
      const response = '''
Hello! I analyzed the receipt and found the following details:

```json
{
  "merchantName": "Costco Wholesale",
  "date": "2026-08-20",
  "totalAmount": 142.50,
  "currency": "USD",
  "items": [
    {"description": "Paper Towels", "quantity": 1, "unitPrice": 24.99},
    {"description": "Greek Yogurt", "quantity": 2, "unitPrice": 6.50}
  ]
}
```

Let me know if you need any additional categorization!
''';

      final result = JsonParserUtils.parseJsonSafe(response);
      expect(result.isRight(), isTrue);

      final map = result.getOrElse(() => {});
      expect(map['merchantName'], 'Costco Wholesale');
      expect(map['totalAmount'], 142.50);
      expect((map['items'] as List).length, 2);
    });

    test('extracts JSON in code fences without the json language tag', () {
      const response = '''
Here is the data:
```
{
  "merchantName": "Trader Joe's",
  "totalAmount": 45.10
}
```
''';
      final result = JsonParserUtils.parseJsonSafe(response);
      expect(result.isRight(), isTrue);
      final map = result.getOrElse(() => {});
      expect(map['merchantName'], "Trader Joe's");
      expect(map['totalAmount'], 45.10);
    });

    test('repairs trailing commas in objects and arrays', () {
      const malformed = '''
{
  "merchantName": "Trader Joe's",
  "totalAmount": 28.75,
  "items": [
    {"description": "Avocados", "quantity": 4, "unitPrice": 1.25,},
    {"description": "Sourdough", "quantity": 1, "unitPrice": 3.99,},
  ],
}
''';

      final map = JsonParserUtils.extractJsonMap(malformed);
      expect(map, isNotNull);
      expect(map!['merchantName'], "Trader Joe's");
      expect(map['totalAmount'], 28.75);
      expect((map['items'] as List).length, 2);
    });

    test('repairs truncated JSON with unclosed outer brackets/braces', () {
      const truncated = '''
{
  "merchantName": "Target",
  "date": "2026-08-22",
  "totalAmount": 55.20,
  "items": [
    {"description": "Detergent", "quantity": 1, "unitPrice": 14.99}
''';

      final map = JsonParserUtils.extractJsonMap(truncated);
      expect(map, isNotNull);
      expect(map!['merchantName'], 'Target');
      expect(map['totalAmount'], 55.20);
      expect((map['items'] as List).length, 1);
    });

    test('repairs unclosed quotes at end of line', () {
      const unclosedQuote = '''
{
  "merchantName": "Whole Foods Market,
  "totalAmount": 34.50,
  "currency": "USD"
}
''';

      final map = JsonParserUtils.extractJsonMap(unclosedQuote);
      expect(map, isNotNull);
      expect(map!['totalAmount'], 34.50);
    });

    test('sanitizes unescaped newlines, tabs, and carriage returns inside string literals', () {
      const rawWithNewlines = '''
{
  "merchantName": "Multi-Line\nStore\tBranch\rHQ",
  "totalAmount": 10.00
}
''';

      final map = JsonParserUtils.extractJsonMap(rawWithNewlines);
      expect(map, isNotNull);
      expect(map!['totalAmount'], 10.00);
      expect(map['merchantName'], contains('Multi-Line'));
    });

    test('replaces Python/JS literals (None, True, False) with standard JSON primitives', () {
      const pythonJson = '''
{
  "merchantName": "Python Cafe",
  "totalAmount": 12.50,
  "isTaxExempt": False,
  "isVerified": True,
  "discountCode": None
}
''';
      final map = JsonParserUtils.extractJsonMap(pythonJson);
      expect(map, isNotNull);
      expect(map!['isTaxExempt'], false);
      expect(map['isVerified'], true);
      expect(map['discountCode'], isNull);
    });

    test('repairs single-quoted keys and values via aggressive repair', () {
      const singleQuoted = "{'merchantName': 'Coffee Roasters', 'totalAmount': 7.25}";
      final map = JsonParserUtils.extractJsonMap(singleQuoted);
      expect(map, isNotNull);
      expect(map!['merchantName'], 'Coffee Roasters');
      expect(map['totalAmount'], 7.25);
    });

    test('strips single-line and multi-line comments from JSON payload', () {
      const withComments = '''
// Extracted receipt
{
  /* Header info */
  "merchantName": "Apple Store",
  "totalAmount": 999.00 // Total purchase
}
''';

      final map = JsonParserUtils.extractJsonMap(withComments);
      expect(map, isNotNull);
      expect(map!['merchantName'], 'Apple Store');
      expect(map['totalAmount'], 999.00);
    });

    test('handles deeply nested truncated arrays and objects without errors', () {
      const deeplyTruncated = '''
{
  "merchantName": "Supermarket",
  "receipt": {
    "sections": [
      {
        "name": "Produce",
        "items": [
          {"name": "Apple", "price": 1.50
''';
      final map = JsonParserUtils.extractJsonMap(deeplyTruncated);
      expect(map, isNotNull);
      expect(map!['merchantName'], 'Supermarket');
      expect(map['receipt'], isNotNull);
    });

    test('returns ParsingFailure on empty or non-JSON input without throwing uncaught exceptions', () {
      final emptyResult = JsonParserUtils.parseJsonSafe('   ');
      expect(emptyResult.isLeft(), isTrue);
      emptyResult.fold(
        (failure) => expect(failure, isA<ParsingFailure>()),
        (_) => fail('Expected ParsingFailure'),
      );

      final nonJsonResult = JsonParserUtils.parseJsonSafe('This text contains no braces at all.');
      expect(nonJsonResult.isLeft(), isTrue);
      expect(JsonParserUtils.extractJsonMap('plain text'), isNull);
    });

    test('createFallbackReceiptMap provides structured defaults and honors overrides', () {
      final fallbackDefault = JsonParserUtils.createFallbackReceiptMap();
      expect(fallbackDefault['merchantName'], 'Unknown Merchant');
      expect(fallbackDefault['totalAmount'], 0.0);
      expect(fallbackDefault['currency'], 'USD');
      expect(fallbackDefault['items'], isEmpty);
      expect(fallbackDefault['date'], isNotEmpty);

      final customDate = DateTime(2026, 7, 4);
      final fallbackCustom = JsonParserUtils.createFallbackReceiptMap(
        merchantName: 'Fallback Store',
        totalAmount: 42.50,
        currency: 'EUR',
        date: customDate,
        items: [
          {'description': 'Test Item', 'unitPrice': 42.50}
        ],
      );

      expect(fallbackCustom['merchantName'], 'Fallback Store');
      expect(fallbackCustom['totalAmount'], 42.50);
      expect(fallbackCustom['currency'], 'EUR');
      expect((fallbackCustom['items'] as List).length, 1);
      expect(fallbackCustom['date'], '2026-07-04');
    });
  });
}
