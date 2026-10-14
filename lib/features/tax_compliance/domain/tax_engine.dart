import 'package:t_aidy/core/financial/money.dart';
import 'package:t_aidy/core/financial/price_basis.dart';
import 'package:t_aidy/features/tax_compliance/domain/tax_rate_resolver.dart';

export 'package:t_aidy/core/financial/price_basis.dart';
export 'package:t_aidy/features/tax_compliance/domain/tax_rate_resolver.dart';

/// Represents a single financial line item for tax calculation.
class TaxableLineItem {
  final String id;
  final String description;
  final int quantity; // Integer unit count (e.g. 1, 2, 5) or scaled decimal
  final Money unitPrice; // Price in fixed-point cents (basis defined by [priceBasis])
  final int taxRateBps; // Tax rate in basis points (e.g. 2200 bps = 22.00%, 400 bps = 4.00%)
  final String? natureCode; // Italian FatturaPA Nature code (N1..N7) if 0% VAT
  final PriceBasis priceBasis;

  const TaxableLineItem({
    required this.id,
    required this.description,
    required this.quantity,
    required this.unitPrice,
    required this.taxRateBps,
    this.natureCode,
    this.priceBasis = PriceBasis.net,
  });

  /// Net line total in fixed-point cents.
  Money get netTotal {
    if (priceBasis == PriceBasis.net) {
      return unitPrice.multiplyInt(quantity);
    }
    // Gross basis: compute net = round_to_even(gross * 10000 / (10000 + rateBps))
    final gross = unitPrice.multiplyInt(quantity);
    return TaxEngine.computeNetFromGross(gross, taxRateBps);
  }

  /// Net unit price in fixed-point cents.
  Money get netUnitPrice {
    if (priceBasis == PriceBasis.net) {
      return unitPrice;
    }
    if (quantity == 0) return Money.zero(unitPrice.currency);
    final netCents = Money.roundIntegerDivision(
      netTotal.cents,
      quantity,
      rounding: MidpointRounding.toEven,
    );
    return Money(cents: netCents, currency: unitPrice.currency);
  }

  /// Gross line total in fixed-point cents.
  Money get grossTotal {
    if (priceBasis == PriceBasis.gross) {
      return unitPrice.multiplyInt(quantity);
    }
    // Net basis: gross = net + round_to_even(net * rateBps / 10000)
    final net = netTotal;
    return TaxEngine.computeGrossFromNet(net, taxRateBps);
  }

  /// Gross unit price in fixed-point cents.
  Money get grossUnitPrice {
    if (priceBasis == PriceBasis.gross) {
      return unitPrice;
    }
    if (quantity == 0) return Money.zero(unitPrice.currency);
    final grossCents = Money.roundIntegerDivision(
      grossTotal.cents,
      quantity,
      rounding: MidpointRounding.toEven,
    );
    return Money(cents: grossCents, currency: unitPrice.currency);
  }

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
  final Money? expectedDocumentTotal;
  final bool invariantSatisfied;
  final int residualCents;

  const InvoiceCalculationResult({
    required this.currency,
    required this.lineNetTotals,
    required this.bracketSummaries,
    required this.totalNet,
    required this.totalTax,
    required this.totalGross,
    this.expectedDocumentTotal,
    required this.invariantSatisfied,
    required this.residualCents,
  });
}

/// Formally verified Financial & Tax Calculation Engine.
///
/// Implements EU Directive 2006/112/EC (Article 226) and European Standard EN 16931:
/// 1. Line items are multiplied in integer cents: `Net_i = UnitPrice_i * Quantity_i` (or backed out from gross).
/// 2. Line items sharing the same tax rate/nature are aggregated into a single Taxable Base: `B_k = sum(Net_i)`.
/// 3. Tax is computed once per bracket with Banker's Rounding: `Tax_k = round_to_even(B_k * rate_k / 10000)`.
/// 4. Verifies reconciliation against stated document total when provided.
class TaxEngine {
  TaxEngine._();

  /// Computes net amount from gross amount using banker's rounding:
  /// net = round_to_even(gross * 10000 / (10000 + rateBps)).
  static Money computeNetFromGross(
    Money gross,
    int rateBps, {
    MidpointRounding rounding = MidpointRounding.toEven,
  }) {
    if (rateBps == 0) return gross;
    final netCents = Money.roundIntegerDivision(
      gross.cents * 10000,
      10000 + rateBps,
      rounding: rounding,
    );
    return Money(cents: netCents, currency: gross.currency);
  }

  /// Computes gross amount from net amount using banker's rounding:
  /// gross = net + round_to_even(net * rateBps / 10000).
  static Money computeGrossFromNet(
    Money net,
    int rateBps, {
    MidpointRounding rounding = MidpointRounding.toEven,
  }) {
    if (rateBps == 0) return net;
    final taxCents = Money.roundIntegerDivision(
      net.cents * rateBps,
      10000,
      rounding: rounding,
    );
    return Money(cents: net.cents + taxCents, currency: net.currency);
  }

  /// Calculates complete invoice totals, VAT bracket summaries, and validates financial invariants.
  static InvoiceCalculationResult calculateInvoice({
    required List<TaxableLineItem> items,
    String currency = 'EUR',
    MidpointRounding rounding = MidpointRounding.toEven,
    Money? expectedDocumentTotal,
    bool strictInvariant = false,
  }) {
    if (items.isEmpty) {
      final zero = Money.zero(currency);
      final residualCents = expectedDocumentTotal != null
          ? zero.cents - expectedDocumentTotal.cents
          : 0;
      final invariantSatisfied = (residualCents == 0);
      if (strictInvariant && !invariantSatisfied) {
        throw StateError(
          'CRITICAL FINANCIAL INVARIANT VIOLATION: Residual = $residualCents cents '
          '(Calculated total: 0 != Stated document total: ${expectedDocumentTotal?.cents})',
        );
      }
      return InvoiceCalculationResult(
        currency: currency,
        lineNetTotals: {},
        bracketSummaries: [],
        totalNet: zero,
        totalTax: zero,
        totalGross: zero,
        expectedDocumentTotal: expectedDocumentTotal,
        invariantSatisfied: invariantSatisfied,
        residualCents: residualCents,
      );
    }

    final lineNetTotals = <String, Money>{};
    // Grouping key: rateBps and optional nature code (e.g., "2200:" or "0:N2.2")
    final bracketBaseMap = <String, int>{};
    final bracketItemCountMap = <String, int>{};
    final bracketRateMap = <String, int>{};
    final bracketNatureMap = <String, String?>{};

    int totalNetCents = 0;

    // 1. Line item calculation (Exact Integer Arithmetic with Banker's Rounding)
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

    final totalGross = Money(cents: totalNetCents + totalTaxCents, currency: currency);

    // 3. Document Total Reconciliation (Formal Invariant Check)
    // Non-tautological: compares calculated gross against stated document total
    final int residualCents = expectedDocumentTotal != null
        ? totalGross.cents - expectedDocumentTotal.cents
        : 0;
    final bool invariantSatisfied = (residualCents == 0);

    if (strictInvariant && !invariantSatisfied) {
      throw StateError(
        'CRITICAL FINANCIAL INVARIANT VIOLATION: Residual = $residualCents cents '
        '(Calculated total: ${totalGross.cents} != Stated document total: ${expectedDocumentTotal?.cents})',
      );
    }

    return InvoiceCalculationResult(
      currency: currency,
      lineNetTotals: lineNetTotals,
      bracketSummaries: bracketSummaries,
      totalNet: Money(cents: totalNetCents, currency: currency),
      totalTax: Money(cents: totalTaxCents, currency: currency),
      totalGross: totalGross,
      expectedDocumentTotal: expectedDocumentTotal,
      invariantSatisfied: invariantSatisfied,
      residualCents: residualCents,
    );
  }

  /// Infers standard Italian / European / German VAT rate in basis points from category keyword heuristics.
  static int inferTaxRateBps(
    String? category, [
    String? subCategory,
    String countryCode = 'IT',
  ]) {
    return TaxRateResolver.inferTaxRateBps(category, subCategory, countryCode);
  }

  /// Determines Italian FatturaPA Nature code for 0% VAT line items.
  static String inferNatureCode(String? category, [String? subCategory]) {
    return TaxRateResolver.inferNatureCode(category, subCategory);
  }
}
