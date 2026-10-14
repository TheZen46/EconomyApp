import 'dart:math' as math;

/// Rounding strategies for financial currency computations.
enum MidpointRounding {
  /// Unbiased Banker's Rounding (IEEE 754 roundTiesToEven).
  /// Rounds ties towards the nearest even number to eliminate statistical drift.
  toEven,

  /// Asymmetric round-half-up (away from zero).
  awayFromZero,

  /// Truncation towards zero.
  towardsZero,
}

/// Immutable Fixed-Point Monetary Value.
///
/// Stores financial amounts as 64-bit integer minor currency units (cents / micro-cents)
/// to eliminate IEEE 754 floating-point representation drift and rounding errors.
///
/// Example:
/// - USD $19.99 is represented internally as `cents = 1999` (scale 10^2).
/// - Micro-precision values (e.g. fractional fuel / exchange rates) use scale 10^4.
class Money implements Comparable<Money> {
  /// Amount in minor currency units (e.g., cents for USD/EUR, yen for JPY).
  final int cents;

  /// ISO 4217 Currency Code (e.g., 'EUR', 'USD', 'GBP').
  final String currency;

  /// Number of decimal places for standard currency representation (default 2).
  final int scale;

  const Money({
    required this.cents,
    this.currency = 'EUR',
    this.scale = 2,
  });

  /// Factory from decimal major units (e.g. 19.99 EUR -> 1999 cents).
  factory Money.fromDecimal(
    num majorUnits, {
    String currency = 'EUR',
    int scale = 2,
    MidpointRounding rounding = MidpointRounding.toEven,
  }) {
    final scalingFactor = math.pow(10, scale).toInt();
    // Convert to scaled integer using exact rational representation
    final scaledValue = (majorUnits * scalingFactor * 1000).round();
    final int roundedCents = roundIntegerDivision(
      scaledValue,
      1000,
      rounding: rounding,
    );
    return Money(cents: roundedCents, currency: currency, scale: scale);
  }

  /// Factory for zero monetary value in specified currency.
  factory Money.zero([String currency = 'EUR']) => Money(cents: 0, currency: currency);

  /// Converts internal minor units (cents) to double representation for display/UI.
  double get toDouble => cents / math.pow(10, scale);

  /// Major unit integer part.
  int get majorUnits => cents ~/ math.pow(10, scale).toInt();

  /// Minor unit fractional remainder (always non-negative; the sign is carried by [majorUnits]
  /// and [isNegative]). Uses the truncating remainder: Dart's `%` is Euclidean, so
  /// `-1999 % 100` is 1, whereas the minor part of -19.99 is 99.
  int get minorUnits => cents.remainder(math.pow(10, scale).toInt()).abs();

  /// Checks if value is zero.
  bool get isZero => cents == 0;

  /// Checks if value is positive (> 0).
  bool get isPositive => cents > 0;

  /// Checks if value is negative (< 0).
  bool get isNegative => cents < 0;

  /// Absolute monetary value.
  Money abs() => Money(cents: cents.abs(), currency: currency, scale: scale);

  // --------------------------------------------------------------------------
  // ARITHMETIC OPERATORS (Fixed-Point Integer Math)
  // --------------------------------------------------------------------------

  Money operator +(Money other) {
    _assertSameCurrency(other);
    return Money(cents: cents + other.cents, currency: currency, scale: scale);
  }

  Money operator -(Money other) {
    _assertSameCurrency(other);
    return Money(cents: cents - other.cents, currency: currency, scale: scale);
  }

  Money operator -() {
    return Money(cents: -cents, currency: currency, scale: scale);
  }

  /// Multiplies money by a factor with Banker's rounding.
  Money multiply(num factor, {MidpointRounding rounding = MidpointRounding.toEven}) {
    // Scale factor by 1,000,000 for high integer precision
    const int factorScale = 1000000;
    final int scaledFactor = (factor * factorScale).round();
    final int numerator = cents * scaledFactor;
    final int resultCents = roundIntegerDivision(
      numerator,
      factorScale,
      rounding: rounding,
    );
    return Money(cents: resultCents, currency: currency, scale: scale);
  }

  /// Exact integer minor units multiplication by an integer quantity.
  Money multiplyInt(int quantity) {
    return Money(cents: cents * quantity, currency: currency, scale: scale);
  }

  /// Divides money by a divisor with Banker's rounding.
  Money divide(num divisor, {MidpointRounding rounding = MidpointRounding.toEven}) {
    if (divisor == 0) throw ArgumentError('Cannot divide Money by zero');
    const int divisorScale = 1000000;
    final int scaledDivisor = (divisor * divisorScale).round();
    final int numerator = cents * divisorScale;
    final int resultCents = roundIntegerDivision(
      numerator,
      scaledDivisor,
      rounding: rounding,
    );
    return Money(cents: resultCents, currency: currency, scale: scale);
  }

  /// Allocates money across integer percentage weights without losing pennies.
  /// (Guarantees sum of split parts exactly equals the total, with each part within
  /// one minor unit of its exact proportional share.)
  List<Money> allocate(List<int> ratios) {
    if (ratios.isEmpty) return [];
    final int totalWeight = ratios.reduce((a, b) => a + b);
    if (totalWeight <= 0) {
      throw ArgumentError('Total allocation weight must be positive');
    }

    int remainder = cents;
    final shares = <int>[];
    final truncationErrors = <int>[];

    for (int i = 0; i < ratios.length; i++) {
      final int exactNumerator = cents * ratios[i];
      final int share = exactNumerator ~/ totalWeight;
      shares.add(share);
      truncationErrors.add((exactNumerator - share * totalWeight).abs());
      remainder -= share;
    }

    // Largest-remainder method: truncation leaves |remainder| units with the sign of
    // the total. Each goes to a bucket whose exact share was truncated the most
    // (ties: higher ratio, then list order), so every part stays within one minor
    // unit of its exact share and negative totals are balanced as well.
    final order = List<int>.generate(ratios.length, (i) => i)
      ..sort((a, b) {
        final byError = truncationErrors[b].compareTo(truncationErrors[a]);
        if (byError != 0) return byError;
        final byRatio = ratios[b].compareTo(ratios[a]);
        return byRatio != 0 ? byRatio : a.compareTo(b);
      });
    final int unit = remainder.sign;
    for (int k = 0; k < remainder.abs(); k++) {
      shares[order[k]] += unit;
    }

    return [
      for (final share in shares) Money(cents: share, currency: currency, scale: scale),
    ];
  }

  // --------------------------------------------------------------------------
  // BANKER'S ROUNDING ENGINE (Integer Division)
  // --------------------------------------------------------------------------

  /// Unbiased Banker's Rounding (MidpointRounding.toEven) over pure integer division.
  static int roundIntegerDivision(
    int numerator,
    int denominator, {
    MidpointRounding rounding = MidpointRounding.toEven,
  }) {
    if (denominator == 0) throw ArgumentError('Division by zero');

    // `~/` truncates towards zero; `remainder` is the matching truncated remainder.
    // (Dart's `%` is Euclidean and must not be used here: -13 % 10 is 7, not 3.)
    final int q = numerator ~/ denominator;
    final int absRem = numerator.remainder(denominator).abs();
    if (absRem == 0) return q;

    final int absDen = denominator.abs();
    final int doubleRem = absRem * 2;
    // Step that moves the truncated quotient away from zero, following the sign
    // of the exact quotient (negative when exactly one operand is negative).
    final int awayStep = (numerator < 0) == (denominator < 0) ? 1 : -1;

    switch (rounding) {
      case MidpointRounding.toEven:
        if (doubleRem == absDen) {
          // Exactly midpoint tie: round to nearest even quotient
          return q.isEven ? q : q + awayStep;
        }
        return doubleRem > absDen ? q + awayStep : q;

      case MidpointRounding.awayFromZero:
        // Round half away from zero: ties and anything above them move away.
        return doubleRem >= absDen ? q + awayStep : q;

      case MidpointRounding.towardsZero:
        return q;
    }
  }

  // --------------------------------------------------------------------------
  // COMPARISON & EQUALITY
  // --------------------------------------------------------------------------

  @override
  int compareTo(Money other) {
    _assertSameCurrency(other);
    return cents.compareTo(other.cents);
  }

  bool operator <(Money other) => compareTo(other) < 0;
  bool operator <=(Money other) => compareTo(other) <= 0;
  bool operator >(Money other) => compareTo(other) > 0;
  bool operator >=(Money other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Money &&
        other.cents == cents &&
        other.currency.toUpperCase() == currency.toUpperCase() &&
        other.scale == scale;
  }

  @override
  int get hashCode => Object.hash(cents, currency.toUpperCase(), scale);

  /// Standard formatted currency string (e.g. "€ 19,99" or "$19.99").
  String format({bool showSymbol = true, String locale = 'it_IT'}) {
    final isNegative = cents < 0;
    final absCents = cents.abs();
    final int divisor = math.pow(10, scale).toInt();
    final int intPart = absCents ~/ divisor;
    final int fracPart = absCents % divisor;
    final String fracStr = fracPart.toString().padLeft(scale, '0');

    final bool isEuropean = locale.startsWith('it') || locale.startsWith('de') || locale.startsWith('fr');
    final String decimalSep = isEuropean ? ',' : '.';
    final String thousandSep = isEuropean ? '.' : ',';

    // Format integer part with thousands separators
    final String rawInt = intPart.toString();
    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i < rawInt.length; i++) {
      if (i > 0 && (rawInt.length - i) % 3 == 0) {
        buffer.write(thousandSep);
      }
      buffer.write(rawInt[i]);
    }

    final formattedNumber = '${isNegative ? '-' : ''}${buffer.toString()}$decimalSep$fracStr';

    if (!showSymbol) return formattedNumber;

    final symbol = _currencySymbol(currency);
    return isEuropean ? '$formattedNumber $symbol' : '$symbol$formattedNumber';
  }

  static String _currencySymbol(String curr) {
    switch (curr.toUpperCase()) {
      case 'EUR':
        return '€';
      case 'USD':
        return '\$';
      case 'GBP':
        return '£';
      case 'CHF':
        return 'CHF';
      case 'JPY':
        return '¥';
      default:
        return curr;
    }
  }

  @override
  String toString() => '$currency ${(cents / math.pow(10, scale)).toStringAsFixed(scale)}';

  void _assertSameCurrency(Money other) {
    if (currency.toUpperCase() != other.currency.toUpperCase()) {
      throw ArgumentError(
        'Currency mismatch: cannot operate on $currency and ${other.currency}',
      );
    }
  }
}
