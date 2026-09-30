import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:t_aidy/features/invoices/data/models/invoice_model.dart';
import 'package:t_aidy/features/invoices/data/providers/invoices_provider.dart';
import 'package:t_aidy/features/receipt_scanning/domain/entities/receipt.dart';
import 'package:t_aidy/features/receipt_scanning/presentation/providers/receipt_provider.dart';
import 'package:t_aidy/features/analytics/domain/subscription_detector_engine.dart';
import 'package:t_aidy/features/tax_compliance/domain/tax_calendar_engine.dart';
import 'package:t_aidy/features/tax_compliance/presentation/providers/tax_shield_provider.dart';

/// Projected daily financial snapshot in the cash flow forecast.
class DailyCashForecast {
  final DateTime date;
  final double projectedBalance;
  final double inflow;
  final double outflow;
  final List<String> inflowSources;
  final List<String> outflowReasons;

  const DailyCashForecast({
    required this.date,
    required this.projectedBalance,
    required this.inflow,
    required this.outflow,
    required this.inflowSources,
    required this.outflowReasons,
  });
}

/// Solvency warning identifying liquidity crunches.
class SolvencyAlert {
  final DateTime alertDate;
  final double deficitAmount;
  final String description;
  final String recommendedMitigation;

  const SolvencyAlert({
    required this.alertDate,
    required this.deficitAmount,
    required this.description,
    required this.recommendedMitigation,
  });
}

/// Consolidated 90-Day Cash Flow & Solvency Forecast.
class CashFlowForecastResult {
  final double startingBalance;
  final double endingBalance;
  final double minProjectedBalance;
  final DateTime minBalanceDate;
  final int runwayDaysWithoutNewRevenue;
  final double averageDailyBurn;
  final double expectedReceivablesTotal;
  final double committedOutflowsTotal;
  final List<DailyCashForecast> dailyTimeline;
  final List<SolvencyAlert> alerts;
  final bool hasSolvencyRisk;

  const CashFlowForecastResult({
    required this.startingBalance,
    required this.endingBalance,
    required this.minProjectedBalance,
    required this.minBalanceDate,
    required this.runwayDaysWithoutNewRevenue,
    required this.averageDailyBurn,
    required this.expectedReceivablesTotal,
    required this.committedOutflowsTotal,
    required this.dailyTimeline,
    required this.alerts,
    required this.hasSolvencyRisk,
  });
}

/// Autonomous, local-first engine for cash flow projection, invoice collection velocity, and liquidity protection.
class CashFlowForecastingEngine {
  /// Default client payment DSO (Days Sales Outstanding) when historical data is absent.
  static const int kDefaultDsoDays = 14;

  /// Generates a forward-looking cash flow forecast for [forecastDays] (default 90).
  static CashFlowForecastResult generateForecast({
    required double startingBalance,
    required List<InvoiceModel> invoices,
    required List<Receipt> receipts,
    required List<TaxCalendarEvent> scheduledTaxes,
    List<DetectedSubscription> activeSubscriptions = const [],
    int forecastDays = 90,
    DateTime? referenceDate,
    double safetyBuffer = 500.0,
  }) {
    final now = referenceDate ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // 1. Compute Historical DSO per client
    final Map<String, List<int>> clientPaymentLags = {};
    for (final inv in invoices) {
      if (inv.status == InvoiceStatus.settled && inv.dueDate != null) {
        final issued = DateTime(inv.issuedDate.year, inv.issuedDate.month, inv.issuedDate.day);
        final due = DateTime(inv.dueDate!.year, inv.dueDate!.month, inv.dueDate!.day);
        final lag = due.difference(issued).inDays;
        if (lag >= 0) {
          clientPaymentLags.putIfAbsent(inv.clientName.trim().toLowerCase(), () => []).add(lag);
        }
      }
    }

    // 2. Compute 30-Day Historical Baseline Daily Variable Burn
    final thirtyDaysAgo = today.subtract(const Duration(days: 30));
    double recentVariableExpenses = 0.0;
    for (final r in receipts) {
      if (r.date.isAfter(thirtyDaysAgo) && !r.date.isAfter(today)) {
        recentVariableExpenses += r.totalAmount;
      }
    }
    final baselineDailyBurn = recentVariableExpenses > 0 ? (recentVariableExpenses / 30.0) : 0.0;

    // 3. Map Expected Pending Inflows
    final Map<DateTime, List<(String, double)>> dailyInflows = {};
    double totalExpectedReceivables = 0.0;

    for (final inv in invoices) {
      if (inv.status == InvoiceStatus.sent || inv.status == InvoiceStatus.overdue || inv.status == InvoiceStatus.draft) {
        final clientKey = inv.clientName.trim().toLowerCase();
        final lags = clientPaymentLags[clientKey];
        final clientDso = (lags != null && lags.isNotEmpty)
            ? (lags.reduce((a, b) => a + b) / lags.length).round()
            : kDefaultDsoDays;

        DateTime expectedArrival;
        if (inv.dueDate != null && inv.dueDate!.isAfter(today)) {
          expectedArrival = DateTime(inv.dueDate!.year, inv.dueDate!.month, inv.dueDate!.day);
        } else {
          expectedArrival = DateTime(inv.issuedDate.year, inv.issuedDate.month, inv.issuedDate.day)
              .add(Duration(days: clientDso));
        }

        // If expected arrival is in the past, assume it settles in 2 days
        if (expectedArrival.isBefore(today)) {
          expectedArrival = today.add(const Duration(days: 2));
        }

        dailyInflows.putIfAbsent(expectedArrival, () => []).add((inv.clientName, inv.amount));
        totalExpectedReceivables += inv.amount;
      }
    }

    // 4. Map Scheduled Tax Outflows
    final Map<DateTime, List<(String, double)>> dailyTaxOutflows = {};
    for (final tax in scheduledTaxes) {
      final dueDate = DateTime(tax.dueDate.year, tax.dueDate.month, tax.dueDate.day);
      if (!dueDate.isBefore(today) && tax.estimatedPaymentAmount > 0) {
        dailyTaxOutflows.putIfAbsent(dueDate, () => []).add((tax.title, tax.estimatedPaymentAmount));
      }
    }

    // 5. Simulate Day-by-Day Financial Timeline
    final List<DailyCashForecast> timeline = [];
    final List<SolvencyAlert> alerts = [];

    double currentBalance = startingBalance;
    double minBalance = startingBalance;
    DateTime minDate = today;
    double totalCommittedOutflows = 0.0;
    int runwayDays = forecastDays;
    bool runwayDepleted = false;

    // Running balance for runway calculation (assuming zero new inflows)
    double noInflowBalance = startingBalance;

    for (int dayOffset = 0; dayOffset <= forecastDays; dayOffset++) {
      final date = today.add(Duration(days: dayOffset));

      double dayInflow = 0.0;
      final inflowSources = <String>[];

      double dayOutflow = baselineDailyBurn;
      final outflowReasons = <String>[];
      if (baselineDailyBurn > 0) {
        outflowReasons.add('Baseline Daily Burn (\$${baselineDailyBurn.toStringAsFixed(2)})');
      }

      // Check Inflows
      final inflowsOnDate = dailyInflows[date];
      if (inflowsOnDate != null) {
        for (final item in inflowsOnDate) {
          dayInflow += item.$2;
          inflowSources.add('${item.$1} Invoice (\$${item.$2.toStringAsFixed(2)})');
        }
      }

      // Check Scheduled Taxes
      final taxesOnDate = dailyTaxOutflows[date];
      if (taxesOnDate != null) {
        for (final item in taxesOnDate) {
          dayOutflow += item.$2;
          outflowReasons.add('${item.$1} (\$${item.$2.toStringAsFixed(2)})');
        }
      }

      // Check Recurring SaaS Subscriptions on specific day of month
      for (final sub in activeSubscriptions) {
        if (sub.cadence == SubscriptionCadence.monthly) {
          if (date.day == sub.lastObservedDate.day || (sub.lastObservedDate.day > 28 && date.day == 28)) {
            dayOutflow += sub.latestAmount;
            outflowReasons.add('${sub.merchantName} SaaS (\$${sub.latestAmount.toStringAsFixed(2)})');
          }
        }
      }

      totalCommittedOutflows += dayOutflow;
      currentBalance = currentBalance + dayInflow - dayOutflow;

      if (currentBalance < minBalance) {
        minBalance = currentBalance;
        minDate = date;
      }

      // Check Solvency Alerts
      if (currentBalance < safetyBuffer) {
        final deficit = safetyBuffer - currentBalance;
        alerts.add(SolvencyAlert(
          alertDate: date,
          deficitAmount: deficit,
          description: currentBalance < 0
              ? 'Negative cash position projected on ${date.month}/${date.day}: \$${currentBalance.toStringAsFixed(2)}'
              : 'Cash reserves drop below \$${safetyBuffer.toStringAsFixed(0)} safety buffer on ${date.month}/${date.day}: \$${currentBalance.toStringAsFixed(2)}',
          recommendedMitigation: currentBalance < 0
              ? 'Accelerate client invoice collections or defer non-essential expenses.'
              : 'Monitor receivables closely to maintain buffer for upcoming statutory tax liabilities.',
        ));
      }

      // Compute runway without new revenue
      if (!runwayDepleted) {
        noInflowBalance -= dayOutflow;
        if (noInflowBalance <= 0) {
          runwayDays = dayOffset;
          runwayDepleted = true;
        }
      }

      timeline.add(DailyCashForecast(
        date: date,
        projectedBalance: currentBalance,
        inflow: dayInflow,
        outflow: dayOutflow,
        inflowSources: inflowSources,
        outflowReasons: outflowReasons,
      ));
    }

    return CashFlowForecastResult(
      startingBalance: startingBalance,
      endingBalance: currentBalance,
      minProjectedBalance: minBalance,
      minBalanceDate: minDate,
      runwayDaysWithoutNewRevenue: runwayDays,
      averageDailyBurn: baselineDailyBurn,
      expectedReceivablesTotal: totalExpectedReceivables,
      committedOutflowsTotal: totalCommittedOutflows,
      dailyTimeline: timeline,
      alerts: alerts,
      hasSolvencyRisk: alerts.any((a) => a.deficitAmount > safetyBuffer),
    );
  }
}

/// Provider exposing autonomous cash flow projections.
final cashFlowForecastProvider = Provider<CashFlowForecastResult>((ref) {
  final invoices = ref.watch(invoicesProvider);
  final receipts = ref.watch(receiptListProvider).valueOrNull ?? [];
  final taxCalc = ref.watch(taxShieldCalculationProvider);

  final taxes = TaxCalendarEngine.generateFiscalCalendar(
    year: DateTime.now().year,
    annualLockedTaxReserve: taxCalc.lockedTaxShield,
  );
  final subscriptions = SubscriptionDetectorEngine.analyzeReceipts(receipts).activeSubscriptions;

  return CashFlowForecastingEngine.generateForecast(
    startingBalance: taxCalc.safeToSpend,
    invoices: invoices,
    receipts: receipts,
    scheduledTaxes: taxes,
    activeSubscriptions: subscriptions,
    forecastDays: 90,
  );
});

