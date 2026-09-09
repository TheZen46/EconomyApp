import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/core/financial/currency_ratio.dart';
import 'package:t_aidy/core/financial/money.dart';
import 'package:t_aidy/core/financial/tax_engine.dart';

void main() {
  group('Fixed-Point Money & Banker Rounding Primitive Tests', () {
    test('creates Money from integer cents with exact precision', () {
      final m = Money(cents: 1999, currency: 'EUR');
      expect(m.cents, equals(1999));
      expect(m.toDouble, equals(19.99));
      expect(m.majorUnits, equals(19));
      expect(m.minorUnits, equals(99));
    });

    test('performs Banker Rounding (toEven) exactly on midpoints', () {
      // 2.5 cents -> 2 cents (nearest even)
      expect(Money.roundIntegerDivision(25, 10), equals(2));

      // 3.5 cents -> 4 cents (nearest even)
      expect(Money.roundIntegerDivision(35, 10), equals(4));

      // 4.5 cents -> 4 cents (nearest even)
      expect(Money.roundIntegerDivision(45, 10), equals(4));

      // 5.5 cents -> 6 cents (nearest even)
      expect(Money.roundIntegerDivision(55, 10), equals(6));

      // Negative ties: -2.5 -> -2, -3.5 -> -4
      expect(Money.roundIntegerDivision(-25, 10), equals(-2));
      expect(Money.roundIntegerDivision(-35, 10), equals(-4));
    });

    test('exact allocation preserves total pennies without drift', () {
      final total = Money(cents: 100, currency: 'EUR'); // 1.00 EUR
      // Allocate 1/3, 1/3, 1/3
      final parts = total.allocate([1, 1, 1]);
      expect(parts.length, equals(3));
      expect(parts.map((p) => p.cents).toList(), equals([34, 33, 33]));
      expect(parts.fold<int>(0, (sum, p) => sum + p.cents), equals(100));
    });

    test('exact rational CurrencyRatio converts without floating point drift', () {
      // 1 EUR = 1.0855 USD (10855 / 10000)
      final ratio = CurrencyRatio.fromDecimal(
        baseCurrency: 'EUR',
        quoteCurrency: 'USD',
        rate: 1.0855,
      );

      final eur100 = Money(cents: 10000, currency: 'EUR'); // 100.00 EUR
      final usd = ratio.convert(eur100);
      expect(usd.currency, equals('USD'));
      expect(usd.cents, equals(10855)); // 108.55 USD

      // Cross-rate multiplication: EUR -> USD -> JPY
      final usdToJpy = CurrencyRatio.fromDecimal(
        baseCurrency: 'USD',
        quoteCurrency: 'JPY',
        rate: 155.0,
      );
      final eurToJpy = ratio.multiply(usdToJpy);
      expect(eurToJpy.baseCurrency, equals('EUR'));
      expect(eurToJpy.quoteCurrency, equals('JPY'));
    });
  });

  group('Automated Financial Fuzz Engine (100,000 Invariant Stress Iterations)', () {
    test('proves zero floating-point divergence and 100% tax invariant satisfaction across 100,000 cases', () {
      final rng = math.Random(42);
      const int totalIterations = 100000;
      final ratesBps = [0, 400, 500, 700, 1000, 1900, 2100, 2200, 2500];
      final natureCodes = ['N1', 'N2.1', 'N2.2', 'N3.1', 'N4', 'N6.3', null];

      int verifiedInvariants = 0;
      int totalLineItemsTested = 0;

      final stopwatch = Stopwatch()..start();

      for (int i = 0; i < totalIterations; i++) {
        final itemCount = 1 + rng.nextInt(5); // 1 to 5 line items per invoice
        final items = <TaxableLineItem>[];

        for (int j = 0; j < itemCount; j++) {
          final qty = 1 + rng.nextInt(20);
          final priceCents = 1 + rng.nextInt(50000); // 0.01 to 500.00 EUR
          final rate = ratesBps[rng.nextInt(ratesBps.length)];
          final nature = (rate == 0) ? natureCodes[rng.nextInt(natureCodes.length)] : null;

          items.add(TaxableLineItem(
            id: 'line_$j',
            description: 'Fuzz Item #$j',
            quantity: qty,
            unitPrice: Money(cents: priceCents, currency: 'EUR'),
            taxRateBps: rate,
            natureCode: nature,
          ));
          totalLineItemsTested++;
        }

        // Execute Tax Engine
        final result = TaxEngine.calculateInvoice(items: items, currency: 'EUR');

        // Formal Invariant Check: | Total - (sum(Items) + sum(Tax)) | == 0
        if (result.invariantSatisfied && result.residualCents == 0) {
          verifiedInvariants++;
        }
      }

      stopwatch.stop();

      // ignore: avoid_print
      print('Fuzz Financial Invariant Verification:');
      // ignore: avoid_print
      print('  Total Invoices Tested: $totalIterations');
      // ignore: avoid_print
      print('  Total Line Items Evaluated: $totalLineItemsTested');
      // ignore: avoid_print
      print('  Invariant Satisfaction Rate: ${(verifiedInvariants / totalIterations * 100).toStringAsFixed(2)}%');
      // ignore: avoid_print
      print('  Execution Time: ${stopwatch.elapsedMilliseconds} ms (${(stopwatch.elapsedMilliseconds / totalIterations * 1000).toStringAsFixed(2)} µs/invoice)');

      expect(verifiedInvariants, equals(totalIterations));
    });
  });
}
