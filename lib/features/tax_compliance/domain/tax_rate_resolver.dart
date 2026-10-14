/// Unified Tax Rate and VAT classification resolver across all compliance modules.
class TaxRateResolver {
  TaxRateResolver._();

  /// Infers standard Italian / European / German VAT rate in basis points (100 bps = 1.00%).
  static int inferTaxRateBps(
    String? category, [
    String? subCategory,
    String countryCode = 'IT',
  ]) {
    final text = '${category ?? ''} ${subCategory ?? ''}'.toLowerCase();
    final isGermany = countryCode.toUpperCase() == 'DE';

    // 1. Check for 0% exemptions first
    if (text.contains('medical visit') ||
        text.contains('visita medica') ||
        text.contains('dentist') ||
        text.contains('dentista') ||
        text.contains('insurance') ||
        text.contains('assicurazione') ||
        text.contains('stamp duty') ||
        text.contains('marca da bollo') ||
        text.contains('forfettario') ||
        text.contains('non soggetta') ||
        text.contains('esportazione') ||
        text.contains('export') ||
        text.contains('reverse charge')) {
      return 0; // 0% Exempt (N1..N7)
    }

    // 2. Super-reduced rate (4% in Italy, 7% in Germany)
    if (text.contains('fresh produce') ||
        text.contains('bread') ||
        text.contains('pane') ||
        text.contains('milk') ||
        text.contains('latte') ||
        text.contains('fruit') ||
        text.contains('frutta') ||
        text.contains('vegetable') ||
        text.contains('verdura') ||
        text.contains('farina') ||
        text.contains("olio d'oliva") ||
        text.contains('alimentari base')) {
      return isGermany ? 700 : 400;
    }

    // 3. Intermediate / Reduced rate (10% in Italy, 7% in Germany)
    if (text.contains('protein') ||
        text.contains('meat') ||
        text.contains('carne') ||
        text.contains('poultry') ||
        text.contains('pollo') ||
        text.contains('fish') ||
        text.contains('pesce') ||
        text.contains('pantry') ||
        text.contains('pasta') ||
        text.contains('water') ||
        text.contains('acqua') ||
        text.contains('restaurant') ||
        text.contains('ristorante') ||
        text.contains('dining') ||
        text.contains('hotel') ||
        text.contains('albergo') ||
        text.contains('pharmacy') ||
        text.contains('farmaco') ||
        text.contains('pharma') ||
        text.contains('farmacia') ||
        text.contains('medicine') ||
        text.contains('medicinali') ||
        text.contains('health & medicine') ||
        text.contains('dairy') ||
        text.contains('latticini') ||
        text.contains('cheese') ||
        text.contains('formaggio') ||
        text.contains('yogurt') ||
        text.contains('personal care') ||
        text.contains('health')) {
      return isGermany ? 700 : 1000;
    }

    // 4. Standard rate (22% in Italy, 19% in Germany)
    return isGermany ? 1900 : 2200;
  }

  /// Infers standard VAT rate as a percentage double (e.g. 22.0, 10.0, 4.0, 0.0).
  static double inferVatRatePercentage(
    String? category, [
    String? subCategory,
    String countryCode = 'IT',
  ]) {
    return inferTaxRateBps(category, subCategory, countryCode) / 100.0;
  }

  /// Determines Italian FatturaPA Nature code (N1..N7) for 0% VAT line items.
  static String inferNatureCode(String? category, [String? subCategory]) {
    final text = '${category ?? ''} ${subCategory ?? ''}'.toLowerCase();
    if (text.contains('stamp duty') ||
        text.contains('marca da bollo') ||
        text.contains('bollo') ||
        text.contains('reimbursement') ||
        text.contains('rimborso')) {
      return 'N1'; // Escluse ex art. 15
    } else if (text.contains('forfettario') || text.contains('non soggetta')) {
      return 'N2.2'; // Non soggette ad IVA
    } else if (text.contains('export') || text.contains('esportazione')) {
      return 'N3.1'; // Non imponibili
    } else if (text.contains('medical') ||
        text.contains('health') ||
        text.contains('esente') ||
        text.contains('visita') ||
        text.contains('dentist')) {
      return 'N4'; // Esenti art. 10
    } else if (text.contains('reverse charge') || text.contains('subappalto')) {
      return 'N6.3'; // Reverse charge
    }
    return 'N4'; // Default exemption code
  }
}
