import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/core/financial/qbi_deduction_engine.dart';

void main() {
  group('Section 199A QBI Deduction Engine Tests', () {
    test('computes full 20% QBI deduction when taxable income is below statutory threshold', () {
      const params = QbiCalculationParams(
        netQualifiedBusinessIncome: 100000.0,
        totalTaxableIncome: 120000.0, // Below $191,950 threshold
        filingStatus: TaxFilingStatus.single,
        tradeType: BusinessTradeType.sstb, // Consulting/Accounting SSTB
      );

      final result = QbiDeductionEngine.calculate(params, marginalTaxRate: 0.24);

      expect(result.grossTentativeDeduction, 20000.0);
      expect(result.allowableQbiDeduction, 20000.0);
      expect(result.effectiveDeductionRate, 20.0);
      expect(result.taxSavings, 4800.0); // 20,000 * 0.24
      expect(result.isSubjectToSstbPhaseOut, false);
      expect(result.auditDefenseNotes, contains('ZONE A'));
    });

    test('phases out SSTB deduction when income is in the phase-out band', () {
      // Single threshold is $191,950; Ceiling is $241,950. Halfway = $216,950 (50% phase-out)
      const params = QbiCalculationParams(
        netQualifiedBusinessIncome: 150000.0,
        totalTaxableIncome: 216950.0,
        filingStatus: TaxFilingStatus.single,
        tradeType: BusinessTradeType.sstb,
      );

      final result = QbiDeductionEngine.calculate(params);

      expect(result.isSubjectToSstbPhaseOut, true);
      expect(result.applicablePercentage, closeTo(0.50, 0.01));
      expect(result.allowableQbiDeduction, lessThan(30000.0));
      expect(result.allowableQbiDeduction, greaterThan(0.0));
    });

    test('completely disallows SSTB deduction above phase-out ceiling', () {
      const params = QbiCalculationParams(
        netQualifiedBusinessIncome: 200000.0,
        totalTaxableIncome: 300000.0, // Above $241,950
        filingStatus: TaxFilingStatus.single,
        tradeType: BusinessTradeType.sstb,
      );

      final result = QbiDeductionEngine.calculate(params);

      expect(result.isSubjectToSstbPhaseOut, true);
      expect(result.allowableQbiDeduction, 0.0);
      expect(result.auditDefenseNotes, contains('ZONE C (SSTB Disallowed)'));
    });

    test('applies W-2 wage and UBIA property limit for high-earning non-SSTB business', () {
      // Software / tech non-SSTB with $400,000 income
      const params = QbiCalculationParams(
        netQualifiedBusinessIncome: 300000.0,
        totalTaxableIncome: 400000.0, // Above ceiling
        filingStatus: TaxFilingStatus.single,
        tradeType: BusinessTradeType.nonSstb,
        w2WagesPaid: 80000.0, // 50% = $40,000
        unadjustedBasisProperty: 100000.0, // 25% W2 ($20k) + 2.5% UBIA ($2.5k) = $22.5k -> Max is $40k
      );

      final result = QbiDeductionEngine.calculate(params);

      expect(result.grossTentativeDeduction, 60000.0); // 20% of 300k
      expect(result.wageUbiaCap, 40000.0); // 50% of 80k
      expect(result.allowableQbiDeduction, 40000.0); // Capped at wage limit
      expect(result.auditDefenseNotes, contains('ZONE C (Non-SSTB Fully Capped)'));
    });

    test('enforces overall taxable income cap (20% of taxable income less net capital gains)', () {
      const params = QbiCalculationParams(
        netQualifiedBusinessIncome: 100000.0, // Tentative 20% = $20,000
        totalTaxableIncome: 60000.0, // Only $60,000 taxable income after deductions
        netCapitalGains: 10000.0, // Net: $50,000 -> 20% cap = $10,000
        filingStatus: TaxFilingStatus.single,
        tradeType: BusinessTradeType.nonSstb,
      );

      final result = QbiDeductionEngine.calculate(params);

      expect(result.overallTaxableIncomeCap, 10000.0); // ($60k - $10k) * 0.20
      expect(result.allowableQbiDeduction, 10000.0); // Capped at $10,000
      expect(result.auditDefenseNotes, contains('Overall taxable income cap applied'));
    });
  });
}
