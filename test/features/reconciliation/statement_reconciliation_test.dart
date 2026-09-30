import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/features/reconciliation/data/datasources/statement_parser.dart';
import 'package:t_aidy/features/reconciliation/domain/reconciliation_engine.dart';
import 'package:t_aidy/features/receipt_scanning/domain/entities/receipt.dart';

void main() {
  group('Statement Parser & Reconciliation Engine Tests', () {
    const csvContent = '''Date,Description,Amount,Currency,Reference
2026-03-15,APPLE.COM/BILL,-1299.99,USD,REF12345
2026-03-16,STARBUCKS STORE #104,-8.50,USD,REF12346
2026-03-18,UBER TRIP PENDING,-24.30,USD,REF12347
''';

    final sampleReceipts = [
      Receipt(
        id: 'rec-001',
        merchantName: 'Apple Store',
        date: DateTime(2026, 3, 15),
        totalAmount: 1299.99,
        currency: 'USD',
        items: const [
          ReceiptItem(description: 'MacBook Pro', unitPrice: 1299.99, quantity: 1, totalPrice: 1299.99, mainCategory: 'Electronics'),
        ],
      ),
      Receipt(
        id: 'rec-002',
        merchantName: 'Starbucks',
        date: DateTime(2026, 3, 16),
        totalAmount: 8.50,
        currency: 'USD',
        items: const [
          ReceiptItem(description: 'Coffee', unitPrice: 8.50, quantity: 1, totalPrice: 8.50, mainCategory: 'Dining'),
        ],
      ),
    ];

    test('parses CSV bank statements correctly', () {
      final transactions = StatementParser.parseCsv(csvContent);
      expect(transactions.length, 3);
      expect(transactions[0].description, 'APPLE.COM/BILL');
      expect(transactions[0].amount, 1299.99);
      expect(transactions[1].description, 'STARBUCKS STORE #104');
      expect(transactions[1].amount, 8.50);
    });

    test('reconciliation engine matches transactions with receipts', () {
      final transactions = StatementParser.parseCsv(csvContent);
      final results = ReconciliationEngine.reconcile(
        transactions: transactions,
        receipts: sampleReceipts,
      );

      expect(results.length, 3);
      final matched = results.where((r) => r.isMatched).toList();
      final unmatched = results.where((r) => !r.isMatched).toList();

      expect(matched.length, 2);
      expect(unmatched.length, 1);
      expect(unmatched.first.transaction.description, 'UBER TRIP PENDING');
    });
  });
}
