/// Preconfigured rule for partial business expense deductibility.
class TaxApportionmentRule {
  final String categoryPattern;
  final double deductiblePercentage; // e.g. 0.50 for 50%
  final String description;
  final String jurisdiction;

  const TaxApportionmentRule({
    required this.categoryPattern,
    required this.deductiblePercentage,
    required this.description,
    this.jurisdiction = 'GLOBAL',
  });
}

/// Baseline statutory deduction disallowance and apportionment rules.
const List<TaxApportionmentRule> kDefaultTaxRules = [
  TaxApportionmentRule(
    categoryPattern: 'meal|restaurant|dining|food|coffee',
    deductiblePercentage: 0.50, // 50% business meals deduction
    description: 'Statutory 50% business meal deduction limitation',
  ),
  TaxApportionmentRule(
    categoryPattern: 'entertainment|concert|sports|tickets',
    deductiblePercentage: 0.0, // 0% non-deductible entertainment
    description: 'Nondeductible business entertainment expense',
  ),
  TaxApportionmentRule(
    categoryPattern: 'phone|cellular|mobile|internet',
    deductiblePercentage: 0.50, // 50% mixed-use telecommunications
    description: '50% standard mixed personal/business telecommunications allocation',
  ),
  TaxApportionmentRule(
    categoryPattern: 'software|cloud|hosting|domain|saas',
    deductiblePercentage: 1.0, // 100% full business write-off
    description: '100% ordinary and necessary technology business expense',
  ),
  TaxApportionmentRule(
    categoryPattern: 'hardware|laptop|computer|monitor|electronics',
    deductiblePercentage: 1.0, // 100% Section 179 / capital asset
    description: '100% capital equipment write-off',
  ),
];

/// Result of evaluating an expense against tax deduction rules.
class DeductibleEvaluation {
  final double grossAmount;
  final double deductibleAmount;
  final double disallowedAmount;
  final double effectivePercentage;
  final String ruleExplanation;

  const DeductibleEvaluation({
    required this.grossAmount,
    required this.deductibleAmount,
    required this.disallowedAmount,
    required this.effectivePercentage,
    required this.ruleExplanation,
  });
}

/// Engine for evaluating statutory tax disallowance and proportional expense apportionment.
class TaxRulesEngine {
  /// Evaluates the deductible portion of an expense of [amount] in [category].
  static DeductibleEvaluation evaluate({
    required double amount,
    String? category,
    String? description,
    List<TaxApportionmentRule>? customRules,
  }) {
    if (amount <= 0) {
      return const DeductibleEvaluation(
        grossAmount: 0.0,
        deductibleAmount: 0.0,
        disallowedAmount: 0.0,
        effectivePercentage: 1.0,
        ruleExplanation: 'Zero amount',
      );
    }

    final rules = customRules ?? kDefaultTaxRules;
    final text = '${category ?? ''} ${description ?? ''}'.toLowerCase();

    for (final rule in rules) {
      final reg = RegExp(rule.categoryPattern, caseSensitive: false);
      if (reg.hasMatch(text)) {
        final deductible = amount * rule.deductiblePercentage;
        final disallowed = amount - deductible;

        return DeductibleEvaluation(
          grossAmount: amount,
          deductibleAmount: deductible,
          disallowedAmount: disallowed,
          effectivePercentage: rule.deductiblePercentage,
          ruleExplanation: rule.description,
        );
      }
    }

    // Default: 100% deductible standard operating expense
    return DeductibleEvaluation(
      grossAmount: amount,
      deductibleAmount: amount,
      disallowedAmount: 0.0,
      effectivePercentage: 1.0,
      ruleExplanation: '100% standard business operating expense',
    );
  }
}

