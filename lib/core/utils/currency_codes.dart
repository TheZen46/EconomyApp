/// ISO 4217 currency codes, the form used by the receipts table (VARCHAR(3)),
/// Money and FatturaPA.
class CurrencyCodes {
  CurrencyCodes._();

  static const Map<String, String> _symbols = {
    '€': 'EUR',
    r'$': 'USD',
    'US\$': 'USD',
    '£': 'GBP',
    '¥': 'JPY',
    '₹': 'INR',
    'CHF': 'CHF',
    'Fr.': 'CHF',
    'kr': 'SEK',
    'zł': 'PLN',
    'R\$': 'BRL',
  };

  static final RegExp _code = RegExp(r'^[A-Z]{3}$');

  /// Returns the ISO 4217 code for [value], which may be a code in any case
  /// or a common currency symbol, or [fallback] when it is neither.
  static String normalize(String? value, {String fallback = 'EUR'}) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return fallback;
    final upper = text.toUpperCase();
    if (_code.hasMatch(upper)) return upper;
    return _symbols[text] ?? fallback;
  }
}
