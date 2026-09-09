import 'dart:math' as math;
import 'dart:typed_data';

/// Lightweight, zero-dependency character-ngram and subword semantic embedder for on-device RAG.
///
/// Produces 128-dimensional dense unit vectors (L2-normalized [Float32List]) from text strings.
/// Optimized for merchant names, receipt descriptions, and line-item taxonomies.
class SemanticHasher {
  /// Dimension of the embedded semantic vector (128 floats = 512 bytes).
  static const int vectorDim = 128;

  static final RegExp _nonAlphaNum = RegExp(r'[^a-z0-9\s]');
  static final RegExp _multiSpace = RegExp(r'\s+');

  SemanticHasher._();

  /// Generates a 128-dimensional L2-normalized dense embedding vector for the input text.
  static Float32List embed(String text) {
    final vector = Float32List(vectorDim);
    final clean = _normalizeText(text);

    if (clean.isEmpty) {
      return vector;
    }

    // 1. Word tokens and subwords
    final words = clean.split(' ').where((w) => w.isNotEmpty).toList();
    for (int i = 0; i < words.length; i++) {
      final word = words[i];
      // Full word feature (higher weight)
      _hashAndAccumulate(vector, 'w:$word', 2.0);

      // Word bigrams for context
      if (i + 1 < words.length) {
        _hashAndAccumulate(vector, 'bi:${words[i]}_${words[i + 1]}', 1.5);
      }
    }

    // 2. Character n-grams (2-grams, 3-grams, 4-grams, 5-grams) with boundary markers
    final padded = '^$clean\$';
    final len = padded.length;

    // 2-grams
    for (int i = 0; i <= len - 2; i++) {
      _hashAndAccumulate(vector, padded.substring(i, i + 2), 0.7);
    }
    // 3-grams
    for (int i = 0; i <= len - 3; i++) {
      _hashAndAccumulate(vector, padded.substring(i, i + 3), 1.2);
    }
    // 4-grams
    for (int i = 0; i <= len - 4; i++) {
      _hashAndAccumulate(vector, padded.substring(i, i + 4), 1.0);
    }
    // 5-grams
    for (int i = 0; i <= len - 5; i++) {
      _hashAndAccumulate(vector, padded.substring(i, i + 5), 0.8);
    }

    // 3. L2 Vector Normalization so that Cosine Similarity == Dot Product
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

  /// Calculates cosine similarity between two L2-normalized 128-d vectors via dot product.
  /// Returns a value between 0.0 and 1.0.
  static double cosineSimilarity(Float32List a, Float32List b) {
    if (a.length != vectorDim || b.length != vectorDim) {
      return 0.0;
    }

    double dot = 0.0;
    for (int i = 0; i < vectorDim; i++) {
      dot += a[i] * b[i];
    }

    if (dot < 0.0) return 0.0;
    if (dot > 1.0) return 1.0;
    return dot;
  }

  /// Calculates token-based lexical overlap score between two strings in [0.0, 1.0].
  static double tokenMatchScore(String query, String target) {
    final qClean = _normalizeText(query);
    final tClean = _normalizeText(target);

    if (qClean.isEmpty || tClean.isEmpty) return 0.0;
    if (qClean == tClean) return 1.0;

    final qTokens = qClean.split(' ').where((t) => t.isNotEmpty).toSet();
    final tTokens = tClean.split(' ').where((t) => t.isNotEmpty).toSet();

    if (qTokens.isEmpty || tTokens.isEmpty) return 0.0;

    int intersectionCount = 0;
    for (final q in qTokens) {
      if (tTokens.contains(q)) {
        intersectionCount++;
      } else {
        // Substring token match for partial abbreviations (e.g. "esselung" inside "esselunga")
        for (final t in tTokens) {
          if (t.contains(q) || q.contains(t)) {
            intersectionCount++;
            break;
          }
        }
      }
    }

    final unionCount = qTokens.length + tTokens.length - intersectionCount;
    if (unionCount <= 0) return 0.0;
    return (intersectionCount / unionCount).clamp(0.0, 1.0);
  }

  /// Computes hybrid semantic + lexical score: `0.5 * CosineSimilarity + 0.5 * TokenMatchScore`.
  static double hybridScore({
    required Float32List queryEmbedding,
    required Float32List candidateEmbedding,
    required String queryString,
    required String candidateString,
  }) {
    final cosine = cosineSimilarity(queryEmbedding, candidateEmbedding);
    final token = tokenMatchScore(queryString, candidateString);
    return (0.5 * cosine + 0.5 * token).clamp(0.0, 1.0);
  }

  /// Serializes [Float32List] to raw byte buffer for SQLite BLOB storage.
  static Uint8List vectorToBytes(Float32List vector) {
    return vector.buffer.asUint8List(vector.offsetInBytes, vector.lengthInBytes);
  }

  /// Deserializes raw byte buffer from SQLite BLOB back to [Float32List].
  static Float32List bytesToVector(Uint8List bytes) {
    if (bytes.lengthInBytes != vectorDim * 4) {
      return Float32List(vectorDim);
    }
    return bytes.buffer.asFloat32List(bytes.offsetInBytes, vectorDim);
  }

  // ════════════════════════════════════════════════════════════════════════════
  // INTERNAL HASHING & NORMALIZATION
  // ════════════════════════════════════════════════════════════════════════════

  static String _normalizeText(String text) {
    return text
        .toLowerCase()
        .replaceAll(_nonAlphaNum, ' ')
        .replaceAll(_multiSpace, ' ')
        .trim();
  }

  static void _hashAndAccumulate(Float32List vector, String feature, double weight) {
    // FNV-1a 32-bit hash implementation
    int hash1 = 0x811c9dc5;
    int hash2 = 0x5bd1e995;

    for (int i = 0; i < feature.length; i++) {
      final code = feature.codeUnitAt(i);
      hash1 ^= code;
      hash1 = (hash1 * 0x01000193) & 0xFFFFFFFF;

      hash2 = ((hash2 ^ code) * 0x1000193) & 0xFFFFFFFF;
    }

    final int index = (hash1 % vectorDim).abs();
    final double sign = ((hash2 & 1) == 0) ? 1.0 : -1.0;

    vector[index] += (sign * weight);
  }
}
