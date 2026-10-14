import 'package:csv/csv.dart';
import 'package:uuid/uuid.dart';
import '../../../receipt_scanning/data/datasources/bank_reconciliation_service.dart';
import '../models/statement_transaction.dart';

class StatementParser {
  static const _uuid = Uuid();

  /// Parses raw CSV bank statement data into structured [StatementTransaction] items.
  static List<StatementTransaction> parseCsv(String csvContent) {
    if (csvContent.trim().isEmpty) return [];

    final bankTxns = BankReconciliationService.parseBankCsv(csvContent);
    if (bankTxns.isNotEmpty) {
      return bankTxns.map((t) => StatementTransaction(
        id: t.id.isNotEmpty ? t.id : _uuid.v4(),
        date: t.date,
        description: t.description,
        amount: t.amount,
        currency: t.currency,
        referenceNumber: t.referenceNumber,
      )).toList();
    }

    final transactions = <StatementTransaction>[];
    try {
      final rows = const CsvToListConverter(eol: '\n').convert(csvContent);
      if (rows.length < 2) return transactions;

      final header = rows.first.map((e) => e.toString().toLowerCase().trim()).toList();

      int dateIdx = -1;
      int descIdx = -1;
      int amountIdx = -1;
      int debitIdx = -1;
      int creditIdx = -1;

      for (int i = 0; i < header.length; i++) {
        final col = header[i];
        if (col.contains('date') || col.contains('data') || col.contains('datum')) {
          dateIdx = i;
        } else if (col.contains('desc') || col.contains('payee') || col.contains('merchant') || col.contains('memo') || col.contains('details') || col.contains('name')) {
          descIdx = i;
        } else if (col.contains('debit') || col.contains('addebito') || col.contains('ausgabe')) {
          debitIdx = i;
        } else if (col.contains('credit') || col.contains('accredito') || col.contains('einnahme')) {
          creditIdx = i;
        } else if (col.contains('amount') || col.contains('importo') || col.contains('betrag') || col.contains('value')) {
          amountIdx = i;
        }
      }

      if (dateIdx == -1) dateIdx = 0;
      if (descIdx == -1) descIdx = 1 < header.length ? 1 : 0;
      if (amountIdx == -1 && debitIdx != -1) amountIdx = debitIdx;
      if (amountIdx == -1 && creditIdx != -1) amountIdx = creditIdx;
      if (amountIdx == -1) amountIdx = header.length > 2 ? 2 : header.length - 1;

      for (int r = 1; r < rows.length; r++) {
        final row = rows[r];
        if (row.isEmpty || row.every((c) => c.toString().trim().isEmpty)) continue;

        try {
          final dateRaw = row.length > dateIdx ? row[dateIdx].toString().trim() : '';
          final descRaw = row.length > descIdx ? row[descIdx].toString().trim() : 'Transaction';

          double amount = 0.0;
          if (debitIdx != -1 && row.length > debitIdx && row[debitIdx].toString().trim().isNotEmpty) {
            amount = _parseAmount(row[debitIdx].toString());
          } else if (amountIdx != -1 && row.length > amountIdx) {
            amount = _parseAmount(row[amountIdx].toString());
          }

          if (amount < 0) amount = amount.abs(); // Store expense amounts as positive numbers

          final parsedDate = _parseDate(dateRaw);

          if (descRaw.isNotEmpty && amount > 0) {
            transactions.add(StatementTransaction(
              id: _uuid.v4(),
              date: parsedDate,
              description: descRaw,
              amount: amount,
            ));
          }
        } catch (_) {}
      }
    } catch (_) {}

    return transactions;
  }

  /// Parses Open Financial Exchange (OFX / QBO) XML payloads.
  static List<StatementTransaction> parseOfx(String ofxContent) {
    final transactions = <StatementTransaction>[];
    if (ofxContent.trim().isEmpty) return transactions;

    final regexTrn = RegExp(r'<STMTTRN>([\s\S]*?)<\/STMTTRN>', caseSensitive: false);
    final matches = regexTrn.allMatches(ofxContent);

    for (final match in matches) {
      final block = match.group(1) ?? '';
      
      final dtPostedMatch = RegExp(r'<DTPOSTED>([0-9]{8})', caseSensitive: false).firstMatch(block);
      final amtMatch = RegExp(r'<TRNAMT>([+-]?[0-9]+(?:\.[0-9]+)?)', caseSensitive: false).firstMatch(block);
      final nameMatch = RegExp(r'<(?:NAME|MEMO)>(.*?)(?:<|\r|\n|$)', caseSensitive: false).firstMatch(block);
      final fitIdMatch = RegExp(r'<FITID>(.*?)(?:<|\r|\n|$)', caseSensitive: false).firstMatch(block);

      if (dtPostedMatch != null && amtMatch != null) {
        final dateStr = dtPostedMatch.group(1)!;
        final year = int.tryParse(dateStr.substring(0, 4)) ?? 2026;
        final month = int.tryParse(dateStr.substring(4, 6)) ?? 1;
        final day = int.tryParse(dateStr.substring(6, 8)) ?? 1;
        final date = DateTime(year, month, day);

        double amount = double.tryParse(amtMatch.group(1)!) ?? 0.0;
        if (amount < 0) amount = amount.abs();

        final name = nameMatch?.group(1)?.trim() ?? 'Bank Transaction';
        final fitId = fitIdMatch?.group(1)?.trim() ?? _uuid.v4();

        if (amount > 0) {
          transactions.add(StatementTransaction(
            id: fitId,
            date: date,
            description: name,
            amount: amount,
            referenceNumber: fitId,
          ));
        }
      }
    }

    return transactions;
  }

  static double _parseAmount(String raw) {
    var cleaned = raw.replaceAll(RegExp(r'[^0-9.,-]'), '').trim();
    if (cleaned.contains(',') && cleaned.contains('.')) {
      if (cleaned.lastIndexOf(',') > cleaned.lastIndexOf('.')) {
        cleaned = cleaned.replaceAll('.', '').replaceAll(',', '.');
      } else {
        cleaned = cleaned.replaceAll(',', '');
      }
    } else if (cleaned.contains(',')) {
      cleaned = cleaned.replaceAll(',', '.');
    }
    return double.tryParse(cleaned) ?? 0.0;
  }

  static DateTime _parseDate(String raw) {
    if (raw.isEmpty) return DateTime.now();
    final direct = DateTime.tryParse(raw);
    if (direct != null) return direct;

    final parts = raw.split(RegExp(r'[/.-]'));
    if (parts.length == 3) {
      final p1 = int.tryParse(parts[0]) ?? 1;
      final p2 = int.tryParse(parts[1]) ?? 1;
      var p3 = int.tryParse(parts[2]) ?? 2026;
      if (p3 < 100) p3 += 2000;

      if (p1 > 1000) {
        return DateTime(p1, p2, p3);
      } else if (p3 > 1000) {
        // DD/MM/YYYY or MM/DD/YYYY
        if (p2 > 12) {
          return DateTime(p3, p1, p2); // MM/DD/YYYY
        }
        return DateTime(p3, p2, p1); // DD/MM/YYYY
      }
    }

    return DateTime.now();
  }
}
