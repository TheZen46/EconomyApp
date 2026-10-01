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
  });
}
