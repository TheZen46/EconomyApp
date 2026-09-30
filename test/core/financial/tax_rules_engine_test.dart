import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/core/financial/tax_rules_engine.dart';

void main() {
  group('TaxRulesEngine Tests', () {
    test('limits business meals to 50% statutory deductibility', () {
      final eval = TaxRulesEngine.evaluate(
        amount: 150.0,
        category: 'Meals & Entertainment',
        description: 'Client Lunch at Bistro',
      );

      expect(eval.grossAmount, 150.0);
      expect(eval.deductibleAmount, 75.0); // 50% of 150
      expect(eval.disallowedAmount, 75.0);
      expect(eval.effectivePercentage, 0.50);
      expect(eval.ruleExplanation.contains('50%'), true);
    });

    test('disallows pure entertainment expenses completely (0% deductible)', () {
      final eval = TaxRulesEngine.evaluate(
        amount: 300.0,
        category: 'Entertainment',
        description: 'Concert Tickets with Prospect',
      );

      expect(eval.grossAmount, 300.0);
      expect(eval.deductibleAmount, 0.0);
      expect(eval.disallowedAmount, 300.0);
      expect(eval.effectivePercentage, 0.0);
    });

    test('apportions mobile phone and internet to 50% mixed-use', () {
      final eval = TaxRulesEngine.evaluate(
        amount: 80.0,
        category: 'Utilities',
        description: 'Monthly Verizon Cellular Bill',
      );

      expect(eval.deductibleAmount, 40.0);
      expect(eval.disallowedAmount, 40.0);
    });

    test('allows standard software and hardware at 100% full deduction', () {
      final eval = TaxRulesEngine.evaluate(
        amount: 2400.0,
        category: 'Hardware',
        description: 'Apple MacBook Pro M3',
      );

      expect(eval.deductibleAmount, 2400.0);
      expect(eval.disallowedAmount, 0.0);
      expect(eval.effectivePercentage, 1.0);
    });
  });
}
