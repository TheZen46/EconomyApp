import 'dart:math' as math;
import '../../receipt_scanning/domain/entities/receipt.dart';
import '../data/models/box_model.dart';

/// Budget health status calculated from predictive spend velocity.
enum BudgetHealthStatus {
  /// Projected spend is safely below 85% of budget.
  onTrack,

  /// Projected spend is between 85% and 100% of budget.
  warning,

  /// Projected spend exceeds 100% of budget.
  overBudget,

  /// No budget configured for this context.
  noBudget,
}

/// Rolling velocity window selection.
enum VelocityWindow {
  days7(7, '7-Day Rolling'),
  days14(14, '14-Day Rolling'),
  days30(30, '30-Day Rolling');

  final int days;
  final String label;
  const VelocityWindow(this.days, this.label);
}

/// Structured calculation results for predictive budget burn-rate forecasting.
class BurnRateMetrics {
  final double currentSpend;
  final double dailyVelocity;
  final double projectedEomSpend;
  final double budget;
  final double budgetConsumptionRatio;
  final double projectedDelta;
  final int daysInMonth;
  final int currentDayOfMonth;
  final int remainingDaysInMonth;
  final VelocityWindow window;
  final BudgetHealthStatus status;
  final String currency;

  const BurnRateMetrics({
    required this.currentSpend,
    required this.dailyVelocity,
    required this.projectedEomSpend,
    required this.budget,
    required this.budgetConsumptionRatio,
    required this.projectedDelta,
    required this.daysInMonth,
    required this.currentDayOfMonth,
    required this.remainingDaysInMonth,
    required this.window,
    required this.status,
    required this.currency,
  });

  /// Percentage of total monthly budget projected to be spent by EOM.
  double get projectedPercentage => budget > 0 ? (projectedEomSpend / budget) * 100.0 : 0.0;

  /// Whether current velocity puts the user in danger of overspending.
  bool get isAtRisk => status == BudgetHealthStatus.warning || status == BudgetHealthStatus.overBudget;
}

/// Domain utility for predictive budget burn-rate forecasting.
class BurnRateCalculator {
  /// Calculates predictive spending metrics for a given Box context and receipt history.
  static BurnRateMetrics calculate({
    required BoxModel? box,
    required List<Receipt> receipts,
    VelocityWindow window = VelocityWindow.days7,
    DateTime? referenceDate,
    String defaultCurrency = 'USD',
  }) {
    final now = referenceDate ?? DateTime.now();
    final currentYear = now.year;
    final currentMonth = now.month;
    final currentDay = now.day;
    final totalDaysInMonth = _getDaysInMonth(currentYear, currentMonth);
    final remainingDays = math.max(0, totalDaysInMonth - currentDay);

    final boxId = box?.id ?? 'main';
    final budget = box?.budget ?? 0.0;
    final currency = box?.currency ?? (receipts.isNotEmpty ? receipts.first.currency : defaultCurrency);

    // 1. Filter receipts matching the active Box (or all if 'all'/'main' with fallback)
    final boxReceipts = receipts.where((r) {
      if (boxId == 'all') return true;
      return (r.boxId ?? 'main') == boxId;
    }).toList();

    // 2. Current Month Spend
    final currentMonthReceipts = boxReceipts.where((r) {
      return r.date.year == currentYear && r.date.month == currentMonth && r.date.isBefore(now.add(const Duration(days: 1)));
    }).toList();

    final currentMonthSpend = currentMonthReceipts.fold<double>(
      0.0,
      (sum, r) => sum + r.totalAmount,
    );

    // 3. Rolling Window Spend Calculation
    final windowStartDate = now.subtract(Duration(days: window.days));
    final windowReceipts = boxReceipts.where((r) {
      return r.date.isAfter(windowStartDate) && r.date.isBefore(now.add(const Duration(days: 1)));
    }).toList();

    final windowSpend = windowReceipts.fold<double>(
      0.0,
      (sum, r) => sum + r.totalAmount,
    );

    // Effective days elapsed for velocity
    final effectiveDays = math.max(1, math.min(currentDay, window.days));
    final dailyVelocity = windowSpend / effectiveDays;

    // 4. Projected End-of-Month Spend
    // Formula: Projected = CurrentSpend + (Velocity * RemainingDays)
    final projectedEomSpend = currentMonthSpend + (dailyVelocity * remainingDays);

    // 5. Budget Status Determination
    final BudgetHealthStatus status;
    final double consumptionRatio;
    final double projectedDelta;

    if (budget <= 0.0) {
      status = BudgetHealthStatus.noBudget;
      consumptionRatio = 0.0;
      projectedDelta = 0.0;
    } else {
      consumptionRatio = (projectedEomSpend / budget).clamp(0.0, 3.0);
      projectedDelta = projectedEomSpend - budget;

      if (projectedEomSpend <= budget * 0.85) {
        status = BudgetHealthStatus.onTrack;
      } else if (projectedEomSpend <= budget) {
        status = BudgetHealthStatus.warning;
      } else {
        status = BudgetHealthStatus.overBudget;
      }
    }

    return BurnRateMetrics(
      currentSpend: currentMonthSpend,
      dailyVelocity: dailyVelocity,
      projectedEomSpend: projectedEomSpend,
      budget: budget,
      budgetConsumptionRatio: consumptionRatio,
      projectedDelta: projectedDelta,
      daysInMonth: totalDaysInMonth,
      currentDayOfMonth: currentDay,
      remainingDaysInMonth: remainingDays,
      window: window,
      status: status,
      currency: currency,
    );
  }

  static int _getDaysInMonth(int year, int month) {
    if (month == 12) {
      return 31;
    }
    return DateTime(year, month + 1, 0).day;
  }
}
