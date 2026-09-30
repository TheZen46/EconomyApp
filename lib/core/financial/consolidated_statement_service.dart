import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/boxes/data/models/box_model.dart';
import '../../features/boxes/data/providers/boxes_provider.dart';
import '../../features/invoices/data/models/invoice_model.dart';
import '../../features/invoices/data/providers/invoices_provider.dart';
import '../../features/receipt_scanning/domain/entities/receipt.dart';
import '../../features/receipt_scanning/presentation/providers/receipt_provider.dart';
import 'package:t_aidy/features/mileage/domain/mileage_engine.dart';

/// An individual line item in a consolidated financial statement.
class StatementLineItem {
  final String category;
  final Map<String, double> perBoxAmounts; // BoxId -> Amount
  final double interEntityElimination; // Negative amount eliminated
  final double consolidatedAmount; // Sum of perBoxAmounts + interEntityElimination

  const StatementLineItem({
    required this.category,
    required this.perBoxAmounts,
    this.interEntityElimination = 0.0,
    required this.consolidatedAmount,
  });
}

/// Consolidated Multi-Entity Financial Statement Report.
class ConsolidatedFinancialStatement {
  final int fiscalYear;
  final List<BoxModel> entities;
  final List<StatementLineItem> revenueLines;
  final List<StatementLineItem> expenseLines;
  final double totalGrossRevenue;
  final double totalInterEntityEliminatedRevenue;
  final double consolidatedNetRevenue;
  final double totalGrossExpenses;
  final double totalInterEntityEliminatedExpenses;
  final double consolidatedNetExpenses;
  final double consolidatedOperatingProfit;
  final double consolidatedProfitMargin;

  const ConsolidatedFinancialStatement({
    required this.fiscalYear,
    required this.entities,
    required this.revenueLines,
    required this.expenseLines,
    required this.totalGrossRevenue,
    required this.totalInterEntityEliminatedRevenue,
    required this.consolidatedNetRevenue,
    required this.totalGrossExpenses,
    required this.totalInterEntityEliminatedExpenses,
    required this.consolidatedNetExpenses,
    required this.consolidatedOperatingProfit,
    required this.consolidatedProfitMargin,
  });

  /// Generates a GAAP-formatted ASCII text summary table.
  String toFormattedTable() {
    final buffer = StringBuffer();
    buffer.writeln('=============================================================================');
    buffer.writeln(' CONSOLIDATED MULTI-ENTITY FINANCIAL STATEMENT - FISCAL YEAR $fiscalYear');
    buffer.writeln('=============================================================================');
    buffer.writeln(' Entities Included: ${entities.map((e) => e.name).join(', ')}');
    buffer.writeln('-----------------------------------------------------------------------------');
    buffer.writeln(' Gross Revenue (Sum of All Boxes):     \$ ${totalGrossRevenue.toStringAsFixed(2)}');
    buffer.writeln(' Inter-Entity Transfer Elimination:   -\$ ${totalInterEntityEliminatedRevenue.toStringAsFixed(2)}');
    buffer.writeln(' Consolidated Net Revenue:             \$ ${consolidatedNetRevenue.toStringAsFixed(2)}');
    buffer.writeln('-----------------------------------------------------------------------------');
    buffer.writeln(' Gross Operating Costs & Mileage:      \$ ${totalGrossExpenses.toStringAsFixed(2)}');
    buffer.writeln(' Inter-Entity Expense Elimination:    -\$ ${totalInterEntityEliminatedExpenses.toStringAsFixed(2)}');
    buffer.writeln(' Consolidated Net Costs:               \$ ${consolidatedNetExpenses.toStringAsFixed(2)}');
    buffer.writeln('-----------------------------------------------------------------------------');
    buffer.writeln(' CONSOLIDATED OPERATING PROFIT:        \$ ${consolidatedOperatingProfit.toStringAsFixed(2)}');
    buffer.writeln(' CONSOLIDATED OPERATING MARGIN:        ${consolidatedProfitMargin.toStringAsFixed(2)}%');
    buffer.writeln('=============================================================================');
    return buffer.toString();
  }
}

/// Service for creating GAAP-compliant consolidated financial statements with inter-box elimination.
class ConsolidatedStatementService {
  /// Generates a consolidated financial statement across multiple box entities.
  static ConsolidatedFinancialStatement generateConsolidatedStatement({
    required List<BoxModel> boxes,
    required List<InvoiceModel> invoices,
    required List<Receipt> receipts,
    List<MileageTrip> mileageTrips = const [],
    int? fiscalYear,
  }) {
    final targetYear = fiscalYear ?? DateTime.now().year;

    // Filter boxes (exclude purely personal envelope if desired, or include all business boxes)
    final businessBoxes = boxes.where((b) => b.id != 'personal_expense_box').toList();

    // 1. Group Invoices by category and box
    final Map<String, Map<String, double>> revenueByCategoryAndBox = {};
    double totalGrossRev = 0.0;
    double eliminatedRev = 0.0;

    for (final inv in invoices) {
      if (inv.status == InvoiceStatus.settled && inv.issuedDate.year == targetYear) {
        // Detect if invoice is billed to another internal box (inter-company transaction)
        final isInternalTransfer = boxes.any((b) =>
            b.name.trim().toLowerCase() == inv.clientName.trim().toLowerCase());

        final category = isInternalTransfer ? 'Inter-Entity Service Invoices' : 'Client Professional Fees';
        final targetBoxId = businessBoxes.isNotEmpty ? businessBoxes.first.id : 'main';

        revenueByCategoryAndBox.putIfAbsent(category, () => {});
        revenueByCategoryAndBox[category]![targetBoxId] =
            (revenueByCategoryAndBox[category]![targetBoxId] ?? 0.0) + inv.amount;

        totalGrossRev += inv.amount;
        if (isInternalTransfer) {
          eliminatedRev += inv.amount;
        }
      }
    }

    // 2. Group Expenses by category and box
    final Map<String, Map<String, double>> expensesByCategoryAndBox = {};
    double totalGrossExp = 0.0;
    double eliminatedExp = 0.0;

    for (final r in receipts) {
      if (r.date.year == targetYear) {
        for (final item in r.items) {
          final boxId = item.boxId ?? r.boxId ?? 'main';
          final category = item.mainCategory ?? 'General Expense';
          final cost = item.totalPrice;

          final isInternalTransfer = boxes.any((b) =>
              b.name.trim().toLowerCase() == r.merchantName.trim().toLowerCase());

          expensesByCategoryAndBox.putIfAbsent(category, () => {});
          expensesByCategoryAndBox[category]![boxId] =
              (expensesByCategoryAndBox[category]![boxId] ?? 0.0) + cost;

          totalGrossExp += cost;
          if (isInternalTransfer) {
            eliminatedExp += cost;
          }
        }
      }
    }

    // Add mileage costs to expenses
    for (final trip in mileageTrips) {
      if (trip.date.year == targetYear) {
        final boxId = trip.boxId ?? 'main';
        const category = 'Business Travel & Mileage';
        final cost = trip.totalDeductible;

        expensesByCategoryAndBox.putIfAbsent(category, () => {});
        expensesByCategoryAndBox[category]![boxId] =
            (expensesByCategoryAndBox[category]![boxId] ?? 0.0) + cost;

        totalGrossExp += cost;
      }
    }

    // 3. Build Statement Line Items
    final revenueLines = <StatementLineItem>[];
    revenueByCategoryAndBox.forEach((category, perBox) {
      final total = perBox.values.fold(0.0, (a, b) => a + b);
      final elimination = category.contains('Inter-Entity') ? total : 0.0;
      revenueLines.add(StatementLineItem(
        category: category,
        perBoxAmounts: perBox,
        interEntityElimination: -elimination,
        consolidatedAmount: total - elimination,
      ));
    });

    final expenseLines = <StatementLineItem>[];
    expensesByCategoryAndBox.forEach((category, perBox) {
      final total = perBox.values.fold(0.0, (a, b) => a + b);
      final elimination = category.contains('Inter-Entity') ? total : 0.0;
      expenseLines.add(StatementLineItem(
        category: category,
        perBoxAmounts: perBox,
        interEntityElimination: -elimination,
        consolidatedAmount: total - elimination,
      ));
    });

    final consolidatedNetRev = totalGrossRev - eliminatedRev;
    final consolidatedNetExp = totalGrossExp - eliminatedExp;
    final consolidatedNetProfit = consolidatedNetRev - consolidatedNetExp;
    final margin = consolidatedNetRev > 0 ? ((consolidatedNetProfit / consolidatedNetRev) * 100.0) : 0.0;

    return ConsolidatedFinancialStatement(
      fiscalYear: targetYear,
      entities: businessBoxes,
      revenueLines: revenueLines,
      expenseLines: expenseLines,
      totalGrossRevenue: totalGrossRev,
      totalInterEntityEliminatedRevenue: eliminatedRev,
      consolidatedNetRevenue: consolidatedNetRev,
      totalGrossExpenses: totalGrossExp,
      totalInterEntityEliminatedExpenses: eliminatedExp,
      consolidatedNetExpenses: consolidatedNetExp,
      consolidatedOperatingProfit: consolidatedNetProfit,
      consolidatedProfitMargin: margin,
    );
  }
}

/// Provider for consolidated financial statements.
final consolidatedStatementProvider = Provider<ConsolidatedFinancialStatement>((ref) {
  final boxes = ref.watch(boxesProvider);
  final invoices = ref.watch(invoicesProvider);
  final receipts = ref.watch(receiptListProvider).valueOrNull ?? [];

  return ConsolidatedStatementService.generateConsolidatedStatement(
    boxes: boxes,
    invoices: invoices,
    receipts: receipts,
    fiscalYear: DateTime.now().year,
  );
});
