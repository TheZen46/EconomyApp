import 'package:t_aidy/features/tax_compliance/presentation/providers/tax_shield_provider.dart';

/// Result of a simulated hypothetical expense on solopreneur taxes and cash flow.
class TaxSimulationResult {
  /// The hypothetical purchase price.
  final double simulatedAmount;

  /// Whether the expense is classified as fully business deductible.
  final bool isDeductible;

  /// Whether Section 179 immediate expensing is applied.
  final bool isSection179;

  /// Direct tax savings earned from this expense.
  final double directTaxSavings;

  /// The effective net out-of-pocket cost after tax shield savings.
  final double netOutOfPocketCost;

  /// Effective discount percentage provided by the tax deduction.
  final double effectiveDiscountPercent;

  /// Projected post-purchase Safe-to-Spend balance.
  final double newSafeToSpend;

  /// Difference in Safe-to-Spend balance (negative value).
  final double safeToSpendDelta;

  /// Projected locked tax reserve needed after this deduction.
  final double newLockedTaxShield;

  /// Difference in tax reserve (tax savings = reduction in locked reserve).
  final double taxReserveReduction;

  const TaxSimulationResult({
    required this.simulatedAmount,
    required this.isDeductible,
    required this.isSection179,
    required this.directTaxSavings,
    required this.netOutOfPocketCost,
    required this.effectiveDiscountPercent,
    required this.newSafeToSpend,
    required this.safeToSpendDelta,
    required this.newLockedTaxShield,
    required this.taxReserveReduction,
  });
}

/// Engine for simulating the tax shield and cashflow impacts of hypothetical business expenses.
class TaxSimulatorEngine {
  /// Simulates the impact of an expense of [amount] on an existing [TaxShieldCalculation].
  static TaxSimulationResult simulateExpense({
    required TaxShieldCalculation currentTaxState,
    required double amount,
    bool isDeductible = true,
    bool isSection179 = false,
  }) {
    if (amount <= 0) {
      return TaxSimulationResult(
        simulatedAmount: 0.0,
        isDeductible: isDeductible,
        isSection179: isSection179,
        directTaxSavings: 0.0,
        netOutOfPocketCost: 0.0,
        effectiveDiscountPercent: 0.0,
        newSafeToSpend: currentTaxState.safeToSpend,
        safeToSpendDelta: 0.0,
        newLockedTaxShield: currentTaxState.lockedTaxShield,
        taxReserveReduction: 0.0,
      );
    }

    final rate = currentTaxState.effectiveTaxRate;

    // Calculate tax savings
    final taxSavings = isDeductible ? (amount * rate) : 0.0;
    final netCost = amount - taxSavings;
    final discountPercent = amount > 0 ? (taxSavings / amount) * 100.0 : 0.0;

    // New taxable income
    final addedDeduction = isDeductible ? amount : 0.0;
    final newDeductibles = currentTaxState.totalDeductibleExpenses + addedDeduction;
    final newNetTaxable = (currentTaxState.grossRevenue > newDeductibles)
        ? (currentTaxState.grossRevenue - newDeductibles)
        : 0.0;

    final newLockedReserve = newNetTaxable * rate;
    final reserveReduction = currentTaxState.lockedTaxShield - newLockedReserve;

    // Projected new safe to spend
    final newTotalExpenses = currentTaxState.totalExpenses + amount;
    final rawSafeToSpend = currentTaxState.grossRevenue - newLockedReserve - newTotalExpenses;
    final newSafeToSpend = rawSafeToSpend > 0.0 ? rawSafeToSpend : 0.0;
    final safeToSpendDelta = newSafeToSpend - currentTaxState.safeToSpend;

    return TaxSimulationResult(
      simulatedAmount: amount,
      isDeductible: isDeductible,
      isSection179: isSection179,
      directTaxSavings: taxSavings,
      netOutOfPocketCost: netCost,
      effectiveDiscountPercent: discountPercent,
      newSafeToSpend: newSafeToSpend,
      safeToSpendDelta: safeToSpendDelta,
      newLockedTaxShield: newLockedReserve,
      taxReserveReduction: reserveReduction,
    );
  }
}

