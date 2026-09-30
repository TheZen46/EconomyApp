import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/core/financial/box_pnl_engine.dart';
import 'package:t_aidy/core/financial/mileage_engine.dart';
import 'package:t_aidy/features/boxes/data/models/box_model.dart';
import 'package:t_aidy/features/invoices/data/models/invoice_model.dart';
import 'package:t_aidy/features/receipt_scanning/domain/entities/receipt.dart';

void main() {
  group('BoxPnlEngine Tests', () {
    final clientBox = BoxModel(
      id: 'box-client-1',
      name: 'Acme Project',
      color: 0xFF3B82F6,
      icon: 'business',
      budget: 10000.0,
      spent: 2000.0,
      currency: 'USD',
    );

    final invoices = [
      InvoiceModel(
        id: 'inv-1',
        invoiceNumber: 'INV-101',
        clientName: 'Acme Corp',
        issuedDate: DateTime(2026, 3, 1),
        amount: 8000.0,
        status: InvoiceStatus.settled,
        notes: 'Acme Project Retainer',
      ),
    ];

    final receipts = [
      Receipt(
        id: 'rec-1',
        merchantName: 'AWS Cloud',
        totalAmount: 500.0,
        date: DateTime(2026, 3, 5),
        boxId: 'box-client-1',
        items: [],
        currency: 'USD',
      ),
    ];

    final mileage = [
      MileageTrip(
        id: 'trip-1',
        date: DateTime(2026, 3, 10),
        purpose: 'Acme Onsite Meeting',
        startLocation: 'Office',
        endLocation: 'Acme HQ',
        distance: 50.0,
        unit: DistanceUnit.miles,
        ratePerUnit: 0.67, // $33.50
        boxId: 'box-client-1',
      ),
    ];

    test('calculates gross revenue, direct costs, net profit and margin per box', () {
      final report = BoxPnlEngine.generateReport(
        boxes: [clientBox],
        invoices: invoices,
        receipts: receipts,
        mileageTrips: mileage,
      );

      expect(report.boxStatements.length, 1);
      final stmt = report.boxStatements.first;
      expect(stmt.grossRevenue, 8000.0);
      expect(stmt.directExpenses, 500.0);
      expect(stmt.mileageDeductions, 33.50);
      expect(stmt.totalCosts, 533.50);
      expect(stmt.netOperatingProfit, 8000.0 - 533.50); // 7466.50
      expect(stmt.profitMarginPercent, closeTo(93.33, 0.05));
    });
  });
}
