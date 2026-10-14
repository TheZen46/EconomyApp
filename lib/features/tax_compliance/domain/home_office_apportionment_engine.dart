import 'dart:math';

/// Representation of the physical home office space configuration under IRS Form 8829.
class HomeOfficeSpace {
  final double totalHomeSqFt;
  final double dedicatedOfficeSqFt;
  final bool isExclusiveUse; // Mandatory IRS test: used exclusively for trade/business
  final bool isRegularUse; // Mandatory IRS test: used on a regular, continuing basis
  final bool isPrincipalPlaceOfBusiness; // Or place to meet clients / administrative hub

  const HomeOfficeSpace({
    required this.totalHomeSqFt,
    required this.dedicatedOfficeSqFt,
    this.isExclusiveUse = true,
    this.isRegularUse = true,
    this.isPrincipalPlaceOfBusiness = true,
  });

  /// Computes the square footage apportionment percentage (0.0 to 1.0)
  double get businessPercentage {
    if (totalHomeSqFt <= 0 || dedicatedOfficeSqFt <= 0) return 0.0;
    return (dedicatedOfficeSqFt / totalHomeSqFt).clamp(0.0, 1.0);
  }

  /// Whether the space qualifies for statutory deduction under IRC § 280A
  bool get qualifiesForDeduction {
    return isExclusiveUse && isRegularUse && isPrincipalPlaceOfBusiness && dedicatedOfficeSqFt > 0;
  }
}

/// Breakdown of indirect and direct household expenses.
class HouseholdExpenses {
  final double directOfficeExpenses; // 100% deductible (e.g. office repairs, painting)
  final double rentPaid; // If renting
  final double mortgageInterest; // If homeowner
  final double realEstateTaxes; // If homeowner
  final double homeownersOrRentersInsurance;
  final double utilitiesElectricAndGas;
  final double utilitiesWaterAndTrash;
  final double generalRepairsAndMaintenance;
  final double internetMonthlyFee;
  final double internetBusinessUsagePercent; // e.g., 0.80 for 80%
  final double mobilePhoneMonthlyFee;
  final double mobilePhoneBusinessUsagePercent; // e.g., 0.70 for 70%
  final double homeBasisExcludingLand; // For depreciation (39-year MACRS straight-line: 2.564%/yr)

  const HouseholdExpenses({
    this.directOfficeExpenses = 0.0,
    this.rentPaid = 0.0,
    this.mortgageInterest = 0.0,
    this.realEstateTaxes = 0.0,
    this.homeownersOrRentersInsurance = 0.0,
    this.utilitiesElectricAndGas = 0.0,
    this.utilitiesWaterAndTrash = 0.0,
    this.generalRepairsAndMaintenance = 0.0,
    this.internetMonthlyFee = 0.0,
    this.internetBusinessUsagePercent = 0.80,
    this.mobilePhoneMonthlyFee = 0.0,
    this.mobilePhoneBusinessUsagePercent = 0.70,
    this.homeBasisExcludingLand = 0.0,
  });

  /// Sum of all general household indirect operating expenses
  double get totalIndirectHouseholdExpenses {
    return rentPaid +
        mortgageInterest +
        realEstateTaxes +
        homeownersOrRentersInsurance +
        utilitiesElectricAndGas +
        utilitiesWaterAndTrash +
        generalRepairsAndMaintenance;
  }

  /// Dedicated telecom & mobile business apportionments
  double get totalBusinessTelecomExpenses {
    final netInternet = internetMonthlyFee * (internetBusinessUsagePercent.clamp(0.0, 1.0));
    final netMobile = mobilePhoneMonthlyFee * (mobilePhoneBusinessUsagePercent.clamp(0.0, 1.0));
    return netInternet + netMobile;
  }

  /// Annual allowable MACRS depreciation (2.564% per IRS Publication 946)
  double get annualAllowableDepreciation {
    return homeBasisExcludingLand * 0.02564;
  }
}

/// Comprehensive outcome comparing Simplified vs. Actual Expense Methods.
class HomeOfficeDeductionResult {
  final bool isEligible;
  final String? ineligibilityReason;
  final double businessSqFt;
  final double businessPercentage;
  final double simplifiedMethodDeduction;
  final double actualMethodDeduction;
  final String recommendedMethod; // 'SIMPLIFIED' or 'ACTUAL'
  final double optimalDeduction;
  final double estimatedTaxSavings; // At user's effective marginal tax rate
  final Map<String, dynamic> irsForm8829Lines;
  final String auditDefenseRATIONALE;

  const HomeOfficeDeductionResult({
    required this.isEligible,
    this.ineligibilityReason,
    required this.businessSqFt,
    required this.businessPercentage,
    required this.simplifiedMethodDeduction,
    required this.actualMethodDeduction,
    required this.recommendedMethod,
    required this.optimalDeduction,
    required this.estimatedTaxSavings,
    required this.irsForm8829Lines,
    required this.auditDefenseRATIONALE,
  });

  Map<String, dynamic> toJson() => {
        'isEligible': isEligible,
        'ineligibilityReason': ineligibilityReason,
        'businessSqFt': businessSqFt,
        'businessPercentage': businessPercentage,
        'simplifiedMethodDeduction': simplifiedMethodDeduction,
        'actualMethodDeduction': actualMethodDeduction,
        'recommendedMethod': recommendedMethod,
        'optimalDeduction': optimalDeduction,
        'estimatedTaxSavings': estimatedTaxSavings,
        'irsForm8829Lines': irsForm8829Lines,
        'auditDefenseRATIONALE': auditDefenseRATIONALE,
      };
}

/// [UNIQUE] Statutory Home Office & Utility Apportionment Engine (IRS Form 8829 & IRC § 280A).
///
/// Computes dual-method optimization (Simplified $5/sq ft vs. Actual Expense ratio)
/// with full telecom/utility apportionment and generates IRS Form 8829 line mappings.
class HomeOfficeApportionmentEngine {
  static const double simplifiedRatePerSqFt = 5.0;
  static const double simplifiedMaxSqFt = 300.0;
  static const double simplifiedMaxDeduction = 1500.0;

  /// Optimizes home office deductions and compares Simplified vs Actual methods.
  static HomeOfficeDeductionResult calculate({
    required HomeOfficeSpace space,
    required HouseholdExpenses expenses,
    double effectiveTaxRate = 0.25, // default 25% combined tax rate
  }) {
    if (!space.qualifiesForDeduction) {
      String reason = 'Space fails statutory IRC § 280A qualification tests: ';
      if (!space.isExclusiveUse) reason += 'Must be used EXCLUSIVELY for business. ';
      if (!space.isRegularUse) reason += 'Must be used on a regular basis. ';
      if (!space.isPrincipalPlaceOfBusiness) reason += 'Must be principal place of business. ';
      if (space.dedicatedOfficeSqFt <= 0) reason += 'Dedicated area must be greater than 0 sq ft.';

      return HomeOfficeDeductionResult(
        isEligible: false,
        ineligibilityReason: reason.trim(),
        businessSqFt: space.dedicatedOfficeSqFt,
        businessPercentage: 0.0,
        simplifiedMethodDeduction: 0.0,
        actualMethodDeduction: 0.0,
        recommendedMethod: 'NONE',
        optimalDeduction: 0.0,
        estimatedTaxSavings: 0.0,
        irsForm8829Lines: {},
        auditDefenseRATIONALE: 'Ineligible for home office deduction: $reason',
      );
    }

    final sqFt = space.dedicatedOfficeSqFt;
    final pct = space.businessPercentage;

    // 1. Simplified Method: $5/sq ft up to 300 sq ft (capped at $1,500)
    final allowableSimplifiedSqFt = min(sqFt, simplifiedMaxSqFt);
    final simplifiedDeduction = min(allowableSimplifiedSqFt * simplifiedRatePerSqFt, simplifiedMaxDeduction);

    // 2. Actual Expense Method:
    // Direct + (Indirect * pct) + (Depreciation * pct) + Business Telecom
    final indirectApportioned = expenses.totalIndirectHouseholdExpenses * pct;
    final depreciationApportioned = expenses.annualAllowableDepreciation * pct;
    final direct = expenses.directOfficeExpenses;
    final telecom = expenses.totalBusinessTelecomExpenses;

    final actualDeduction = direct + indirectApportioned + depreciationApportioned + telecom;

    // Recommendation logic
    final isActualBetter = actualDeduction > simplifiedDeduction;
    final recommended = isActualBetter ? 'ACTUAL' : 'SIMPLIFIED';
    final optimal = isActualBetter ? actualDeduction : simplifiedDeduction;
    final taxSavings = optimal * effectiveTaxRate.clamp(0.0, 0.60);

    // IRS Form 8829 Line Mappings
    final irsLines = <String, dynamic>{
      'Line_1_Office_Area_SqFt': space.dedicatedOfficeSqFt,
      'Line_2_Total_Home_Area_SqFt': space.totalHomeSqFt,
      'Line_3_Business_Percentage': '${(pct * 100).toStringAsFixed(2)}%',
      'Line_9_Direct_Expenses': direct,
      'Line_10_Indirect_Expenses_Total': expenses.totalIndirectHouseholdExpenses,
      'Line_11_Indirect_Expenses_Apportioned': indirectApportioned,
      'Line_27_Business_Depreciation': depreciationApportioned,
      'Line_35_Total_Allowable_Actual': actualDeduction,
      'Schedule_C_Line_30_Simplified_Option': simplifiedDeduction,
      'Recommended_Method': recommended,
      'Max_Tax_Shield_Deduction': optimal,
    };

    final auditRationale = isActualBetter
        ? 'ACTUAL EXPENSES METHOD RECOMMENDED: Yields \$${actualDeduction.toStringAsFixed(2)} deduction '
            'vs \$${simplifiedDeduction.toStringAsFixed(2)} under simplified method (+\$${(actualDeduction - simplifiedDeduction).toStringAsFixed(2)} benefit). '
            'Calculated based on ${(pct * 100).toStringAsFixed(1)}% space apportionment (${space.dedicatedOfficeSqFt.toStringAsFixed(0)} / ${space.totalHomeSqFt.toStringAsFixed(0)} sq ft).'
        : 'SIMPLIFIED METHOD RECOMMENDED: Yields \$${simplifiedDeduction.toStringAsFixed(2)} deduction '
            'with zero receipt substantiation burden for indirect utilities vs \$${actualDeduction.toStringAsFixed(2)} actual expenses.';

    return HomeOfficeDeductionResult(
      isEligible: true,
      businessSqFt: sqFt,
      businessPercentage: pct,
      simplifiedMethodDeduction: simplifiedDeduction,
      actualMethodDeduction: actualDeduction,
      recommendedMethod: recommended,
      optimalDeduction: optimal,
      estimatedTaxSavings: taxSavings,
      irsForm8829Lines: irsLines,
      auditDefenseRATIONALE: auditRationale,
    );
  }
}

