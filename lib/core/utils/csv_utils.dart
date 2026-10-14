/// Helpers for writing CSV files that are safe to open in spreadsheet
/// applications.
class CsvUtils {
  CsvUtils._();

  /// Leading characters that make Excel, LibreOffice Calc or Google Sheets
  /// evaluate a cell as a formula (OWASP "CSV Injection").
  static const Set<String> _formulaTriggers = {'=', '+', '-', '@', '\t', '\r'};

  static final RegExp _plainNumber = RegExp(r'^[+-]?\d+(\.\d+)?$');

  /// Returns [value] in a form that a spreadsheet displays as text.
  ///
  /// Merchant names, item descriptions and notes come from OCR, model output,
  /// imports or user input; a cell such as `=HYPERLINK("https://...")` would
  /// otherwise run as a formula when the export is opened. Such cells are
  /// prefixed with a single quote. Non-string values and plain signed numbers
  /// (for example `-12.50`) are returned unchanged.
  static Object? sanitizeCell(Object? value) {
    if (value is! String || value.isEmpty) return value;
    if (!_formulaTriggers.contains(value[0])) return value;
    if (_plainNumber.hasMatch(value)) return value;
    return "'$value";
  }

  /// Applies [sanitizeCell] to every cell of [rows].
  static List<List<dynamic>> sanitizeRows(List<List<dynamic>> rows) {
    return [
      for (final row in rows) [for (final cell in row) sanitizeCell(cell)],
    ];
  }
}
