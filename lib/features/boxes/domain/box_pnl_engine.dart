import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  const BoxPnlStatement({
    required this.box,
    required this.grossRevenue,
    required this.directExpenses,
    required this.mileageDeductions,
    required this.totalCosts,
    required this.netOperatingProfit,
    required this.profitMarginPercent,
    required this.invoiceCount,
    required this.receiptCount,
    required this.mileageTripCount,
  });
}

/// Consolidated multi-entity P&L portfolio report.
class PortfolioPnlReport {
  final List<BoxPnlStatement> boxStatements;
  final double totalPortfolioRevenue;
  final double totalPortfolioCosts;
  final double totalPortfolioNetProfit;
  final double overallProfitMarginPercent;

  const PortfolioPnlReport({
    required this.boxStatements,
    required this.totalPortfolioRevenue,
    required this.totalPortfolioCosts,
    required this.totalPortfolioNetProfit,
    required this.overallProfitMarginPercent,
  });
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
    double totalRev = 0.0;
    double totalCosts = 0.0;

    final List<BoxPnlStatement> statements = [];

    for (final box in boxes) {
      // 1. Invoiced Revenue for this box
      double boxRev = 0.0;
      int invCount = 0;
      for (final inv in invoices) {
        // Matching by notes or direct box attribution
        if (inv.notes.toLowerCase().contains(box.name.toLowerCase()) || box.id == 'main') {
          if (inv.status == InvoiceStatus.settled || inv.status == InvoiceStatus.sent) {
            boxRev += inv.amount;
            invCount++;
          }
        }
      }

      // 2. Direct Receipts & Split Line-Items for this box
      double boxExpenses = 0.0;
      int recCount = 0;
      for (final r in receipts) {
        if (r.boxId == box.id) {
          boxExpenses += r.totalAmount;
          recCount++;
        } else {
          // Check line items
          for (final item in r.items) {
            if (item.boxId == box.id) {
              boxExpenses += item.unitPrice * item.quantity;
            }
          }
        }
      }

      // 3. Mileage Deductions for this box
      double boxMileage = 0.0;
      int tripCount = 0;
      for (final trip in mileageTrips) {
        if (trip.boxId == box.id || (box.id == 'main' && trip.boxId == null)) {
          boxMileage += trip.totalDeductible;
          tripCount++;
        }
      }

      final boxTotalCost = boxExpenses + boxMileage;
      final netProfit = boxRev - boxTotalCost;
      final margin = boxRev > 0 ? (netProfit / boxRev) * 100.0 : 0.0;

      totalRev += boxRev;
      totalCosts += boxTotalCost;

      statements.add(BoxPnlStatement(
        box: box,
        grossRevenue: boxRev,
        directExpenses: boxExpenses,
        mileageDeductions: boxMileage,
        totalCosts: boxTotalCost,
        netOperatingProfit: netProfit,
        profitMarginPercent: margin,
        invoiceCount: invCount,
        receiptCount: recCount,
        mileageTripCount: tripCount,
      ));
    }

    final totalNet = totalRev - totalCosts;
    final overallMargin = totalRev > 0 ? (totalNet / totalRev) * 100.0 : 0.0;

    return PortfolioPnlReport(
      boxStatements: statements,
      totalPortfolioRevenue: totalRev,
      totalPortfolioCosts: totalCosts,
      totalPortfolioNetProfit: totalNet,
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

