import 'package:t_aidy/features/evault/data/models/asset_model.dart';

/// Supported statutory depreciation recovery methods.
enum DepreciationMethod {
  section179, // 100% full immediate write-off in acquisition year
  macrs5Year,  // MACRS 5-year half-year convention (Computers, Laptops, Phones, Electronics)
  macrs7Year,  // MACRS 7-year half-year convention (Office Furniture, Desks, Fixtures)
  straightLine3Year, // 3-year Straight Line
}

/// Annual deduction row in a multi-year recovery schedule.
class YearlyDepreciationEntry {
  final int fiscalYear;
  final int scheduleYearIndex; // 1-based index (e.g. Year 1, Year 2)
  final double deductionRate; // percentage (e.g. 0.20 for 20%)
  final double deductionAmount; // In currency units
  final double endingBookValue;
  final double accumulatedDepreciation;

  const YearlyDepreciationEntry({
    required this.fiscalYear,
    required this.scheduleYearIndex,
    required this.deductionRate,
    required this.deductionAmount,
    required this.endingBookValue,
    required this.accumulatedDepreciation,
  });
}

/// Complete multi-year tax depreciation schedule for an asset.
class AssetDepreciationSchedule {
  final String assetId;
  final String assetName;
  final int purchaseYear;
  final double initialCost;
  final DepreciationMethod method;
  final List<YearlyDepreciationEntry> yearlyEntries;
  final double currentYearDeduction;
  final double currentBookValue;
  final double totalAccumulatedDepreciation;
  final bool isFullyDepreciated;

  const AssetDepreciationSchedule({
    required this.assetId,
    required this.assetName,
    required this.purchaseYear,
    required this.initialCost,
    required this.method,
    required this.yearlyEntries,
    required this.currentYearDeduction,
    required this.currentBookValue,
    required this.totalAccumulatedDepreciation,
    required this.isFullyDepreciated,
  });
}

/// Aggregated portfolio depreciation metrics for vault inventory.
class VaultPortfolioTaxSummary {
  final double totalAcquisitionCost;
  final double totalCurrentBookValue;
  final double totalSection179Eligible;
  final double totalCurrentYearMACRS;
  final int activeWarrantyCount;
  final int expiringSoonWarrantyCount; // < 30 days
  final int expiredWarrantyCount;

  const VaultPortfolioTaxSummary({
    required this.totalAcquisitionCost,
    required this.totalCurrentBookValue,
    required this.totalSection179Eligible,
    required this.totalCurrentYearMACRS,
    required this.activeWarrantyCount,
    required this.expiringSoonWarrantyCount,
    required this.expiredWarrantyCount,
  });
}

/// Section 179 and MACRS Tax Depreciation Engine.
///
/// Implements IRS Publication 946 (How to Depreciate Property):
/// - Section 179 100% full expensing for qualified tangible personal property.
/// - 5-Year MACRS 200% declining balance with half-year convention:
///   [Year 1: 20.00%, Year 2: 32.00%, Year 3: 19.20%, Year 4: 11.52%, Year 5: 11.52%, Year 6: 5.76%]
/// - 7-Year MACRS 200% declining balance with half-year convention:
///   [Year 1: 14.29%, Year 2: 24.49%, Year 3: 17.49%, Year 4: 12.49%, Year 5: 8.93%, Year 6: 8.92%, Year 7: 8.93%, Year 8: 4.46%]
class DepreciationEngine {
  DepreciationEngine._();

  static const List<double> kMacrs5YearRates = [0.2000, 0.3200, 0.1920, 0.1152, 0.1152, 0.0576];
  static const List<double> kMacrs7YearRates = [0.1429, 0.2449, 0.1749, 0.1249, 0.0893, 0.0892, 0.0893, 0.0446];
  static const List<double> kStraightLine3YearRates = [0.3333, 0.3333, 0.3334];

  /// Infers appropriate depreciation recovery method based on item name and category.
  static DepreciationMethod inferMethod(String assetName) {
    final lower = assetName.toLowerCase();
    if (lower.contains('desk') ||
        lower.contains('chair') ||
        lower.contains('table') ||
        lower.contains('shelf') ||
        lower.contains('furniture') ||
        lower.contains('cabinet')) {
      return DepreciationMethod.macrs7Year;
    }
    return DepreciationMethod.macrs5Year; // Default for tech, phones, laptops, tools
  }

  /// Calculates the complete statutory depreciation schedule for an asset.
  static AssetDepreciationSchedule calculateSchedule({
    required AssetModel asset,
    DepreciationMethod? customMethod,
    int? currentFiscalYear,
  }) {
    final method = customMethod ?? inferMethod(asset.name);
    final purchaseYear = asset.purchaseDate.year;
    final nowYear = currentFiscalYear ?? DateTime.now().year;
    final cost = asset.price;

    if (cost <= 0) {
      return AssetDepreciationSchedule(
        assetId: asset.id,
        assetName: asset.name,
        purchaseYear: purchaseYear,
        initialCost: 0,
        method: method,
        yearlyEntries: [],
        currentYearDeduction: 0,
        currentBookValue: 0,
        totalAccumulatedDepreciation: 0,
        isFullyDepreciated: true,
      );
    }

    if (method == DepreciationMethod.section179) {
      final isPurchaseYear = (nowYear == purchaseYear);
      final entry = YearlyDepreciationEntry(
        fiscalYear: purchaseYear,
        scheduleYearIndex: 1,
        deductionRate: 1.0,
        deductionAmount: cost,
        endingBookValue: 0.0,
        accumulatedDepreciation: cost,
      );

      return AssetDepreciationSchedule(
        assetId: asset.id,
        assetName: asset.name,
        purchaseYear: purchaseYear,
        initialCost: cost,
        method: method,
        yearlyEntries: [entry],
        currentYearDeduction: isPurchaseYear ? cost : 0.0,
        currentBookValue: 0.0,
        totalAccumulatedDepreciation: cost,
        isFullyDepreciated: true,
      );
    }

    List<double> rates;
    switch (method) {
      case DepreciationMethod.macrs7Year:
        rates = kMacrs7YearRates;
        break;
      case DepreciationMethod.straightLine3Year:
        rates = kStraightLine3YearRates;
        break;
      case DepreciationMethod.macrs5Year:
      default:
        rates = kMacrs5YearRates;
        break;
    }

    final entries = <YearlyDepreciationEntry>[];
    double accumulated = 0.0;
    double currentYearDeduction = 0.0;
    double currentBookValue = cost;

    for (int i = 0; i < rates.length; i++) {
      final fYear = purchaseYear + i;
      final rate = rates[i];
      final deduction = (cost * rate);
      accumulated += deduction;
      final endingValue = (cost - accumulated) > 0 ? (cost - accumulated) : 0.0;

      if (fYear == nowYear) {
        currentYearDeduction = deduction;
      }
      if (fYear <= nowYear) {
        currentBookValue = endingValue;
      }

      entries.add(YearlyDepreciationEntry(
        fiscalYear: fYear,
        scheduleYearIndex: i + 1,
        deductionRate: rate,
        deductionAmount: deduction,
        endingBookValue: endingValue,
        accumulatedDepreciation: accumulated > cost ? cost : accumulated,
      ));
    }

    final isFullyDepr = nowYear >= (purchaseYear + rates.length);

    return AssetDepreciationSchedule(
      assetId: asset.id,
      assetName: asset.name,
      purchaseYear: purchaseYear,
      initialCost: cost,
      method: method,
      yearlyEntries: entries,
      currentYearDeduction: currentYearDeduction,
      currentBookValue: isFullyDepr ? 0.0 : currentBookValue,
      totalAccumulatedDepreciation: isFullyDepr ? cost : (cost - currentBookValue),
      isFullyDepreciated: isFullyDepr,
    );
  }

  /// Aggregates portfolio tax metrics across all assets in the digital vault.
  static VaultPortfolioTaxSummary calculatePortfolioSummary(List<AssetModel> assets) {
    double totalCost = 0.0;
    double totalBookValue = 0.0;
    double totalSection179 = 0.0;
    double totalMacrsCurrentYear = 0.0;

    int activeCount = 0;
    int expiringSoonCount = 0;
    int expiredCount = 0;

    final now = DateTime.now();

    for (final asset in assets) {
      totalCost += asset.price;
      
      // Calculate MACRS schedule
      final sched = calculateSchedule(asset: asset);
      totalBookValue += sched.currentBookValue;
      totalMacrsCurrentYear += sched.currentYearDeduction;

      // Section 179 eligible if purchased in current calendar year
      if (asset.purchaseDate.year == now.year) {
        totalSection179 += asset.price;
      }

      // Warranty calculation
      final daysLeft = asset.warrantyExpiryDate.difference(now).inDays;
      if (daysLeft <= 0) {
        expiredCount++;
      } else {
        activeCount++;
        if (daysLeft <= 30) {
          expiringSoonCount++;
        }
      }
    }

    return VaultPortfolioTaxSummary(
      totalAcquisitionCost: totalCost,
      totalCurrentBookValue: totalBookValue,
      totalSection179Eligible: totalSection179,
      totalCurrentYearMACRS: totalMacrsCurrentYear,
      activeWarrantyCount: activeCount,
      expiringSoonWarrantyCount: expiringSoonCount,
      expiredWarrantyCount: expiredCount,
    );
  }
}

