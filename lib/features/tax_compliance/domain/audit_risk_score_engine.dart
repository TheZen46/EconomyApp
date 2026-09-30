import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:t_aidy/features/invoices/data/models/invoice_model.dart';
import 'package:t_aidy/features/invoices/data/providers/invoices_provider.dart';
import 'package:t_aidy/features/receipt_scanning/domain/entities/receipt.dart';
import 'package:t_aidy/features/receipt_scanning/presentation/providers/receipt_provider.dart';
import 'package:t_aidy/features/tax_compliance/domain/contractor_compliance_engine.dart';

/// Severity of a detected tax audit trigger.
enum AuditRiskSeverity {
  low,
  moderate,
  high,
  critical,
}

/// A specific IRS / Tax Authority audit risk factor.
class AuditRiskFactor {
  final String title;
  final String description;
  final AuditRiskSeverity severity;
  final double scoreImpact; // Points added to overall audit risk index
  final String mitigationAdvice;

  const AuditRiskFactor({
    required this.title,
    required this.description,
    required this.severity,
    required this.scoreImpact,
    required this.mitigationAdvice,
  });
}

/// Consolidated Audit Risk Assessment Report.
class AuditRiskAssessment {
  final int overallRiskScore; // 0 to 100
  final String riskLevel; // 'Low' | 'Moderate' | 'High' | 'Critical'
  final List<AuditRiskFactor> riskFactors;
  final double roundNumbersRatio; // % of expenses that are round multiples of $10 or $100
  final double mealsToRevenueRatio; // % of revenue spent on meals/entertainment
  final double receiptsMissingDocumentationCount;
  final int contractorsMissingW9Count;
  final bool hasDefensibleAuditReadiness;

  const AuditRiskAssessment({
    required this.overallRiskScore,
    required this.riskLevel,
    required this.riskFactors,
    required this.roundNumbersRatio,
    required this.mealsToRevenueRatio,
    required this.receiptsMissingDocumentationCount,
    required this.contractorsMissingW9Count,
    required this.hasDefensibleAuditReadiness,
  });
}

/// Autonomous, on-device engine for computing IRS / Statutory Tax Audit Risk Indices (DIF scoring).
class AuditRiskScoreEngine {
  AuditRiskScoreEngine._();

  /// Evaluates a user's transactions and calculates their statutory audit risk profile.
  static AuditRiskAssessment evaluateAuditRisk({
    required List<Receipt> receipts,
    required List<InvoiceModel> invoices,
    int? fiscalYear,
  }) {
    final targetYear = fiscalYear ?? DateTime.now().year;

    final targetReceipts = receipts.where((r) => r.date.year == targetYear).toList();
    final targetInvoices = invoices.where((i) => i.issuedDate.year == targetYear && i.status == InvoiceStatus.settled).toList();

    final double grossRevenue = targetInvoices.fold(0.0, (sum, i) => sum + i.amount);
    final double totalExpenses = targetReceipts.fold(0.0, (sum, r) => sum + r.totalAmount);

    final factors = <AuditRiskFactor>[];
    double riskScore = 0.0;

    // 1. Audit Trigger: Round Number Ratio (Estimates vs Exact Receipts)
    int roundExpensesCount = 0;
    for (final r in targetReceipts) {
      if (r.totalAmount >= 20.0 && (r.totalAmount % 10.0 == 0.0 || r.totalAmount % 50.0 == 0.0)) {
        roundExpensesCount++;
      }
    }
    final roundRatio = targetReceipts.isNotEmpty ? (roundExpensesCount / targetReceipts.length) : 0.0;
    if (roundRatio > 0.35 && targetReceipts.length >= 5) {
      final impact = (roundRatio * 30.0).clamp(5.0, 25.0);
      riskScore += impact;
      factors.add(AuditRiskFactor(
        title: 'High Ratio of Round-Number Deductions (${(roundRatio * 100).toStringAsFixed(0)}%)',
        description: 'IRS statistical algorithms (DIF) flag returns where a large percentage of expense amounts end in exact \$0.00, suggesting estimates rather than receipts.',
        severity: roundRatio > 0.50 ? AuditRiskSeverity.high : AuditRiskSeverity.moderate,
        scoreImpact: impact,
        mitigationAdvice: 'Ensure you retain itemized receipts showing exact cents for all business transactions.',
      ));
    }

    // 2. Audit Trigger: Disproportionately High Meals & Entertainment Ratio
    double mealsTotal = 0.0;
    for (final r in targetReceipts) {
      for (final item in r.items) {
        final cat = (item.mainCategory ?? '').toLowerCase();
        if (cat.contains('meal') || cat.contains('food') || cat.contains('dining') || cat.contains('entertainment')) {
          mealsTotal += item.totalPrice;
        }
      }
    }
    final mealsRatio = grossRevenue > 0 ? (mealsTotal / grossRevenue) : 0.0;
    if (mealsRatio > 0.20 && mealsTotal > 1000.0) {
      final impact = (mealsRatio * 40.0).clamp(10.0, 30.0);
      riskScore += impact;
      factors.add(AuditRiskFactor(
        title: 'Disproportionate Meals & Dining Deductions (${(mealsRatio * 100).toStringAsFixed(0)}% of Revenue)',
        description: 'Business meals exceeding 20% of gross receipts are statistically scrutinized for disguised personal consumption.',
        severity: AuditRiskSeverity.high,
        scoreImpact: impact,
        mitigationAdvice: 'Maintain business purpose logs and attendee names for all dining expenses under IRC §274.',
      ));
    }

    // 3. Audit Trigger: Subcontractor 1099-NEC & W-9 Non-Compliance
    final contractorSummary = ContractorComplianceEngine.analyzeReceipts(
      receipts: targetReceipts,
      fiscalYear: targetYear,
    );
    final missingW9s = contractorSummary.missingW9Vendors.length;
    if (missingW9s > 0) {
      final impact = (missingW9s * 15.0).clamp(15.0, 35.0);
      riskScore += impact;
      factors.add(AuditRiskFactor(
        title: 'Subcontractors Paid ≥ \$600 Missing Form W-9 ($missingW9s Vendors)',
        description: 'Paying non-corporate subcontractors over \$600 without a TIN/W-9 on file triggers failure-to-file penalties and audit scrutiny.',
        severity: AuditRiskSeverity.critical,
        scoreImpact: impact,
        mitigationAdvice: 'Request signed Form W-9s from all contractors before issuing year-end Form 1099-NEC.',
      ));
    }

    // 4. Audit Trigger: Negative Net Income / Schedule C Loss
    final netIncome = grossRevenue - totalExpenses;
    if (grossRevenue > 5000.0 && netIncome < 0) {
      riskScore += 20.0;
      factors.add(const AuditRiskFactor(
        title: 'Net Schedule C Business Loss',
        description: 'Reporting ongoing net operating losses on freelance income invites IRS Hobby Loss rules (IRC §183) scrutiny.',
        severity: AuditRiskSeverity.moderate,
        scoreImpact: 20.0,
        mitigationAdvice: 'Ensure you document a clear profit motive and maintain separate business bank accounts.',
      ));
    }

    final int finalScore = riskScore.clamp(0.0, 100.0).round();
    String level = 'Low';
    if (finalScore >= 65) {
      level = 'Critical';
    } else if (finalScore >= 40) {
      level = 'High';
    } else if (finalScore >= 20) {
      level = 'Moderate';
    }

    return AuditRiskAssessment(
      overallRiskScore: finalScore,
      riskLevel: level,
      riskFactors: factors,
      roundNumbersRatio: roundRatio,
      mealsToRevenueRatio: mealsRatio,
      receiptsMissingDocumentationCount: 0.0,
      contractorsMissingW9Count: missingW9s,
      hasDefensibleAuditReadiness: finalScore <= 30,
    );
  }
}

/// Provider for statutory audit risk evaluation.
final auditRiskAssessmentProvider = Provider<AuditRiskAssessment>((ref) {
  final receipts = ref.watch(receiptListProvider).valueOrNull ?? [];
  final invoices = ref.watch(invoicesProvider);

  return AuditRiskScoreEngine.evaluateAuditRisk(
    receipts: receipts,
    invoices: invoices,
    fiscalYear: DateTime.now().year,
  );
});

