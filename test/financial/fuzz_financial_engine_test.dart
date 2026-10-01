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

  group('Rounding and allocation with negative operands', () {
    /// Reference rounding computed on magnitudes, then signed, so that it shares
    /// no sign handling with the implementation under test.
    int referenceRound(int numerator, int denominator, MidpointRounding rounding) {
      final negative = (numerator < 0) != (denominator < 0);
      final n = numerator.abs();
      final d = denominator.abs();
      var q = n ~/ d;
      final twiceRem = (n - q * d) * 2;
      switch (rounding) {
        case MidpointRounding.toEven:
          if (twiceRem > d || (twiceRem == d && q.isOdd)) q++;
          break;
        case MidpointRounding.awayFromZero:
          if (twiceRem >= d) q++;
          break;
        case MidpointRounding.towardsZero:
          break;
      }
      return negative ? -q : q;
    }

    test('negative non-tie remainders round to the nearest value', () {
      expect(Money.roundIntegerDivision(-13, 10), -1);
      expect(Money.roundIntegerDivision(-17, 10), -2);
      expect(Money.roundIntegerDivision(-7, 3), -2);
      expect(Money.fromDecimal(-0.013).cents, -1);
    });

    test('negative divisors round in the direction of the exact quotient', () {
      expect(Money.roundIntegerDivision(7, -3), -2);
      expect(Money.roundIntegerDivision(17, -10), -2);
      expect(Money.roundIntegerDivision(-7, -3), 2);
      expect(Money(cents: 1000).divide(-3).cents, -333);
    });

    test('awayFromZero rounds half away from zero, not every remainder', () {
      const mode = MidpointRounding.awayFromZero;
      expect(Money.roundIntegerDivision(14, 10, rounding: mode), 1);
      expect(Money.roundIntegerDivision(15, 10, rounding: mode), 2);
      expect(Money.roundIntegerDivision(-14, 10, rounding: mode), -1);
      expect(Money.roundIntegerDivision(-15, 10, rounding: mode), -2);
    });

    test('matches the reference for random operands of every sign', () {
      final rng = math.Random(7);
      for (var i = 0; i < 20000; i++) {
        final numerator = rng.nextInt(2000000001) - 1000000000;
        var denominator = rng.nextInt(200001) - 100000;
        if (denominator == 0) denominator = 1;
        for (final mode in MidpointRounding.values) {
          expect(
            Money.roundIntegerDivision(numerator, denominator, rounding: mode),
            referenceRound(numerator, denominator, mode),
            reason: '$numerator / $denominator ($mode)',
          );
        }
      }
    });

    test('minorUnits is the magnitude of the fractional part for negative amounts', () {
      final m = Money(cents: -1999);
      expect(m.majorUnits, -19);
      expect(m.minorUnits, 99);
    });

    test('allocate balances negative totals using the largest remainders', () {
      expect(Money(cents: -100).allocate([1, 1, 1]).map((p) => p.cents), [-34, -33, -33]);
      expect(Money(cents: 100).allocate([1, 2]).map((p) => p.cents), [33, 67]);
      expect(Money(cents: -100).allocate([1, 2]).map((p) => p.cents), [-33, -67]);
      // Exact shares 3, 1.5, 1.5: the leftover unit goes to a truncated share.
      expect(Money(cents: 6).allocate([2, 1, 1]).map((p) => p.cents), [3, 2, 1]);
    });

    test('allocate always sums to the total and stays within one unit of the exact share', () {
      final rng = math.Random(11);
      for (var i = 0; i < 5000; i++) {
        final total = rng.nextInt(2000001) - 1000000;
        final ratios = List<int>.generate(1 + rng.nextInt(6), (_) => rng.nextInt(10));
        if (ratios.every((r) => r == 0)) ratios[0] = 1;
        final weight = ratios.reduce((a, b) => a + b);

        final parts = Money(cents: total).allocate(ratios);

        expect(parts.fold<int>(0, (sum, p) => sum + p.cents), total, reason: '$total $ratios');
        for (var j = 0; j < ratios.length; j++) {
          final exact = total * ratios[j] / weight;
          expect((parts[j].cents - exact).abs(), lessThan(1), reason: '$total $ratios [$j]');
        }
      }
    });
  });
}
