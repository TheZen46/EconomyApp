import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/core/financial/meal_apportionment_engine.dart';

void main() {
  group('MealApportionmentEngine Statutory Tests', () {
    test('applies 50% deduction to standard client business meal with proportional tip/tax', () {
      final items = [
        const MealReceiptItem(
          description: 'Grilled Salmon & Salad',
          amount: 80.0,
          deductionClass: MealDeductionClass.standardBusiness50,
        ),
      ];

      final result = MealApportionmentEngine.apportion(
        items: items,
        tipAndTaxAmount: 20.0, // Total = $100
        businessPurpose: 'Q2 Strategy contract discussion',
        attendees: 'Jane Doe (VP Client Acme)',
        isTaxpayerPresent: true,
      );

      expect(result.totalReceiptAmount, 100.0);
      expect(result.deductibleAmount, 50.0); // 50% of $100
      expect(result.nonDeductibleAmount, 50.0);
      expect(result.effectiveDeductionPercentage, 50.0);
      expect(result.satisfiesSubstantiationRules, true);
      expect(result.auditComplianceWarnings.isEmpty, true);
    });

    test('correctly splits mixed meal receipt containing 50% food and 0% disallowed entertainment tickets', () {
      final items = [
        const MealReceiptItem(
          description: 'Steak Dinner for Two',
          amount: 100.0,
          deductionClass: MealDeductionClass.standardBusiness50,
        ),
        const MealReceiptItem(
          description: 'VIP NBA Basketball Game Tickets',
          amount: 300.0,
          deductionClass: MealDeductionClass.entertainmentDisallowed0,
        ),
      ];

      final result = MealApportionmentEngine.apportion(
        items: items,
        tipAndTaxAmount: 0.0,
        businessPurpose: 'Client relationship building',
        attendees: 'Bob Client (Acme Corp)',
      );

      expect(result.totalReceiptAmount, 400.0);
      // Dinner: 50% of $100 = $50. Tickets: 0% of $300 = $0 -> Total deductible: $50
      expect(result.deductibleAmount, 50.0);
      expect(result.nonDeductibleAmount, 350.0);
      expect(result.effectiveDeductionPercentage, 12.5); // $50 / $400 = 12.5%
      expect(result.auditComplianceWarnings.any((w) => w.contains('flagged as 0%')), true);
    });

    test('awards 100% deduction for company-wide all-employee social gathering (§ 274(e)(4))', () {
      final items = [
        const MealReceiptItem(
          description: 'Holiday Team Dinner Buffet',
          amount: 500.0,
          deductionClass: MealDeductionClass.companyWideEvent100,
        ),
      ];

      final result = MealApportionmentEngine.apportion(
        items: items,
        tipAndTaxAmount: 100.0, // Total = $600
        businessPurpose: 'Annual Holiday Party for all staff',
        attendees: 'All team members & contractors',
      );

      expect(result.totalReceiptAmount, 600.0);
      expect(result.deductibleAmount, 600.0); // 100% deductible
      expect(result.effectiveDeductionPercentage, 100.0);
    });

    test('flags substantiation failure when taxpayer is not present', () {
      final items = [
        const MealReceiptItem(
          description: 'Catered Lunch',
          amount: 50.0,
          deductionClass: MealDeductionClass.standardBusiness50,
        ),
      ];

      final result = MealApportionmentEngine.apportion(
        items: items,
        tipAndTaxAmount: 10.0,
        businessPurpose: 'Lunch meeting',
        attendees: 'Client team only',
        isTaxpayerPresent: false, // Taxpayer absent
      );

      expect(result.satisfiesSubstantiationRules, false);
      expect(result.auditComplianceWarnings.any((w) => w.contains('Taxpayer or authorized employee must be present')), true);
    });
  });
}
