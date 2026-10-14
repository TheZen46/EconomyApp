import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/core/error/failures.dart';
import 'package:t_aidy/core/utils/currency_codes.dart';
import 'package:t_aidy/features/receipt_scanning/data/datasources/gemini_ai_service.dart';

void main() {
  group('GeminiAIService.detectImageMimeType', () {
    Uint8List bytes(List<int> head) => Uint8List.fromList([...head, ...List.filled(16, 0)]);

    test('recognises the formats Gemini accepts by their signature', () {
      expect(GeminiAIService.detectImageMimeType(bytes([0xFF, 0xD8, 0xFF, 0xE0])), 'image/jpeg');
      expect(GeminiAIService.detectImageMimeType(bytes([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])), 'image/png');
      expect(GeminiAIService.detectImageMimeType(bytes([...'RIFF'.codeUnits, 0, 0, 0, 0, ...'WEBP'.codeUnits])), 'image/webp');
      expect(GeminiAIService.detectImageMimeType(bytes([0, 0, 0, 24, ...'ftypheic'.codeUnits])), 'image/heic');
      expect(GeminiAIService.detectImageMimeType(bytes([0, 0, 0, 24, ...'ftypmif1'.codeUnits])), 'image/heif');
    });

    test('returns null for other content', () {
      expect(GeminiAIService.detectImageMimeType(bytes('%PDF-1.4'.codeUnits)), isNull);
      expect(GeminiAIService.detectImageMimeType(Uint8List(0)), isNull);
    });
  });

  group('GeminiAIService configuration and input', () {
    test('uses a configurable model with a supported default', () {
      expect(GeminiAIService('key').modelName, GeminiAIService.defaultModel);
      expect(GeminiAIService('key', model: '').modelName, GeminiAIService.defaultModel);
      expect(GeminiAIService('key', model: 'gemini-x-pro').modelName, 'gemini-x-pro');
      expect(GeminiAIService.defaultModel, isNot(startsWith('gemini-1.5')));
    });

    test('rejects missing files and unsupported formats before calling the API', () async {
      final dir = await Directory.systemTemp.createTemp('gemini_input_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final service = GeminiAIService('key');

      final missing = await service.extractReceiptData('${dir.path}/missing.jpg');
      expect(missing.fold((f) => f, (_) => null), isA<CacheFailure>());

      final pdf = File('${dir.path}/receipt.jpg')..writeAsBytesSync('%PDF-1.4 not an image'.codeUnits);
      final unsupported = await service.extractReceiptData(pdf.path);
      expect(unsupported.fold((f) => f, (_) => null), isA<AIProcessingFailure>());
    });
  });

  test('CurrencyCodes.normalize maps symbols and codes to ISO 4217', () {
    expect(CurrencyCodes.normalize('€'), 'EUR');
    expect(CurrencyCodes.normalize(r'$'), 'USD');
    expect(CurrencyCodes.normalize('£'), 'GBP');
    expect(CurrencyCodes.normalize('eur'), 'EUR');
    expect(CurrencyCodes.normalize(' CHF '), 'CHF');
    expect(CurrencyCodes.normalize(null), 'EUR');
    expect(CurrencyCodes.normalize('Euro', fallback: 'USD'), 'USD');
  });
}
