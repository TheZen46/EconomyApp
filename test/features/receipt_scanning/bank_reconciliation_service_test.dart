import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/features/receipt_scanning/data/datasources/bank_reconciliation_service.dart';
import 'package:t_aidy/features/receipt_scanning/domain/entities/receipt.dart';

void main() {
  group('BankReconciliationService Tests', () {
    const sampleBankCsv = '''Date,Description,Amount,Currency,Ref
2026-09-14,ESSELUNGA MILANO VIA ROMA,-45.90,EUR,TX-9901
2026-09-12,CONAD CENTRO COMMERCIALE,-28.50,EUR,TX-9902
2026-09-10,APPLE STORE CAROUSEL DU LOUVRE,-1299.00,EUR,TX-9903
2026-09-08,ATM CASH WITHDRAWAL,-100.00,EUR,TX-9904
''';

    final scannedReceipts = [
      // Close date (Sep 15 vs Sep 14), exact amount, matching merchant
      Receipt(
        id: 'rec-1',
        merchantName: 'Esselunga Supermercato',
        date: DateTime(2026, 9, 15),
        totalAmount: 45.90,
        currency: 'EUR',
      ),
      // Exact date (Sep 12), amount within $0.02 (28.48 vs 28.50), matching merchant
      Receipt(
        id: 'rec-2',
        merchantName: 'Conad Superstore',
        date: DateTime(2026, 9, 12),
        totalAmount: 28.48,
        currency: 'EUR',
      ),
      // Scanned receipt with no bank match (paid in cash)
      Receipt(
        id: 'rec-unmatched',
        merchantName: 'Panificio Local Bakery',
        date: DateTime(2026, 9, 13),
        totalAmount: 5.50,
        currency: 'EUR',
      ),
    ];

    test('parses bank CSV rows into structured BankTransactions', () {
      final transactions = BankReconciliationService.parseBankCsv(sampleBankCsv);

      expect(transactions.length, equals(4));
      expect(transactions[0].amount, equals(45.90));
      expect(transactions[0].description, equals('ESSELUNGA MILANO VIA ROMA'));
      expect(transactions[0].date.year, equals(2026));
      expect(transactions[0].date.month, equals(9));
      expect(transactions[0].date.day, equals(14));
      expect(transactions[2].amount, equals(1299.00));
    });

    test('reconciles scanned receipts with bank statements by date, amount, and merchant similarity', () {
      final bankTransactions = BankReconciliationService.parseBankCsv(sampleBankCsv);
      final report = BankReconciliationService.reconcile(
        receipts: scannedReceipts,
        bankTransactions: bankTransactions,
        amountTolerance: 0.05,
        dateToleranceDays: 3,
      );

      // Verify matched pairs
      expect(report.matchedPairs.length, equals(2));

      // Match 1: Esselunga
      final esselungaMatch = report.matchedPairs.firstWhere((m) => m.receipt.id == 'rec-1');
      expect(esselungaMatch.bankTransaction.description, contains('ESSELUNGA'));
      expect(esselungaMatch.amountDifference, closeTo(0.0, 0.001));
      expect(esselungaMatch.dateDifferenceDays, equals(1));
      expect(esselungaMatch.confidenceScore, greaterThan(0.80));
      expect(esselungaMatch.isHighConfidence, isTrue);

      // Match 2: Conad (within 0.02 EUR delta)
      final conadMatch = report.matchedPairs.firstWhere((m) => m.receipt.id == 'rec-2');
      expect(conadMatch.bankTransaction.description, contains('CONAD'));
      expect(conadMatch.amountDifference, closeTo(0.02, 0.005));
      expect(conadMatch.dateDifferenceDays, equals(0));
      expect(conadMatch.confidenceScore, greaterThan(0.80));

      // Verify unmatched collections
      expect(report.unmatchedReceipts.length, equals(1));
      expect(report.unmatchedReceipts.first.id, equals('rec-unmatched'));

      expect(report.unmatchedBankTransactions.length, equals(2)); // Apple Store and ATM
      expect(report.receiptMatchRate, closeTo(66.66, 0.1));
    });
  });
}
