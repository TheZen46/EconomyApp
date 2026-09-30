import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:t_aidy/features/invoices/data/models/invoice_model.dart';
import 'package:t_aidy/features/invoices/data/providers/invoices_provider.dart';
import 'package:t_aidy/features/receipt_scanning/domain/entities/receipt.dart';
import 'package:t_aidy/features/receipt_scanning/presentation/providers/receipt_provider.dart';
import 'package:t_aidy/features/mileage/domain/mileage_engine.dart';

/// Tax profile and statutory parameters of a specific state/local jurisdiction.
class JurisdictionProfile {
  final String stateCode; // e.g. 'CA', 'NY', 'TX', 'FL', 'IL', 'WA'
  final String stateName;
  final double flatOrTopTaxRate; // e.g. 0.093 for CA, 0.0685 for NY, 0.0 for TX
  final double economicNexusRevenueThreshold; // e.g. 100,000 or 500,000
  final bool hasPersonalIncomeTax;
  final double standardDeduction;

  const JurisdictionProfile({
    required this.stateCode,
    required this.stateName,
    required this.flatOrTopTaxRate,
    this.economicNexusRevenueThreshold = 100000.0,
    required this.hasPersonalIncomeTax,
    this.standardDeduction = 0.0,
  });
}

/// Standard predefined US State profiles.
const Map<String, JurisdictionProfile> kKnownJurisdictions = {
  'CA': JurisdictionProfile(
    stateCode: 'CA',
    stateName: 'California',
    flatOrTopTaxRate: 0.093,
    economicNexusRevenueThreshold: 500000.0,
    hasPersonalIncomeTax: true,
    standardDeduction: 5202.0,
  ),
  'NY': JurisdictionProfile(
    stateCode: 'NY',
    stateName: 'New York',
    flatOrTopTaxRate: 0.0685,
    economicNexusRevenueThreshold: 100000.0,
    hasPersonalIncomeTax: true,
    standardDeduction: 8000.0,
  ),
  'TX': JurisdictionProfile(
    stateCode: 'TX',
    stateName: 'Texas',
    flatOrTopTaxRate: 0.0,
    economicNexusRevenueThreshold: 500000.0,
    hasPersonalIncomeTax: false,
  ),
  'FL': JurisdictionProfile(
    stateCode: 'FL',
    stateName: 'Florida',
    flatOrTopTaxRate: 0.0,
    economicNexusRevenueThreshold: 100000.0,
    hasPersonalIncomeTax: false,
  ),
  'WA': JurisdictionProfile(
    stateCode: 'WA',
    stateName: 'Washington',
    flatOrTopTaxRate: 0.0,
    economicNexusRevenueThreshold: 100000.0,
    hasPersonalIncomeTax: false,
  ),
  'IL': JurisdictionProfile(
    stateCode: 'IL',
    stateName: 'Illinois',
    flatOrTopTaxRate: 0.0495,
    economicNexusRevenueThreshold: 100000.0,
    hasPersonalIncomeTax: true,
    standardDeduction: 2625.0,
  ),
  'CO': JurisdictionProfile(
    stateCode: 'CO',
    stateName: 'Colorado',
    flatOrTopTaxRate: 0.0440,
    economicNexusRevenueThreshold: 100000.0,
    hasPersonalIncomeTax: true,
    standardDeduction: 0.0,
  ),
};

/// Apportionment calculation for a single jurisdiction.
class JurisdictionApportionment {
  final JurisdictionProfile profile;
  final double grossRevenue;
  final double directExpenses;
  final double mileageDeduction;
  final double totalDeductions;
  final double netStateTaxableIncome;
  final double estimatedStateTax;
  final double apportionmentRatio; // Percentage of total business revenue
  final bool hasEconomicNexus;
  final bool filingRequired;

  const JurisdictionApportionment({
    required this.profile,
    required this.grossRevenue,
    required this.directExpenses,
    required this.mileageDeduction,
    required this.totalDeductions,
    required this.netStateTaxableIncome,
    required this.estimatedStateTax,
    required this.apportionmentRatio,
    required this.hasEconomicNexus,
    required this.filingRequired,
  });
}

/// Consolidated Multi-Jurisdiction SALT Apportionment Summary.
class SaltComplianceSummary {
  final int fiscalYear;
  final String primaryHomeState;
  final double totalApportionedRevenue;
  final double totalApportionedExpenses;
  final double totalEstimatedStateTaxLiability;
  final List<JurisdictionApportionment> stateApportionments;
  final List<String> requiredStateReturns;

  const SaltComplianceSummary({
    required this.fiscalYear,
    required this.primaryHomeState,
    required this.totalApportionedRevenue,
    required this.totalApportionedExpenses,
    required this.totalEstimatedStateTaxLiability,
    required this.stateApportionments,
    required this.requiredStateReturns,
  });
}

/// Autonomous State & Local Tax (SALT) Apportionment Engine.
class SaltApportionmentEngine {
  /// Apportions revenues and expenses across physical and economic state jurisdictions.
  static SaltComplianceSummary calculateApportionment({
    required List<InvoiceModel> invoices,
    required List<Receipt> receipts,
    List<MileageTrip> mileageTrips = const [],
    String primaryHomeState = 'CA',
    int? fiscalYear,
    Map<String, String>? clientStateMapping,
  }) {
    final targetYear = fiscalYear ?? DateTime.now().year;

    // 1. Group Invoices by Destination State
    double totalRevenue = 0.0;
    final Map<String, double> revenueByState = {};

    for (final inv in invoices) {
      if (inv.status == InvoiceStatus.settled && inv.issuedDate.year == targetYear) {
        final stateCode = _resolveInvoiceState(inv, clientStateMapping, primaryHomeState);
        revenueByState[stateCode] = (revenueByState[stateCode] ?? 0.0) + inv.amount;
        totalRevenue += inv.amount;
      }
    }

    // 2. Group Direct Expenses by State
    double totalExpenses = 0.0;
    final Map<String, double> expensesByState = {};

    for (final r in receipts) {
      if (r.date.year == targetYear) {
        final stateCode = primaryHomeState; // By default localized to home state or merchant parse
        expensesByState[stateCode] = (expensesByState[stateCode] ?? 0.0) + r.totalAmount;
        totalExpenses += r.totalAmount;
      }
    }

    // 3. Group Mileage Deductions by State
    final Map<String, double> mileageByState = {};
    for (final trip in mileageTrips) {
      if (trip.date.year == targetYear) {
        final stateCode = primaryHomeState;
        mileageByState[stateCode] = (mileageByState[stateCode] ?? 0.0) + trip.totalDeductible;
      }
    }

    // Ensure primary home state is present in jurisdiction map
    if (!revenueByState.containsKey(primaryHomeState) && totalRevenue > 0) {
      revenueByState[primaryHomeState] = 0.0;
    }

    // 4. Calculate Per-State Apportionments
    final List<JurisdictionApportionment> apportionments = [];
    final List<String> filingRequirements = [];
    double totalStateTax = 0.0;

    final allStates = {...revenueByState.keys, ...expensesByState.keys, primaryHomeState};

    for (final code in allStates) {
      final profile = kKnownJurisdictions[code] ??
          JurisdictionProfile(
            stateCode: code,
            stateName: 'State ($code)',
            flatOrTopTaxRate: 0.05,
            hasPersonalIncomeTax: true,
          );

      final grossRev = revenueByState[code] ?? 0.0;
      final directExp = expensesByState[code] ?? 0.0;
      final mileageDed = mileageByState[code] ?? 0.0;
      final totalDed = directExp + mileageDed;

      final ratio = totalRevenue > 0 ? (grossRev / totalRevenue) : 0.0;

      // Net State Taxable Income
      double netTaxable = (grossRev - totalDed) > 0 ? (grossRev - totalDed) : 0.0;
      if (profile.standardDeduction > 0 && netTaxable > profile.standardDeduction) {
        netTaxable -= profile.standardDeduction;
      }

      final stateTax = profile.hasPersonalIncomeTax ? (netTaxable * profile.flatOrTopTaxRate) : 0.0;
      totalStateTax += stateTax;

      final hasNexus = grossRev >= profile.economicNexusRevenueThreshold || code == primaryHomeState;
      final requiresFiling = (grossRev > 0 && profile.hasPersonalIncomeTax) || code == primaryHomeState;

      if (requiresFiling) {
        filingRequirements.add('${profile.stateName} (${profile.stateCode})');
      }

      apportionments.add(JurisdictionApportionment(
        profile: profile,
        grossRevenue: grossRev,
        directExpenses: directExp,
        mileageDeduction: mileageDed,
        totalDeductions: totalDed,
        netStateTaxableIncome: netTaxable,
        estimatedStateTax: stateTax,
        apportionmentRatio: ratio,
        hasEconomicNexus: hasNexus,
        filingRequired: requiresFiling,
      ));
    }

    // Sort apportionments: home state first, then by revenue descending
    apportionments.sort((a, b) {
      if (a.profile.stateCode == b.profile.stateCode) return 0;
      if (a.profile.stateCode == primaryHomeState) return -1;
      if (b.profile.stateCode == primaryHomeState) return 1;
      return b.grossRevenue.compareTo(a.grossRevenue);
    });

    return SaltComplianceSummary(
      fiscalYear: targetYear,
      primaryHomeState: primaryHomeState,
      totalApportionedRevenue: totalRevenue,
      totalApportionedExpenses: totalExpenses,
      totalEstimatedStateTaxLiability: totalStateTax,
      stateApportionments: apportionments,
      requiredStateReturns: filingRequirements,
    );
  }

  static String _resolveInvoiceState(
    InvoiceModel invoice,
    Map<String, String>? clientStateMapping,
    String defaultState,
  ) {
    if (clientStateMapping != null) {
      final match = clientStateMapping[invoice.clientName.trim().toLowerCase()];
      if (match != null && match.isNotEmpty) {
        return match.toUpperCase();
      }
    }

    final combinedText = '${invoice.clientName} ${invoice.notes}';

    // 1. Look for explicit parentheses e.g. "(TX)", "(CA)", "(NY)"
    final parenRegex = RegExp(r'\(([A-Z]{2})\)');
    final parenMatch = parenRegex.firstMatch(combinedText);
    if (parenMatch != null && kKnownJurisdictions.containsKey(parenMatch.group(1)!)) {
      return parenMatch.group(1)!;
    }

    // 2. Look for standalone uppercase state codes (case-sensitive)
    final codeRegex = RegExp(r'\b(CA|NY|TX|FL|IL|WA|CO)\b');
    final codeMatch = codeRegex.firstMatch(combinedText);
    if (codeMatch != null) {
      return codeMatch.group(1)!;
    }

    return defaultState;
  }
}

/// Provider for Multi-Jurisdiction SALT Apportionment.
final saltComplianceProvider = Provider<SaltComplianceSummary>((ref) {
  final invoices = ref.watch(invoicesProvider);
  final receipts = ref.watch(receiptListProvider).valueOrNull ?? [];

  return SaltApportionmentEngine.calculateApportionment(
    invoices: invoices,
    receipts: receipts,
    primaryHomeState: 'CA',
    fiscalYear: DateTime.now().year,
  );
});

