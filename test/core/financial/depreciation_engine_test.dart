import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/core/financial/depreciation_engine.dart';
import 'package:t_aidy/features/evault/data/models/asset_model.dart';

void main() {
  group('DepreciationEngine Tests (Section 179 & MACRS)', () {
    final macBook = AssetModel(
      id: 'a1',
      name: 'MacBook Pro 16 M3 Max',
      purchaseDate: DateTime(2026, 1, 15),
      warrantyMonths: 24,
      price: 3500.0,
      receiptImagePath: '',
      merchantName: 'Apple Store',
    );

    final standingDesk = AssetModel(
      id: 'a2',
      name: 'Motorized Standing Desk',
      purchaseDate: DateTime(2025, 6, 1),
      warrantyMonths: 60,
      price: 1200.0,
      receiptImagePath: '',
      merchantName: 'Fully Ergonomics',
    );

    test('calculates 5-Year MACRS schedule with half-year convention', () {
      final sched = DepreciationEngine.calculateSchedule(
        asset: macBook,
        customMethod: DepreciationMethod.macrs5Year,
        currentFiscalYear: 2026,
      );

      expect(sched.method, DepreciationMethod.macrs5Year);
      expect(sched.yearlyEntries.length, 6); // 5-year MACRS spans 6 recovery years
      expect(sched.yearlyEntries[0].deductionRate, 0.2000); // 20% Year 1
      expect(sched.yearlyEntries[0].deductionAmount, 700.0); // 3500 * 0.20
      expect(sched.currentYearDeduction, 700.0);
      expect(sched.currentBookValue, 2800.0); // 3500 - 700
    });

    test('calculates Section 179 100% full expensing write-off', () {
      final sched = DepreciationEngine.calculateSchedule(
        asset: macBook,
        customMethod: DepreciationMethod.section179,
        currentFiscalYear: 2026,
      );

      expect(sched.method, DepreciationMethod.section179);
      expect(sched.currentYearDeduction, 3500.0);
      expect(sched.currentBookValue, 0.0);
      expect(sched.isFullyDepreciated, true);
    });

    test('calculates 7-Year MACRS for office furniture', () {
      final sched = DepreciationEngine.calculateSchedule(
        asset: standingDesk,
        currentFiscalYear: 2026, // Year 2 of desk
      );

      expect(sched.method, DepreciationMethod.macrs7Year);
      expect(sched.yearlyEntries.length, 8); // 7-year MACRS spans 8 recovery years
      expect(sched.yearlyEntries[0].fiscalYear, 2025);
      expect(sched.yearlyEntries[1].fiscalYear, 2026);
      expect(sched.yearlyEntries[1].deductionRate, 0.2449); // 24.49% Year 2
    });

    test('computes vault portfolio tax summary', () {
      final summary = DepreciationEngine.calculatePortfolioSummary([macBook, standingDesk]);

      expect(summary.totalAcquisitionCost, 4700.0);
      expect(summary.totalSection179Eligible, 3500.0); // Only macBook purchased in 2026
      expect(summary.activeWarrantyCount, 2);
    });
  });
}
