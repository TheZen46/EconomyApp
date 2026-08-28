import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/features/boxes/data/providers/boxes_provider.dart';
import 'package:t_aidy/features/receipt_scanning/domain/entities/receipt.dart';
import 'package:t_aidy/features/receipt_scanning/presentation/providers/category_provider.dart';
import 'package:t_aidy/features/receipt_scanning/presentation/providers/dashboard_provider.dart';
import 'package:t_aidy/features/receipt_scanning/presentation/widgets/dashboard/customizable_metrics_grid.dart';
import 'package:t_aidy/features/receipt_scanning/presentation/widgets/dashboard/dashboard_summary_card.dart';
import 'package:t_aidy/features/receipt_scanning/presentation/widgets/dashboard/gamification_header.dart';
import 'package:t_aidy/features/receipt_scanning/presentation/widgets/dashboard/recent_receipts_list.dart';

void main() {
  final sampleReceipts = [
    Receipt(
      id: 'rec-1',
      merchantName: 'Trader Joe\'s',
      totalAmount: 75.50,
      date: DateTime.now(),
      items: [
        ReceiptItem(
          description: 'Oat Milk',
          unitPrice: 4.50,
          quantity: 1,
          totalPrice: 4.50,
          necessity: ItemNecessity.essential,
          mainCategory: 'Groceries',
        ),
        ReceiptItem(
          description: 'Snacks',
          unitPrice: 71.00,
          quantity: 1,
          totalPrice: 71.00,
          necessity: ItemNecessity.essential,
          mainCategory: 'Groceries',
        ),
      ],
      currency: 'USD',
    ),
    Receipt(
      id: 'rec-2',
      merchantName: 'Apple Store',
      totalAmount: 199.00,
      date: DateTime.now().subtract(const Duration(days: 1)),
      items: [
        ReceiptItem(
          description: 'AirPods',
          unitPrice: 199.00,
          quantity: 1,
          totalPrice: 199.00,
          necessity: ItemNecessity.discretional,
          mainCategory: 'Electronics',
        ),
      ],
      currency: 'USD',
    ),
  ];

  group('GamificationHeader Widget Tests', () {
    testWidgets('renders level, XP progress bar, and streak badge', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: GamificationHeader(
                receipts: sampleReceipts,
                isDark: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('LVL'), findsOneWidget);
      expect(find.text('XP Progress'), findsOneWidget);
      expect(find.textContaining('/ 300 XP'), findsOneWidget);
      expect(find.byIcon(Icons.local_fire_department), findsOneWidget);
    });
  });

  group('DashboardSummaryCard Widget Tests', () {
    testWidgets('renders monthly runway card and calculated burn', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: DashboardSummaryCard(
                receipts: sampleReceipts,
                isDark: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('MONTHLY RUNWAY'), findsOneWidget);
      expect(find.text('Calculated Monthly Burn'), findsOneWidget);
    });
  });

  group('RecentReceiptsList Widget Tests', () {
    testWidgets('renders receipts and filter dropdown', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            categoryListProvider.overrideWith((ref) => CategoryNotifier()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: RecentReceiptsList(
                receipts: sampleReceipts,
                isDark: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Recent Transactions'), findsOneWidget);
      expect(find.text('Trader Joe\'s'), findsOneWidget);
      expect(find.text('\$75.50'), findsOneWidget);
      expect(find.text('Apple Store'), findsOneWidget);
      expect(find.text('\$199.00'), findsOneWidget);
    });
  });

  group('CustomizableMetricsGrid Widget Tests', () {
    testWidgets('renders normal grid layout with gamification header and widget cards', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dashboardProvider.overrideWith((ref) => DashboardNotifier()),
            boxesProvider.overrideWith((ref) => BoxesNotifier()),
            activeBoxIdProvider.overrideWith((ref) => 'main'),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: CustomizableMetricsGrid(
                receipts: sampleReceipts,
                isDark: false,
                isEditMode: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(GamificationHeader), findsOneWidget);
      expect(find.byType(CustomizableMetricsGrid), findsOneWidget);
    });

    testWidgets('renders reorderable edit mode when isEditMode is true', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dashboardProvider.overrideWith((ref) => DashboardNotifier()),
            boxesProvider.overrideWith((ref) => BoxesNotifier()),
            activeBoxIdProvider.overrideWith((ref) => 'main'),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: CustomizableMetricsGrid(
                receipts: sampleReceipts,
                isDark: false,
                isEditMode: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ReorderableListView), findsOneWidget);
    });
  });
}
