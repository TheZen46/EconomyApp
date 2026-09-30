import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:t_aidy/features/invoices/data/models/invoice_model.dart';
import 'package:t_aidy/features/invoices/data/providers/invoices_provider.dart';
import 'package:t_aidy/features/receipt_scanning/presentation/providers/receipt_provider.dart';
import 'package:t_aidy/features/boxes/data/providers/boxes_provider.dart';

/// Predefined statutory tax profiles for freelance and solopreneur withholding.
class TaxProfilePreset {
  final String id;
  final String name;
  final double defaultRate;
  final String jurisdiction;
  final String description;

  const TaxProfilePreset({
    required this.id,
    required this.name,
    required this.defaultRate,
    required this.jurisdiction,
    required this.description,
  });
}

const List<TaxProfilePreset> kTaxProfilePresets = [
  TaxProfilePreset(
    id: 'us_1099',
    name: 'US 1099 Solopreneur (25%)',
    defaultRate: 0.25,
    jurisdiction: 'USA',
    description: '15.3% Self-Employment (FICA) + estimated 10% Federal/State bracket reserve.',
  ),
  TaxProfilePreset(
    id: 'us_high',
    name: 'US High-Bracket Solopreneur (35%)',
    defaultRate: 0.35,
    jurisdiction: 'USA',
    description: '15.3% Self-Employment (FICA) + 20% upper Federal/State income tax reserve.',
  ),
  TaxProfilePreset(
    id: 'it_forfettario',
    name: 'Italy Regime Forfettario (15%)',
    defaultRate: 0.15,
    jurisdiction: 'ITA',
    description: '15% Imposta Sostitutiva flat tax rate for freelance regimes.',
  ),
  TaxProfilePreset(
    id: 'it_startup',
    name: 'Italy Forfettario Start-up (5%)',
    defaultRate: 0.05,
    jurisdiction: 'ITA',
    description: '5% Imposta Sostitutiva reduced rate for first 5 years of activity.',
  ),
  TaxProfilePreset(
    id: 'uk_sole_trader',
    name: 'UK Sole Trader (29%)',
    defaultRate: 0.29,
    jurisdiction: 'GBR',
    description: 'Class 4 National Insurance + 20% Basic Rate Income Tax buffer.',
  ),
  TaxProfilePreset(
    id: 'de_freiberufler',
    name: 'Germany Freiberufler (30%)',
    defaultRate: 0.30,
    jurisdiction: 'DEU',
    description: 'Progressive Einkommensteuer base bracket estimated reserve.',
  ),
  TaxProfilePreset(
    id: 'custom',
    name: 'Custom Auto-Stash Rate',
    defaultRate: 0.20,
    jurisdiction: 'GLOBAL',
    description: 'User-configured custom tax buffer allocation.',
  ),
];

/// Immutable state containing the complete real-time tax shield calculation.
class TaxShieldCalculation {
  /// Total collected freelance revenue from paid and active invoices.
  final double grossRevenue;

  /// Total sum of all expense receipts.
  final double totalExpenses;

  /// Business deductible expenses that reduce taxable net income.
  final double totalDeductibleExpenses;

  /// Net taxable income = max(0, grossRevenue - totalDeductibleExpenses).
  final double netTaxableIncome;

  /// Effective tax withholding rate in range [0.0, 1.0] (e.g. 0.25 for 25%).
  final double effectiveTaxRate;

  /// Total tax reserve needed to avoid quarterly shortfall (netTaxableIncome * effectiveTaxRate).
  final double lockedTaxShield;

  /// Amount saved in taxes through business deductions (totalDeductibleExpenses * effectiveTaxRate).
  final double taxSavingsEarned;

  /// Real post-tax, post-expense disposable balance safe to spend or withdraw.
  final double safeToSpend;

  /// Current fiscal quarter (1..4).
  final int currentQuarter;

  /// Current fiscal year.
  final int currentYear;

  /// Target deadline for current quarterly estimated tax payment.
  final DateTime nextQuarterDeadline;

  /// Days remaining until quarterly tax payment deadline.
  final int daysUntilDeadline;

  /// Active tax profile metadata.
  final TaxProfilePreset profile;

  const TaxShieldCalculation({
    required this.grossRevenue,
    required this.totalExpenses,
    required this.totalDeductibleExpenses,
    required this.netTaxableIncome,
    required this.effectiveTaxRate,
    required this.lockedTaxShield,
    required this.taxSavingsEarned,
    required this.safeToSpend,
    required this.currentQuarter,
    required this.currentYear,
    required this.nextQuarterDeadline,
    required this.daysUntilDeadline,
    required this.profile,
  });
}

/// Provider for active tax profile preset selection.
final selectedTaxProfileIdProvider = StateProvider<String>((ref) => 'us_1099');

/// Primary provider calculating real-time Live Tax Withholding Shield and Safe-to-Spend balance.
final taxShieldCalculationProvider = Provider<TaxShieldCalculation>((ref) {
  final invoices = ref.watch(invoicesProvider);
  final receiptsAsync = ref.watch(receiptListProvider);
  final receipts = receiptsAsync.valueOrNull ?? [];
  final boxes = ref.watch(boxesProvider);
  final customRate = ref.watch(taxNestRateProvider);
  final selectedProfileId = ref.watch(selectedTaxProfileIdProvider);

  final profile = kTaxProfilePresets.firstWhere(
    (p) => p.id == selectedProfileId,
    orElse: () => kTaxProfilePresets.first,
  );

  final effectiveRate = (selectedProfileId == 'custom') ? customRate : profile.defaultRate;

  // 1. Calculate Gross Freelance Revenue (settled invoices + sent invoices)
  double grossRevenue = 0.0;
  for (final inv in invoices) {
    if (inv.status == InvoiceStatus.settled || inv.status == InvoiceStatus.sent) {
      grossRevenue += inv.amount;
    }
  }

  // 2. Classify Deductible vs Personal Expenses
  double totalExpenses = 0.0;
  double deductibleExpenses = 0.0;

  final businessBoxIds = boxes.where((b) => b.id != 'main').map((b) => b.id).toSet();

  for (final r in receipts) {
    totalExpenses += r.totalAmount;

    final isBusinessBox = r.boxId != null && businessBoxIds.contains(r.boxId);
    final isDeductibleCategory = _isDeductibleTaxCategory(r.category);

    if (isBusinessBox || isDeductibleCategory) {
      deductibleExpenses += r.totalAmount;
    } else {
      // Check individual line items for granular box or category assignment
      double itemDeductibleSum = 0.0;
      for (final item in r.items) {
        if ((item.boxId != null && businessBoxIds.contains(item.boxId)) ||
            _isDeductibleTaxCategory(item.mainCategory ?? item.subCategory)) {
          itemDeductibleSum += item.unitPrice * item.quantity;
        }
      }
      deductibleExpenses += itemDeductibleSum;
    }
  }

  // 3. Taxable Net and Reserve Calculations
  final netTaxable = (grossRevenue > deductibleExpenses) ? (grossRevenue - deductibleExpenses) : 0.0;
  final lockedTaxShield = netTaxable * effectiveRate;
  final taxSavingsEarned = deductibleExpenses * effectiveRate;
  
  // Safe-to-spend = Gross Revenue - Locked Tax Shield - Total Expenses
  final rawSafeToSpend = grossRevenue - lockedTaxShield - totalExpenses;
  final safeToSpend = rawSafeToSpend > 0.0 ? rawSafeToSpend : 0.0;

  // 4. Fiscal Quarter & Deadline Calculation
  final now = DateTime.now();
  final currentQuarter = ((now.month - 1) ~/ 3) + 1;
  final currentYear = now.year;

  final nextDeadline = _getQuarterlyTaxDeadline(currentQuarter, currentYear);
  final daysUntil = nextDeadline.difference(now).inDays;

  return TaxShieldCalculation(
    grossRevenue: grossRevenue,
    totalExpenses: totalExpenses,
    totalDeductibleExpenses: deductibleExpenses,
    netTaxableIncome: netTaxable,
    effectiveTaxRate: effectiveRate,
    lockedTaxShield: lockedTaxShield,
    taxSavingsEarned: taxSavingsEarned,
    safeToSpend: safeToSpend,
    currentQuarter: currentQuarter,
    currentYear: currentYear,
    nextQuarterDeadline: nextDeadline,
    daysUntilDeadline: daysUntil >= 0 ? daysUntil : 0,
    profile: profile,
  );
});

DateTime _getQuarterlyTaxDeadline(int quarter, int year) {
  switch (quarter) {
    case 1:
      return DateTime(year, 4, 15);
    case 2:
      return DateTime(year, 6, 15);
    case 3:
      return DateTime(year, 9, 15);
    case 4:
    default:
      return DateTime(year + 1, 1, 15);
  }
}

bool _isDeductibleTaxCategory(String? category) {
  final text = (category ?? '').toLowerCase();
  if (text.isEmpty) return false;

  return text.contains('office') ||
      text.contains('software') ||
      text.contains('hardware') ||
      text.contains('equipment') ||
      text.contains('travel') ||
      text.contains('transport') ||
      text.contains('client') ||
      text.contains('business') ||
      text.contains('marketing') ||
      text.contains('advertising') ||
      text.contains('consulting') ||
      text.contains('utilities') ||
      text.contains('phone') ||
      text.contains('internet') ||
      text.contains('supplies') ||
      text.contains('subscription') ||
      text.contains('professional');
}

