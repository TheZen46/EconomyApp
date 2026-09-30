import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/features/receipt_scanning/data/datasources/mock_ai_service.dart';
import 'package:t_aidy/core/constants/taxonomy_constants.dart';

void main() {
  group('FallbackAIService and MockAIService Heuristic Tests', () {
    late FallbackAIService service;

    setUp(() {
      service = FallbackAIService();
    });

    test('extracts dynamic tech/hardware receipt from file path', () async {
      final result = await service.extractReceiptData('/storage/receipt_apple_hardware.jpg');
      expect(result.isRight(), isTrue);
      result.fold(
        (failure) => fail('Should succeed'),
        (receipt) {
          expect(receipt.merchantName, equals('Apple Store'));
          expect(receipt.currency, equals('USD'));
          expect(receipt.items, isNotEmpty);
          expect(receipt.items.any((i) => i.isAsset), isTrue);
          expect(receipt.totalAmount, greaterThan(0));
        },
      );
    });

    test('extracts coffee/restaurant receipt from starbucks file path', () async {
      final result = await service.extractReceiptData('/cache/starbucks_coffee_scan.png');
      expect(result.isRight(), isTrue);
      result.fold(
        (failure) => fail('Should succeed'),
        (receipt) {
          expect(receipt.merchantName, equals('Starbucks Coffee'));
          expect(receipt.currency, equals('USD'));
          expect(receipt.items.length, equals(2));
          expect(receipt.totalAmount, equals(8.25));
        },
      );
    });

    test('extracts mobility receipt from uber file path', () async {
      final result = await service.extractReceiptData('uber_trip_invoice.pdf');
      expect(result.isRight(), isTrue);
      result.fold(
        (failure) => fail('Should succeed'),
        (receipt) {
          expect(receipt.merchantName, equals('Uber Mobility'));
          expect(receipt.currency, equals('EUR'));
          expect(receipt.totalAmount, equals(24.50));
        },
      );
    });

    test('extracts receipt using provided taxonomy when generic file path is given', () async {
      final taxonomy = <String, Map<String, List<TaxonomyItem>>>{
        'Office Supplies': {
          'Stationery': [
            const TaxonomyItem('pen', 'essential'),
          ],
        },
      };

      final result = await service.extractReceiptData('/tmp/image_picker_123.jpg', taxonomy: taxonomy);
      expect(result.isRight(), isTrue);
      result.fold(
        (failure) => fail('Should succeed'),
        (receipt) {
          expect(receipt.merchantName, equals('Office Supplies Store'));
          expect(receipt.items, isNotEmpty);
          expect(receipt.totalAmount, greaterThan(0));
        },
      );
    });

    test('MockAIService subclass behaves identically to FallbackAIService', () async {
      final mockService = MockAIService();
      final result = await mockService.extractReceiptData('/storage/receipt_apple.jpg');
      expect(result.isRight(), isTrue);
      result.fold(
        (failure) => fail('Should succeed'),
        (receipt) {
          expect(receipt.merchantName, equals('Apple Store'));
        },
      );
    });

    test('parses European receipt OCR with trailing currency symbol and comma decimals', () {
      const ocr = '''
SUPERMERCATO ROMA
Via Del Corso 12
27/09/2026 14:30

PANE CASERECCIO    1,50 €
LATTE FRESCO       1,80 €
-------------------------
TOTALE             3,30 €
''';

      final receipt = service.parseOcrText(ocr);
      expect(receipt, isNotNull);
      final r = receipt!;
      expect(r.merchantName, equals('SUPERMERCATO ROMA'));
      expect(r.currency, equals('EUR'));
      expect(r.date.year, equals(2026));
      expect(r.date.month, equals(9));
      expect(r.date.day, equals(27));
      expect(r.totalAmount, closeTo(3.30, 0.01));
      expect(r.items.length, greaterThanOrEqualTo(2));
      expect(r.items[0].description, contains('PANE CASERECCIO'));
      expect(r.items[0].unitPrice, closeTo(1.50, 0.01));
    });

    test('parses US receipt OCR with leading dollar sign and US date format without month rollover', () {
      const ocr = '''
TARGET STORE #1240
09/27/2026 10:15 AM

USB-C CABLE        \$14.99
DESK LAMP          \$29.99
-------------------------
TOTAL             \$44.98
''';

      final receipt = service.parseOcrText(ocr);
      expect(receipt, isNotNull);
      final r = receipt!;
      expect(r.merchantName, equals('TARGET STORE #1240'));
      expect(r.currency, equals('USD'));
      expect(r.date.year, equals(2026));
      expect(r.date.month, equals(9));
      expect(r.date.day, equals(27));
      expect(r.totalAmount, closeTo(44.98, 0.01));
      expect(r.items.any((i) => i.isAsset), isTrue);
      expect(r.items.any((i) => i.mainCategory == 'Tech & Gadgets' || i.mainCategory == 'Home & Living'), isTrue);
    });

    test('classifyItem accurately categorizes grocery, tech, and dining items', () {
      final dairy = TaxonomyConstants.classifyItem('Fresh Organic Milk');
      expect(dairy.mainCategory, equals('Proteins & Dairy'));
      expect(dairy.necessity, equals('essential'));

      final tech = TaxonomyConstants.classifyItem('MacBook Pro Laptop');
      expect(tech.mainCategory, equals('Tech & Gadgets'));
      expect(tech.necessity, equals('discretional'));

      final dining = TaxonomyConstants.classifyItem('Espresso Coffee Bar');
      expect(dining.mainCategory, equals('Snacks & Drinks'));
      expect(dining.subCategory, equals('Beverages'));
    });
  });
}
