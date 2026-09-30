import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/core/financial/cash_flow_forecasting_engine.dart';
import 'package:t_aidy/core/financial/subscription_detector_engine.dart';
import 'package:t_aidy/core/financial/tax_calendar_engine.dart';
import 'package:t_aidy/features/invoices/data/models/invoice_model.dart';
import 'package:t_aidy/features/receipt_scanning/domain/entities/receipt.dart';

void main() {
  group('CashFlowForecastingEngine Tests', () {
    final refDate = DateTime(2026, 4, 1);

    test('projects positive cash flow when receivables exceed baseline burn', () {
      final sampleInvoices = [
        // Historical settled invoice (for DSO calculation: issued Jan 1, due Jan 15 = 14 days DSO)
        InvoiceModel(
          id: 'inv-hist',
          invoiceNumber: 'INV-001',
          clientName: 'Acme Corp',
          amount: 5000.0,
          status: InvoiceStatus.settled,
          issuedDate: DateTime(2026, 1, 1),
          dueDate: DateTime(2026, 1, 15),
        ),
        // Open pending invoice
        InvoiceModel(
          id: 'inv-open',
          invoiceNumber: 'INV-002',
          clientName: 'Acme Corp',
          amount: 6000.0,
          status: InvoiceStatus.sent,
          issuedDate: DateTime(2026, 4, 1),
          dueDate: DateTime(2026, 4, 15),
        ),
      ];

      final sampleReceipts = [
        Receipt(
          id: 'r1',
          merchantName: 'Supermarket',
          totalAmount: 300.0,
          date: DateTime(2026, 3, 20),
          currency: 'USD',
          items: const [],
        ),
      ];

      final sampleTaxes = [
        TaxCalendarEvent(
          id: 'tax-q1',
          title: 'Q1 Estimated Tax Due',
          jurisdiction: 'USA',
          dueDate: DateTime(2026, 4, 15),
          description: 'Q1 Tax',
          estimatedPaymentAmount: 1500.0,
          daysRemaining: 14,
          isOverdue: false,
        ),
      ];

      final result = CashFlowForecastingEngine.generateForecast(
        startingBalance: 2000.0,
        invoices: sampleInvoices,
        receipts: sampleReceipts,
        scheduledTaxes: sampleTaxes,
        forecastDays: 30,
        referenceDate: refDate,
      );

      expect(result.startingBalance, 2000.0);
      expect(result.expectedReceivablesTotal, 6000.0);
      expect(result.endingBalance, greaterThan(2000.0));
      expect(result.dailyTimeline.length, 31); // 0 to 30 days
      expect(result.hasSolvencyRisk, false);
    });

    test('flags solvency danger when tax liability exceeds balance before invoice arrives', () {
      final sampleInvoices = [
        InvoiceModel(
          id: 'inv-late',
          invoiceNumber: 'INV-003',
          clientName: 'Slow Client LLC',
          amount: 10000.0,
          status: InvoiceStatus.sent,
          issuedDate: DateTime(2026, 4, 1),
          dueDate: DateTime(2026, 4, 25), // Arrives on April 25
        ),
      ];

      final sampleTaxes = [
        TaxCalendarEvent(
          id: 'tax-q1',
          title: 'Q1 Estimated Tax Due',
          jurisdiction: 'USA',
          dueDate: DateTime(2026, 4, 15), // Due on April 15 ($4,000)
          description: 'Q1 Tax',
          estimatedPaymentAmount: 4000.0,
          daysRemaining: 14,
          isOverdue: false,
        ),
      ];

      final result = CashFlowForecastingEngine.generateForecast(
        startingBalance: 1000.0, // Only $1,000 starting cash
        invoices: sampleInvoices,
        receipts: const [],
        scheduledTaxes: sampleTaxes,
        forecastDays: 30,
        referenceDate: refDate,
        safetyBuffer: 500.0,
      );

      // On April 15, balance drops from $1,000 to -$3,000 before $10k arrives on April 25
      expect(result.hasSolvencyRisk, true);
      expect(result.minProjectedBalance, lessThan(0.0));
      expect(result.alerts.isNotEmpty, true);
    });

    test('accurately accounts for monthly SaaS subscription outflows on billing day', () {
      final activeSubs = [
        DetectedSubscription(
          merchantName: 'GitHub Copilot',
          normalizedMerchant: 'github',
          latestAmount: 20.0,
          averageAmount: 20.0,
          cadence: SubscriptionCadence.monthly,
          occurrenceCount: 3,
          firstObservedDate: DateTime(2026, 1, 10),
          lastObservedDate: DateTime(2026, 3, 10),
          estimatedNextRenewalDate: DateTime(2026, 4, 10),
          estimatedAnnualCost: 240.0,
          hasPriceIncreased: false,
          priceIncreaseAmount: 0.0,
          receiptIds: const ['r1', 'r2', 'r3'],
        ),
      ];

      final result = CashFlowForecastingEngine.generateForecast(
        startingBalance: 500.0,
        invoices: const [],
        receipts: const [],
        scheduledTaxes: const [],
        activeSubscriptions: activeSubs,
        forecastDays: 15,
        referenceDate: refDate, // April 1 -> April 10 is day 9
      );

      // On April 10 (day 9), outflow should include GitHub Copilot ($20.00)
      final april10 = result.dailyTimeline.firstWhere((d) => d.date.day == 10);
      expect(april10.outflow, greaterThanOrEqualTo(20.0));
      expect(april10.outflowReasons.any((r) => r.contains('GitHub Copilot')), true);
    });
  });
}
