import 'dart:math' as math;
import 'dart:typed_data';

/// High-performance Subword & FastText-style Semantic Embedder.
///
/// Produces 128-dimensional dense L2-normalized embedding vectors:
/// e(s) = (1 / sqrt(|N(s)|)) * sum_{g in N(s)} W_g
///
/// Handles typo tolerance, subwords, character n-grams (2-5), and word boundary markers.
class SubwordSemanticEmbedder {
  /// Output embedding dimensionality.
  static const int vectorDim = 128;

  /// FastText-style subword vocabulary bucket size for projection matrix.
  static const int numBuckets = 32768;

  static final RegExp _nonAlphaNum = RegExp(r'[^a-z0-9\s]');
  static final RegExp _multiSpace = RegExp(r'\s+');

  SubwordSemanticEmbedder._();

  /// Computes a 128-dimensional L2-normalized dense embedding vector for the input text.
  static Float32List embed(String text) {
    final vector = Float32List(vectorDim);
    final clean = normalizeText(text);

    if (clean.isEmpty) {
      return vector;
    }

    int nGramsCount = 0;

    // 1. Full string character n-grams (3, 4, 5) with word boundary markers
    final fullBounded = '^$clean\$';
    final fullLen = fullBounded.length;
    for (int n = 3; n <= 5; n++) {
      if (fullLen < n) continue;
      final weight = (n == 3 || n == 4) ? 2.0 : 1.5;
      for (int i = 0; i <= fullLen - n; i++) {
        final gram = fullBounded.substring(i, i + n);
        _projectAndAccumulate(vector, gram, weight);
        nGramsCount++;
      }
    }

    // 2. Full Word Features and Word Bigrams
    final words = clean.split(' ').where((w) => w.isNotEmpty).toList();
    for (int i = 0; i < words.length; i++) {
      final word = words[i];
      _projectAndAccumulate(vector, '<w>$word</w>', 3.0);
      nGramsCount++;

      if (i + 1 < words.length) {
        _projectAndAccumulate(vector, '<bi>${words[i]}_${words[i + 1]}</bi>', 2.2);
        nGramsCount++;
      }

      final bounded = '^$word\$';
      final len = bounded.length;
      for (int n = 2; n <= 5; n++) {
        if (len < n) continue;
        final weight = (n == 3 || n == 4) ? 1.8 : 1.2;
        for (int j = 0; j <= len - n; j++) {
          final gram = bounded.substring(j, j + n);
          _projectAndAccumulate(vector, gram, weight);
          nGramsCount++;
        }
      }
    }

    // 3. FastText scaling factor: 1 / sqrt(|N(s)|)
    if (nGramsCount > 0) {
      final scale = 1.0 / math.sqrt(nGramsCount.toDouble());
      for (int i = 0; i < vectorDim; i++) {
        vector[i] *= scale;
      }
    }

    // 4. Strict L2 Normalization (||e||_2 = 1.0)
    double sumSq = 0.0;
    for (int i = 0; i < vectorDim; i++) {
      final v = vector[i];
      sumSq += v * v;
    }

    if (sumSq > 0.0) {
      final norm = 1.0 / math.sqrt(sumSq);
      for (int i = 0; i < vectorDim; i++) {
        vector[i] *= norm;
      }
    }

    return vector;
  }

  /// Calculates cosine distance D_C(u, v) = 1.0 - (u . v) between two L2-normalized vectors.
  /// Returns a distance in [0.0, 2.0]. (0.0 = identical, 1.0 = orthogonal).
  static double cosineDistance(Float32List a, Float32List b) {
    if (a.length != vectorDim || b.length != vectorDim) {
      return 1.0;
    }

    double dot = 0.0;
    for (int i = 0; i < vectorDim; i++) {
      dot += a[i] * b[i];
    }

    final sim = dot.clamp(-1.0, 1.0);
    return 1.0 - sim;
  }

  /// Calculates cosine similarity S_C(u, v) = (u . v) in [-1.0, 1.0].
  static double cosineSimilarity(Float32List a, Float32List b) {
    if (a.length != vectorDim || b.length != vectorDim) {
      return 0.0;
    }

    double dot = 0.0;
    for (int i = 0; i < vectorDim; i++) {
      dot += a[i] * b[i];
    }

    return dot.clamp(-1.0, 1.0);
  }

  /// Serializes [Float32List] vector to binary bytes (512 bytes).
  static Uint8List vectorToBytes(Float32List vector) {
    return vector.buffer.asUint8List(vector.offsetInBytes, vector.lengthInBytes);
  }

  /// Deserializes binary bytes to [Float32List] (128 floats).
  static Float32List bytesToVector(Uint8List bytes) {
    if (bytes.lengthInBytes != vectorDim * 4) {
      return Float32List(vectorDim);
    }
    return bytes.buffer.asFloat32List(bytes.offsetInBytes, vectorDim);
  }

  /// Normalizes input string for robust semantic tokenization.
  static String normalizeText(String text) {
    return text
        .toLowerCase()
        .replaceAll(_nonAlphaNum, ' ')
        .replaceAll(_multiSpace, ' ')
        .trim();
  }

  // ----------------------------------------------------------------------------
  // INTERNAL SUBWORD PROJECTION
  // ----------------------------------------------------------------------------

  static void _projectAndAccumulate(Float32List vector, String subword, double weight) {
    // 64-bit FNV-1a Hash
    int h1 = 0x811c9dc5;
    int h2 = 0x5bd1e995;

    for (int i = 0; i < subword.length; i++) {
      final code = subword.codeUnitAt(i);
      h1 ^= code;
      h1 = (h1 * 0x01000193) & 0xFFFFFFFF;

      h2 = ((h2 ^ code) * 0x1000193) & 0xFFFFFFFF;
    }

    // Pseudo-random dense projection into 4 sparse coordinate slots
    for (int step = 0; step < 4; step++) {
      final int seed = (h1 + step * 0x9e3779b9 + h2) & 0xFFFFFFFF;
      final int dimIdx = (seed.abs() % vectorDim);
      final double sign = ((seed >> 16) & 1 == 0) ? 1.0 : -1.0;
      final double basis = 0.5 + (((seed >> 8) & 0xFF) / 512.0);

      vector[dimIdx] += (sign * weight * basis);
    }
  }
}
