import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:t_aidy/core/financial/tax_shield_provider.dart';
import 'package:t_aidy/features/invoices/data/models/invoice_model.dart';
import 'package:t_aidy/features/invoices/data/providers/invoices_provider.dart';
import 'package:t_aidy/features/receipt_scanning/domain/entities/receipt.dart';
import 'package:t_aidy/features/receipt_scanning/presentation/providers/receipt_provider.dart';
import 'package:t_aidy/features/boxes/data/models/box_model.dart';
import 'package:t_aidy/features/boxes/data/providers/boxes_provider.dart';

class MockReceiptListNotifier extends StateNotifier<AsyncValue<List<Receipt>>> implements ReceiptListNotifier {
  MockReceiptListNotifier(super.state);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('Tax Shield Provider Tests', () {
    test('computes real-time gross revenue, deductible expenses, and safe-to-spend balance', () async {
      final sampleReceipts = [
        Receipt(
          id: 'r1',
          merchantName: 'Office Depot',
          date: DateTime(2026, 3, 10),
          totalAmount: 200.0,
          currency: 'USD',
          boxId: 'consulting_box',
          items: const [
            ReceiptItem(description: 'Printer Paper', unitPrice: 200.0, quantity: 1, totalPrice: 200.0, mainCategory: 'Office Supplies'),
          ],
        ),
        Receipt(
          id: 'r2',
          merchantName: 'Cinema Snack',
          date: DateTime(2026, 3, 12),
          totalAmount: 50.0,
          currency: 'USD',
          boxId: 'main',
          items: const [
            ReceiptItem(description: 'Popcorn', unitPrice: 50.0, quantity: 1, totalPrice: 50.0, mainCategory: 'Entertainment'),
          ],
        ),
      ];

      final container = ProviderContainer(
        overrides: [
          invoicesProvider.overrideWith((ref) => InvoicesNotifier()),
          boxesProvider.overrideWith((ref) => BoxesNotifier()),
          receiptListProvider.overrideWith((ref) => MockReceiptListNotifier(AsyncValue.data(sampleReceipts))),
        ],
      );

      // Add a business box
      await container.read(boxesProvider.notifier).addBox(BoxModel(
        id: 'consulting_box',
        name: 'Consulting Ops',
        budget: 1000,
        spent: 200,
        currency: 'USD',
        color: 0xFF10B981,
      ));

      // Create a settled invoice and await completion
      await container.read(invoicesProvider.notifier).createInvoice(
        clientName: 'Acme Corp',
        amount: 2000.0,
        status: InvoiceStatus.settled,
        issuedDate: DateTime(2026, 3, 1),
      );

      final calc = container.read(taxShieldCalculationProvider);

      expect(calc.grossRevenue, 2000.0);
      expect(calc.totalExpenses, 250.0);
      expect(calc.totalDeductibleExpenses, 200.0);
      expect(calc.netTaxableIncome, 1800.0); // 2000 - 200
      expect(calc.effectiveTaxRate, 0.25);
      expect(calc.lockedTaxShield, 450.0); // 1800 * 0.25
      expect(calc.taxSavingsEarned, 50.0); // 200 * 0.25
      expect(calc.safeToSpend, 1300.0); // 2000 - 450 - 250
    });
  });
}
