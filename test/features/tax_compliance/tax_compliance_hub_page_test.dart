import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/core/financial/tax_shield_provider.dart';
import 'package:t_aidy/features/boxes/data/models/box_model.dart';
import 'package:t_aidy/features/boxes/data/providers/boxes_provider.dart';
import 'package:t_aidy/features/invoices/data/models/invoice_model.dart';
import 'package:t_aidy/features/invoices/data/providers/invoices_provider.dart';
import 'package:t_aidy/features/receipt_scanning/domain/entities/receipt.dart';
import 'package:t_aidy/features/receipt_scanning/presentation/providers/receipt_provider.dart';
import 'package:t_aidy/features/tax_compliance/presentation/pages/tax_compliance_hub_page.dart';

class _FakeBoxesNotifier extends BoxesNotifier {
  _FakeBoxesNotifier(List<BoxModel> initial) {
    state = initial;
  }
}

class _FakeReceiptListNotifier extends StateNotifier<AsyncValue<List<Receipt>>> implements ReceiptListNotifier {
  _FakeReceiptListNotifier(List<Receipt> receipts) : super(AsyncValue.data(receipts));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeInvoicesNotifier extends InvoicesNotifier {
  _FakeInvoicesNotifier(List<InvoiceModel> initial) {
    state = initial;
  }
}

void main() {
  final sampleReceipts = [
    Receipt(
      id: 'r1',
      merchantName: 'Figma Inc',
      totalAmount: 15.0,
      date: DateTime.now().subtract(const Duration(days: 30)),
      currency: 'USD',
      items: const [
        ReceiptItem(description: 'Figma Subscription', unitPrice: 15.0, quantity: 1, totalPrice: 15.0, mainCategory: 'Software'),
      ],
    ),
    Receipt(
      id: 'r2',
      merchantName: 'Figma Inc',
      totalAmount: 15.0,
      date: DateTime.now(),
      currency: 'USD',
      items: const [
        ReceiptItem(description: 'Figma Subscription', unitPrice: 15.0, quantity: 1, totalPrice: 15.0, mainCategory: 'Software'),
      ],
    ),
    Receipt(
      id: 'r3',
      merchantName: 'John Contractor Dev',
      totalAmount: 1200.0,
      date: DateTime.now(),
      currency: 'USD',
      items: const [
        ReceiptItem(description: 'Flutter Engineering Services', unitPrice: 1200.0, quantity: 1, totalPrice: 1200.0, mainCategory: 'Professional Services'),
      ],
    ),
  ];

  final sampleBoxes = [
    BoxModel(
      id: 'consulting_box',
      name: 'Consulting Ops',
      budget: 10000.0,
      spent: 1230.0,
      currency: 'USD',
      color: 0xFF10B981,
    ),
  ];

  final sampleInvoices = [
    InvoiceModel(
      id: 'inv-1',
      invoiceNumber: 'INV-2026-001',
      clientName: 'Big Client Inc',
      amount: 8000.0,
      status: InvoiceStatus.settled,
      issuedDate: DateTime(DateTime.now().year, 1, 15),
      dueDate: DateTime(DateTime.now().year, 2, 1),
    ),
  ];

  final sampleTaxCalc = TaxShieldCalculation(
    grossRevenue: 8000.0,
    totalExpenses: 1230.0,
    totalDeductibleExpenses: 1230.0,
    netTaxableIncome: 6770.0,
    effectiveTaxRate: 0.25,
    lockedTaxShield: 1692.5,
    taxSavingsEarned: 307.5,
    safeToSpend: 5077.5,
    currentQuarter: 1,
    currentYear: DateTime.now().year,
    nextQuarterDeadline: DateTime(DateTime.now().year, 4, 15),
    daysUntilDeadline: 20,
    profile: kTaxProfilePresets.first,
  );

  testWidgets('TaxComplianceHubPage renders tabs, quarterly deadlines, 1099 radar, SaaS and P&L', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          boxesProvider.overrideWith((ref) => _FakeBoxesNotifier(sampleBoxes)),
          invoicesProvider.overrideWith((ref) => _FakeInvoicesNotifier(sampleInvoices)),
          taxShieldCalculationProvider.overrideWithValue(sampleTaxCalc),
          receiptListProvider.overrideWith((ref) => _FakeReceiptListNotifier(sampleReceipts)),
        ],
        child: const MaterialApp(
          home: TaxComplianceHubPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify Title and Tabs
    expect(find.text('Tax & Compliance Command Center'), findsOneWidget);
    expect(find.text('Quarterly Deadlines'), findsOneWidget);
    expect(find.text('1099-NEC Radar'), findsOneWidget);
    expect(find.text('SaaS Subscriptions'), findsOneWidget);
    expect(find.text('Entity P&L'), findsOneWidget);

    // Verify Quarterly tab content
    expect(find.text('Next Estimated Tax Deadline'), findsOneWidget);
    expect(find.text('Export .ics Tax Calendar'), findsOneWidget);

    // Switch to 1099-NEC Radar tab
    await tester.tap(find.text('1099-NEC Radar'));
    await tester.pumpAndSettle();

    expect(find.text('1099-NEC Required'), findsOneWidget);
    expect(find.text('John Contractor Dev'), findsOneWidget);
    expect(find.text('W-9 Missing'), findsOneWidget);

    // Switch to SaaS Subscriptions tab
    await tester.tap(find.text('SaaS Subscriptions'));
    await tester.pumpAndSettle();

    expect(find.text('Monthly SaaS Burn'), findsOneWidget);
    expect(find.text('Annualized SaaS'), findsOneWidget);
    expect(find.text('Figma Inc'), findsOneWidget);

    // Switch to Entity P&L tab
    await tester.tap(find.text('Entity P&L'));
    await tester.pumpAndSettle();

    expect(find.text('Multi-Box Entity Performance'), findsOneWidget);
    expect(find.text('Consulting Ops'), findsOneWidget);

    // Switch to Cash Runway tab
    await tester.tap(find.text('Cash Runway'));
    await tester.pumpAndSettle();

    expect(find.text('90-Day Cash Runway Forecast'), findsOneWidget);
    expect(find.text('Pending Receivables'), findsOneWidget);

    // Switch to Audit Shield tab
    await tester.tap(find.text('Audit Shield'));
    await tester.pumpAndSettle();

    expect(find.text('IRS Statutory Audit Risk Index'), findsOneWidget);
    expect(find.text('Export Merkle Audit Dossier (.html)'), findsOneWidget);

    // Switch to Flow & 8829 Home Office tab
    await tester.tap(find.text('Flow & 8829 Home Office'));
    await tester.pumpAndSettle();

    expect(find.text('Capital Allocation Flow (Sankey / Waterfall)'), findsOneWidget);

    // Scroll down to reveal the Form 8829 section
    await tester.drag(find.byType(ListView).last, const Offset(0, -500));
    await tester.pumpAndSettle();

    expect(find.text('IRS Form 8829 Home Office Optimizer'), findsOneWidget);
    expect(find.text('Optimal Tax Shield Deduction'), findsOneWidget);

    // Scroll further down to reveal Section 199A QBI Pass-Through Optimizer
    await tester.drag(find.byType(ListView).last, const Offset(0, -500));
    await tester.pumpAndSettle();

    expect(find.text('IRC § 199A QBI Pass-Through Optimizer'), findsOneWidget);
    expect(find.text('Allowable Section 199A Deduction'), findsOneWidget);
    expect(find.text('20% PASS-THROUGH SHIELD'), findsOneWidget);
    expect(find.text('Tentative 20% QBI'), findsOneWidget);
    expect(find.text('Estimated Tax Savings'), findsOneWidget);

    // Scroll back up and ensure node chip is visible
    await tester.drag(find.byType(ListView).last, const Offset(0, 1200));
    await tester.pumpAndSettle();

    // Tap a node chip in the flow topology widget to open the isolated receipts bottom sheet
    final nodeChip = find.textContaining('Gross Inflow:').first;
    expect(nodeChip, findsOneWidget);
    await tester.ensureVisible(nodeChip);
    await tester.pumpAndSettle();
    await tester.tap(nodeChip);
    await tester.pumpAndSettle();

    // Verify Isolated Flow bottom sheet appears
    expect(find.textContaining('Isolated Flow:'), findsOneWidget);
    expect(find.text('Settled Invoices'), findsOneWidget);
    expect(find.text('Big Client Inc'), findsOneWidget);
  });
}
