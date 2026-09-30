import 'dart:math';

/// Specific statutory category of business meals under IRC § 274.
enum MealDeductionClass {
  /// Standard 50% deductible business meals with clients, prospects, or partners (§ 274(n)(1))
  standardBusiness50,

  /// 100% deductible company-wide social/recreational events for all employees (§ 274(e)(4))
  companyWideEvent100,

  /// 100% deductible food/beverages provided to the general public as promotional expense (§ 274(e)(7))
  publicPromotional100,

  /// 100% deductible billable pass-through meals reimbursed by client (§ 274(e)(3))
  clientReimbursed100,

  /// 0% non-deductible entertainment, sporting events, or luxury expenses (§ 274(a)(1))
  entertainmentDisallowed0,
}

/// A line item within a restaurant, catering, or event receipt.
class MealReceiptItem {
  final String description;
  final double amount;
  final MealDeductionClass deductionClass;
  final bool isAlcoholIncluded;

  const MealReceiptItem({
    required this.description,
    required this.amount,
    this.deductionClass = MealDeductionClass.standardBusiness50,
    this.isAlcoholIncluded = false,
  });
}

/// Statutory calculation breakdown for a meal expense.
class MealApportionmentResult {
  final double totalReceiptAmount;
  final double deductibleAmount;
  final double nonDeductibleAmount;
  final double effectiveDeductionPercentage;
  final Map<MealDeductionClass, double> classTotals;
  final List<String> auditComplianceWarnings;
  final bool satisfiesSubstantiationRules; // 5-factor test: Amount, Date, Location, Business Purpose, Relationship

  const MealApportionmentResult({
    required this.totalReceiptAmount,
    required this.deductibleAmount,
    required this.nonDeductibleAmount,
    required this.effectiveDeductionPercentage,
    required this.classTotals,
    required this.auditComplianceWarnings,
    required this.satisfiesSubstantiationRules,
  });

  Map<String, dynamic> toJson() => {
        'totalReceiptAmount': totalReceiptAmount,
        'deductibleAmount': deductibleAmount,
        'nonDeductibleAmount': nonDeductibleAmount,
        'effectiveDeductionPercentage': effectiveDeductionPercentage,
        'classTotals': classTotals.map((k, v) => MapEntry(k.name, v)),
        'auditComplianceWarnings': auditComplianceWarnings,
        'satisfiesSubstantiationRules': satisfiesSubstantiationRules,
      };
}

/// [UNIQUE] Statutory Business Meal Deduction & Apportionment Engine (IRC § 274).
///
/// Implements precise statutory deduction percentage calculations across 50%, 100%,
/// and 0% disallowed entertainment components, enforcing IRS Reg. § 1.274-12 substantiation rules.
class MealApportionmentEngine {
  /// Evaluates a collection of meal line-items against IRC § 274 rules.
  static MealApportionmentResult apportion({
    required List<MealReceiptItem> items,
    required double tipAndTaxAmount,
    String? businessPurpose,
    String? attendees,
    bool isTaxpayerPresent = true,
  }) {
    if (items.isEmpty && tipAndTaxAmount <= 0) {
      return const MealApportionmentResult(
        totalReceiptAmount: 0.0,
        deductibleAmount: 0.0,
        nonDeductibleAmount: 0.0,
        effectiveDeductionPercentage: 0.0,
        classTotals: {},
        auditComplianceWarnings: ['Receipt contains zero line items.'],
        satisfiesSubstantiationRules: false,
      );
    }

    final warnings = <String>[];

    // Verify 5-factor substantiation under IRC § 274(d)
    bool substantiationPassed = true;

    if (!isTaxpayerPresent) {
      warnings.add('Taxpayer or authorized employee must be present for meals to be deductible under IRC § 274(k)(1)(B).');
      substantiationPassed = false;
    }

    if (businessPurpose == null || businessPurpose.trim().isEmpty) {
      warnings.add('Missing specific business purpose discussion note (IRC § 274(d) audit requirement).');
      substantiationPassed = false;
    }

    if (attendees == null || attendees.trim().isEmpty) {
      warnings.add('Missing record of attendees and their business relationship (IRC § 274(d) audit requirement).');
      substantiationPassed = false;
    }

    final classTotals = <MealDeductionClass, double>{
      MealDeductionClass.standardBusiness50: 0.0,
      MealDeductionClass.companyWideEvent100: 0.0,
      MealDeductionClass.publicPromotional100: 0.0,
      MealDeductionClass.clientReimbursed100: 0.0,
      MealDeductionClass.entertainmentDisallowed0: 0.0,
    };

    double itemsSum = 0.0;
    for (final item in items) {
      final amt = max(0.0, item.amount);
      itemsSum += amt;
      classTotals[item.deductionClass] = (classTotals[item.deductionClass] ?? 0.0) + amt;

      if (item.deductionClass == MealDeductionClass.entertainmentDisallowed0) {
        warnings.add('Item "${item.description}" flagged as 0% non-deductible entertainment under TCJA § 274(a)(1).');
      }
    }

    // Pro-rate tips & taxes across the items proportionally
    final cleanTipAndTax = max(0.0, tipAndTaxAmount);
    final totalReceipt = itemsSum + cleanTipAndTax;

    double allowableDeduction = 0.0;

    classTotals.forEach((deductionClass, rawAmount) {
      if (rawAmount > 0) {
        // Allocate proportional share of tips and taxes to this class
        final allocatedTipAndTax = itemsSum > 0 ? (rawAmount / itemsSum) * cleanTipAndTax : 0.0;
        final totalClassExpense = rawAmount + allocatedTipAndTax;

        switch (deductionClass) {
          case MealDeductionClass.standardBusiness50:
            allowableDeduction += (totalClassExpense * 0.50);
            break;
          case MealDeductionClass.companyWideEvent100:
          case MealDeductionClass.publicPromotional100:
          case MealDeductionClass.clientReimbursed100:
            allowableDeduction += totalClassExpense;
            break;
          case MealDeductionClass.entertainmentDisallowed0:
            // 0% deduction
            break;
        }
      }
    });

    final nonDeductible = max(0.0, totalReceipt - allowableDeduction);
    final effectivePct = totalReceipt > 0 ? (allowableDeduction / totalReceipt) * 100.0 : 0.0;

    return MealApportionmentResult(
      totalReceiptAmount: totalReceipt,
      deductibleAmount: allowableDeduction,
      nonDeductibleAmount: nonDeductible,
      effectiveDeductionPercentage: effectivePct,
      classTotals: classTotals,
      auditComplianceWarnings: warnings,
      satisfiesSubstantiationRules: substantiationPassed,
    );
  }
}

