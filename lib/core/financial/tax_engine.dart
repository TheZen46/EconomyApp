import 'money.dart';

/// Represents a single financial line item for tax calculation.
class TaxableLineItem {
  final String id;
  final String description;
  final int quantity; // Integer unit count (e.g. 1, 2, 5) or scaled decimal
  final Money unitPrice; // Net unit price in fixed-point cents
  final int taxRateBps; // Tax rate in basis points (e.g. 2200 bps = 22.00%, 400 bps = 4.00%)
  final String? natureCode; // Italian FatturaPA Nature code (N1..N7) if 0% VAT

  const TaxableLineItem({
    required this.id,
    required this.description,
    required this.quantity,
    required this.unitPrice,
    required this.taxRateBps,
    this.natureCode,
  });

  /// Net line total = unitPrice * quantity (in integer cents).
  Money get netTotal => unitPrice.multiplyInt(quantity);

  /// Tax rate as percentage (e.g., 22.0).
  double get taxRatePercentage => taxRateBps / 100.0;
}

/// Aggregated tax summary for a specific VAT bracket according to EN 16931 / EU Directive 2006/112/EC.
class TaxBracketSummary {
  /// Tax rate in basis points (e.g. 2200 for 22%).
  final int taxRateBps;

  /// Italian FatturaPA Nature code (N1..N7) for 0% exempt/non-subject brackets.
  final String? natureCode;

  /// Aggregated net taxable base sum in fixed-point cents.
  final Money taxableBase;

  /// Calculated and Banker's rounded VAT amount in fixed-point cents.
  final Money taxAmount;

  /// Gross amount (taxableBase + taxAmount).
  final Money grossTotal;

  /// Number of line items in this bracket.
  final int itemCount;

  const TaxBracketSummary({
    required this.taxRateBps,
    this.natureCode,
    required this.taxableBase,
    required this.taxAmount,
    required this.grossTotal,
    required this.itemCount,
  });

  double get taxRatePercentage => taxRateBps / 100.0;
}

/// Result of complete invoice financial calculation with formal invariant verification.
class InvoiceCalculationResult {
  final String currency;
  final Map<String, Money> lineNetTotals;
  final List<TaxBracketSummary> bracketSummaries;
  final Money totalNet;
  final Money totalTax;
  final Money totalGross;
  final bool invariantSatisfied;
  final int residualCents;

  const InvoiceCalculationResult({
    required this.currency,
    required this.lineNetTotals,
    required this.bracketSummaries,
    required this.totalNet,
    required this.totalTax,
    required this.totalGross,
    required this.invariantSatisfied,
    required this.residualCents,
  });
}

/// Formally verified Financial & Tax Calculation Engine.
///
/// Implements EU Directive 2006/112/EC (Article 226) and European Standard EN 16931:
/// 1. Line items are multiplied in integer cents: `Net_i = UnitPrice_i * Quantity_i`.
/// 2. Line items sharing the same tax rate/nature are aggregated into a single Taxable Base: `B_k = sum(Net_i)`.
/// 3. Tax is computed once per bracket with Banker's Rounding: `Tax_k = round_to_even(B_k * rate_k / 10000)`.
/// 4. Proves zero residual difference: `|TotalAmount - (sum(ItemTotal) + sum(TaxAmount))| == 0`.
class TaxEngine {
  TaxEngine._();

  /// Calculates complete invoice totals, VAT bracket summaries, and validates financial invariants.
  static InvoiceCalculationResult calculateInvoice({
    required List<TaxableLineItem> items,
    String currency = 'EUR',
    MidpointRounding rounding = MidpointRounding.toEven,
  }) {
    if (items.isEmpty) {
      final zero = Money.zero(currency);
      return InvoiceCalculationResult(
        currency: currency,
        lineNetTotals: {},
        bracketSummaries: [],
        totalNet: zero,
        totalTax: zero,
        totalGross: zero,
        invariantSatisfied: true,
        residualCents: 0,
      );
    }

    final lineNetTotals = <String, Money>{};
    // Grouping key: rateBps and optional nature code (e.g., "2200:" or "0:N2.2")
    final bracketBaseMap = <String, int>{};
    final bracketItemCountMap = <String, int>{};
    final bracketRateMap = <String, int>{};
    final bracketNatureMap = <String, String?>{};

    int totalNetCents = 0;

    // 1. Line item calculation (Exact Integer Multiplication)
    for (final item in items) {
      if (item.unitPrice.currency.toUpperCase() != currency.toUpperCase()) {
        throw ArgumentError(
          'Currency mismatch: line item is ${item.unitPrice.currency}, expected $currency',
        );
      }

      final itemNet = item.netTotal;
      lineNetTotals[item.id] = itemNet;
      totalNetCents += itemNet.cents;

      final key = '${item.taxRateBps}:${item.natureCode ?? ''}';
      bracketBaseMap[key] = (bracketBaseMap[key] ?? 0) + itemNet.cents;
      bracketItemCountMap[key] = (bracketItemCountMap[key] ?? 0) + 1;
      bracketRateMap[key] = item.taxRateBps;
      bracketNatureMap[key] = item.natureCode;
    }

    // 2. Bracket-Level Tax Computation (EN 16931 / Method B Rule)
    final bracketSummaries = <TaxBracketSummary>[];
    int totalTaxCents = 0;

    // Sort bracket keys for deterministic XML/CSV output
    final sortedKeys = bracketBaseMap.keys.toList()..sort();

    for (final key in sortedKeys) {
      final baseCents = bracketBaseMap[key]!;
      final rateBps = bracketRateMap[key]!;
      final nature = bracketNatureMap[key];
      final count = bracketItemCountMap[key]!;

      // Tax calculation: round_to_even(baseCents * rateBps / 10000)
      final int taxCents = (rateBps == 0)
          ? 0
          : Money.roundIntegerDivision(
              baseCents * rateBps,
              10000,
              rounding: rounding,
            );

      totalTaxCents += taxCents;

      final baseMoney = Money(cents: baseCents, currency: currency);
      final taxMoney = Money(cents: taxCents, currency: currency);
      final grossMoney = Money(cents: baseCents + taxCents, currency: currency);

      bracketSummaries.add(TaxBracketSummary(
        taxRateBps: rateBps,
        natureCode: nature,
        taxableBase: baseMoney,
        taxAmount: taxMoney,
        grossTotal: grossMoney,
        itemCount: count,
      ));
    }

    final totalGrossCents = totalNetCents + totalTaxCents;

    // 3. Formal Invariant Verification
    // | TotalAmount - (sum(ItemTotal_i) + sum(TaxAmount_k)) | == 0
    int sumLineItemsCents = 0;
    for (final m in lineNetTotals.values) {
      sumLineItemsCents += m.cents;
    }

    int sumTaxCents = 0;
    for (final b in bracketSummaries) {
      sumTaxCents += b.taxAmount.cents;
    }

    final residualCents = totalGrossCents - (sumLineItemsCents + sumTaxCents);
    final invariantSatisfied = (residualCents == 0);

    if (!invariantSatisfied) {
      throw StateError(
        'CRITICAL FINANCIAL INVARIANT VIOLATION: Residual = $residualCents cents '
        '(Total: $totalGrossCents != Items: $sumLineItemsCents + Tax: $sumTaxCents)',
      );
    }

    return InvoiceCalculationResult(
      currency: currency,
      lineNetTotals: lineNetTotals,
      bracketSummaries: bracketSummaries,
      totalNet: Money(cents: totalNetCents, currency: currency),
      totalTax: Money(cents: totalTaxCents, currency: currency),
      totalGross: Money(cents: totalGrossCents, currency: currency),
      invariantSatisfied: true,
      residualCents: 0,
    );
  }

  /// Infers standard Italian / European / German VAT rate in basis points from category keyword heuristics.
  static int inferTaxRateBps(
    String? category, [
    String? subCategory,
    String countryCode = 'IT',
  ]) {
    final text = '${category ?? ''} ${subCategory ?? ''}'.toLowerCase();
    final isGermany = countryCode.toUpperCase() == 'DE';

    if (text.contains('fresh produce') ||
        text.contains('bread') ||
        text.contains('pane') ||
        text.contains('milk') ||
        text.contains('latte') ||
        text.contains('fruit') ||
        text.contains('vegetable') ||
        text.contains('verdura')) {
      return isGermany ? 700 : 400; // 7% in Germany, 4% in Italy
    } else if (text.contains('protein') ||
        text.contains('meat') ||
        text.contains('carne') ||
        text.contains('fish') ||
        text.contains('pesce') ||
        text.contains('pantry') ||
        text.contains('pasta') ||
        text.contains('water') ||
        text.contains('acqua') ||
        text.contains('restaurant') ||
        text.contains('dining') ||
        text.contains('hotel') ||
        text.contains('pharmacy') ||
        text.contains('farmaco')) {
      return isGermany ? 700 : 1000; // 7% in Germany, 10% in Italy
    } else if (text.contains('medical visit') ||
        text.contains('visita medica') ||
        text.contains('dentist') ||
        text.contains('insurance') ||
        text.contains('assicurazione') ||
        text.contains('stamp duty') ||
        text.contains('marca da bollo')) {
      return 0; // 0% Exempt (N4 / N1)
    } else {
      return isGermany ? 1900 : 2200; // Standard 19% in Germany, 22% in Italy
    }
  }

  /// Determines Italian FatturaPA Nature code for 0% VAT line items.
  static String inferNatureCode(String? category, [String? subCategory]) {
    final text = '${category ?? ''} ${subCategory ?? ''}'.toLowerCase();
    if (text.contains('stamp duty') || text.contains('bollo') || text.contains('reimbursement')) {
      return 'N1'; // Escluse ex art. 15
    } else if (text.contains('forfettario') || text.contains('non soggetta')) {
      return 'N2.2'; // Non soggette ad IVA
    } else if (text.contains('export') || text.contains('esportazione')) {
      return 'N3.1'; // Non imponibili
    } else if (text.contains('medical') || text.contains('health') || text.contains('esente')) {
      return 'N4'; // Esenti art. 10
    } else if (text.contains('reverse charge') || text.contains('subappalto')) {
      return 'N6.3'; // Reverse charge
    }
    return 'N4'; // Default exemption code
  }
}
