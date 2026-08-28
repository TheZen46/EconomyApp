import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/core/theme/app_theme.dart';
import 'package:t_aidy/features/evault/data/models/asset_model.dart';
import 'package:t_aidy/features/evault/presentation/pages/vault_page.dart';
import 'package:t_aidy/features/evault/presentation/providers/asset_provider.dart';
import 'package:t_aidy/features/invoices/data/models/invoice_model.dart';
import 'package:t_aidy/features/invoices/data/providers/invoices_provider.dart';
import 'package:t_aidy/features/invoices/presentation/pages/invoices_page.dart';

void main() {
  group('showDestructiveConfirmationDialog - Behavior & Theming', () {
    testWidgets('returns true when confirm button is tapped', (tester) async {
      bool? dialogResult;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  dialogResult = await showDestructiveConfirmationDialog(
                    context: context,
                    title: 'Delete Item?',
                    message: 'This cannot be undone.',
                    confirmLabel: 'Delete Now',
                    cancelLabel: 'Keep Item',
                  );
                },
                child: const Text('Trigger Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Trigger Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Delete Item?'), findsOneWidget);
      expect(find.text('This cannot be undone.'), findsOneWidget);
      expect(find.text('Delete Now'), findsOneWidget);
      expect(find.text('Keep Item'), findsOneWidget);

      await tester.tap(find.text('Delete Now'));
      await tester.pumpAndSettle();

      expect(dialogResult, isTrue);
      expect(find.text('Delete Item?'), findsNothing);
    });

    testWidgets('returns false when cancel button is tapped', (tester) async {
      bool? dialogResult;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  dialogResult = await AppTheme.showDestructiveConfirmationDialog(
                    context: context,
                    title: 'Delete Asset?',
                    message: 'Are you sure?',
                  );
                },
                child: const Text('Trigger Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Trigger Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Delete Asset?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(dialogResult, isFalse);
      expect(find.text('Delete Asset?'), findsNothing);
    });
  });

  group('InvoicesPage - Destructive Action Confirmation', () {
    testWidgets('tapping delete from popup menu prompts confirmation and aborts when cancelled', (tester) async {
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final testInvoice = InvoiceModel(
        id: 'inv-test-01',
        invoiceNumber: 'INV-202608-0001',
        clientName: 'Acme Corp',
        amount: 1500.0,
        status: InvoiceStatus.draft,
        issuedDate: DateTime(2026, 8, 1),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            invoicesProvider.overrideWith((ref) => _FakeInvoicesNotifier([testInvoice])),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            home: const InvoicesPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Acme Corp'), findsOneWidget);

      // Open popup menu
      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();

      expect(find.text('Delete'), findsOneWidget);

      // Tap Delete in popup menu
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      // Verify destructive confirmation dialog is shown
      expect(find.text('Delete Invoice?'), findsOneWidget);
      expect(find.text('Are you sure? This action cannot be undone.'), findsOneWidget);

      // Cancel deletion
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Invoice is still displayed
      expect(find.text('Acme Corp'), findsOneWidget);
    });

    testWidgets('confirming delete in dialog executes invoice deletion', (tester) async {
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final testInvoice = InvoiceModel(
        id: 'inv-test-02',
        invoiceNumber: 'INV-202608-0002',
        clientName: 'Globex Inc',
        amount: 2500.0,
        status: InvoiceStatus.draft,
        issuedDate: DateTime(2026, 8, 1),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            invoicesProvider.overrideWith((ref) => _FakeInvoicesNotifier([testInvoice])),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: const InvoicesPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Globex Inc'), findsOneWidget);

      // Open popup menu
      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();

      // Tap Delete in popup menu
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      // Confirm deletion in dialog
      expect(find.text('Delete Invoice?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();

      // Invoice was deleted
      expect(find.text('Globex Inc'), findsNothing);
      expect(find.text('No invoices found'), findsOneWidget);
    });
  });

  group('VaultPage - Destructive Action Confirmation', () {
    testWidgets('swiping asset card triggers confirmation dialog and preserves asset when cancelled', (tester) async {
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final testAsset = AssetModel(
        id: 'asset-test-01',
        name: 'MacBook M3 Pro',
        purchaseDate: DateTime(2026, 1, 1),
        warrantyMonths: 24,
        price: 2499.0,
        receiptImagePath: '',
        merchantName: 'Apple Store',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            assetListProvider.overrideWith((ref) => _FakeAssetNotifier([testAsset])),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: const VaultPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('MacBook M3 Pro'), findsOneWidget);

      // Swipe dismissible end to start
      await tester.drag(find.byType(Dismissible), const Offset(-500, 0));
      await tester.pumpAndSettle();

      // Verify destructive confirmation dialog is shown
      expect(find.text('Delete Asset?'), findsOneWidget);

      // Cancel deletion
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Asset is still present
      expect(find.text('MacBook M3 Pro'), findsOneWidget);
    });

    testWidgets('confirming delete in dialog removes asset from vault', (tester) async {
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final testAsset = AssetModel(
        id: 'asset-test-02',
        name: 'Ergonomic Desk',
        purchaseDate: DateTime(2026, 1, 1),
        warrantyMonths: 12,
        price: 799.0,
        receiptImagePath: '',
        merchantName: 'Herman Miller',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            assetListProvider.overrideWith((ref) => _FakeAssetNotifier([testAsset])),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const VaultPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ergonomic Desk'), findsOneWidget);

      // Swipe dismissible
      await tester.drag(find.byType(Dismissible), const Offset(-500, 0));
      await tester.pumpAndSettle();

      // Confirm deletion in dialog
      expect(find.text('Delete Asset?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();

      // Asset was deleted
      expect(find.text('Ergonomic Desk'), findsNothing);
      expect(find.text('Your vault is empty'), findsOneWidget);
    });
  });
}

class _FakeInvoicesNotifier extends InvoicesNotifier {
  _FakeInvoicesNotifier(List<InvoiceModel> initial) {
    state = initial;
  }

  @override
  Future<void> delete(String id) async {
    state = state.where((i) => i.id != id).toList();
  }
}

class _FakeAssetNotifier extends AssetNotifier {
  _FakeAssetNotifier(List<AssetModel> initial) {
    state = initial;
  }

  @override
  Future<void> deleteAsset(String id) async {
    state = state.where((a) => a.id != id).toList();
  }
}
