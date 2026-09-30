import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:t_aidy/features/receipt_scanning/domain/entities/receipt.dart';
import 'package:t_aidy/features/receipt_scanning/presentation/providers/receipt_provider.dart';

/// Compliance status of an external subcontractor / vendor.
enum Contractor1099Status {
  underThreshold, // Paid < $600
  requires1099, // Paid >= $600, W-9 / 1099-NEC filing required
  w9Collected, // W-9 on file with valid TIN/EIN
  exemptEntity, // C-Corp or S-Corp exempt from 1099-NEC
}

/// Profile of an external contractor/vendor for tax compliance.
class VendorComplianceProfile {
  final String vendorName;
  final String normalizedName;
  final double totalPaidInYear;
  final int paymentCount;
  final Contractor1099Status status;
  final String? tinOrEin;
  final bool isW9OnFile;
  final List<String> receiptIds;

  const VendorComplianceProfile({
    required this.vendorName,
    required this.normalizedName,
    required this.totalPaidInYear,
    required this.paymentCount,
    required this.status,
    this.tinOrEin,
    this.isW9OnFile = false,
    required this.receiptIds,
  });

  /// Amount remaining before crossing the $600 mandatory 1099-NEC reporting threshold.
  double get distanceToThreshold => (600.0 - totalPaidInYear) > 0 ? (600.0 - totalPaidInYear) : 0.0;
}

/// Consolidated 1099-NEC / Subcontractor Compliance Report.
class ContractorComplianceReport {
  final int fiscalYear;
  final List<VendorComplianceProfile> vendors;
  final int totalVendorsRequiring1099;
  final double totalSubcontractorSpend;
  final List<VendorComplianceProfile> missingW9Vendors;

  const ContractorComplianceReport({
    required this.fiscalYear,
    required this.vendors,
    required this.totalVendorsRequiring1099,
    required this.totalSubcontractorSpend,
    required this.missingW9Vendors,
  });
}

/// Engine for tracking vendor payments and statutory Form 1099-NEC compliance.
class ContractorComplianceEngine {
  /// Statutory IRS 1099-NEC threshold ($600).
  static const double k1099Threshold = 600.0;

  /// Analyzes a list of [Receipt]s for contractor/subcontractor expenses in [year].
  static ContractorComplianceReport analyzeReceipts({
    required List<Receipt> receipts,
    int? fiscalYear,
    Map<String, String>? knownVendorTins,
  }) {
    final targetYear = fiscalYear ?? DateTime.now().year;

    // Filter receipts in target fiscal year with contractor/consulting/services categories
    final relevantReceipts = receipts.where((r) {
      if (r.date.year != targetYear) return false;
      final cat = r.category.toLowerCase();
      final merchant = r.merchantName.toLowerCase();
      return cat.contains('contract') ||
          cat.contains('subcontract') ||
          cat.contains('consult') ||
          cat.contains('freelance') ||
          cat.contains('professional') ||
          cat.contains('legal') ||
          merchant.contains('consulting') ||
          merchant.contains('design') ||
          merchant.contains('studio');
    }).toList();

    // Group by normalized vendor name
    final Map<String, List<Receipt>> grouped = {};
    for (final r in relevantReceipts) {
      final key = _normalize(r.merchantName);
      if (key.isEmpty) continue;
      grouped.putIfAbsent(key, () => []).add(r);
    }

    final List<VendorComplianceProfile> profiles = [];
    int requiring1099Count = 0;
    double totalSpend = 0.0;
    final List<VendorComplianceProfile> missingW9 = [];

    grouped.forEach((normKey, receiptList) {
      final totalPaid = receiptList.fold(0.0, (sum, r) => sum + r.totalAmount);
      totalSpend += totalPaid;

      final tin = knownVendorTins?[normKey];
      final isW9 = tin != null && tin.isNotEmpty;

      Contractor1099Status status;
      if (totalPaid >= k1099Threshold) {
        status = isW9 ? Contractor1099Status.w9Collected : Contractor1099Status.requires1099;
        requiring1099Count++;
      } else {
        status = Contractor1099Status.underThreshold;
      }

      final profile = VendorComplianceProfile(
        vendorName: receiptList.last.merchantName,
        normalizedName: normKey,
        totalPaidInYear: totalPaid,
        paymentCount: receiptList.length,
        status: status,
        tinOrEin: tin,
        isW9OnFile: isW9,
        receiptIds: receiptList.map((r) => r.id).toList(),
      );

      profiles.add(profile);

      if (status == Contractor1099Status.requires1099) {
        missingW9.add(profile);
      }
    });

    profiles.sort((a, b) => b.totalPaidInYear.compareTo(a.totalPaidInYear));

    return ContractorComplianceReport(
      fiscalYear: targetYear,
      vendors: profiles,
      totalVendorsRequiring1099: requiring1099Count,
      totalSubcontractorSpend: totalSpend,
      missingW9Vendors: missingW9,
    );
  }

  static String _normalize(String name) {
    return name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '')
        .replaceAll('inc', '')
        .replaceAll('llc', '')
        .replaceAll('ltd', '')
        .replaceAll('corp', '')
        .trim();
  }

  /// Generates a standardized, pre-filled Form W-9 request dunning template.
  static String generateW9RequestTemplate({
    required VendorComplianceProfile vendor,
    String clientName = 'tAIdy Verified Business',
    int? taxYear,
  }) {
    final year = taxYear ?? DateTime.now().year;
    return '''
SUBJECT: Statutory Form W-9 Request for $year 1099-NEC Compliance - ${vendor.vendorName}

Dear ${vendor.vendorName},

In accordance with IRS statutory reporting requirements under 26 U.S.C. § 6041A for tax year $year, cumulative disbursements to your trade have reached \$${vendor.totalPaidInYear.toStringAsFixed(2)}, which meets or exceeds the \$600.00 Form 1099-NEC mandatory reporting threshold.

To maintain air-gapped ledger compliance and avoid statutory 24% backup withholding, please supply your signed Form W-9 containing:
1. Legal Name / Trade Name
2. Federal Tax Classification (Sole Proprietor, Single-Member LLC, C-Corp, S-Corp, Partnership)
3. Taxpayer Identification Number (TIN / EIN / SSN)
4. Certification & Signature

Please return your completed Form W-9 at your earliest convenience.

Sincerely,
$clientName
''';
  }
}

/// Provider for contractor 1099-NEC compliance report.
final contractorComplianceReportProvider = Provider<ContractorComplianceReport>((ref) {
  final receipts = ref.watch(receiptListProvider).valueOrNull ?? [];
  return ContractorComplianceEngine.analyzeReceipts(receipts: receipts);
});

