import 'dart:math';

/// Filing status for Section 199A QBI calculations.
enum TaxFilingStatus {
  single,
  marriedFilingJointly,
  marriedFilingSeparately,
  headOfHousehold,
}

/// Nature of the business trade under IRC § 199A(d)(2).
enum BusinessTradeType {
  /// Specified Service Trade or Business (Law, Accounting, Health, Consulting, Financial Services, Performing Arts, Athletics)
  sstb,

  /// Non-SSTB qualified trade or business (Tech, Software, Retail, Manufacturing, Architecture, Engineering, etc.)
  nonSstb,
}

/// Input parameters for Section 199A Qualified Business Income deduction calculation.
class QbiCalculationParams {
  final double netQualifiedBusinessIncome; // Net business profit (QBI)
  final double totalTaxableIncome; // Overall taxable income before QBI deduction
  final double netCapitalGains; // Net capital gains + qualified dividends
  final TaxFilingStatus filingStatus;
  final BusinessTradeType tradeType;
  final double w2WagesPaid; // W-2 wages paid by business (e.g. if S-Corp or employing contractors/staff)
  final double unadjustedBasisProperty; // UBIA of qualified depreciable property (Section 179 assets, equipment)
  final int taxYear;

  const QbiCalculationParams({
    required this.netQualifiedBusinessIncome,
    required this.totalTaxableIncome,
    this.netCapitalGains = 0.0,
    required this.filingStatus,
    required this.tradeType,
    this.w2WagesPaid = 0.0,
    this.unadjustedBasisProperty = 0.0,
    this.taxYear = 2026,
  });
}

/// Comprehensive outcome of Section 199A QBI statutory evaluation.
class QbiCalculationResult {
  final double grossTentativeDeduction; // 20% of net QBI
  final double allowableQbiDeduction; // Final legally allowable deduction
  final double effectiveDeductionRate; // As a percentage of QBI
  final double taxSavings; // At effective marginal rate
  final bool isSubjectToWageUbiaLimit;
  final bool isSubjectToSstbPhaseOut;
  final double applicablePercentage; // 0.0 to 1.0 for phase-out
  final double wageUbiaCap;
  final double overallTaxableIncomeCap;
  final String auditDefenseNotes;

  const QbiCalculationResult({
    required this.grossTentativeDeduction,
    required this.allowableQbiDeduction,
    required this.effectiveDeductionRate,
    required this.taxSavings,
    required this.isSubjectToWageUbiaLimit,
    required this.isSubjectToSstbPhaseOut,
    required this.applicablePercentage,
    required this.wageUbiaCap,
    required this.overallTaxableIncomeCap,
    required this.auditDefenseNotes,
  });

  Map<String, dynamic> toJson() => {
        'grossTentativeDeduction': grossTentativeDeduction,
        'allowableQbiDeduction': allowableQbiDeduction,
        'effectiveDeductionRate': effectiveDeductionRate,
        'taxSavings': taxSavings,
        'isSubjectToWageUbiaLimit': isSubjectToWageUbiaLimit,
        'isSubjectToSstbPhaseOut': isSubjectToSstbPhaseOut,
        'applicablePercentage': applicablePercentage,
        'wageUbiaCap': wageUbiaCap,
        'overallTaxableIncomeCap': overallTaxableIncomeCap,
        'auditDefenseNotes': auditDefenseNotes,
      };
}

/// [UNIQUE] Section 199A Qualified Business Income (QBI) Deduction Engine.
///
/// Implements full TCJA IRC § 199A statutory logic including SSTB phase-outs,
/// W-2 wage & UBIA limitation formulas, and overall taxable income caps.
class QbiDeductionEngine {
  // 2026 Statutory Thresholds (Inflation adjusted)
  static const double thresholdSingle = 191950.0;
  static const double phaseOutWidthSingle = 50000.0; // Ceiling: $241,950

  static const double thresholdMfj = 383900.0;
  static const double phaseOutWidthMfj = 100000.0; // Ceiling: $483,900

  /// Computes the exact statutory QBI deduction under IRC § 199A.
  static QbiCalculationResult calculate(
    QbiCalculationParams params, {
    double marginalTaxRate = 0.24,
  }) {
    final qbi = max(0.0, params.netQualifiedBusinessIncome);
    final taxableIncome = max(0.0, params.totalTaxableIncome);
    final capitalGains = max(0.0, params.netCapitalGains);

    if (qbi <= 0 || taxableIncome <= 0) {
      return const QbiCalculationResult(
        grossTentativeDeduction: 0.0,
        allowableQbiDeduction: 0.0,
        effectiveDeductionRate: 0.0,
        taxSavings: 0.0,
        isSubjectToWageUbiaLimit: false,
        isSubjectToSstbPhaseOut: false,
        applicablePercentage: 1.0,
        wageUbiaCap: 0.0,
        overallTaxableIncomeCap: 0.0,
        auditDefenseNotes: 'No qualifying business income or taxable income to deduct.',
      );
    }

    // 1. Initial 20% Tentative QBI Deduction
    final tentativeDeduction = qbi * 0.20;

    // 2. Determine Statutory Income Thresholds
    final isMfj = params.filingStatus == TaxFilingStatus.marriedFilingJointly;
    final lowerThreshold = isMfj ? thresholdMfj : thresholdSingle;
    final phaseOutWidth = isMfj ? phaseOutWidthMfj : phaseOutWidthSingle;
    final upperCeiling = lowerThreshold + phaseOutWidth;

    double allowableDeduction = tentativeDeduction;
    double applicablePct = 1.0;
    bool isWageUbiaSubject = false;
    bool isSstbSubject = false;

    // Wage & UBIA Limitation formula: Greater of (50% W-2) or (25% W-2 + 2.5% UBIA)
    final wageLimit1 = params.w2WagesPaid * 0.50;
    final wageLimit2 = (params.w2WagesPaid * 0.25) + (params.unadjustedBasisProperty * 0.025);
    final wageUbiaLimit = max(wageLimit1, wageLimit2);

    String auditRationale = '';

    // Zone A: Taxable income <= Lower Threshold (Full 20% deduction for SSTB and Non-SSTB)
    if (taxableIncome <= lowerThreshold) {
      allowableDeduction = tentativeDeduction;
      auditRationale = 'ZONE A (Below \$${lowerThreshold.toStringAsFixed(0)} threshold): Full 20% deduction allowable regardless of SSTB classification or W-2 wage caps.';
    }
    // Zone B: In Phase-out Range (Between Lower Threshold and Upper Ceiling)
    else if (taxableIncome > lowerThreshold && taxableIncome <= upperCeiling) {
      final excess = taxableIncome - lowerThreshold;
      final phaseOutFraction = excess / phaseOutWidth;
      applicablePct = (1.0 - phaseOutFraction).clamp(0.0, 1.0);

      if (params.tradeType == BusinessTradeType.sstb) {
        isSstbSubject = true;
        // SSTB reduces QBI and tentative deduction by applicable percentage
        final reducedQbi = qbi * applicablePct;
        final reducedTentative = reducedQbi * 0.20;
        final reducedWageLimit = wageUbiaLimit * applicablePct;

        final excessTentativeOverWage = max(0.0, reducedTentative - reducedWageLimit);
        final wageReduction = excessTentativeOverWage * phaseOutFraction;

        allowableDeduction = max(0.0, reducedTentative - wageReduction);
        auditRationale = 'ZONE B (SSTB Phase-out): Income of \$${taxableIncome.toStringAsFixed(0)} reduces allowable deduction by ${(phaseOutFraction * 100).toStringAsFixed(1)}% due to Specified Service Trade rules.';
      } else {
        isWageUbiaSubject = true;
        // Non-SSTB phase-in of wage/UBIA limit
        if (tentativeDeduction > wageUbiaLimit) {
          final excessDeduction = tentativeDeduction - wageUbiaLimit;
          final reduction = excessDeduction * phaseOutFraction;
          allowableDeduction = max(0.0, tentativeDeduction - reduction);
          auditRationale = 'ZONE B (Non-SSTB Phase-in): Partial W-2 wage/UBIA limit applied with reduction of \$${reduction.toStringAsFixed(2)}.';
        } else {
          allowableDeduction = tentativeDeduction;
          auditRationale = 'ZONE B: Tentative deduction does not exceed W-2 wage limitation.';
        }
      }
    }
    // Zone C: Taxable income > Upper Ceiling (Fully phased out for SSTB; Wage/UBIA cap for Non-SSTB)
    else {
      if (params.tradeType == BusinessTradeType.sstb) {
        isSstbSubject = true;
        applicablePct = 0.0;
        allowableDeduction = 0.0;
        auditRationale = 'ZONE C (SSTB Disallowed): Taxable income exceeds \$${upperCeiling.toStringAsFixed(0)} ceiling. Specified Service Trade deduction is fully phased out.';
      } else {
        isWageUbiaSubject = true;
        applicablePct = 0.0;
        allowableDeduction = min(tentativeDeduction, wageUbiaLimit);
        auditRationale = 'ZONE C (Non-SSTB Fully Capped): Deduction fully limited to greater of 50% W-2 wages or 25% W-2 + 2.5% UBIA property (\$${wageUbiaLimit.toStringAsFixed(2)}).';
      }
    }

    // 3. Overall Taxable Income Limitation: 20% of (Taxable Income - Net Capital Gain)
    final overallCap = max(0.0, (taxableIncome - capitalGains) * 0.20);
    if (allowableDeduction > overallCap) {
      auditRationale += ' Overall taxable income cap applied (capped at 20% of taxable income less net capital gains: \$${overallCap.toStringAsFixed(2)}).';
      allowableDeduction = overallCap;
    }

    final effectiveRate = qbi > 0 ? (allowableDeduction / qbi) * 100 : 0.0;
    final savings = allowableDeduction * marginalTaxRate.clamp(0.0, 0.50);

    return QbiCalculationResult(
      grossTentativeDeduction: tentativeDeduction,
      allowableQbiDeduction: allowableDeduction,
      effectiveDeductionRate: effectiveRate,
      taxSavings: savings,
      isSubjectToWageUbiaLimit: isWageUbiaSubject,
      isSubjectToSstbPhaseOut: isSstbSubject,
      applicablePercentage: applicablePct,
      wageUbiaCap: wageUbiaLimit,
      overallTaxableIncomeCap: overallCap,
      auditDefenseNotes: auditRationale.trim(),
    );
  }
}

