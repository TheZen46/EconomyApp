import '../models/statement_transaction.dart';

/// Layout-aware parser for banking text streams extracted from PDF statements.
class PdfStatementParser {
  /// Parses raw text extracted from a PDF bank statement into a list of [StatementTransaction]s.
  static List<StatementTransaction> parsePdfText(String rawText, {String defaultCurrency = 'USD'}) {
    final List<StatementTransaction> transactions = [];
    final lines = rawText.split(RegExp(r'\r?\n'));

    // Common date patterns at start of transaction lines
    // Pattern 1: 03/15/2026 or 15/03/2026 or 2026-03-15
    final dateRegex = RegExp(r'^(\d{1,4}[-/\.]\d{1,2}[-/\.]\d{1,4})\s+(.+)$');
    // Pattern 2: Mar 15, 2026 or 15 Mar 2026
    final alphaDateRegex = RegExp(r'^([A-Za-z]{3,9}\s+\d{1,2},?\s+\d{4}|\d{1,2}\s+[A-Za-z]{3,9}\s+\d{4})\s+(.+)$');

    // Amount extraction regex (matches trailing amounts like -154.20 or $154.20 or 154,20)
    final amountRegex = RegExp(r'(-?\$?\s*\d{1,3}(?:[,\.]\d{3})*(?:[,\.]\d{2}))\s*$');

    int index = 0;
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      // Skip common statement headers & footers
      final lower = trimmed.toLowerCase();
      if (lower.contains('balance forward') ||
          lower.contains('account number') ||
          lower.contains('statement period') ||
          lower.contains('page ') ||
          lower.contains('total debits') ||
          lower.contains('total credits')) {
        continue;
      }

      DateTime? parsedDate;
      String remaining = '';

      final dateMatch = dateRegex.firstMatch(trimmed);
      if (dateMatch != null) {
        parsedDate = _parseFlexibleDate(dateMatch.group(1)!);
        remaining = dateMatch.group(2)!.trim();
      } else {
        final alphaMatch = alphaDateRegex.firstMatch(trimmed);
        if (alphaMatch != null) {
          parsedDate = _parseAlphaDate(alphaMatch.group(1)!);
          remaining = alphaMatch.group(2)!.trim();
        }
      }

      if (parsedDate == null || remaining.isEmpty) continue;

      // Extract amount from remaining text
      final amountMatch = amountRegex.firstMatch(remaining);
      if (amountMatch != null) {
        final rawAmountStr = amountMatch.group(1)!;
        final cleanAmount = _sanitizeAmount(rawAmountStr);
        final description = remaining.substring(0, amountMatch.start).trim();

        if (description.isNotEmpty && cleanAmount > 0) {
          transactions.add(StatementTransaction(
            id: 'pdf-tx-${index++}',
            date: parsedDate,
            description: description,
            amount: cleanAmount,
            currency: defaultCurrency,
          ));
        }
      }
    }

    return transactions;
  }

  static DateTime? _parseFlexibleDate(String input) {
    try {
      final parts = input.split(RegExp(r'[-/\.]'));
      if (parts.length != 3) return null;

      int year, month, day;
      if (parts[0].length == 4) {
        // YYYY-MM-DD
        year = int.parse(parts[0]);
        month = int.parse(parts[1]);
        day = int.parse(parts[2]);
      } else if (parts[2].length == 4) {
        // MM/DD/YYYY or DD/MM/YYYY
        year = int.parse(parts[2]);
        final p0 = int.parse(parts[0]);
        final p1 = int.parse(parts[1]);
        if (p0 > 12) {
          day = p0;
          month = p1;
        } else {
          month = p0;
          day = p1;
        }
      } else {
        return null;
      }

      return DateTime(year, month, day);
    } catch (_) {
      return null;
    }
  }

  static DateTime? _parseAlphaDate(String input) {
    const months = {
      'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
      'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
    };

    try {
      final cleaned = input.replaceAll(',', '').toLowerCase();
      final parts = cleaned.split(RegExp(r'\s+'));
      if (parts.length != 3) return null;

      int year = int.parse(parts[2]);
      int? month;
      int? day;

      for (final key in months.keys) {
        if (parts[0].startsWith(key)) {
          month = months[key];
          day = int.parse(parts[1]);
          break;
        } else if (parts[1].startsWith(key)) {
          month = months[key];
          day = int.parse(parts[0]);
          break;
        }
      }

      if (month != null && day != null) {
        return DateTime(year, month, day);
      }
    } catch (_) {}
    return null;
  }

  static double _sanitizeAmount(String raw) {
    final cleaned = raw.replaceAll('\$', '').replaceAll(' ', '').trim();
    if (cleaned.contains(',') && cleaned.contains('.')) {
      // e.g. 1,250.50
      final norm = cleaned.replaceAll(',', '');
      return (double.tryParse(norm) ?? 0.0).abs();
    } else if (cleaned.contains(',')) {
      // European format e.g. 125,50
      final norm = cleaned.replaceAll(',', '.');
      return (double.tryParse(norm) ?? 0.0).abs();
    } else {
      return (double.tryParse(cleaned) ?? 0.0).abs();
    }
  }
}
