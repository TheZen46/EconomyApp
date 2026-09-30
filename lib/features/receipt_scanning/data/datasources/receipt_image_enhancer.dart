import 'dart:typed_data';
import 'dart:math' as math;

/// On-device pixel processing and contrast normalization engine for receipts.
class ReceiptImageEnhancer {
  /// Applies linear contrast stretching and gamma correction to raw grayscale/RGB pixel bytes.
  static Uint8List stretchContrast({
    required Uint8List pixelBytes,
    double gamma = 1.2,
    int lowPercentileCutoff = 5,
    int highPercentileCutoff = 95,
  }) {
    if (pixelBytes.isEmpty) return pixelBytes;

    final output = Uint8List(pixelBytes.length);

    // 1. Compute histogram
    final histogram = List<int>.filled(256, 0);
    for (int i = 0; i < pixelBytes.length; i++) {
      histogram[pixelBytes[i]]++;
    }

    // 2. Find low and high percentile thresholds
    final totalPixels = pixelBytes.length;
    final lowTarget = (totalPixels * (lowPercentileCutoff / 100.0)).round();
    final highTarget = (totalPixels * (highPercentileCutoff / 100.0)).round();

    int cumulative = 0;
    int minVal = 0;
    int maxVal = 255;

    for (int i = 0; i < 256; i++) {
      cumulative += histogram[i];
      if (cumulative >= lowTarget && minVal == 0) {
        minVal = i;
      }
      if (cumulative >= highTarget) {
        maxVal = i;
        break;
      }
    }

    if (maxVal <= minVal) {
      maxVal = minVal + 1;
    }

    // 3. Precompute lookup table (LUT) with gamma correction
    final lut = Uint8List(256);
    final invGamma = 1.0 / gamma;

    for (int i = 0; i < 256; i++) {
      if (i <= minVal) {
        lut[i] = 0;
      } else if (i >= maxVal) {
        lut[i] = 255;
      } else {
        final normalized = (i - minVal) / (maxVal - minVal);
        final gammaCorrected = math.pow(normalized, invGamma).toDouble();
        lut[i] = (gammaCorrected * 255.0).clamp(0, 255).round();
      }
    }

    // 4. Apply LUT to pixel buffer
    for (int i = 0; i < pixelBytes.length; i++) {
      output[i] = lut[pixelBytes[i]];
    }

    return output;
  }

  /// Evaluates average luminance / lightness of an image buffer.
  static double computeAverageLuminance(Uint8List pixelBytes) {
    if (pixelBytes.isEmpty) return 0.0;
    int sum = 0;
    for (int i = 0; i < pixelBytes.length; i++) {
      sum += pixelBytes[i];
    }
    return sum / pixelBytes.length;
  }
}
