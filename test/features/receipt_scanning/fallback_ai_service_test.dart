import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/core/constants/taxonomy_constants.dart';
import 'package:t_aidy/core/error/failures.dart';
import 'package:t_aidy/features/receipt_scanning/data/datasources/mock_ai_service.dart';

void main() {
  group('FallbackAIService without OCR', () {
    // The test host is neither Android nor iOS, so ML Kit OCR is unavailable,
    // as on desktop and web.
    final taxonomy = <String, Map<String, List<TaxonomyItem>>>{
      'Office Supplies': {
        'Stationery': [const TaxonomyItem('pen', 'essential')],
      },
    };

    for (final path in [
      '/storage/receipt_apple_hardware.jpg',
      '/cache/starbucks_coffee_scan.png',
      'uber_trip_invoice.pdf',
      '/tmp/image_picker_123.jpg',
    ]) {
      test('does not invent a receipt for $path', () async {
        final result = await FallbackAIService().extractReceiptData(path, taxonomy: taxonomy);

        expect(result.isLeft(), isTrue);
        result.fold(
          (failure) => expect(failure, isA<ExtractionUnavailableFailure>()),
          (receipt) => fail('Returned data that was not read from the image: ${receipt.merchantName}'),
        );
      });
    }

    test('MockAIService behaves like FallbackAIService', () async {
      final result = await MockAIService().extractReceiptData('/storage/receipt_apple.jpg');
      expect(result.fold((f) => f, (_) => null), isA<ExtractionUnavailableFailure>());
    });

    final service = FallbackAIService();

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

    test('rejects calendar overflow dates such as 31/02/2026 via component round-trip validation', () {
      const ocr = '''
PHARMACY PLUS
31/02/2026 10:00
ASPIRIN   5.00 EUR
TOTAL:    5.00 EUR
''';
      final receipt = service.parseOcrText(ocr);
      expect(receipt, isNotNull);
      // Because 31/02/2026 is an invalid date with month overflow, it must be flagged as uncertain
      expect(receipt!.dateUncertain, isTrue);
    });

    test('correctly parses USD receipt with MM/DD/YYYY format without day-first assumption', () {
      const ocr = '''
NEW YORK BISTRO
04/05/2026 12:30
COFFEE   \$4.50
TOTAL:   \$4.50
''';
      final receipt = service.parseOcrText(ocr);
      expect(receipt, isNotNull);
      expect(receipt!.currency, equals('USD'));
      // In USD context with ambiguous 04/05, April 5th is preferred
      expect(receipt.date.month, equals(4));
      expect(receipt.date.day, equals(5));
      expect(receipt.dateUncertain, isFalse);
    });
  });
}
