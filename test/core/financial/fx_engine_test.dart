import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/core/financial/fx_engine.dart';

void main() {
  group('FxEngine Tests', () {
    test('converts identical currency without mutation', () {
      expect(FxEngine.convert(amount: 100.0, fromCurrency: 'USD', toCurrency: 'USD'), 100.0);
      expect(FxEngine.convert(amount: 50.0, fromCurrency: 'EUR', toCurrency: 'EUR'), 50.0);
    });

    test('converts EUR to USD accurately with default baseline rates', () {
      // 100 EUR -> USD (100 / 0.92 = 108.695)
      final usd = FxEngine.convert(amount: 100.0, fromCurrency: 'EUR', toCurrency: 'USD');
      expect(usd, closeTo(108.70, 0.05));
    });

    test('converts USD to JPY accurately', () {
      // 10 USD -> JPY (10 * 155 = 1550)
      final jpy = FxEngine.convert(amount: 10.0, fromCurrency: 'USD', toCurrency: 'JPY');
      expect(jpy, 1550.0);
    });

    test('parses raw string with currency symbols properly', () {
      final euroRes = FxEngine.parseAmountWithCurrency('€ 149.99');
      expect(euroRes.amount, 149.99);
      expect(euroRes.currency, 'EUR');

      final gbpRes = FxEngine.parseAmountWithCurrency('£45.00');
      expect(gbpRes.amount, 45.00);
      expect(gbpRes.currency, 'GBP');

      final jpyRes = FxEngine.parseAmountWithCurrency('¥ 2500');
      expect(jpyRes.amount, 2500.0);
      expect(jpyRes.currency, 'JPY');

      final codeRes = FxEngine.parseAmountWithCurrency('500.00 CAD');
      expect(codeRes.amount, 500.00);
      expect(codeRes.currency, 'CAD');
    });

    test('formats currency with symbols and decimal precision', () {
      expect(FxEngine.formatCurrency(1234.56, 'USD'), '\$1234.56');
      expect(FxEngine.formatCurrency(89.50, 'EUR'), '€89.50');
      expect(FxEngine.formatCurrency(2500.0, 'JPY'), '¥2500');
    });
  });
}
