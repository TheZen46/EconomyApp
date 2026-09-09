import 'dart:math' as math;
import 'package:csv/csv.dart';
import '../../../../core/services/vlm/semantic_hasher.dart';
import '../../domain/entities/receipt.dart';

/// Represents a single transaction parsed from an imported bank or credit card statement.
class BankTransaction {
  final String id;
  final DateTime date;
  final String description;
  final double amount;
  final String currency;
  final String? referenceNumber;

  const BankTransaction({
    required this.id,
    required this.date,
    required this.description,
    required this.amount,
    required this.currency,
    this.referenceNumber,
  });
}

/// Represents a successfully reconciled match between a physical receipt and a bank transaction.
class ReconciledMatch {
  final Receipt receipt;
  final BankTransaction bankTransaction;
  final double confidenceScore;
  final double amountDifference;
  final int dateDifferenceDays;
  final double merchantSimilarity;
  final String matchReason;

  const ReconciledMatch({
    required this.receipt,
    required this.bankTransaction,
    required this.confidenceScore,
    required this.amountDifference,
    required this.dateDifferenceDays,
    required this.merchantSimilarity,
    required this.matchReason,
  });

  /// High confidence match (score >= 0.80)
  bool get isHighConfidence => confidenceScore >= 0.80;
}

/// Comprehensive report summarizing the smart reconciliation operation.
class ReconciliationReport {
  final List<ReconciledMatch> matchedPairs;
  final List<Receipt> unmatchedReceipts;
  final List<BankTransaction> unmatchedBankTransactions;
  final double totalReconciledAmount;
  final double totalUnreconciledReceiptAmount;
  final double totalUnreconciledBankAmount;
  final DateTime generatedAt;

  const ReconciliationReport({
    required this.matchedPairs,
    required this.unmatchedReceipts,
    required this.unmatchedBankTransactions,
    required this.totalReconciledAmount,
    required this.totalUnreconciledReceiptAmount,
    required this.totalUnreconciledBankAmount,
    required this.generatedAt,
  });

  int get totalScannedReceipts => matchedPairs.length + unmatchedReceipts.length;
  int get totalBankTransactions => matchedPairs.length + unmatchedBankTransactions.length;

  /// Percentage of scanned receipts successfully matched against bank statements.
  double get receiptMatchRate => totalScannedReceipts > 0 ? (matchedPairs.length / totalScannedReceipts) * 100.0 : 0.0;

  /// Percentage of bank transactions matched to scanned receipts.
  double get bankMatchRate => totalBankTransactions > 0 ? (matchedPairs.length / totalBankTransactions) * 100.0 : 0.0;
}

/// Smart Bank Reconciliation Engine.
///
/// Matches scanned receipts against imported bank statement CSVs by
/// evaluating multi-factor criteria:
/// - Date match within +/- 3 days
/// - Amount match within +/- $0.05 / 0.05 EUR
/// - Fuzzy semantic merchant matching
class BankReconciliationService {
  /// Parses a bank CSV statement into a list of [BankTransaction]s.
  static List<BankTransaction> parseBankCsv(String csvString) {
    if (csvString.trim().isEmpty) return [];

    final rows = const CsvToListConverter(eol: '\n', shouldParseNumbers: false).convert(csvString);
    if (rows.isEmpty) return [];

    final transactions = <BankTransaction>[];
    int dateCol = -1;
    int descCol = -1;
    int amountCol = -1;
    int currencyCol = -1;

    // Detect header columns
    if (rows.isNotEmpty) {
      final header = rows.first.map((e) => e.toString().toLowerCase().trim()).toList();
      for (int i = 0; i < header.length; i++) {
        final col = header[i];
        if (col.contains('date') || col.contains('data') || col.contains('datum')) {
          dateCol = i;
        } else if (col.contains('desc') || col.contains('payee') || col.contains('merchant') || col.contains('causale') || col.contains('name')) {
          descCol = i;
        } else if (col.contains('amount') || col.contains('importo') || col.contains('betrag') || col.contains('total') || col.contains('sum')) {
          amountCol = i;
        } else if (col.contains('curr') || col.contains('valuta')) {
          currencyCol = i;
        }
      }
    }

    final startIndex = (dateCol != -1 || descCol != -1 || amountCol != -1) ? 1 : 0;

    for (int i = startIndex; i < rows.length; i++) {
      final row = rows[i];
      if (row.isEmpty || row.every((c) => c.toString().trim().isEmpty)) continue;

      DateTime? date;
      String description = 'Bank Transaction #$i';
      double? amount;
      String currency = 'EUR';

      if (dateCol != -1 && dateCol < row.length) {
        date = _parseDate(row[dateCol].toString());
      }
      if (descCol != -1 && descCol < row.length) {
        final val = row[descCol].toString().trim();
        if (val.isNotEmpty) description = val;
      }
      if (amountCol != -1 && amountCol < row.length) {
        amount = _parseAmount(row[amountCol].toString());
      }
      if (currencyCol != -1 && currencyCol < row.length) {
        final curr = row[currencyCol].toString().trim().toUpperCase();
        if (curr.length == 3) currency = curr;
      }

      // Fallback sequential heuristic if columns weren't detected
      if (date == null || amount == null) {
        for (final cell in row) {
          final cellStr = cell.toString().trim();
          if (date == null) {
            date = _parseDate(cellStr);
            if (date != null) continue;
          }
          if (amount == null) {
            amount = _parseAmount(cellStr);
            if (amount != null && amount > 0) continue;
          }
        }
      }

      if (date != null && amount != null && amount > 0) {
        transactions.add(BankTransaction(
          id: 'bank_tx_$i',
          date: date,
          description: description,
          amount: amount,
          currency: currency,
        ));
      }
    }

    return transactions;
  }

  /// Performs multi-factor smart reconciliation between receipts and bank transactions.
  static ReconciliationReport reconcile({
    required List<Receipt> receipts,
    required List<BankTransaction> bankTransactions,
    double amountTolerance = 0.05,
    int dateToleranceDays = 3,
  }) {
    final matchedPairs = <ReconciledMatch>[];
    final unmatchedReceipts = <Receipt>[];
    final availableBankTx = List<BankTransaction>.from(bankTransactions);

    for (final receipt in receipts) {
      _CandidateMatch? bestCandidate;

      for (int bIdx = 0; bIdx < availableBankTx.length; bIdx++) {
        final bankTx = availableBankTx[bIdx];

        // 1. Amount Match Check
        final amountDiff = (receipt.totalAmount - bankTx.amount).abs();
        if (amountDiff > amountTolerance) {
          continue; // Amount mismatch beyond tolerance
        }

        // 2. Date Match Check
        final dateDiffDays = receipt.date.difference(bankTx.date).inDays.abs();
        if (dateDiffDays > dateToleranceDays) {
          continue; // Date difference beyond tolerance
        }

        // 3. Merchant / Payee Fuzzy Matching
        final merchantSim = _calculateMerchantSimilarity(
          receipt.merchantName,
          bankTx.description,
        );

        // 4. Calculate Multi-Factor Score
        // Amount score (0.0 to 1.0)
        final amountScore = 1.0 - (amountDiff / amountTolerance).clamp(0.0, 1.0) * 0.15;
        // Date score (0.0 to 1.0)
        final dateScore = 1.0 - (dateDiffDays / dateToleranceDays).clamp(0.0, 1.0) * 0.25;
        // Combined confidence: 45% amount, 30% date, 25% merchant similarity
        final compositeConfidence = (0.45 * amountScore) + (0.30 * dateScore) + (0.25 * merchantSim);

        if (bestCandidate == null || compositeConfidence > bestCandidate.confidence) {
          bestCandidate = _CandidateMatch(
            bankIndex: bIdx,
            bankTx: bankTx,
            confidence: compositeConfidence,
            amountDiff: amountDiff,
            dateDiffDays: dateDiffDays,
            merchantSim: merchantSim,
          );
        }
      }

      if (bestCandidate != null && bestCandidate.confidence >= 0.50) {
        matchedPairs.add(ReconciledMatch(
          receipt: receipt,
          bankTransaction: bestCandidate.bankTx,
          confidenceScore: bestCandidate.confidence,
          amountDifference: bestCandidate.amountDiff,
          dateDifferenceDays: bestCandidate.dateDiffDays,
          merchantSimilarity: bestCandidate.merchantSim,
          matchReason: 'Matched by amount (diff: ${bestCandidate.amountDiff.toStringAsFixed(2)}), '
              'date (diff: ${bestCandidate.dateDiffDays}d), '
              'and merchant similarity (${(bestCandidate.merchantSim * 100).toStringAsFixed(0)}%)',
        ));
        availableBankTx.removeAt(bestCandidate.bankIndex);
      } else {
        unmatchedReceipts.add(receipt);
      }
    }

    final totalReconciled = matchedPairs.fold<double>(0.0, (s, m) => s + m.receipt.totalAmount);
    final totalUnrecReceipts = unmatchedReceipts.fold<double>(0.0, (s, r) => s + r.totalAmount);
    final totalUnrecBank = availableBankTx.fold<double>(0.0, (s, b) => s + b.amount);

    return ReconciliationReport(
      matchedPairs: matchedPairs,
      unmatchedReceipts: unmatchedReceipts,
      unmatchedBankTransactions: availableBankTx,
      totalReconciledAmount: totalReconciled,
      totalUnreconciledReceiptAmount: totalUnrecReceipts,
      totalUnreconciledBankAmount: totalUnrecBank,
      generatedAt: DateTime.now(),
    );
  }

  static double _calculateMerchantSimilarity(String str1, String str2) {
    final tokens1 = str1.toLowerCase().split(RegExp(r'[^a-z0-9]+')).where((s) => s.length >= 2).toSet();
    final tokens2 = str2.toLowerCase().split(RegExp(r'[^a-z0-9]+')).where((s) => s.length >= 2).toSet();

    if (tokens1.isEmpty || tokens2.isEmpty) return 0.0;

    int matchCount = 0;
    for (final t1 in tokens1) {
      for (final t2 in tokens2) {
        if (t1 == t2 || t1.startsWith(t2) || t2.startsWith(t1)) {
          matchCount++;
          break;
        }
      }
    }

    final overlap = matchCount / math.max(1, math.min(tokens1.length, tokens2.length));
    final tokenScore = SemanticHasher.tokenMatchScore(str1, str2);
    return math.max(overlap, tokenScore).clamp(0.0, 1.0);
  }

  static DateTime? _parseDate(String val) {
    if (val.isEmpty) return null;
    final clean = val.replaceAll('/', '-').replaceAll('.', '-').trim();
    final parts = clean.split('-');

    if (parts.length == 3) {
      // Check YYYY-MM-DD
      if (parts[0].length == 4) {
        final y = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        final d = int.tryParse(parts[2]);
        if (y != null && m != null && d != null) return DateTime(y, m, d);
      }
      // Check DD-MM-YYYY
      if (parts[2].length == 4) {
        final d = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        final y = int.tryParse(parts[2]);
        if (y != null && m != null && d != null) return DateTime(y, m, d);
      }
    }
    return DateTime.tryParse(val);
  }

  static double? _parseAmount(String val) {
    if (val.isEmpty) return null;
    var clean = val.replaceAll(RegExp(r'[^0-9.,-]'), '').trim();
    if (clean.isEmpty) return null;

    if (clean.contains(',') && clean.contains('.')) {
      if (clean.indexOf(',') > clean.indexOf('.')) {
        clean = clean.replaceAll('.', '').replaceAll(',', '.');
      } else {
        clean = clean.replaceAll(',', '');
      }
    } else if (clean.contains(',')) {
      clean = clean.replaceAll(',', '.');
    }

    final parsed = double.tryParse(clean);
    return parsed?.abs();
  }
}

class _CandidateMatch {
  final int bankIndex;
  final BankTransaction bankTx;
  final double confidence;
  final double amountDiff;
  final int dateDiffDays;
  final double merchantSim;

  const _CandidateMatch({
    required this.bankIndex,
    required this.bankTx,
    required this.confidence,
    required this.amountDiff,
    required this.dateDiffDays,
    required this.merchantSim,
  });
}
