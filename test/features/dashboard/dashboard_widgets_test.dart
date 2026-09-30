import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/features/tax_compliance/presentation/providers/tax_shield_provider.dart';
import 'package:t_aidy/features/boxes/data/providers/boxes_provider.dart';
import 'package:t_aidy/features/receipt_scanning/domain/entities/receipt.dart';
import 'package:t_aidy/features/receipt_scanning/presentation/providers/category_provider.dart';
import 'package:t_aidy/features/dashboard/presentation/providers/dashboard_provider.dart';
import 'package:t_aidy/features/dashboard/presentation/widgets/customizable_metrics_grid.dart';
import 'package:t_aidy/features/dashboard/presentation/widgets/dashboard_summary_card.dart';
import 'package:t_aidy/features/dashboard/presentation/widgets/gamification_header.dart';
import 'package:t_aidy/features/dashboard/presentation/widgets/recent_receipts_list.dart';
import 'package:t_aidy/features/receipt_scanning/presentation/providers/receipt_provider.dart';
import 'package:t_aidy/features/dashboard/data/models/dashboard_config.dart';

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

  final mockTaxShield = TaxShieldCalculation(
    grossRevenue: 5000.0,
    totalExpenses: 274.50,
    totalDeductibleExpenses: 75.50,
    netTaxableIncome: 4924.50,
    effectiveTaxRate: 0.25,
    lockedTaxShield: 1231.13,
    taxSavingsEarned: 18.88,
    safeToSpend: 3494.37,
    currentQuarter: 1,
    currentYear: 2026,
    nextQuarterDeadline: DateTime(2026, 4, 15),
    daysUntilDeadline: 20,
    profile: kTaxProfilePresets.first,
  );

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
    testWidgets('renders safe-to-spend liquidity cockpit and financial metrics', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            taxShieldCalculationProvider.overrideWithValue(mockTaxShield),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: DashboardSummaryCard(
                  receipts: sampleReceipts,
                  isDark: false,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('SAFE-TO-SPEND LIQUIDITY'), findsOneWidget);
      expect(find.text('AIR-GAPPED VAULT ACTIVE'), findsOneWidget);
      expect(find.text('Gross Inflows'), findsOneWidget);
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

    testWidgets('renders masked amounts when privacyModeProvider is enabled', (tester) async {
      final privacyNotifier = PrivacyModeNotifier();
      await privacyNotifier.setEnabled(true);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            categoryListProvider.overrideWith((ref) => CategoryNotifier()),
            privacyModeProvider.overrideWith((ref) => privacyNotifier),
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
      expect(find.text('••••••'), findsNWidgets(2));
      expect(find.text('\$75.50'), findsNothing);
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
            taxShieldCalculationProvider.overrideWithValue(mockTaxShield),
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
            taxShieldCalculationProvider.overrideWithValue(mockTaxShield),
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

  group('DashboardWidgetSpansNotifier Tests', () {
    test('loads default column spans when settings box is null or empty', () {
      final notifier = DashboardWidgetSpansNotifier(null);
      expect(notifier.state[DashboardWidgetType.summary], 2);
      expect(notifier.state[DashboardWidgetType.taxNest], 1);
      expect(notifier.state[DashboardWidgetType.necessityBreakdown], 1);
    });

    test('updates span in state when setSpan is called', () {
      final notifier = DashboardWidgetSpansNotifier(null);
      notifier.setSpan(DashboardWidgetType.taxNest, 2);
      expect(notifier.state[DashboardWidgetType.taxNest], 2);
    });
  });
}
