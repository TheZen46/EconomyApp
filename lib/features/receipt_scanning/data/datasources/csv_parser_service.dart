import 'package:csv/csv.dart';
import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/utils/date_parser.dart';
import '../../domain/entities/receipt.dart';

/// Detailed information about a failed CSV row during import.
class CsvRowError extends Equatable {
  final int lineNumber;
  final String rawRow;
  final String reason;

  const CsvRowError({
    required this.lineNumber,
    required this.rawRow,
    required this.reason,
  });

  @override
  List<Object> get props => [lineNumber, rawRow, reason];
}

/// Structured summary of a CSV batch import operation.
class CsvImportReport extends Equatable {
  final int totalRows;
  final List<Receipt> successfulReceipts;
  final List<CsvRowError> failedRows;

  /// Valid rows that were deliberately not imported: incoming transactions
  /// (credits, refunds) and rows already present from an earlier import.
  final List<CsvRowError> skippedRows;

  const CsvImportReport({
    required this.totalRows,
    required this.successfulReceipts,
    required this.failedRows,
    this.skippedRows = const [],
  });

  int get successCount => successfulReceipts.length;
  int get failureCount => failedRows.length;
  int get skippedCount => skippedRows.length;
  bool get hasErrors => failedRows.isNotEmpty;
  bool get isFullSuccess => failedRows.isEmpty && successfulReceipts.isNotEmpty;

  @override
  List<Object> get props => [totalRows, successfulReceipts, failedRows, skippedRows];
}

/// An amount read from a CSV cell.
class _Money {
  final double value;
  final String? currency;

  const _Money(this.value, this.currency);
}

/// Where a row's amount came from, which decides its direction.
enum _AmountSource { signed, debit, credit }

class _ParsedRow {
  final int lineNumber;
  final String rawRow;
  final DateTime date;
  final _Money money;
  final _AmountSource source;
  final String description;

  const _ParsedRow(this.lineNumber, this.rawRow, this.date, this.money, this.source, this.description);
}

/// Column roles recognised from a header row.
class _Columns {
  int? date;
  int? amount;
  int? debit;
  int? credit;
  int? currency;
  final Set<int> ignored = {};

  bool get hasAmount => amount != null || debit != null || credit != null;
}

class CsvParserService {
  final _uuid = const Uuid();

  static const Map<String, String> _currencySymbols = {
    '€': 'EUR',
    '£': 'GBP',
    '¥': 'JPY',
    '₹': 'INR',
    r'$': 'USD',
  };

  static const Set<String> _currencyCodes = {
    'EUR', 'USD', 'GBP', 'CHF', 'JPY', 'CAD', 'AUD', 'NZD', 'SEK', 'NOK', 'DKK', 'PLN', 'CZK',
    'HUF', 'RON', 'BGN', 'TRY', 'CNY', 'HKD', 'SGD', 'INR', 'BRL', 'MXN', 'ZAR',
  };

  static final RegExp _numberBody = RegExp(r'^\d[\d.,]*$');

  /// Parses a bank CSV string and returns a structured [CsvImportReport] or [CsvParsingFailure].
  ///
  /// Individual row failures are collected without aborting the entire batch.
  ///
  /// - Amounts accept both decimal separators: `12,50`, `1.234,56` and
  ///   `1,234.56` are read as written. A value such as `1.234`, which is
  ///   valid either way, follows the separator used by the rest of the file.
  /// - With a single signed amount column, the sign that most rows share is
  ///   taken as the expense direction (negative on ties, as in most bank
  ///   exports); rows with the opposite sign are incoming transactions and are
  ///   reported in [CsvImportReport.skippedRows]. Explicit debit and credit
  ///   columns are honoured.
  /// - The currency is read from a currency column, a currency symbol or an
  ///   ISO 4217 code in the amount, and otherwise is [defaultCurrency].
  /// - Ambiguous dates such as 03/04/2026 follow the order of the file's
  ///   unambiguous dates, and are read day-first when there are none. Dates
  ///   that do not exist (31/02) are rejected.
  /// - Rows matching one of [existing] by date, amount and description are
  ///   skipped, so that importing the same file twice does not duplicate it.
  Either<CsvParsingFailure, CsvImportReport> importCsv(
    String csvString, {
    String defaultCurrency = 'EUR',
    Iterable<Receipt> existing = const [],
  }) {
    if (csvString.trim().isEmpty) {
      return const Left(CsvParsingFailure('CSV file is empty or blank.'));
    }

    // European bank exports commonly separate fields with semicolons, since
    // the comma is their decimal separator.
    final firstLine = csvString.trimLeft().split('\n').first;
    final delimiter = ';'.allMatches(firstLine).length > ','.allMatches(firstLine).length ? ';' : ',';

    List<List<dynamic>> rows;
    try {
      rows = CsvToListConverter(eol: '\n', fieldDelimiter: delimiter, shouldParseNumbers: false).convert(csvString);
      if (rows.isEmpty || rows.length == 1) {
        // Fallback to \r\n if standard newline conversion yielded a single line or nothing
        final crlfRows =
            CsvToListConverter(eol: '\r\n', fieldDelimiter: delimiter, shouldParseNumbers: false).convert(csvString);
        if (crlfRows.length > rows.length) {
          rows = crlfRows;
        }
      }
    } catch (e) {
      return Left(CsvParsingFailure('Failed to decode CSV structure: $e'));
    }

    if (rows.isEmpty) {
      return const Left(CsvParsingFailure('No valid data rows found in CSV.'));
    }

    final cells = [
      for (final row in rows) [for (final cell in row) cell.toString().trim()],
    ];
    final firstContentRow = cells.indexWhere((row) => row.any((cell) => cell.isNotEmpty));
    final hasHeader = firstContentRow != -1 && _isLikelyHeaderRow(cells[firstContentRow]);
    final columns = hasHeader ? _detectColumns(cells[firstContentRow]) : _Columns();
    final dataRows = [
      for (var i = 0; i < cells.length; i++)
        if (!(hasHeader && i == firstContentRow) && cells[i].any((cell) => cell.isNotEmpty)) i,
    ];

    final dayFirst = ReceiptDateParser.detectDayFirst([
      for (final i in dataRows) ...(columns.date != null ? [_cell(cells[i], columns.date!)] : cells[i]),
    ]);
    final decimalComma = _detectDecimalComma([
      for (final i in dataRows) ...cells[i],
    ]);
    final now = DateTime.now();

    final List<CsvRowError> failedRows = [];
    final List<_ParsedRow> parsed = [];

    for (final i in dataRows) {
      final row = cells[i];
      final lineNumber = i + 1;
      final rawRowString = row.join(', ');

      DateTime? parsedDate;
      _Money? money;
      var source = _AmountSource.signed;
      final used = <int>{...columns.ignored};

      if (columns.date != null) {
        parsedDate = ReceiptDateParser.parsePurchaseDate(_cell(row, columns.date!), now: now, dayFirst: dayFirst);
        used.add(columns.date!);
      }
      if (columns.hasAmount) {
        for (final (index, kind) in [
          (columns.debit, _AmountSource.debit),
          (columns.credit, _AmountSource.credit),
          (columns.amount, _AmountSource.signed),
        ]) {
          if (index == null) continue;
          used.add(index);
          final value = _readMoney(_cell(row, index), decimalComma: decimalComma);
          if (money == null && value != null && value.value != 0) {
            money = value;
            source = kind;
          }
        }
      }
      if (columns.currency != null) used.add(columns.currency!);

      final description = StringBuffer();
      for (var c = 0; c < row.length; c++) {
        final cellStr = row[c];
        if (cellStr.isEmpty || used.contains(c)) continue;

        if (parsedDate == null && columns.date == null) {
          final possibleDate = ReceiptDateParser.parsePurchaseDate(cellStr, now: now, dayFirst: dayFirst);
          if (possibleDate != null) {
            parsedDate = possibleDate;
            continue;
          }
        }

        final possibleMoney = _readMoney(cellStr, decimalComma: decimalComma);
        if (possibleMoney != null) {
          // Further amounts (a balance column, for example) are not text.
          if (money == null && !columns.hasAmount && possibleMoney.value != 0) money = possibleMoney;
          continue;
        }

        // Build description with remaining strings
        if (cellStr.length > 2 && !RegExp(r'^\d+$').hasMatch(cellStr) && !_currencyCodes.contains(cellStr)) {
          description.write('$cellStr ');
        }
      }

      // Validation check
      if (parsedDate == null && money == null) {
        failedRows.add(CsvRowError(
          lineNumber: lineNumber,
          rawRow: rawRowString,
          reason: 'Missing both valid transaction date and numerical amount.',
        ));
      } else if (parsedDate == null) {
        failedRows.add(CsvRowError(
          lineNumber: lineNumber,
          rawRow: rawRowString,
          reason: 'Missing or unparseable transaction date.',
        ));
      } else if (money == null) {
        failedRows.add(CsvRowError(
          lineNumber: lineNumber,
          rawRow: rawRowString,
          reason: 'Missing or unparseable transaction amount.',
        ));
      } else {
        final currencyCell = columns.currency != null ? _cell(row, columns.currency!).toUpperCase() : '';
        final currency = _currencyCodes.contains(currencyCell) ? currencyCell : money.currency;
        parsed.add(_ParsedRow(
          lineNumber,
          rawRowString,
          parsedDate,
          _Money(money.value, currency ?? defaultCurrency),
          source,
          description.toString().trim(),
        ));
      }
    }

    // Direction of a single signed amount column: the sign most rows share.
    final signed = parsed.where((r) => r.source == _AmountSource.signed);
    final negatives = signed.where((r) => r.money.value < 0).length;
    final expensesAreNegative = negatives * 2 >= signed.length && negatives > 0;

    final remainingExisting = <String, int>{};
    for (final receipt in existing) {
      final key = _duplicateKey(receipt.date, receipt.totalAmount, receipt.merchantName);
      remainingExisting[key] = (remainingExisting[key] ?? 0) + 1;
    }

    final List<Receipt> successfulReceipts = [];
    final List<CsvRowError> skippedRows = [];
    for (final row in parsed) {
      final isExpense = switch (row.source) {
        _AmountSource.debit => true,
        _AmountSource.credit => false,
        _AmountSource.signed => (row.money.value < 0) == expensesAreNegative,
      };
      if (!isExpense) {
        skippedRows.add(CsvRowError(
          lineNumber: row.lineNumber,
          rawRow: row.rawRow,
          reason: 'Incoming transaction (credit or refund); not imported as an expense.',
        ));
        continue;
      }

      final finalAmount = row.money.value.abs();
      final merchant = row.description.isNotEmpty ? row.description : 'Unknown Transaction';
      final key = _duplicateKey(row.date, finalAmount, merchant);
      final remaining = remainingExisting[key] ?? 0;
      if (remaining > 0) {
        remainingExisting[key] = remaining - 1;
        skippedRows.add(CsvRowError(
          lineNumber: row.lineNumber,
          rawRow: row.rawRow,
          reason: 'Already imported (same date, amount and description).',
        ));
        continue;
      }

      successfulReceipts.add(Receipt(
        id: _uuid.v4(),
        merchantName: merchant,
        date: row.date,
        totalAmount: finalAmount,
        currency: row.money.currency!,
        items: [
          ReceiptItem(
            description: merchant,
            unitPrice: finalAmount,
            totalPrice: finalAmount,
            quantity: 1,
          ),
        ],
      ));
    }

    return Right(CsvImportReport(
      totalRows: dataRows.length,
      successfulReceipts: successfulReceipts,
      failedRows: failedRows,
      skippedRows: skippedRows,
    ));
  }

  /// Backward-compatible method returning only successfully parsed receipts.
  List<Receipt> parseBankCsv(String csvString) {
    final result = importCsv(csvString);
    return result.fold(
      (failure) => [],
      (report) => report.successfulReceipts,
    );
  }

  static String _cell(List<String> row, int index) => index < row.length ? row[index] : '';

  static String _duplicateKey(DateTime date, double amount, String description) =>
      '${date.year}-${date.month}-${date.day}|${(amount.abs() * 100).round()}|'
      '${description.trim().toLowerCase()}';

  bool _isLikelyHeaderRow(List<String> row) {
    final joined = row.map((e) => e.toLowerCase()).join(' ');
    final headerKeywords = [
      'date', 'amount', 'description', 'merchant', 'trans', 'debit', 'credit', 'balance', 'total', 'currency',
      // Italian bank exports
      'data', 'importo', 'descrizione', 'addebit', 'accredit', 'saldo', 'divisa',
    ];
    int matchCount = 0;
    for (final kw in headerKeywords) {
      if (joined.contains(kw)) matchCount++;
    }
    // If it contains header keywords and lacks a valid date or amount, it's definitely a header
    if (matchCount >= 1) {
      bool hasDate = false;
      bool hasAmount = false;
      for (final str in row) {
        if (ReceiptDateParser.parse(str) != null) hasDate = true;
        if (_readMoney(str) != null) hasAmount = true;
      }
      if (!hasDate || !hasAmount) return true;
    }
    return false;
  }

  /// Assigns column roles from header labels (English and Italian).
  _Columns _detectColumns(List<String> header) {
    final columns = _Columns();
    for (var i = 0; i < header.length; i++) {
      final label = header[i].toLowerCase();
      bool has(List<String> words) => words.any(label.contains);

      final isDebit = has(['debit', 'addebit', 'uscit', 'withdrawal']);
      final isCredit = has(['credit', 'accredit', 'entrat', 'deposit']);
      if (has(['balance', 'saldo'])) {
        columns.ignored.add(i);
      } else if (isDebit && !isCredit) {
        columns.debit ??= i;
      } else if (isCredit && !isDebit) {
        columns.credit ??= i;
      } else if (has(['date', 'data'])) {
        columns.date ??= i;
      } else if (has(['amount', 'importo', 'total']) || (isDebit && isCredit)) {
        columns.amount ??= i;
      } else if (has(['currency', 'divisa', 'ccy'])) {
        columns.currency ??= i;
      }
    }
    return columns;
  }

  /// Whether the amounts in [values] use a decimal comma, judged from the
  /// values whose separator is unambiguous; null when none of them is.
  static bool? _detectDecimalComma(Iterable<String> values) {
    var comma = 0;
    var point = 0;
    for (final value in values) {
      final body = _stripMoneyDecorations(value)?.body;
      if (body == null || !_numberBody.hasMatch(body)) continue;
      final lastComma = body.lastIndexOf(',');
      final lastPoint = body.lastIndexOf('.');
      if (lastComma != -1 && lastPoint != -1) {
        lastComma > lastPoint ? comma++ : point++;
      } else if (lastComma != -1 && ','.allMatches(body).length == 1 && body.length - lastComma - 1 != 3) {
        comma++;
      } else if (lastPoint != -1 && '.'.allMatches(body).length == 1 && body.length - lastPoint - 1 != 3) {
        point++;
      }
    }
    if (comma == 0 && point == 0) return null;
    return comma > point;
  }

  /// Removes currency markers, spaces and sign notation from [input]. Returns
  /// the remaining digits and separators, the sign and the currency found.
  static ({String body, bool negative, String? currency})? _stripMoneyDecorations(String input) {
    var text = input.trim();
    if (text.isEmpty) return null;
    String? currency;

    final code = RegExp(r'\b([A-Z]{3})\b').firstMatch(text);
    if (code != null && _currencyCodes.contains(code.group(1))) {
      currency = code.group(1);
      text = text.replaceFirst(code.group(0)!, '');
    }
    for (final entry in _currencySymbols.entries) {
      if (text.contains(entry.key)) {
        currency ??= entry.value;
        text = text.replaceAll(entry.key, '');
      }
    }
    text = text.replaceAll(RegExp("[\\s '’]"), '');

    var negative = false;
    if (text.startsWith('(') && text.endsWith(')')) {
      negative = true;
      text = text.substring(1, text.length - 1);
    }
    if (text.startsWith('-')) {
      negative = true;
      text = text.substring(1);
    } else if (text.startsWith('+')) {
      text = text.substring(1);
    } else if (text.endsWith('-')) {
      negative = true;
      text = text.substring(0, text.length - 1);
    }
    return (body: text, negative: negative, currency: currency);
  }

  /// Reads a monetary amount. Returns null unless the cell contains only a
  /// number with optional sign, currency symbol or code, and separators.
  static _Money? _readMoney(String input, {bool? decimalComma}) {
    final parts = _stripMoneyDecorations(input);
    if (parts == null || !_numberBody.hasMatch(parts.body)) return null;

    final body = parts.body;
    final lastComma = body.lastIndexOf(',');
    final lastPoint = body.lastIndexOf('.');
    String normalized;
    if (lastComma != -1 && lastPoint != -1) {
      // Both present: the last one is the decimal separator.
      normalized = lastComma > lastPoint
          ? body.replaceAll('.', '').replaceAll(',', '.')
          : body.replaceAll(',', '');
    } else if (lastComma != -1) {
      final single = ','.allMatches(body).length == 1;
      final threeDecimals = body.length - lastComma - 1 == 3;
      final isDecimal = single && (!threeDecimals || decimalComma == true);
      normalized = isDecimal ? body.replaceAll(',', '.') : body.replaceAll(',', '');
    } else if (lastPoint != -1) {
      final single = '.'.allMatches(body).length == 1;
      final threeDecimals = body.length - lastPoint - 1 == 3;
      final isDecimal = single && (!threeDecimals || decimalComma != true);
      normalized = isDecimal ? body : body.replaceAll('.', '');
    } else {
      normalized = body;
    }

    final value = double.tryParse(normalized);
    if (value == null) return null;
    return _Money(parts.negative ? -value : value, parts.currency);
  }
}
