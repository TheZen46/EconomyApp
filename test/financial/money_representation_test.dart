import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:t_aidy/core/financial/currency_ratio.dart';
import 'package:t_aidy/core/financial/money.dart';
import 'package:t_aidy/features/boxes/data/models/box_model.dart';
import 'package:t_aidy/features/boxes/domain/box_pnl_engine.dart';
import 'package:t_aidy/features/invoices/data/models/invoice_model.dart';
import 'package:t_aidy/features/invoices/data/providers/invoices_provider.dart';
import 'package:t_aidy/features/receipt_scanning/data/models/receipt_model.dart';
import 'package:t_aidy/features/receipt_scanning/domain/entities/receipt.dart';

void main() {
  group('Money ISO 4217 Scale & Arithmetic Tests', () {
    test('resolves default ISO 4217 scale correctly', () {
      expect(Money.defaultScale('JPY'), 0);
      expect(Money.defaultScale('KRW'), 0);
      expect(Money.defaultScale('VND'), 0);
      expect(Money.defaultScale('BHD'), 3);
      expect(Money.defaultScale('KWD'), 3);
      expect(Money.defaultScale('JOD'), 3);
      expect(Money.defaultScale('OMR'), 3);
      expect(Money.defaultScale('USD'), 2);
      expect(Money.defaultScale('EUR'), 2);
      expect(Money.defaultScale('GBP'), 2);
      expect(Money.defaultScale('CHF'), 2);
    });

    test('creates Money from minor units and decimals without floating point drift', () {
      final m1 = Money.fromMinorUnits(150, currency: 'USD', scale: 2);
      expect(m1.cents, 150);
      expect(m1.scale, 2);
      expect(m1.toDouble, 1.50);

      // 0.1 + 0.2 in IEEE 754 is 0.30000000000000004
      final m2 = Money.fromDecimal(0.1 + 0.2, currency: 'USD');
      expect(m2.cents, 30);
      expect(m2.toDouble, 0.30);

      // JPY scale 0
      final yen = Money.fromDecimal(1250.0, currency: 'JPY');
      expect(yen.cents, 1250);
      expect(yen.scale, 0);
      expect(yen.format(locale: 'en_US'), '¥1,250');
      expect(yen.format(locale: 'it_IT'), '1.250 ¥');

      // KWD scale 3
      final kwd = Money.fromDecimal(1.234, currency: 'KWD');
      expect(kwd.cents, 1234);
      expect(kwd.scale, 3);
      expect(kwd.format(locale: 'en_US'), 'KWD1.234');
    });

    test('aligns scales across cross-scale addition and subtraction', () {
      final a = Money.fromMinorUnits(100, currency: 'EUR', scale: 2); // 1.00 EUR
      final b = Money.fromMinorUnits(500, currency: 'EUR', scale: 3); // 0.500 EUR

      final sum = a + b;
      expect(sum.scale, 3);
      expect(sum.cents, 1500);
      expect(sum.toDouble, 1.5);

      final diff = a - b;
      expect(diff.scale, 3);
      expect(diff.cents, 500);
      expect(diff.toDouble, 0.5);
    });

    test('performs cross-scale comparisons accurately', () {
      final a = Money.fromMinorUnits(100, currency: 'EUR', scale: 2); // 1.00 EUR
      final b = Money.fromMinorUnits(1000, currency: 'EUR', scale: 3); // 1.000 EUR
      final c = Money.fromMinorUnits(1001, currency: 'EUR', scale: 3); // 1.001 EUR

      expect(a == b, isTrue);
      expect(a.compareTo(b), 0);
      expect(a < c, isTrue);
      expect(c > b, isTrue);
      expect(a.hashCode == b.hashCode, isTrue);
    });

    test('formats amounts correctly for 2-decimal and 0-decimal currencies', () {
      expect(Money.fromDecimal(42.50, currency: 'USD').format(locale: 'en_US'), '\$42.50');
      expect(Money.fromDecimal(100.0, currency: 'EUR').format(locale: 'en_US'), '€100.00');
      expect(Money.fromDecimal(5000.0, currency: 'JPY').format(locale: 'en_US'), '¥5,000');
      expect(Money.fromDecimal(25000.0, currency: 'KRW').format(locale: 'en_US'), '₩25,000');

      expect(Money.fromDecimal(42.50, currency: 'USD').format(locale: 'it_IT'), '42,50 \$');
      expect(Money.fromDecimal(100.0, currency: 'EUR').format(locale: 'it_IT'), '100,00 €');
      expect(Money.fromDecimal(5000.0, currency: 'JPY').format(locale: 'it_IT'), '5.000 ¥');
    });

    test('serializes and deserializes Money to and from JSON', () {
      final m = Money.fromMinorUnits(4250, currency: 'USD', scale: 2);
      final json = m.toJson();
      expect(json, {
        'cents': 4250,
        'currency': 'USD',
        'scale': 2,
      });

      final reconstructed = Money.fromJson(json);
      expect(reconstructed, m);

      // Also supports amount_minor payload key
      final fromAmountMinor = Money.fromJson({
        'amount_minor': 4250,
        'currency': 'USD',
        'scale': 2,
      });
      expect(fromAmountMinor, m);
    });

    test('MoneyIterableExtension sum accumulates without floating point drift', () {
      final items = [
        Money.fromDecimal(0.1, currency: 'EUR'),
        Money.fromDecimal(0.2, currency: 'EUR'),
        Money.fromDecimal(0.3, currency: 'EUR'),
      ];
      final sum = items.sum('EUR');
      expect(sum.cents, 60);
      expect(sum.toDouble, 0.60);
    });

    test('CurrencyRatio converts across currencies adjusting target ISO 4217 scale', () {
      // 100 EUR to JPY at rate 160.0
      // 100.00 EUR has minor units 10000 (scale 2)
      // JPY has scale 0
      final eur = Money.fromDecimal(100.0, currency: 'EUR');
      final ratio = CurrencyRatio(
        baseCurrency: 'EUR',
        quoteCurrency: 'JPY',
        numerator: 160,
        denominator: 1,
      );

      final jpy = ratio.convert(eur);
      expect(jpy.currency, 'JPY');
      expect(jpy.scale, 0);
      expect(jpy.cents, 16000);
      expect(jpy.toDouble, 16000.0);
    });
  });

  group('Hive Adapters & Models Minor Units Persistence Tests', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('money_hive_test_');
      Hive.init(tempDir.path);
      if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ReceiptModelAdapter());
      if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(ReceiptItemModelAdapter());
      if (!Hive.isAdapterRegistered(10)) Hive.registerAdapter(BoxModelAdapter());
      if (!Hive.isAdapterRegistered(11)) Hive.registerAdapter(InvoiceModelAdapter());
    });

    tearDown(() async {
      await Hive.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('BoxModel stores minor units and supports Money operations', () async {
      final boxHive = await Hive.openBox<BoxModel>('test_boxes');
      final box = BoxModel(
        id: 'box_1',
        name: 'Groceries',
        budget: 200.0,
        spent: 50.25,
        currency: 'EUR',
        color: 0xFF123456,
      );
      expect(box.budgetMinor, 20000);
      expect(box.spentMinor, 5025);
      expect(box.budgetMoney, Money.fromMinorUnits(20000, currency: 'EUR'));
      expect(box.spentMoney, Money.fromMinorUnits(5025, currency: 'EUR'));
      expect(box.remainingMoney, Money.fromMinorUnits(14975, currency: 'EUR'));

      await boxHive.put(box.id, box);
      await boxHive.close();

      final reopened = await Hive.openBox<BoxModel>('test_boxes');
      final loaded = reopened.get('box_1');
      expect(loaded, isNotNull);
      expect(loaded!.budgetMinor, 20000);
      expect(loaded.spentMinor, 5025);
      expect(loaded.budgetMoney.toDouble, 200.0);
      expect(loaded.spentMoney.toDouble, 50.25);
      await reopened.close();
    });

    test('ReceiptModel and ReceiptItemModel persist minor units in Hive', () async {
      final receiptsHive = await Hive.openBox<ReceiptModel>('test_receipts');
      final receipt = ReceiptModel(
        id: 'rec_1',
        merchantName: 'Supermarket',
        date: DateTime(2026, 1, 1),
        totalAmount: 35.50,
        currency: 'EUR',
        items: [
          ReceiptItemModel(
            description: 'Apples',
            unitPrice: 2.50,
            quantity: 2,
            totalPrice: 5.00,
          ),
          ReceiptItemModel(
            description: 'Olive Oil',
            unitPrice: 30.50,
            quantity: 1,
            totalPrice: 30.50,
          ),
        ],
      );

      expect(receipt.totalAmountMinor, 3550);
      expect(receipt.items[0].unitPriceMinor, 250);
      expect(receipt.items[0].totalPriceMinor, 500);

      await receiptsHive.put(receipt.id, receipt);
      await receiptsHive.close();

      final reopened = await Hive.openBox<ReceiptModel>('test_receipts');
      final loaded = reopened.get('rec_1');
      expect(loaded, isNotNull);
      expect(loaded!.totalAmountMinor, 3550);
      expect(loaded.totalMoney, Money.fromMinorUnits(3550, currency: 'EUR'));
      expect(loaded.items[0].unitPriceMinor, 250);
      expect(loaded.items[0].totalPriceMinor, 500);
      expect(loaded.items[0].unitPriceMoney('EUR'), Money.fromMinorUnits(250, currency: 'EUR'));
      expect(loaded.items[0].totalPriceMoney('EUR'), Money.fromMinorUnits(500, currency: 'EUR'));
      await reopened.close();
    });

    test('InvoiceModel persists minor units and provides amountMoney', () async {
      final invoicesHive = await Hive.openBox<InvoiceModel>('test_invoices');
      final inv = InvoiceModel(
        id: 'inv_1',
        invoiceNumber: 'INV-2026-0001',
        clientName: 'Acme Corp',
        amount: 1500.75,
        status: InvoiceStatus.sent,
        issuedDate: DateTime(2026, 1, 1),
        currency: 'USD',
      );

      expect(inv.amountMinor, 150075);
      expect(inv.amountMoney, Money.fromMinorUnits(150075, currency: 'USD'));

      await invoicesHive.put(inv.id, inv);
      await invoicesHive.close();

      final reopened = await Hive.openBox<InvoiceModel>('test_invoices');
      final loaded = reopened.get('inv_1');
      expect(loaded, isNotNull);
      expect(loaded!.amountMinor, 150075);
      expect(loaded.amountMoney, Money.fromMinorUnits(150075, currency: 'USD'));
      await reopened.close();
    });
  });

  group('Financial Engines & Providers Fixed-Point Tests', () {
    test('BoxPnlEngine calculates exact P&L using fixed-point Money arithmetic', () {
      final box = BoxModel(
        id: 'box_design',
        name: 'Design Consulting',
        budget: 1000.0,
        spent: 0.0,
        currency: 'USD',
        color: 0xFF00FF00,
      );

      final invoice = InvoiceModel(
        id: 'inv_d1',
        invoiceNumber: 'INV-001',
        clientName: 'Design Client',
        amount: 2500.0,
        status: InvoiceStatus.settled,
        issuedDate: DateTime(2026, 1, 1),
        notes: 'Design Consulting project revenue',
        currency: 'USD',
      );

      final receipt = Receipt(
        id: 'rec_d1',
        merchantName: 'Software Subscription',
        date: DateTime(2026, 1, 2),
        totalAmount: 150.25,
        currency: 'USD',
        boxId: 'box_design',
      );

      final report = BoxPnlEngine.generateReport(
        boxes: [box],
        invoices: [invoice],
        receipts: [receipt],
        mileageTrips: [],
      );

      expect(report.boxStatements.length, 1);
      final stmt = report.boxStatements.first;
      expect(stmt.grossRevenueMoney, Money.fromDecimal(2500.0, currency: 'USD'));
      expect(stmt.directExpensesMoney, Money.fromDecimal(150.25, currency: 'USD'));
      expect(stmt.totalCostsMoney, Money.fromDecimal(150.25, currency: 'USD'));
      expect(stmt.netOperatingProfitMoney, Money.fromDecimal(2349.75, currency: 'USD'));
      expect(stmt.netOperatingProfit, 2349.75);
      expect(report.totalPortfolioNetProfitMoney, Money.fromDecimal(2349.75, currency: 'USD'));
    });

    test('InvoicesNotifier calculates exact financial stats using Money', () {
      final inv1 = InvoiceModel(
        id: 'inv_1',
        invoiceNumber: 'INV-1',
        clientName: 'Client A',
        amount: 100.10,
        status: InvoiceStatus.sent,
        issuedDate: DateTime(2026, 1, 1),
        currency: 'EUR',
      );
      final inv2 = InvoiceModel(
        id: 'inv_2',
        invoiceNumber: 'INV-2',
        clientName: 'Client B',
        amount: 200.20,
        status: InvoiceStatus.overdue,
        issuedDate: DateTime(2026, 1, 1),
        currency: 'EUR',
      );
      final inv3 = InvoiceModel(
        id: 'inv_3',
        invoiceNumber: 'INV-3',
        clientName: 'Client C',
        amount: 50.05,
        status: InvoiceStatus.draft,
        issuedDate: DateTime(2026, 1, 1),
        currency: 'EUR',
      );

      final notifier = InvoicesNotifier();
      // Directly assign state for isolated unit test
      notifier.state = [inv1, inv2, inv3];

      expect(notifier.totalOutstandingMoney, Money.fromMinorUnits(30030, currency: 'EUR'));
      expect(notifier.totalOutstanding, 300.30);
      expect(notifier.totalOverdueMoney, Money.fromMinorUnits(20020, currency: 'EUR'));
      expect(notifier.totalOverdue, 200.20);
      expect(notifier.totalDraftMoney, Money.fromMinorUnits(5005, currency: 'EUR'));
      expect(notifier.totalDraft, 50.05);
    });
  });
}
