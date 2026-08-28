import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/features/receipt_scanning/domain/entities/receipt.dart';
import 'package:t_aidy/features/receipt_scanning/presentation/widgets/receipt_item_row.dart';
import 'package:t_aidy/features/receipt_scanning/presentation/widgets/universal_receipt_image.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UniversalReceiptImage Widget Tests', () {
    testWidgets('renders fallback icon gracefully when imagePath is null', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: UniversalReceiptImage(
              imagePath: null,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.receipt_long_outlined), findsOneWidget);
    });

    testWidgets('renders custom errorBuilder if provided on empty/invalid source', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UniversalReceiptImage(
              imagePath: '',
              errorBuilder: (context, err, stack) => const Text('Custom Error Widget'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Custom Error Widget'), findsOneWidget);
    });
  });

  group('ReceiptItemRow Quantity Input Tests', () {
    testWidgets('renders spacious quantity input with suffix and readable number', (tester) async {
      const testItem = ReceiptItem(
        description: 'Espresso Roast',
        unitPrice: 3.50,
        quantity: 4,
        totalPrice: 14.00,
        necessity: ItemNecessity.essential,
      );

      String? capturedQty;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ReceiptItemRow(
                item: testItem,
                onDelete: () {},
                onDescriptionChanged: (_) {},
                onTaxonomyChanged: (a, b, c) {},
                onPriceChanged: (_) {},
                onQuantityChanged: (qty) => capturedQty = qty,
                onAssetChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('4'), findsOneWidget);
      expect(find.text('×'), findsOneWidget);
      expect(find.text('Espresso Roast'), findsOneWidget);

      // Enter new quantity
      await tester.enterText(find.byType(TextFormField).first, '12');
      await tester.pump();

      expect(capturedQty, '12');
    });
  });
}
