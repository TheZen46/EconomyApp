import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:t_aidy/features/receipt_scanning/domain/entities/receipt.dart';
import 'package:t_aidy/features/receipt_scanning/presentation/providers/receipt_provider.dart';

/// Recurrence cadence frequency.
enum SubscriptionCadence {
  monthly,
  annual,
  quarterly,
  irregular,
}

/// Profile of a detected active recurring SaaS subscription.
class DetectedSubscription {
  final String merchantName;
  final String normalizedMerchant;
  final double latestAmount;
  final double averageAmount;
  final SubscriptionCadence cadence;
  final int occurrenceCount;
  final DateTime firstObservedDate;
  final DateTime lastObservedDate;
  final DateTime estimatedNextRenewalDate;
  final double estimatedAnnualCost;
  final bool hasPriceIncreased;
  final double priceIncreaseAmount;
  final List<String> receiptIds;

  const DetectedSubscription({
    required this.merchantName,
    required this.normalizedMerchant,
    required this.latestAmount,
    required this.averageAmount,
    required this.cadence,
    required this.occurrenceCount,
    required this.firstObservedDate,
    required this.lastObservedDate,
    required this.estimatedNextRenewalDate,
    required this.estimatedAnnualCost,
    required this.hasPriceIncreased,
    required this.priceIncreaseAmount,
    required this.receiptIds,
  });
}

/// Consolidated portfolio SaaS & subscription report.
class SubscriptionReport {
  final List<DetectedSubscription> activeSubscriptions;
  final double totalMonthlySaaSExpense;
  final double totalAnnualSaaSBurn;
  final int totalSubscriptionCount;
  final List<DetectedSubscription> priceHikedSubscriptions;

  const SubscriptionReport({
    required this.activeSubscriptions,
    required this.totalMonthlySaaSExpense,
    required this.totalAnnualSaaSBurn,
    required this.totalSubscriptionCount,
    required this.priceHikedSubscriptions,
  });
}

/// Pure on-device recurring transaction and SaaS subscription detection engine.
class SubscriptionDetectorEngine {
  /// Analyzes a list of historical [Receipt]s and identifies recurring subscriptions.
  static SubscriptionReport analyzeReceipts(List<Receipt> receipts) {
    if (receipts.isEmpty) {
      return const SubscriptionReport(
        activeSubscriptions: [],
        totalMonthlySaaSExpense: 0.0,
        totalAnnualSaaSBurn: 0.0,
        totalSubscriptionCount: 0,
        priceHikedSubscriptions: [],
      );
    }

    // 1. Group receipts by normalized merchant name
    final Map<String, List<Receipt>> grouped = {};
    for (final r in receipts) {
      final key = _normalize(r.merchantName);
      if (key.isEmpty) continue;
      grouped.putIfAbsent(key, () => []).add(r);
    }

    final List<DetectedSubscription> subscriptions = [];

    // 2. Evaluate recurrence intervals and price consistency
    grouped.forEach((normKey, receiptList) {
      if (receiptList.length < 2) return;

      // Sort by date ascending
      receiptList.sort((a, b) => a.date.compareTo(b.date));

      final intervals = <int>[];
      for (int i = 1; i < receiptList.length; i++) {
        intervals.add(receiptList[i].date.difference(receiptList[i - 1].date).inDays);
      }

      final avgInterval = intervals.reduce((a, b) => a + b) / intervals.length;
      SubscriptionCadence cadence = SubscriptionCadence.irregular;

      if (avgInterval >= 25 && avgInterval <= 35) {
        cadence = SubscriptionCadence.monthly;
      } else if (avgInterval >= 80 && avgInterval <= 100) {
        cadence = SubscriptionCadence.quarterly;
      } else if (avgInterval >= 340 && avgInterval <= 390) {
        cadence = SubscriptionCadence.annual;
      }

      // If irregular or noisy, skip
      if (cadence == SubscriptionCadence.irregular) return;

      final amounts = receiptList.map((r) => r.totalAmount).toList();
      final latestAmount = amounts.last;
      final firstAmount = amounts.first;
      final avgAmount = amounts.reduce((a, b) => a + b) / amounts.length;

      final hasPriceIncreased = latestAmount > firstAmount + 0.01;
      final priceIncrease = hasPriceIncreased ? (latestAmount - firstAmount) : 0.0;

      double annualCost = 0.0;
      DateTime nextRenewal;

      if (cadence == SubscriptionCadence.monthly) {
        annualCost = latestAmount * 12.0;
        nextRenewal = receiptList.last.date.add(const Duration(days: 30));
      } else if (cadence == SubscriptionCadence.quarterly) {
        annualCost = latestAmount * 4.0;
        nextRenewal = receiptList.last.date.add(const Duration(days: 90));
      } else {
        annualCost = latestAmount;
        nextRenewal = receiptList.last.date.add(const Duration(days: 365));
      }

      subscriptions.add(DetectedSubscription(
        merchantName: receiptList.last.merchantName,
        normalizedMerchant: normKey,
        latestAmount: latestAmount,
        averageAmount: avgAmount,
        cadence: cadence,
        occurrenceCount: receiptList.length,
        firstObservedDate: receiptList.first.date,
        lastObservedDate: receiptList.last.date,
        estimatedNextRenewalDate: nextRenewal,
        estimatedAnnualCost: annualCost,
        hasPriceIncreased: hasPriceIncreased,
        priceIncreaseAmount: priceIncrease,
        receiptIds: receiptList.map((r) => r.id).toList(),
      ));
    });

    double totalMonthly = 0.0;
    double totalAnnual = 0.0;
    final List<DetectedSubscription> hiked = [];

    for (final s in subscriptions) {
      if (s.cadence == SubscriptionCadence.monthly) {
        totalMonthly += s.latestAmount;
        totalAnnual += s.latestAmount * 12.0;
      } else if (s.cadence == SubscriptionCadence.quarterly) {
        totalMonthly += s.latestAmount / 3.0;
        totalAnnual += s.latestAmount * 4.0;
      } else {
        totalMonthly += s.latestAmount / 12.0;
        totalAnnual += s.latestAmount;
      }

      if (s.hasPriceIncreased) {
        hiked.add(s);
      }
    }

    return SubscriptionReport(
      activeSubscriptions: subscriptions,
      totalMonthlySaaSExpense: totalMonthly,
      totalAnnualSaaSBurn: totalAnnual,
      totalSubscriptionCount: subscriptions.length,
      priceHikedSubscriptions: hiked,
    );
  }

  static String _normalize(String name) {
    return name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '')
        .replaceAll('inc', '')
        .replaceAll('llc', '')
        .replaceAll('corp', '')
        .trim();
  }
}

/// Provider for recurring subscriptions report.
final subscriptionReportProvider = Provider<SubscriptionReport>((ref) {
  final receiptsAsync = ref.watch(receiptListProvider);
  final receipts = receiptsAsync.valueOrNull ?? [];
  return SubscriptionDetectorEngine.analyzeReceipts(receipts);
});

