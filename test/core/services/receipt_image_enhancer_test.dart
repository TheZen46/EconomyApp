import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/core/services/receipt_image_enhancer.dart';

void main() {
  group('ReceiptImageEnhancer Tests', () {
    test('computes average luminance correctly', () {
      final bytes = Uint8List.fromList([100, 150, 200, 250]);
      final avg = ReceiptImageEnhancer.computeAverageLuminance(bytes);
      expect(avg, 175.0);
    });

    test('stretches contrast of low-contrast compressed image buffer', () {
      // Create a low-contrast image buffer with values compressed in [100, 140]
      final lowContrastBytes = Uint8List.fromList(
        List.generate(100, (i) => 100 + (i % 40)),
      );

      final enhanced = ReceiptImageEnhancer.stretchContrast(
        pixelBytes: lowContrastBytes,
        gamma: 1.0,
        lowPercentileCutoff: 5,
        highPercentileCutoff: 95,
      );

      expect(enhanced.length, lowContrastBytes.length);

      // Verify that the dynamic range was expanded (min is now closer to 0, max closer to 255)
      int minVal = 255;
      int maxVal = 0;
      for (final b in enhanced) {
        if (b < minVal) minVal = b;
        if (b > maxVal) maxVal = b;
      }

      expect(minVal, lessThan(30));
      expect(maxVal, greaterThan(220));
    });

    test('handles empty pixel buffer safely', () {
      final empty = Uint8List(0);
      expect(ReceiptImageEnhancer.stretchContrast(pixelBytes: empty).length, 0);
      expect(ReceiptImageEnhancer.computeAverageLuminance(empty), 0.0);
    });
  });
}
