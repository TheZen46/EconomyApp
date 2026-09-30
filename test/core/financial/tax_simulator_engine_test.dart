import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/core/financial/tax_shield_provider.dart';
import 'package:t_aidy/core/financial/tax_simulator_engine.dart';

void main() {
  group('TaxSimulatorEngine Tests', () {
    final baseTaxState = TaxShieldCalculation(
      grossRevenue: 10000.0,
      totalExpenses: 2000.0,
      totalDeductibleExpenses: 2000.0,
      netTaxableIncome: 8000.0,
      effectiveTaxRate: 0.25, // 25% tax bracket
      lockedTaxShield: 2000.0, // 8000 * 0.25
      taxSavingsEarned: 500.0,
      safeToSpend: 6000.0, // 10000 - 2000 (tax) - 2000 (exp)
      currentQuarter: 1,
      currentYear: 2026,
      nextQuarterDeadline: DateTime(2026, 4, 15),
      daysUntilDeadline: 20,
      profile: kTaxProfilePresets.first,
    );

    test('simulates deductible 1000 dollar expense accurately with 25% bracket', () {
      final sim = TaxSimulatorEngine.simulateExpense(
        currentTaxState: baseTaxState,
        amount: 1000.0,
        isDeductible: true,
      );

      // 1000 * 0.25 = 250 in tax savings
      expect(sim.directTaxSavings, 250.0);
      // Net out of pocket = 1000 - 250 = 750
      expect(sim.netOutOfPocketCost, 750.0);
      expect(sim.effectiveDiscountPercent, 25.0);

      // New taxable income = 10000 - 3000 = 7000
      // New locked tax reserve = 7000 * 0.25 = 1750
      expect(sim.newLockedTaxShield, 1750.0);
      expect(sim.taxReserveReduction, 250.0);

      // New safe to spend = 10000 - 1750 - 3000 = 5250
      expect(sim.newSafeToSpend, 5250.0);
      expect(sim.safeToSpendDelta, -750.0);
    });

    test('simulates non-deductible personal expense (zero tax savings)', () {
      final sim = TaxSimulatorEngine.simulateExpense(
        currentTaxState: baseTaxState,
        amount: 500.0,
        isDeductible: false,
      );

      expect(sim.directTaxSavings, 0.0);
      expect(sim.netOutOfPocketCost, 500.0);
      expect(sim.effectiveDiscountPercent, 0.0);
      expect(sim.newLockedTaxShield, 2000.0); // unchanged
      expect(sim.taxReserveReduction, 0.0);
      expect(sim.newSafeToSpend, 5500.0); // 6000 - 500
      expect(sim.safeToSpendDelta, -500.0);
    });

    test('handles zero or negative amount gracefully', () {
      final sim = TaxSimulatorEngine.simulateExpense(
        currentTaxState: baseTaxState,
        amount: 0.0,
      );

      expect(sim.directTaxSavings, 0.0);
      expect(sim.netOutOfPocketCost, 0.0);
      expect(sim.newSafeToSpend, 6000.0);
      expect(sim.safeToSpendDelta, 0.0);
    });
  });
}
