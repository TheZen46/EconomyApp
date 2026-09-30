import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/core/financial/tax_shield_provider.dart';
import 'package:t_aidy/features/boxes/data/models/box_model.dart';
import 'package:t_aidy/features/boxes/data/providers/boxes_provider.dart';
import 'package:t_aidy/features/invoices/data/providers/invoices_provider.dart';
import 'package:t_aidy/features/receipt_scanning/domain/entities/receipt.dart';
import 'package:t_aidy/features/receipt_scanning/presentation/providers/receipt_provider.dart';
import 'package:t_aidy/features/receipt_scanning/presentation/widgets/copilot_sheet.dart';

void main() {
  final sampleReceipts = [
    Receipt(
      id: 'rec-1',
      merchantName: 'Apple Store',
      totalAmount: 1500.0,
      date: DateTime.now(),
      items: [],
      currency: 'USD',
    ),
  ];

  final List<BoxModel> sampleBoxes = [
    BoxModel(
      id: 'main',
      name: 'Main Box',
      color: 0xFF3B82F6,
      icon: 'business',
      budget: 5000.0,
      spent: 1500.0,
      currency: 'USD',
    ),
  ];

  final sampleTaxCalc = TaxShieldCalculation(
    grossRevenue: 10000.0,
    totalExpenses: 1500.0,
    totalDeductibleExpenses: 1500.0,
    netTaxableIncome: 8500.0,
    effectiveTaxRate: 0.25,
    lockedTaxShield: 2125.0,
    taxSavingsEarned: 375.0,
    safeToSpend: 6375.0,
    currentQuarter: 1,
    currentYear: 2026,
    nextQuarterDeadline: DateTime(2026, 4, 15),
    daysUntilDeadline: 20,
    profile: kTaxProfilePresets.first,
  );

  testWidgets('CopilotSheet renders header, chips, and answers quick query on tap', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          boxesProvider.overrideWith((ref) => _FakeBoxesNotifier(sampleBoxes)),
          invoicesProvider.overrideWith((ref) => InvoicesNotifier()),
          taxShieldCalculationProvider.overrideWithValue(sampleTaxCalc),
          receiptListProvider.overrideWith((ref) => _FakeReceiptListNotifier(sampleReceipts)),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CopilotSheet(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ask tAIdy Financial Copilot'), findsOneWidget);
    expect(find.text('How much can I safely spend?'), findsOneWidget);

    // Tap quick prompt chip
    await tester.tap(find.text('How much can I safely spend?'));
    await tester.pumpAndSettle();

    // Verify response headline
    expect(find.text('Safe-to-Spend: \$6375.00'), findsOneWidget);
  });
}

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
