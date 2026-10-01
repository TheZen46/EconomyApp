/// Parses purchase dates printed on receipts, returned by models or found in
/// imported files.
class ReceiptDateParser {
  ReceiptDateParser._();

  static final RegExp _numericDate = RegExp(r'^(\d{1,4})[-/.](\d{1,2})[-/.](\d{1,4})$');

  /// Returns the calendar date in [input], or null when there is none or it
  /// does not exist (for example 31/02/2026).
  ///
  /// Accepts ISO-8601 (with or without a time), year-first dates with `-`, `/`
  /// or `.` separators, and day-first dates such as 15/01/2026 or 15.01.26.
  /// A numeric date whose first two fields are both 12 or lower is read
  /// day-first, the order used on receipts in the app's primary markets,
  /// unless [dayFirst] is false (for example when other dates in the same file
  /// are month-first). A date that is valid in only one order is read in that
  /// order.
  static DateTime? parse(String? input, {bool? dayFirst}) {
    final text = input?.trim() ?? '';
    if (text.isEmpty) return null;

    final match = _numericDate.firstMatch(text);
    if (match == null) {
      final iso = DateTime.tryParse(text);
      return iso == null ? null : DateTime(iso.year, iso.month, iso.day);
    }

    final a = match.group(1)!;
    final b = int.parse(match.group(2)!);
    final c = match.group(3)!;
    if (a.length == 4) return _date(int.parse(a), b, int.parse(c));
    if (a.length > 2 || (c.length != 2 && c.length != 4)) return null;

    final year = c.length == 2 ? 2000 + int.parse(c) : int.parse(c);
    final first = int.parse(a);
    if (b > 12 && first <= 12) return _date(year, first, b);
    if (first <= 12 && b <= 12 && dayFirst == false) return _date(year, first, b);
    return _date(year, b, first);
  }

  /// Which field order the numeric dates in [values] use: true for day-first,
  /// false for month-first, or null when none of them is unambiguous. Used to
  /// read ambiguous dates of a file consistently with its unambiguous ones.
  static bool? detectDayFirst(Iterable<String> values) {
    var dayFirst = 0;
    var monthFirst = 0;
    for (final value in values) {
      final match = _numericDate.firstMatch(value.trim());
      if (match == null || match.group(1)!.length > 2) continue;
      final first = int.parse(match.group(1)!);
      final second = int.parse(match.group(2)!);
      if (first > 12 && second <= 12) dayFirst++;
      if (second > 12 && first <= 12) monthFirst++;
    }
    if (dayFirst == 0 && monthFirst == 0) return null;
    return dayFirst >= monthFirst;
  }

  /// Like [parse], but also rejects dates that cannot be a purchase date:
  /// more than one day in the future, or before the year 2000.
  static DateTime? parsePurchaseDate(String? input, {DateTime? now, bool? dayFirst}) {
    final date = parse(input, dayFirst: dayFirst);
    if (date == null) return null;
    final today = now ?? DateTime.now();
    if (date.isAfter(today.add(const Duration(days: 1))) || date.year < 2000) return null;
    return date;
  }

  static DateTime? _date(int year, int month, int day) {
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    final date = DateTime(year, month, day);
    // DateTime normalizes overflow (31/02 becomes 03/03); reject it instead.
    if (date.month != month || date.day != day) return null;
    return date;
  }
}
