import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/features/boxes/data/models/box_model.dart';
import 'package:t_aidy/features/boxes/domain/burn_rate_calculator.dart';
import 'package:t_aidy/features/receipt_scanning/domain/entities/receipt.dart';

void main() {
  group('BurnRateCalculator Domain Tests', () {
    final testBox = BoxModel(
      id: 'box-groceries',
      name: 'Groceries & Household',
      budget: 600.0,
      spent: 0.0,
      currency: 'EUR',
      color: 0xFF2196F3,
    );

    final fixedNow = DateTime(2026, 9, 15, 12, 0); // Day 15 of 30-day month (15 days remaining)

    final sampleReceipts = [
      // Within last 7 days (Sep 9 - Sep 15)
      Receipt(
        id: 'rec-1',
        merchantName: 'Esselunga',
        date: DateTime(2026, 9, 14),
        totalAmount: 70.0,
        currency: 'EUR',
        boxId: 'box-groceries',
      ),
      Receipt(
        id: 'rec-2',
        merchantName: 'Conad',
        date: DateTime(2026, 9, 12),
        totalAmount: 70.0,
        currency: 'EUR',
        boxId: 'box-groceries',
      ),
      // Earlier in current month (Sep 3)
      Receipt(
        id: 'rec-3',
        merchantName: 'Coop',
        date: DateTime(2026, 9, 3),
        totalAmount: 110.0,
        currency: 'EUR',
        boxId: 'box-groceries',
      ),
      // Different Box (should be ignored)
      Receipt(
        id: 'rec-other',
        merchantName: 'Apple Store',
        date: DateTime(2026, 9, 10),
        totalAmount: 999.0,
        currency: 'EUR',
        boxId: 'box-tech',
      ),
    ];

    test('calculates 7-day velocity and projected EOM spend accurately', () {
      // Last 7 days spend = 70 + 70 = 140
      // Effective days in window = min(15, 7) = 7
      // Daily velocity = 140 / 7 = 20.0 EUR/day
      // Current month spend = 70 + 70 + 110 = 250 EUR
      // Remaining days in Sep (30 - 15) = 15
      // Projected EOM = 250 + (20.0 * 15) = 550.0 EUR
      final metrics = BurnRateCalculator.calculate(
        box: testBox,
        receipts: sampleReceipts,
        window: VelocityWindow.days7,
        referenceDate: fixedNow,
      );

      expect(metrics.currentSpend, equals(250.0));
      expect(metrics.dailyVelocity, closeTo(20.0, 0.01));
      expect(metrics.remainingDaysInMonth, equals(15));
      expect(metrics.projectedEomSpend, closeTo(550.0, 0.01));
      expect(metrics.budget, equals(600.0));
      // 550 <= 600 * 0.85 (510)? No, 550 > 510 and <= 600 -> warning
      expect(metrics.status, equals(BudgetHealthStatus.warning));
      expect(metrics.projectedDelta, closeTo(-50.0, 0.01)); // 50 under budget
    });

    test('determines onTrack status when projected spend is well below budget', () {
      final lowSpendReceipts = [
        Receipt(
          id: 'rec-low-1',
          merchantName: 'Lidl',
          date: DateTime(2026, 9, 14),
          totalAmount: 20.0,
          currency: 'EUR',
          boxId: 'box-groceries',
        ),
      ];

      final metrics = BurnRateCalculator.calculate(
        box: testBox,
        receipts: lowSpendReceipts,
        window: VelocityWindow.days7,
        referenceDate: fixedNow,
      );

      // Current spend = 20
      // Velocity = 20 / 7 = 2.857
      // Projected = 20 + (2.857 * 15) = 62.85
      // 62.85 <= 600 * 0.85 (510) -> onTrack
      expect(metrics.status, equals(BudgetHealthStatus.onTrack));
      expect(metrics.projectedPercentage, lessThan(85.0));
    });

    test('determines overBudget status when projected spend exceeds 100% of budget', () {
      final highSpendReceipts = [
        Receipt(
          id: 'rec-high-1',
          merchantName: 'Eataly',
          date: DateTime(2026, 9, 14),
          totalAmount: 300.0,
          currency: 'EUR',
          boxId: 'box-groceries',
        ),
        Receipt(
          id: 'rec-high-2',
          merchantName: 'Carrefour Gourmet',
          date: DateTime(2026, 9, 10),
          totalAmount: 250.0,
          currency: 'EUR',
          boxId: 'box-groceries',
        ),
      ];

      final metrics = BurnRateCalculator.calculate(
        box: testBox,
        receipts: highSpendReceipts,
        window: VelocityWindow.days7,
        referenceDate: fixedNow,
      );

      // Current spend = 550
      // Velocity = 550 / 7 = 78.57
      // Projected = 550 + (78.57 * 15) = 1728.57 > 600 -> overBudget
      expect(metrics.status, equals(BudgetHealthStatus.overBudget));
      expect(metrics.projectedDelta, greaterThan(0));
      expect(metrics.isAtRisk, isTrue);
    });

    test('handles no budget configured gracefully', () {
      final noBudgetBox = BoxModel(
        id: 'box-free',
        name: 'Unbudgeted Box',
        budget: 0.0,
        spent: 0.0,
        currency: 'EUR',
        color: 0xFF9E9E9E,
      );

      final metrics = BurnRateCalculator.calculate(
        box: noBudgetBox,
        receipts: sampleReceipts,
        window: VelocityWindow.days7,
        referenceDate: fixedNow,
      );

      expect(metrics.status, equals(BudgetHealthStatus.noBudget));
      expect(metrics.projectedPercentage, equals(0.0));
      expect(metrics.budgetConsumptionRatio, equals(0.0));
    });
  });
}
