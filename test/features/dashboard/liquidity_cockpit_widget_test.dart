import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/features/boxes/data/models/box_model.dart';
import 'package:t_aidy/features/boxes/data/providers/boxes_provider.dart';
import 'package:t_aidy/features/invoices/data/models/invoice_model.dart';
import 'package:t_aidy/features/invoices/data/providers/invoices_provider.dart';
import 'package:t_aidy/features/receipt_scanning/domain/entities/receipt.dart';
import 'package:t_aidy/features/receipt_scanning/presentation/providers/receipt_provider.dart';
import 'package:t_aidy/features/dashboard/presentation/widgets/liquidity_cockpit_widget.dart';

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
  testWidgets('LiquidityCockpitWidget renders 28pt/14pt hierarchy, formula, 1-click dunning notice, and entity strips', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1400));
    addTearDown(() async => await tester.binding.setSurfaceSize(null));

    final testBoxes = [
      BoxModel(id: 'main', name: 'Main LLC Box', budget: 5000, spent: 1000, currency: 'USD', color: 0xFF10B981),
      BoxModel(id: 'side', name: 'Side Freelance', budget: 3000, spent: 500, currency: 'USD', color: 0xFF38BDF8),
    ];

    final sampleReceipts = [
      Receipt(
        id: 'r1',
        merchantName: 'GitHub Copilot',
        totalAmount: 19.00,
        currency: 'USD',
        date: DateTime.now(),
        items: [
          const ReceiptItem(
            description: 'Monthly Copilot Subscription',
            unitPrice: 19.00,
            quantity: 1,
            totalPrice: 19.00,
            mainCategory: 'Software & Subscriptions',
          ),
        ],
      ),
    ];

    final sampleInvoices = [
      InvoiceModel(
        id: 'inv-overdue',
        invoiceNumber: 'INV-2026-042',
        clientName: 'Acme Corp',
        amount: 4500.0,
        issuedDate: DateTime.now().subtract(const Duration(days: 45)),
        dueDate: DateTime.now().subtract(const Duration(days: 15)),
        status: InvoiceStatus.overdue,
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          boxesProvider.overrideWith((ref) => MockBoxesNotifier(testBoxes)),
          receiptListProvider.overrideWith((ref) => MockReceiptListNotifier(AsyncValue.data(sampleReceipts))),
          invoicesProvider.overrideWith((ref) => MockInvoicesNotifier(sampleInvoices)),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: LiquidityCockpitWidget(
                receipts: [],
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 1. Verify Typography Hierarchy
    expect(find.text('AIR-GAPPED VAULT ACTIVE'), findsOneWidget);
    expect(find.text('SAFE-TO-SPEND LIQUIDITY'), findsOneWidget);
    expect(find.textContaining('TAX RESERVE'), findsOneWidget);

    // 2. Verify Mathematical Decomposition Ribbon
    expect(find.text('Gross Inflows'), findsOneWidget);
    expect(find.textContaining('Tax Shield'), findsOneWidget);
    expect(find.text('OpEx / SaaS'), findsOneWidget);
    expect(find.text('Safe Nest'), findsOneWidget);

    // 3. Verify Contextual 1-Click Dunning Notice for overdue invoice
    expect(find.textContaining('Acme Corp'), findsWidgets);
    expect(find.text('1-Click Dunning Notice'), findsOneWidget);

    // Tap 1-Click Dunning Notice
    await tester.tap(find.text('1-Click Dunning Notice'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Offline Dunning Notice copied'), findsOneWidget);

    // 4. Verify Modular Entity Strips
    expect(find.text('MODULAR ENTITY STRIPS'), findsOneWidget);
    expect(find.text('Main LLC Box'), findsOneWidget);
    expect(find.text('Side Freelance'), findsOneWidget);

    // 5. Verify Predictive Action Ribbon
    expect(find.text('Capture Ingestion'), findsOneWidget);
    expect(find.text('Tax Hub'), findsOneWidget);
    expect(find.text('What-If'), findsOneWidget);
  });
}
