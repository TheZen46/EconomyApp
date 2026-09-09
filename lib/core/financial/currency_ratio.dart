import 'money.dart';

/// Exact rational exchange rate representation between two currencies.
///
/// Stores conversion rate as an irreducible integer fraction (numerator / denominator)
/// to avoid binary floating-point representation errors during currency conversion.
///
/// Formula: `Converted = round((SourceCents * Numerator) / Denominator)`
class CurrencyRatio {
  /// Base currency being converted from (e.g. 'USD').
  final String baseCurrency;

  /// Quote currency being converted to (e.g. 'EUR').
  final String quoteCurrency;

  /// Exact integer numerator of the exchange rate.
  final int numerator;

  /// Exact integer denominator of the exchange rate.
  final int denominator;

  const CurrencyRatio({
    required this.baseCurrency,
    required this.quoteCurrency,
    required this.numerator,
    required this.denominator,
  }) : assert(denominator > 0, 'Denominator must be positive');

  /// Creates a ratio from a decimal rate (e.g., 1.0855 USD/EUR -> 10855 / 10000).
  factory CurrencyRatio.fromDecimal({
    required String baseCurrency,
    required String quoteCurrency,
    required double rate,
    int precision = 1000000,
  }) {
    if (rate <= 0) throw ArgumentError('Exchange rate must be positive');
    final num = (rate * precision).round();
    final g = _gcd(num, precision);
    return CurrencyRatio(
      baseCurrency: baseCurrency,
      quoteCurrency: quoteCurrency,
      numerator: num ~/ g,
      denominator: precision ~/ g,
    );
  }

  /// Exact 1:1 identity ratio for same-currency operations.
  factory CurrencyRatio.identity(String currency) => CurrencyRatio(
        baseCurrency: currency,
        quoteCurrency: currency,
        numerator: 1,
        denominator: 1,
      );

  /// Converts a [Money] amount in [baseCurrency] to [quoteCurrency] with Banker's rounding.
  Money convert(
    Money source, {
    MidpointRounding rounding = MidpointRounding.toEven,
  }) {
    if (source.currency.toUpperCase() != baseCurrency.toUpperCase()) {
      throw ArgumentError(
        'Currency mismatch: ratio base is $baseCurrency but money is ${source.currency}',
      );
    }

    if (baseCurrency.toUpperCase() == quoteCurrency.toUpperCase()) {
      return Money(cents: source.cents, currency: quoteCurrency, scale: source.scale);
    }

    final int num = source.cents * numerator;
    final int convertedCents = Money.roundIntegerDivision(
      num,
      denominator,
      rounding: rounding,
    );

    return Money(
      cents: convertedCents,
      currency: quoteCurrency,
      scale: source.scale,
    );
  }

  /// Computes the exact inverse exchange rate (Quote -> Base).
  CurrencyRatio inverse() {
    return CurrencyRatio(
      baseCurrency: quoteCurrency,
      quoteCurrency: baseCurrency,
      numerator: denominator,
      denominator: numerator,
    );
  }

  /// Multiplies with another ratio to form a currency cross-rate (A/B * B/C = A/C).
  CurrencyRatio multiply(CurrencyRatio other) {
    if (quoteCurrency.toUpperCase() != other.baseCurrency.toUpperCase()) {
      throw ArgumentError(
        'Cannot chain ratio $baseCurrency/$quoteCurrency with ${other.baseCurrency}/${other.quoteCurrency}',
      );
    }

    final int num = numerator * other.numerator;
    final int den = denominator * other.denominator;
    final int g = _gcd(num, den);

    return CurrencyRatio(
      baseCurrency: baseCurrency,
      quoteCurrency: other.quoteCurrency,
      numerator: num ~/ g,
      denominator: den ~/ g,
    );
  }

  /// Rate expressed as floating-point decimal for display purposes only.
  double get toDouble => numerator / denominator;

  static int _gcd(int a, int b) {
    a = a.abs();
    b = b.abs();
    while (b != 0) {
      final t = b;
      b = a % b;
      a = t;
    }
    return a == 0 ? 1 : a;
  }

  @override
  String toString() =>
      '$baseCurrency/$quoteCurrency ($numerator/$denominator = ${(toDouble).toStringAsFixed(4)})';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CurrencyRatio &&
        other.baseCurrency.toUpperCase() == baseCurrency.toUpperCase() &&
        other.quoteCurrency.toUpperCase() == quoteCurrency.toUpperCase() &&
        other.numerator == numerator &&
        other.denominator == denominator;
  }

  @override
  int get hashCode => Object.hash(
        baseCurrency.toUpperCase(),
        quoteCurrency.toUpperCase(),
        numerator,
        denominator,
      );
}
