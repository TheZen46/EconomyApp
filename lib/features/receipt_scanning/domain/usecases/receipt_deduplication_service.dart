import 'package:t_aidy/features/receipt_scanning/domain/entities/receipt.dart';

/// Result of a duplicate scan comparison against existing receipts.
class DuplicateMatchResult {
  final Receipt candidateReceipt;
  final Receipt existingReceipt;
  final double confidenceScore;
  final bool isPotentialDuplicate;
  final List<String> matchingReasons;

  const DuplicateMatchResult({
    required this.candidateReceipt,
    required this.existingReceipt,
    required this.confidenceScore,
    required this.isPotentialDuplicate,
    required this.matchingReasons,
  });
}

/// Zero-cloud, on-device multi-factor duplicate receipt detection service.
class ReceiptDeduplicationService {
  /// Duplicate detection threshold score in range [0.0, 1.0].
  static const double kDuplicateThreshold = 0.82;

  /// Scans [candidate] against a collection of [existingReceipts] and returns the highest-scoring duplicate match if above threshold.
  static DuplicateMatchResult? findDuplicate({
    required Receipt candidate,
    required List<Receipt> existingReceipts,
    double threshold = kDuplicateThreshold,
  }) {
    DuplicateMatchResult? bestMatch;
    double highestScore = 0.0;

    for (final existing in existingReceipts) {
      if (existing.id == candidate.id) continue;

      final match = compareReceipts(candidate, existing);
      if (match.confidenceScore > highestScore && match.confidenceScore >= threshold) {
        highestScore = match.confidenceScore;
        bestMatch = match;
      }
    }

    return bestMatch;
  }

  /// Evaluates multi-factor similarity score between two receipts.
  static DuplicateMatchResult compareReceipts(Receipt a, Receipt b) {
    final reasons = <String>[];

    // 1. Amount Similarity (Weight: 40%)
    double amountScore = 0.0;
    if (a.totalMoney.cents > 0 && b.totalMoney.cents > 0 && a.currency.toUpperCase() == b.currency.toUpperCase()) {
      final diffCents = (a.totalMoney.cents - b.totalMoney.cents).abs();
      if (diffCents == 0) {
        amountScore = 1.0;
        reasons.add('Identical total amount (${a.totalMoney.format()})');
      } else if (diffCents <= 50) {
        amountScore = 0.8;
      }
    } else if (a.totalAmount > 0 && b.totalAmount > 0) {
      final diff = (a.totalAmount - b.totalAmount).abs();
      if (diff < 0.01) {
        amountScore = 1.0;
        reasons.add('Identical total amount (${a.totalMoney.format()})');
      } else if (diff < 0.50) {
        amountScore = 0.8;
      }
    }

    // 2. Date/Time Proximity (Weight: 25%)
    double dateScore = 0.0;
    final hoursDiff = a.date.difference(b.date).inHours.abs();
    if (hoursDiff == 0) {
      dateScore = 1.0;
      reasons.add('Identical transaction date');
    } else if (hoursDiff <= 24) {
      dateScore = 1.0 - (hoursDiff / 24.0) * 0.4;
      reasons.add('Same-day transaction (~${hoursDiff}h apart)');
    } else if (hoursDiff <= 48) {
      dateScore = 0.4;
    }

    // 3. Merchant Name Normalized Similarity (Weight: 20%)
    final merchantNormA = _normalizeMerchant(a.merchantName);
    final merchantNormB = _normalizeMerchant(b.merchantName);
    double merchantScore = 0.0;

    if (merchantNormA == merchantNormB && merchantNormA.isNotEmpty) {
      merchantScore = 1.0;
      reasons.add('Exact merchant match: "${a.merchantName}"');
    } else if (merchantNormA.isNotEmpty && merchantNormB.isNotEmpty) {
      final sim = _calculateStringSimilarity(merchantNormA, merchantNormB);
      if (sim > 0.7) {
        merchantScore = sim;
        reasons.add('Fuzzy merchant match: "${a.merchantName}" ≈ "${b.merchantName}"');
      }
    }

    // 4. Line Items Jaccard Overlap (Weight: 15%)
    double itemScore = 0.0;
    if (a.items.isNotEmpty && b.items.isNotEmpty) {
      final setA = a.items.map((i) => i.description.toLowerCase().trim()).toSet();
      final setB = b.items.map((i) => i.description.toLowerCase().trim()).toSet();
      final intersection = setA.intersection(setB).length;
      final union = setA.union(setB).length;

      if (union > 0) {
        itemScore = intersection / union;
        if (itemScore > 0.5) {
          reasons.add('$intersection overlapping item description(s)');
        }
      }
    }

    // Composite Weighted Score
    final compositeScore = (amountScore * 0.40) +
        (dateScore * 0.25) +
        (merchantScore * 0.20) +
        (itemScore * 0.15);

    return DuplicateMatchResult(
      candidateReceipt: a,
      existingReceipt: b,
      confidenceScore: compositeScore,
      isPotentialDuplicate: compositeScore >= kDuplicateThreshold,
      matchingReasons: reasons,
    );
  }

  static String _normalizeMerchant(String name) {
    return name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '')
        .replaceAll('inc', '')
        .replaceAll('llc', '')
        .replaceAll('ltd', '')
        .replaceAll('corp', '')
        .trim();
  }

  static double _calculateStringSimilarity(String s1, String s2) {
    if (s1 == s2) return 1.0;
    if (s1.isEmpty || s2.isEmpty) return 0.0;

    final pairs1 = _getBigrams(s1);
    final pairs2 = _getBigrams(s2);

    int intersection = 0;
    final total = pairs1.length + pairs2.length;

    for (final pair in pairs1) {
      if (pairs2.contains(pair)) {
        intersection++;
      }
    }

    return total > 0 ? (2.0 * intersection) / total : 0.0;
  }

  static List<String> _getBigrams(String s) {
    final bigrams = <String>[];
    for (int i = 0; i < s.length - 1; i++) {
      bigrams.add(s.substring(i, i + 2));
    }
    return bigrams;
  }
}

