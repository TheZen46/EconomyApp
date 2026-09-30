import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/core/financial/home_office_apportionment_engine.dart';

void main() {
  group('HomeOfficeApportionmentEngine Tests', () {
    test('computes simplified method accurately for spaces <= 300 sq ft', () {
      const space = HomeOfficeSpace(
        totalHomeSqFt: 1000,
        dedicatedOfficeSqFt: 200,
        isExclusiveUse: true,
        isRegularUse: true,
        isPrincipalPlaceOfBusiness: true,
      );

      const expenses = HouseholdExpenses();

      final result = HomeOfficeApportionmentEngine.calculate(
        space: space,
        expenses: expenses,
        effectiveTaxRate: 0.30,
      );

      expect(result.isEligible, true);
      // 200 sq ft * $5 = $1000
      expect(result.simplifiedMethodDeduction, 1000.0);
      expect(result.recommendedMethod, 'SIMPLIFIED');
      expect(result.optimalDeduction, 1000.0);
      expect(result.estimatedTaxSavings, 300.0); // 1000 * 0.30
    });

    test('caps simplified method at 300 sq ft (\$1,500 max limit)', () {
      const space = HomeOfficeSpace(
        totalHomeSqFt: 2500,
        dedicatedOfficeSqFt: 500,
      );

      const expenses = HouseholdExpenses();

      final result = HomeOfficeApportionmentEngine.calculate(
        space: space,
        expenses: expenses,
      );

      expect(result.simplifiedMethodDeduction, 1500.0);
    });

    test('optimizes actual expenses method when indirect rent/utilities exceed simplified cap', () {
      const space = HomeOfficeSpace(
        totalHomeSqFt: 1000,
        dedicatedOfficeSqFt: 250, // 25%
      );

      // Rent: $2,000/mo = $24,000/yr. Utilities: $3,000/yr. Total indirect: $27,000.
      // 25% of $27,000 = $6,750. Plus internet (80% of $1,200 = $960) -> Actual = $7,710.
      const expenses = HouseholdExpenses(
        rentPaid: 24000.0,
        utilitiesElectricAndGas: 3000.0,
        internetMonthlyFee: 1200.0,
        internetBusinessUsagePercent: 0.80,
      );

      final result = HomeOfficeApportionmentEngine.calculate(
        space: space,
        expenses: expenses,
        effectiveTaxRate: 0.25,
      );

      expect(result.isEligible, true);
      expect(result.businessPercentage, 0.25);
      expect(result.simplifiedMethodDeduction, 1250.0); // 250 * $5
      expect(result.actualMethodDeduction, 7710.0); // 6750 + 960
      expect(result.recommendedMethod, 'ACTUAL');
      expect(result.optimalDeduction, 7710.0);
      expect(result.estimatedTaxSavings, 7710.0 * 0.25);
      expect(result.irsForm8829Lines['Line_3_Business_Percentage'], '25.00%');
      expect(result.auditDefenseRATIONALE, contains('ACTUAL EXPENSES METHOD RECOMMENDED'));
    });

    test('handles ineligibility when exclusive use test is failed', () {
      const space = HomeOfficeSpace(
        totalHomeSqFt: 1200,
        dedicatedOfficeSqFt: 200,
        isExclusiveUse: false, // Fails exclusive use test (e.g. shared kids playroom)
      );

      const expenses = HouseholdExpenses(rentPaid: 20000);

      final result = HomeOfficeApportionmentEngine.calculate(
        space: space,
        expenses: expenses,
      );

      expect(result.isEligible, false);
      expect(result.optimalDeduction, 0.0);
      expect(result.recommendedMethod, 'NONE');
      expect(result.ineligibilityReason, contains('EXCLUSIVELY'));
    });
  });
}
