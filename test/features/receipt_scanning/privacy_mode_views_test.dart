import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:t_aidy/features/boxes/data/models/box_model.dart';
import 'package:t_aidy/features/boxes/data/providers/boxes_provider.dart';
import 'package:t_aidy/features/boxes/presentation/pages/boxes_page.dart';
import 'package:t_aidy/features/evault/data/models/asset_model.dart';
import 'package:t_aidy/features/evault/presentation/pages/vault_page.dart';
import 'package:t_aidy/features/evault/presentation/providers/asset_provider.dart';
import 'package:t_aidy/features/invoices/data/models/invoice_model.dart';
import 'package:t_aidy/features/invoices/data/providers/invoices_provider.dart';
import 'package:t_aidy/features/invoices/presentation/pages/invoices_page.dart';
import 'package:t_aidy/features/receipt_scanning/domain/entities/receipt.dart';
import 'package:t_aidy/features/receipt_scanning/presentation/pages/price_watch_page.dart';
import 'package:t_aidy/features/receipt_scanning/presentation/providers/receipt_provider.dart';

class MockReceiptListNotifier extends StateNotifier<AsyncValue<List<Receipt>>> implements ReceiptListNotifier {
  MockReceiptListNotifier(super.state);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final sampleReceipts = [
    Receipt(
      id: 'rec-1',
      merchantName: 'Trader Joe\'s',
      totalAmount: 75.50,
      date: DateTime.now(),
      boxId: 'main',
      items: [
        ReceiptItem(
          description: 'Oat Milk',
          unitPrice: 4.50,
          quantity: 1,
          totalPrice: 4.50,
        ),
        ReceiptItem(
          description: 'Snacks',
          unitPrice: 71.00,
          quantity: 1,
          totalPrice: 71.00,
        ),
      ],
      currency: 'USD',
    ),
    Receipt(
      id: 'rec-2',
      merchantName: 'Trader Joe\'s',
      totalAmount: 5.00,
      date: DateTime.now().subtract(const Duration(days: 2)),
      boxId: 'main',
      items: [
        ReceiptItem(
          description: 'Oat Milk',
          unitPrice: 5.00,
          quantity: 1,
          totalPrice: 5.00,
        ),
      ],
      currency: 'USD',
    ),
  ];

  final sampleAssets = [
    AssetModel(
      id: 'asset-1',
      name: 'MacBook Pro 16',
      purchaseDate: DateTime.now().subtract(const Duration(days: 30)),
      warrantyMonths: 24,
      price: 2499.00,
      receiptImagePath: '',
      merchantName: 'Apple Store',
    ),
  ];

  final sampleInvoices = [
    InvoiceModel(
      id: 'inv-1',
      invoiceNumber: 'INV-2026-0001',
      clientName: 'Acme Corp',
      amount: 1500.00,
      status: InvoiceStatus.sent,
      issuedDate: DateTime.now(),
    ),
    InvoiceModel(
      id: 'inv-2',
      invoiceNumber: 'INV-2026-0002',
      clientName: 'Beta LLC',
      amount: 500.00,
      status: InvoiceStatus.overdue,
      issuedDate: DateTime.now(),
    ),
  ];

  group('Privacy Mode Views Tests', () {
    testWidgets('VaultPage displays masked totals and asset prices when privacy mode is enabled', (tester) async {
      final privacyNotifier = PrivacyModeNotifier();
      await privacyNotifier.setEnabled(true);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            assetListProvider.overrideWith((ref) {
              final notifier = AssetNotifier();
              notifier.state = sampleAssets;
              return notifier;
            }),
            privacyModeProvider.overrideWith((ref) => privacyNotifier),
            receiptListProvider.overrideWith((ref) => MockReceiptListNotifier(AsyncValue.data(sampleReceipts))),
          ],
          child: const MaterialApp(
            home: VaultPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('••••••'), findsWidgets);
      expect(find.text('\$2,499.00'), findsNothing);
    });

    testWidgets('InvoicesPage displays masked KPI balances when privacy mode is enabled', (tester) async {
      final privacyNotifier = PrivacyModeNotifier();
      await privacyNotifier.setEnabled(true);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            invoicesProvider.overrideWith((ref) {
              final notifier = InvoicesNotifier(null, null);
              notifier.state = sampleInvoices;
              return notifier;
            }),
            privacyModeProvider.overrideWith((ref) => privacyNotifier),
          ],
          child: const MaterialApp(
            home: InvoicesPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('••••••'), findsWidgets);
      expect(find.text('\$1,500.00'), findsNothing);
      expect(find.text('\$500.00'), findsNothing);
    });

    testWidgets('PriceWatchPage displays masked prices when privacy mode is enabled', (tester) async {
      final privacyNotifier = PrivacyModeNotifier();
      await privacyNotifier.setEnabled(true);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            receiptListProvider.overrideWith((ref) => MockReceiptListNotifier(AsyncValue.data(sampleReceipts))),
            privacyModeProvider.overrideWith((ref) => privacyNotifier),
          ],
          child: const MaterialApp(
            home: PriceWatchPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('••••••'), findsWidgets);
      expect(find.text('\$4.50'), findsNothing);
      expect(find.text('\$5.00'), findsNothing);
    });

    testWidgets('BoxesPage displays masked budget and spent amounts when privacy mode is enabled', (tester) async {
      final privacyNotifier = PrivacyModeNotifier();
      await privacyNotifier.setEnabled(true);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            boxesProvider.overrideWith((ref) {
              final notifier = BoxesNotifier();
              notifier.state = [
                BoxModel(id: 'main', name: 'Main', budget: 1000, spent: 80.50, currency: 'USD', color: 0xFF2196F3),
              ];
              return notifier;
            }),
            activeBoxIdProvider.overrideWith((ref) => 'main'),
            receiptListProvider.overrideWith((ref) => MockReceiptListNotifier(AsyncValue.data(sampleReceipts))),
            privacyModeProvider.overrideWith((ref) => privacyNotifier),
          ],
          child: const MaterialApp(
            home: BoxesPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('••••••'), findsWidgets);
      expect(find.text('\$1,000.00'), findsNothing);
    });
  });
}
