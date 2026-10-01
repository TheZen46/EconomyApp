/// Parses monetary amounts typed by users in either decimal convention.
class AmountParser {
  AmountParser._();

  static final RegExp _allowed = RegExp(r'^-?\d[\d.,]*$');

  /// Returns the amount in [input], or null when it is not a number.
  ///
  /// Accepts "12.50", "12,50", "1,234.56", "1.234,56" and "1 234,56", with an
  /// optional currency symbol. With both separators the last one is the
  /// decimal separator. A lone separator followed by exactly three digits
  /// ("1,234" or "1.234") is a thousands separator, since prices are written
  /// with at most two decimals; otherwise it is the decimal separator.
  static double? parse(String input) {
    var text = input.trim().replaceAll(RegExp("[\\s '’€\$£¥₹]"), '');
    if (text.isEmpty || !_allowed.hasMatch(text)) return null;

    final negative = text.startsWith('-');
    if (negative) text = text.substring(1);

    final lastComma = text.lastIndexOf(',');
    final lastPoint = text.lastIndexOf('.');
    String normalized;
    if (lastComma != -1 && lastPoint != -1) {
      normalized = lastComma > lastPoint
          ? text.replaceAll('.', '').replaceAll(',', '.')
          : text.replaceAll(',', '');
    } else if (lastComma != -1 || lastPoint != -1) {
      final separator = lastComma != -1 ? ',' : '.';
      final last = lastComma != -1 ? lastComma : lastPoint;
      final single = separator.allMatches(text).length == 1;
      final isDecimal = single && text.length - last - 1 != 3;
      normalized = isDecimal ? text.replaceAll(separator, '.') : text.replaceAll(separator, '');
    } else {
      normalized = text;
    }

    final value = double.tryParse(normalized);
    if (value == null) return null;
    return negative ? -value : value;
  }
}
