import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:t_aidy/core/financial/money.dart';
import 'package:t_aidy/features/boxes/data/models/box_model.dart';
import 'package:t_aidy/features/boxes/data/providers/boxes_provider.dart';
import 'package:t_aidy/features/invoices/data/models/invoice_model.dart';
import 'package:t_aidy/features/invoices/data/providers/invoices_provider.dart';
import 'package:t_aidy/features/receipt_scanning/domain/entities/receipt.dart';
import 'package:t_aidy/features/receipt_scanning/presentation/providers/receipt_provider.dart';
import 'package:t_aidy/features/mileage/domain/mileage_engine.dart';

/// Financial statement representing the Profit & Loss profile of an individual Box or Project.
class BoxPnlStatement {
  final BoxModel box;
  final double grossRevenue;
  final double directExpenses;
  final double mileageDeductions;
  final double totalCosts;
  final double netOperatingProfit;
  final double profitMarginPercent;
  final int invoiceCount;
  final int receiptCount;
  final int mileageTripCount;
  final Money grossRevenueMoney;
  final Money directExpensesMoney;
  final Money mileageDeductionsMoney;
  final Money totalCostsMoney;
  final Money netOperatingProfitMoney;

  BoxPnlStatement({
    required this.box,
    required this.grossRevenueMoney,
    required this.directExpensesMoney,
    required this.mileageDeductionsMoney,
    required this.totalCostsMoney,
    required this.netOperatingProfitMoney,
    required this.profitMarginPercent,
    required this.invoiceCount,
    required this.receiptCount,
    required this.mileageTripCount,
    double? grossRevenue,
    double? directExpenses,
    double? mileageDeductions,
    double? totalCosts,
    double? netOperatingProfit,
  })  : grossRevenue = grossRevenue ?? grossRevenueMoney.toDouble,
        directExpenses = directExpenses ?? directExpensesMoney.toDouble,
        mileageDeductions = mileageDeductions ?? mileageDeductionsMoney.toDouble,
        totalCosts = totalCosts ?? totalCostsMoney.toDouble,
        netOperatingProfit = netOperatingProfit ?? netOperatingProfitMoney.toDouble;
}

/// Consolidated multi-entity P&L portfolio report.
class PortfolioPnlReport {
  final List<BoxPnlStatement> boxStatements;
  final double totalPortfolioRevenue;
  final double totalPortfolioCosts;
  final double totalPortfolioNetProfit;
  final double overallProfitMarginPercent;
  final Money totalPortfolioRevenueMoney;
  final Money totalPortfolioCostsMoney;
  final Money totalPortfolioNetProfitMoney;

  PortfolioPnlReport({
    required this.boxStatements,
    required this.totalPortfolioRevenueMoney,
    required this.totalPortfolioCostsMoney,
    required this.totalPortfolioNetProfitMoney,
    required this.overallProfitMarginPercent,
    double? totalPortfolioRevenue,
    double? totalPortfolioCosts,
    double? totalPortfolioNetProfit,
  })  : totalPortfolioRevenue = totalPortfolioRevenue ?? totalPortfolioRevenueMoney.toDouble,
        totalPortfolioCosts = totalPortfolioCosts ?? totalPortfolioCostsMoney.toDouble,
        totalPortfolioNetProfit = totalPortfolioNetProfit ?? totalPortfolioNetProfitMoney.toDouble;
}

/// Engine for generating isolated, per-box Profit & Loss balance statements.
class BoxPnlEngine {
  /// Generates a consolidated [PortfolioPnlReport] across all boxes.
  static PortfolioPnlReport generateReport({
    required List<BoxModel> boxes,
    required List<InvoiceModel> invoices,
    required List<Receipt> receipts,
    required List<MileageTrip> mileageTrips,
  }) {
    final portfolioCurrency = boxes.isNotEmpty ? boxes.first.currency : 'USD';
    final hasSingleCurrency = boxes.every((b) => b.currency.toUpperCase() == portfolioCurrency.toUpperCase());

    var totalRevMoney = Money.zero(portfolioCurrency);
    var totalCostsMoney = Money.zero(portfolioCurrency);
    double totalRevFallback = 0.0;
    double totalCostsFallback = 0.0;

    final List<BoxPnlStatement> statements = [];

    for (final box in boxes) {
      final boxCurrency = box.currency;

      // 1. Invoiced Revenue for this box
      var boxRev = Money.zero(boxCurrency);
      int invCount = 0;
      for (final inv in invoices) {
        if (inv.notes.toLowerCase().contains(box.name.toLowerCase()) || box.id == 'main') {
          if (inv.status == InvoiceStatus.settled || inv.status == InvoiceStatus.sent) {
            boxRev = boxRev + inv.amountMoney;
            invCount++;
          }
        }
      }

      // 2. Direct Receipts & Split Line-Items for this box
      var boxExpenses = Money.zero(boxCurrency);
      int recCount = 0;
      for (final r in receipts) {
        if (r.boxId == box.id) {
          boxExpenses = boxExpenses + r.totalMoney;
          recCount++;
        } else {
          for (final item in r.items) {
            if (item.boxId == box.id) {
              boxExpenses = boxExpenses + item.totalPriceMoney(r.currency);
            }
          }
        }
      }

      // 3. Mileage Deductions for this box
      var boxMileage = Money.zero(boxCurrency);
      int tripCount = 0;
      for (final trip in mileageTrips) {
        if (trip.boxId == box.id || (box.id == 'main' && trip.boxId == null)) {
          boxMileage = boxMileage + Money.fromDecimal(trip.totalDeductible, currency: boxCurrency);
          tripCount++;
        }
      }

      final boxTotalCost = boxExpenses + boxMileage;
      final netProfit = boxRev - boxTotalCost;
      final margin = boxRev.cents > 0 ? (netProfit.cents / boxRev.cents) * 100.0 : 0.0;

      if (hasSingleCurrency) {
        totalRevMoney = totalRevMoney + boxRev;
        totalCostsMoney = totalCostsMoney + boxTotalCost;
      } else {
        totalRevFallback += boxRev.toDouble;
        totalCostsFallback += boxTotalCost.toDouble;
      }

      statements.add(BoxPnlStatement(
        box: box,
        grossRevenueMoney: boxRev,
        directExpensesMoney: boxExpenses,
        mileageDeductionsMoney: boxMileage,
        totalCostsMoney: boxTotalCost,
        netOperatingProfitMoney: netProfit,
        profitMarginPercent: margin,
        invoiceCount: invCount,
        receiptCount: recCount,
        mileageTripCount: tripCount,
      ));
    }

    if (!hasSingleCurrency) {
      totalRevMoney = Money.fromDecimal(totalRevFallback, currency: portfolioCurrency);
      totalCostsMoney = Money.fromDecimal(totalCostsFallback, currency: portfolioCurrency);
    }

    final totalNetMoney = totalRevMoney - totalCostsMoney;
    final overallMargin = totalRevMoney.cents > 0 ? (totalNetMoney.cents / totalRevMoney.cents) * 100.0 : 0.0;

    return PortfolioPnlReport(
      boxStatements: statements,
      totalPortfolioRevenueMoney: totalRevMoney,
      totalPortfolioCostsMoney: totalCostsMoney,
      totalPortfolioNetProfitMoney: totalNetMoney,
      overallProfitMarginPercent: overallMargin,
    );
  }
}

/// Provider for portfolio Box P&L report.
final portfolioPnlReportProvider = Provider<PortfolioPnlReport>((ref) {
  final boxes = ref.watch(boxesProvider);
  final invoices = ref.watch(invoicesProvider);
  final receipts = ref.watch(receiptListProvider).valueOrNull ?? [];
  final mileage = ref.watch(mileageTripsProvider);

  return BoxPnlEngine.generateReport(
    boxes: boxes,
    invoices: invoices,
    receipts: receipts,
    mileageTrips: mileage,
  );
});

