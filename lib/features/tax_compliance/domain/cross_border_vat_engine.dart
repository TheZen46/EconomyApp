/// Supported cross-border tax treatment rules.
enum VatTreatment {
  domesticStandard, // Domestic sale subject to local VAT
  euB2bReverseCharge, // Intra-Community B2B supply (0% VAT + reverse charge note)
  euB2cOss, // B2C sale subject to destination country VAT rate via OSS
  exportNonEu, // Zero-rated export outside EU/jurisdiction
  exempt, // Tax-exempt supply
}

/// Profile of a country's standard VAT regime.
class VatJurisdiction {
  final String countryCode; // e.g. 'DE', 'FR', 'IT', 'ES', 'GB', 'US'
  final String countryName;
  final double standardVatRate; // e.g. 0.19 for Germany, 0.20 for France/UK
  final bool isEuMember;
  final String vatRegexPattern;

  const VatJurisdiction({
    required this.countryCode,
    required this.countryName,
    required this.standardVatRate,
    required this.isEuMember,
    required this.vatRegexPattern,
  });
}

/// Known EU & Global standard VAT rates and VIES syntax patterns.
const Map<String, VatJurisdiction> kKnownVatJurisdictions = {
  'DE': VatJurisdiction(countryCode: 'DE', countryName: 'Germany', standardVatRate: 0.19, isEuMember: true, vatRegexPattern: r'^DE[0-9]{9}$'),
  'FR': VatJurisdiction(countryCode: 'FR', countryName: 'France', standardVatRate: 0.20, isEuMember: true, vatRegexPattern: r'^FR[0-9A-Z]{2}[0-9]{9}$'),
  'IT': VatJurisdiction(countryCode: 'IT', countryName: 'Italy', standardVatRate: 0.22, isEuMember: true, vatRegexPattern: r'^IT[0-9]{11}$'),
  'ES': VatJurisdiction(countryCode: 'ES', countryName: 'Spain', standardVatRate: 0.21, isEuMember: true, vatRegexPattern: r'^ES[0-9A-Z][0-9]{7}[0-9A-Z]$'),
  'NL': VatJurisdiction(countryCode: 'NL', countryName: 'Netherlands', standardVatRate: 0.21, isEuMember: true, vatRegexPattern: r'^NL[0-9]{9}B[0-9]{2}$'),
  'IE': VatJurisdiction(countryCode: 'IE', countryName: 'Ireland', standardVatRate: 0.23, isEuMember: true, vatRegexPattern: r'^IE[0-9]{7}[A-Z]{1,2}$'),
  'SE': VatJurisdiction(countryCode: 'SE', countryName: 'Sweden', standardVatRate: 0.25, isEuMember: true, vatRegexPattern: r'^SE[0-9]{12}$'),
  'PL': VatJurisdiction(countryCode: 'PL', countryName: 'Poland', standardVatRate: 0.23, isEuMember: true, vatRegexPattern: r'^PL[0-9]{10}$'),
  'GB': VatJurisdiction(countryCode: 'GB', countryName: 'United Kingdom', standardVatRate: 0.20, isEuMember: false, vatRegexPattern: r'^(GB)?([0-9]{9}|[0-9]{12})$'),
  'US': VatJurisdiction(countryCode: 'US', countryName: 'United States', standardVatRate: 0.0, isEuMember: false, vatRegexPattern: r'^[0-9]{2}-[0-9]{7}$'),
};

/// Result of a cross-border VAT evaluation.
class VatEvaluationResult {
  final VatTreatment treatment;
  final double applicableVatRate;
  final double calculatedVatAmount;
  final double netAmount;
  final double grossTotal;
  final bool isValidVatId;
  final String? statutoryInvoiceNote;
  final String customerJurisdiction;

  const VatEvaluationResult({
    required this.treatment,
    required this.applicableVatRate,
    required this.calculatedVatAmount,
    required this.netAmount,
    required this.grossTotal,
    required this.isValidVatId,
    this.statutoryInvoiceNote,
    required this.customerJurisdiction,
  });
}

/// Autonomous Cross-Border VAT & Reverse Charge Engine.
class CrossBorderVatEngine {
  /// Evaluates the correct VAT treatment and statutory notes for a transaction.
  static VatEvaluationResult evaluateTransaction({
    required double baseAmount,
    required String sellerCountryCode,
    required String customerCountryCode,
    required bool isCustomerBusiness,
    String customerVatId = '',
  }) {
    final sellerCountry = sellerCountryCode.trim().toUpperCase();
    final customerCountry = customerCountryCode.trim().toUpperCase();
    final cleanVatId = customerVatId.trim().replaceAll(RegExp(r'[\s\.\-]'), '').toUpperCase();

    final sellerProfile = kKnownVatJurisdictions[sellerCountry] ??
        VatJurisdiction(countryCode: sellerCountry, countryName: sellerCountry, standardVatRate: 0.20, isEuMember: false, vatRegexPattern: '.*');
    final customerProfile = kKnownVatJurisdictions[customerCountry] ??
        VatJurisdiction(countryCode: customerCountry, countryName: customerCountry, standardVatRate: 0.20, isEuMember: false, vatRegexPattern: '.*');

    final isValidVat = cleanVatId.isNotEmpty && _validateVatSyntax(cleanVatId, customerProfile);

    // 1. Domestic Supply (Seller & Buyer in same country)
    if (sellerCountry == customerCountry) {
      final rate = sellerProfile.standardVatRate;
      final vatAmt = baseAmount * rate;
      return VatEvaluationResult(
        treatment: VatTreatment.domesticStandard,
        applicableVatRate: rate,
        calculatedVatAmount: vatAmt,
        netAmount: baseAmount,
        grossTotal: baseAmount + vatAmt,
        isValidVatId: isValidVat,
        customerJurisdiction: customerCountry,
      );
    }

    // 2. Intra-Community EU B2B Supply with valid VAT ID -> Reverse Charge
    if (sellerProfile.isEuMember && customerProfile.isEuMember && isCustomerBusiness && isValidVat) {
      return VatEvaluationResult(
        treatment: VatTreatment.euB2bReverseCharge,
        applicableVatRate: 0.0,
        calculatedVatAmount: 0.0,
        netAmount: baseAmount,
        grossTotal: baseAmount,
        isValidVatId: true,
        statutoryInvoiceNote: 'Reverse charge: VAT payable by recipient pursuant to Article 196 of Council Directive 2006/112/EC.',
        customerJurisdiction: customerCountry,
      );
    }

    // 3. Intra-Community EU B2C Supply -> Destination Country VAT (OSS)
    if (sellerProfile.isEuMember && customerProfile.isEuMember && !isCustomerBusiness) {
      final rate = customerProfile.standardVatRate;
      final vatAmt = baseAmount * rate;
      return VatEvaluationResult(
        treatment: VatTreatment.euB2cOss,
        applicableVatRate: rate,
        calculatedVatAmount: vatAmt,
        netAmount: baseAmount,
        grossTotal: baseAmount + vatAmt,
        isValidVatId: false,
        statutoryInvoiceNote: 'EU One-Stop-Shop (OSS) declaration for destination country ${customerProfile.countryName} (${(rate * 100).toStringAsFixed(0)}% VAT).',
        customerJurisdiction: customerCountry,
      );
    }

    // 4. Export outside EU (e.g. US, Canada, Australia) -> Zero-rated export
    return VatEvaluationResult(
      treatment: VatTreatment.exportNonEu,
      applicableVatRate: 0.0,
      calculatedVatAmount: 0.0,
      netAmount: baseAmount,
      grossTotal: baseAmount,
      isValidVatId: isValidVat,
      statutoryInvoiceNote: 'Zero-rated export of services outside the European Union tax territory.',
      customerJurisdiction: customerCountry,
    );
  }

  static bool _validateVatSyntax(String vatId, VatJurisdiction profile) {
    if (profile.vatRegexPattern.isEmpty) return true;
    final regex = RegExp(profile.vatRegexPattern, caseSensitive: false);
    return regex.hasMatch(vatId);
  }
}

