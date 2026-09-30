import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/core/financial/tax_shield_provider.dart';
import 'package:t_aidy/core/financial/mileage_engine.dart';
import 'package:t_aidy/core/services/financial_copilot_service.dart';
import 'package:t_aidy/features/boxes/data/models/box_model.dart';
import 'package:t_aidy/features/invoices/data/models/invoice_model.dart';
import 'package:t_aidy/features/receipt_scanning/domain/entities/receipt.dart';

void main() {
  group('FinancialCopilotService Tests', () {
    final taxCalc = TaxShieldCalculation(
      grossRevenue: 12000.0,
      totalExpenses: 3000.0,
      totalDeductibleExpenses: 2500.0,
      netTaxableIncome: 9500.0,
      effectiveTaxRate: 0.25,
      lockedTaxShield: 2375.0,
      taxSavingsEarned: 625.0,
      safeToSpend: 6625.0,
      currentQuarter: 1,
      currentYear: 2026,
      nextQuarterDeadline: DateTime(2026, 4, 15),
      daysUntilDeadline: 20,
      profile: kTaxProfilePresets.first,
    );

    final boxes = [
      BoxModel(
        id: 'box-acme',
        name: 'Acme Project',
        color: 0xFF3B82F6,
        icon: 'business',
        budget: 5000.0,
        spent: 1200.0,
        currency: 'USD',
      ),
    ];

    final receipts = [
      Receipt(
        id: 'rec-1',
        merchantName: 'Apple Store',
        totalAmount: 1200.0,
        date: DateTime(2026, 3, 1),
        boxId: 'box-acme',
        items: [],
        currency: 'USD',
      ),
      Receipt(
        id: 'rec-2',
        merchantName: 'Trader Joe\'s',
        totalAmount: 85.0,
        date: DateTime(2026, 3, 5),
        boxId: null,
        items: [],
        currency: 'USD',
      ),
    ];

    final invoices = [
      InvoiceModel(
        id: 'inv-1',
        invoiceNumber: 'INV-001',
        clientName: 'Acme Corp',
        issuedDate: DateTime(2026, 3, 1),
        amount: 5000.0,
        status: InvoiceStatus.sent,
      ),
    ];

    final mileage = [
      MileageTrip(
        id: 'trip-1',
        date: DateTime(2026, 3, 10),
        purpose: 'Acme Onsite Delivery',
        startLocation: 'Office',
        endLocation: 'Acme',
        distance: 20.0,
        unit: DistanceUnit.miles,
        ratePerUnit: 0.67,
        boxId: 'box-acme',
      ),
    ];

    test('answers "How much can I safely spend?" accurately with tax reserve', () {
      final ans = FinancialCopilotService.answerQuery(
        query: 'How much can I safely spend right now?',
        receipts: receipts,
        invoices: invoices,
        boxes: boxes,
        mileageTrips: mileage,
        taxCalculation: taxCalc,
      );

      expect(ans.intent, CopilotQueryIntent.taxReserveAndSafeToSpend);
      expect(ans.headline.contains('\$6625.00'), true);
      expect(ans.detailedExplanation.contains('2375.00'), true);
      expect(ans.suggestions.isNotEmpty, true);
    });

    test('answers questions about specific box project expenses', () {
      final ans = FinancialCopilotService.answerQuery(
        query: 'What did I spend on Acme Project?',
        receipts: receipts,
        invoices: invoices,
        boxes: boxes,
        mileageTrips: mileage,
        taxCalculation: taxCalc,
      );

      expect(ans.intent, CopilotQueryIntent.spendByBox);
      expect(ans.headline.contains('\$1200.00'), true);
    });

    test('answers queries about uncollected / overdue invoices', () {
      final ans = FinancialCopilotService.answerQuery(
        query: 'Do I have any unpaid invoices?',
        receipts: receipts,
        invoices: invoices,
        boxes: boxes,
        mileageTrips: mileage,
        taxCalculation: taxCalc,
      );

      expect(ans.intent, CopilotQueryIntent.overdueInvoices);
      expect(ans.headline.contains('\$5000.00'), true);
    });

    test('answers queries about business mileage deductions', () {
      final ans = FinancialCopilotService.answerQuery(
        query: 'What is my total travel mileage deduction?',
        receipts: receipts,
        invoices: invoices,
        boxes: boxes,
        mileageTrips: mileage,
        taxCalculation: taxCalc,
      );

      expect(ans.intent, CopilotQueryIntent.mileageSummary);
      expect(ans.headline.contains('\$13.40'), true);
    });
  });
}
