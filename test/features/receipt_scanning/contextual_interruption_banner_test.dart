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
import 'package:t_aidy/features/receipt_scanning/presentation/widgets/contextual_interruption_banner.dart';

class MockBoxesNotifier extends StateNotifier<List<BoxModel>> implements BoxesNotifier {
  MockBoxesNotifier(super.state);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockReceiptListNotifier extends StateNotifier<AsyncValue<List<Receipt>>> implements ReceiptListNotifier {
  MockReceiptListNotifier(super.state);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockInvoicesNotifier extends StateNotifier<List<InvoiceModel>> implements InvoicesNotifier {
  MockInvoicesNotifier(super.state);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('ContextualInterruptionBanner displays DIF alert, triggers action, and supports dismiss', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1000));
    addTearDown(() async => await tester.binding.setSurfaceSize(null));

    // Create 6 round-number receipts to trigger high round-number DIF warning
    final roundReceipts = List.generate(
      6,
      (i) => Receipt(
        id: 'r_$i',
        merchantName: 'Round Vendor $i',
        totalAmount: 100.0,
        currency: 'USD',
        date: DateTime.now(),
        items: const [
          ReceiptItem(
            description: 'Estimate item',
            unitPrice: 100.0,
            quantity: 1,
            totalPrice: 100.0,
            mainCategory: 'Supplies',
          ),
        ],
      ),
    );

    final invoices = [
      InvoiceModel(
        id: 'inv-1',
        invoiceNumber: 'INV-001',
        clientName: 'Client A',
        amount: 5000.0,
        status: InvoiceStatus.settled,
        issuedDate: DateTime.now(),
      ),
    ];

    bool actionClicked = false;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          boxesProvider.overrideWith((ref) => MockBoxesNotifier([])),
          invoicesProvider.overrideWith((ref) => MockInvoicesNotifier(invoices)),
          receiptListProvider.overrideWith((ref) => MockReceiptListNotifier(AsyncValue.data(roundReceipts))),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ContextualInterruptionBanner(
              receipts: roundReceipts,
              onActionTriggered: () {
                actionClicked = true;
              },
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify DIF Audit Radar banner is rendered
    expect(find.text('IRS DIF AUDIT RADAR TRIGGER'), findsOneWidget);
    expect(find.text('Review Risk Factor'), findsOneWidget);

    // Tap the action button
    await tester.tap(find.text('Review Risk Factor'));
    await tester.pumpAndSettle();

    expect(actionClicked, isTrue);

    // Tap dismiss (close icon)
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    // Banner dismissed
    expect(find.text('IRS DIF AUDIT RADAR TRIGGER'), findsNothing);
  });

  testWidgets('ContextualInterruptionBanner displays 1099-NEC threshold alert, copies pre-filled W-9 template, and supports swipe-to-defer', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1000));
    addTearDown(() async => await tester.binding.setSurfaceSize(null));

    final contractorReceipts = [
      Receipt(
        id: 'rec_contractor_1',
        merchantName: 'John Contractor Dev',
        totalAmount: 1200.0,
        currency: 'USD',
        date: DateTime.now(),
        items: const [
          ReceiptItem(
            description: 'Flutter Engineering Consulting',
            unitPrice: 1200.0,
            quantity: 1,
            totalPrice: 1200.0,
            mainCategory: 'Professional Services',
          ),
        ],
      ),
    ];

    bool actionClicked = false;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          boxesProvider.overrideWith((ref) => MockBoxesNotifier([])),
          invoicesProvider.overrideWith((ref) => MockInvoicesNotifier([])),
          receiptListProvider.overrideWith((ref) => MockReceiptListNotifier(AsyncValue.data(contractorReceipts))),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ContextualInterruptionBanner(
              receipts: contractorReceipts,
              onActionTriggered: () {
                actionClicked = true;
              },
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify 1099-NEC alert is displayed
    expect(find.text('1099-NEC THRESHOLD EXCEEDED'), findsOneWidget);
    expect(find.textContaining('Contractor "John Contractor Dev" reached \$1,200. W-9 Missing.'), findsOneWidget);
    expect(find.text('Request W-9'), findsOneWidget);

    // Tap the pre-computed resolution action
    await tester.tap(find.text('Request W-9'));
    await tester.pumpAndSettle();

    expect(actionClicked, isTrue);

    // Test swipe-to-defer gesture
    await tester.drag(find.byType(Dismissible), const Offset(-500, 0));
    await tester.pumpAndSettle();

    // Banner is dismissed via swipe
    expect(find.text('1099-NEC THRESHOLD EXCEEDED'), findsNothing);
  });

  testWidgets('ContextualInterruptionBanner displays statutory tax deadline alert with Safe Harbor reserve action', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1000));
    addTearDown(() async => await tester.binding.setSurfaceSize(null));

    final sampleTaxCalc = TaxShieldCalculation(
      grossRevenue: 10000.0,
      totalExpenses: 2000.0,
      totalDeductibleExpenses: 2000.0,
      netTaxableIncome: 8000.0,
      effectiveTaxRate: 0.25,
      lockedTaxShield: 2000.0,
      taxSavingsEarned: 500.0,
      safeToSpend: 6000.0,
      currentQuarter: 2,
      currentYear: DateTime.now().year,
      nextQuarterDeadline: DateTime.now().add(const Duration(days: 10)),
      daysUntilDeadline: 10,
      profile: kTaxProfilePresets.first,
    );

    bool actionClicked = false;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          boxesProvider.overrideWith((ref) => MockBoxesNotifier([])),
          invoicesProvider.overrideWith((ref) => MockInvoicesNotifier([])),
          receiptListProvider.overrideWith((ref) => MockReceiptListNotifier(const AsyncValue.data([]))),
          taxShieldCalculationProvider.overrideWithValue(sampleTaxCalc),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ContextualInterruptionBanner(
              receipts: const [],
              onActionTriggered: () {
                actionClicked = true;
              },
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify statutory quarterly deadline banner
    expect(find.text('Q2 ESTIMATED TAX DUE IN 10 DAYS'), findsOneWidget);
    expect(find.textContaining('Statutory reserve: \$2,000 to satisfy Safe Harbor'), findsOneWidget);
    expect(find.text('Lock \$2,000 Reserve'), findsOneWidget);

    await tester.tap(find.text('Lock \$2,000 Reserve'));
    await tester.pumpAndSettle();

    expect(actionClicked, isTrue);
  });
}
