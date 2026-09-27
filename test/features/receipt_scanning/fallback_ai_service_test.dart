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
  });
}
