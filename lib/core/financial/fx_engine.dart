import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Currency metadata representing an ISO-4217 financial currency.
class CurrencyInfo {
  final String code;
  final String symbol;
  final String name;
  final int decimalDigits;

  const CurrencyInfo({
    required this.code,
    required this.symbol,
    required this.name,
    this.decimalDigits = 2,
  });
}

/// Supported fiat currencies for international freelancing and receipt processing.
const Map<String, CurrencyInfo> kSupportedCurrencies = {
  'USD': CurrencyInfo(code: 'USD', symbol: '\$', name: 'US Dollar'),
  'EUR': CurrencyInfo(code: 'EUR', symbol: '€', name: 'Euro'),
  'GBP': CurrencyInfo(code: 'GBP', symbol: '£', name: 'British Pound'),
  'CAD': CurrencyInfo(code: 'CAD', symbol: 'C\$', name: 'Canadian Dollar'),
  'AUD': CurrencyInfo(code: 'AUD', symbol: 'A\$', name: 'Australian Dollar'),
  'JPY': CurrencyInfo(code: 'JPY', symbol: '¥', name: 'Japanese Yen', decimalDigits: 0),
  'CHF': CurrencyInfo(code: 'CHF', symbol: 'CHF', name: 'Swiss Franc'),
};

/// Offline baseline exchange rate table relative to USD (1.0 USD = X Currency units).
const Map<String, double> kDefaultUsdExchangeRates = {
  'USD': 1.0,
  'EUR': 0.92,
  'GBP': 0.79,
  'CAD': 1.36,
  'AUD': 1.52,
  'JPY': 155.0,
  'CHF': 0.90,
};

/// High-precision multi-currency conversion and rate interpolation engine.
class FxEngine {
  /// Converts an [amount] from [fromCurrency] to [toCurrency] using available rates.
  static double convert({
    required double amount,
    required String fromCurrency,
    required String toCurrency,
    Map<String, double>? customRates,
  }) {
    final from = fromCurrency.toUpperCase().trim();
    final to = toCurrency.toUpperCase().trim();

    if (from == to || amount == 0.0) {
      return amount;
    }

    final rates = customRates ?? kDefaultUsdExchangeRates;
    final rateFromUsdToSource = rates[from] ?? 1.0;
    final rateFromUsdToTarget = rates[to] ?? 1.0;

    // Convert source -> USD -> target
    final amountInUsd = amount / rateFromUsdToSource;
    final convertedAmount = amountInUsd * rateFromUsdToTarget;

    return convertedAmount;
  }

  /// Parses currency symbols and ISO codes from raw text strings (e.g., "€150.00", "£ 45.50", "2000 JPY").
  static ({double amount, String currency}) parseAmountWithCurrency(String rawInput, {String defaultCurrency = 'USD'}) {
    final trimmed = rawInput.trim();
    if (trimmed.isEmpty) {
      return (amount: 0.0, currency: defaultCurrency);
    }

    String detectedCurrency = defaultCurrency;

    // Match symbols
    if (trimmed.contains('€')) {
      detectedCurrency = 'EUR';
    } else if (trimmed.contains('£')) {
      detectedCurrency = 'GBP';
    } else if (trimmed.contains('¥')) {
      detectedCurrency = 'JPY';
    } else if (trimmed.contains('C\$')) {
      detectedCurrency = 'CAD';
    } else if (trimmed.contains('A\$')) {
      detectedCurrency = 'AUD';
    } else if (trimmed.contains('\$')) {
      detectedCurrency = 'USD';
    } else {
      // Check ISO codes
      for (final code in kSupportedCurrencies.keys) {
        if (RegExp('\\b$code\\b', caseSensitive: false).hasMatch(trimmed)) {
          detectedCurrency = code;
          break;
        }
      }
    }

    // Extract numeric amount
    final cleaned = trimmed.replaceAll(RegExp(r'[^0-9.,]'), '');
    final sanitized = cleaned.replaceAll(',', '.');
    final amount = double.tryParse(sanitized) ?? 0.0;

    return (amount: amount, currency: detectedCurrency);
  }

  /// Formats [amount] into localized currency string with correct symbol and decimal placement.
  static String formatCurrency(double amount, String currencyCode) {
    final info = kSupportedCurrencies[currencyCode.toUpperCase()] ??
        CurrencyInfo(code: currencyCode, symbol: currencyCode, name: currencyCode);

    final formattedValue = amount.toStringAsFixed(info.decimalDigits);
    return '${info.symbol}$formattedValue';
  }
}

/// Provider for user's primary operating/reporting base currency.
final userBaseCurrencyProvider = StateProvider<String>((ref) => 'USD');
