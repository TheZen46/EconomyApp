import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/core/services/bayesian_categorizer_engine.dart';
import 'package:t_aidy/features/receipt_scanning/domain/entities/receipt.dart';

void main() {
  group('Bayesian & Markov Categorizer Engine Tests', () {
    test('handles cold-start state gracefully with default suggestion', () {
      final engine = BayesianCategorizerEngine();
      final prediction = engine.predict(merchantName: 'Unknown New Shop');

      expect(prediction.predictedCategory, 'General Business Expense');
      expect(prediction.reasoning, contains('Cold-start'));
      expect(prediction.categoryConfidence, 0.20);
    });

    test('trains on historical receipts and accurately predicts category and box for known merchants', () {
      final trainingReceipts = <Receipt>[
        Receipt(
          id: '1',
          merchantName: 'Starbucks Coffee',
          totalAmount: 6.50,
          currency: 'USD',
          date: DateTime.now(),
          boxId: 'consulting_box',
          items: const [ReceiptItem(description: 'Latte', unitPrice: 6.50, quantity: 1, totalPrice: 6.50, mainCategory: 'Meals & Entertainment')],
        ),
        Receipt(
          id: '2',
          merchantName: 'Starbucks Coffee',
          totalAmount: 8.20,
          currency: 'USD',
          date: DateTime.now(),
          boxId: 'consulting_box',
          items: const [ReceiptItem(description: 'Cappuccino and Muffin', unitPrice: 8.20, quantity: 1, totalPrice: 8.20, mainCategory: 'Meals & Entertainment')],
        ),
        Receipt(
          id: '3',
          merchantName: 'Amazon AWS Cloud',
          totalAmount: 145.00,
          currency: 'USD',
          date: DateTime.now(),
          boxId: 'tech_box',
          items: const [ReceiptItem(description: 'EC2 and S3 Server Hosting', unitPrice: 145.00, quantity: 1, totalPrice: 145.00, mainCategory: 'Software & SaaS')],
        ),
        Receipt(
          id: '4',
          merchantName: 'Amazon AWS Cloud',
          totalAmount: 210.00,
          currency: 'USD',
          date: DateTime.now(),
          boxId: 'tech_box',
          items: const [ReceiptItem(description: 'Database RDS Postgres', unitPrice: 210.00, quantity: 1, totalPrice: 210.00, mainCategory: 'Software & SaaS')],
        ),
        Receipt(
          id: '5',
          merchantName: 'Uber Trip',
          totalAmount: 32.50,
          currency: 'USD',
          date: DateTime.now(),
          boxId: 'travel_box',
          items: const [ReceiptItem(description: 'Airport Transit', unitPrice: 32.50, quantity: 1, totalPrice: 32.50, mainCategory: 'Travel & Transportation')],
        ),
      ];

      final engine = BayesianCategorizerEngine();
      engine.train(trainingReceipts);

      expect(engine.totalTrainedReceipts, 5);
      expect(engine.vocabularySize, greaterThan(10));

      // Test Query 1: Starbucks coffee
      final pred1 = engine.predict(merchantName: 'Starbucks Airport Terminal');
      expect(pred1.predictedCategory, 'Meals & Entertainment');
      expect(pred1.predictedBoxId, 'consulting_box');
      expect(pred1.categoryConfidence, greaterThan(0.50));

      // Test Query 2: AWS Hosting
      final pred2 = engine.predict(merchantName: 'AWS Cloud Services', lineItemText: 'Virtual server');
      expect(pred2.predictedCategory, 'Software & SaaS');
      expect(pred2.predictedBoxId, 'tech_box');
      expect(pred2.categoryConfidence, greaterThan(0.50));

      // Test Query 3: Uber ride
      final pred3 = engine.predict(merchantName: 'Uber Technologies');
      expect(pred3.predictedCategory, 'Travel & Transportation');
      expect(pred3.predictedBoxId, 'travel_box');
    });

    test('Markov transition booster elevates probability of staying in same box sequence', () {
      final trainingReceipts = <Receipt>[
        Receipt(
          id: '1',
          merchantName: 'Client Lunch',
          totalAmount: 50.0,
          currency: 'USD',
          date: DateTime.now(),
          boxId: 'consulting_box',
          items: const [ReceiptItem(description: 'Lunch', unitPrice: 50.0, quantity: 1, totalPrice: 50.0, mainCategory: 'Meals')],
        ),
        Receipt(
          id: '2',
          merchantName: 'Client Coffee',
          totalAmount: 10.0,
          currency: 'USD',
          date: DateTime.now(),
          boxId: 'consulting_box',
          items: const [ReceiptItem(description: 'Coffee', unitPrice: 10.0, quantity: 1, totalPrice: 10.0, mainCategory: 'Meals')],
        ),
      ];

      final engine = BayesianCategorizerEngine();
      engine.train(trainingReceipts);

      final pred = engine.predict(
        merchantName: 'Cafe',
        previousBoxId: 'consulting_box',
      );

      expect(pred.predictedBoxId, 'consulting_box');
    });
  });
}
