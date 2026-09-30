import '../../receipt_scanning/domain/entities/receipt.dart';
import '../data/models/statement_transaction.dart';

class ReconciliationMatch {
  final StatementTransaction transaction;
  final Receipt? matchedReceipt;
  final double confidenceScore;
  final String rationale;

  const ReconciliationMatch({
    required this.transaction,
    this.matchedReceipt,
    this.confidenceScore = 0.0,
    this.rationale = 'Unmatched debit',
  });

  bool get isMatched => matchedReceipt != null && confidenceScore >= 0.60;
}

class ReconciliationEngine {
  const ReconciliationEngine();

  /// Reconciles a list of [StatementTransaction] records against stored [Receipt] entities.
  static List<ReconciliationMatch> reconcile({
    required List<StatementTransaction> transactions,
    required List<Receipt> receipts,
  }) {
    final matches = <ReconciliationMatch>[];
    final claimedReceiptIds = <String>{};

    for (final trn in transactions) {
      Receipt? bestReceipt;
      double bestScore = 0.0;
      String bestRationale = 'No matching receipt found';

      for (final r in receipts) {
        if (claimedReceiptIds.contains(r.id)) continue;

        final scoreData = _calculateMatchScore(trn, r);
        if (scoreData.score > bestScore) {
          bestScore = scoreData.score;
          bestReceipt = r;
          bestRationale = scoreData.rationale;
        }
      }

      if (bestScore >= 0.60 && bestReceipt != null) {
        claimedReceiptIds.add(bestReceipt.id);
        matches.add(ReconciliationMatch(
          transaction: trn.copyWith(
            isReconciled: true,
            matchedReceiptId: bestReceipt.id,
            matchConfidence: bestScore,
          ),
          matchedReceipt: bestReceipt,
          confidenceScore: bestScore,
          rationale: bestRationale,
        ));
      } else {
        matches.add(ReconciliationMatch(
          transaction: trn,
          matchedReceipt: null,
          confidenceScore: bestScore,
          rationale: bestScore > 0 ? 'Weak match candidate: $bestRationale' : 'Unmatched transaction',
        ));
      }
    }

    return matches;
  }

  static _ScoreResult _calculateMatchScore(StatementTransaction trn, Receipt receipt) {
    // 1. Amount Score (Weight: 50%)
    double amountScore = 0.0;
    final diff = (trn.amount - receipt.totalAmount).abs();
    if (diff < 0.01) {
      amountScore = 1.0;
    } else if (receipt.totalAmount > 0 && diff / receipt.totalAmount <= 0.03) {
      amountScore = 0.85; // Within 3% tolerance (e.g. FX rate / tip)
    } else if (receipt.totalAmount > 0 && diff / receipt.totalAmount <= 0.08) {
      amountScore = 0.40;
    }

    if (amountScore == 0.0) {
      return const _ScoreResult(score: 0.0, rationale: 'Amount mismatch');
    }

    // 2. Date Score (Weight: 30%)
    double dateScore = 0.0;
    final daysDiff = trn.date.difference(receipt.date).inDays.abs();
    if (daysDiff == 0) {
      dateScore = 1.0;
    } else if (daysDiff <= 2) {
      dateScore = 0.85;
    } else if (daysDiff <= 5) {
      dateScore = 0.50;
    } else {
      dateScore = 0.10;
    }

    // 3. Merchant String Overlap (Weight: 20%)
    final merchantScore = _computeStringSimilarity(trn.description, receipt.merchantName);

    final totalScore = (amountScore * 0.50) + (dateScore * 0.30) + (merchantScore * 0.20);
    final rationale = 'Amt ${(amountScore * 100).round()}% | Date \u00B1$daysDiff d | Merchant ${(merchantScore * 100).round()}%';

    return _ScoreResult(score: totalScore, rationale: rationale);
  }

  static double _computeStringSimilarity(String s1, String s2) {
    final clean1 = s1.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), ' ').trim();
    final clean2 = s2.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), ' ').trim();

    if (clean1.isEmpty || clean2.isEmpty) return 0.0;
    if (clean1 == clean2) return 1.0;
    if (clean1.contains(clean2) || clean2.contains(clean1)) return 0.90;

    final tokens1 = clean1.split(RegExp(r'\s+')).where((t) => t.length > 2).toSet();
    final tokens2 = clean2.split(RegExp(r'\s+')).where((t) => t.length > 2).toSet();

    if (tokens1.isEmpty || tokens2.isEmpty) return 0.10;

    final intersection = tokens1.intersection(tokens2);
    final union = tokens1.union(tokens2);

    return intersection.length / union.length;
  }
}

class _ScoreResult {
  final double score;
  final String rationale;

  const _ScoreResult({required this.score, required this.rationale});
}
