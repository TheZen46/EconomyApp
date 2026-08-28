import 'package:csv/csv.dart';
import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/error/failures.dart';
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

  const CsvImportReport({
    required this.totalRows,
    required this.successfulReceipts,
    required this.failedRows,
  });

  int get successCount => successfulReceipts.length;
  int get failureCount => failedRows.length;
  bool get hasErrors => failedRows.isNotEmpty;
  bool get isFullSuccess => failedRows.isEmpty && successfulReceipts.isNotEmpty;

  @override
  List<Object> get props => [totalRows, successfulReceipts, failedRows];
}

class CsvParserService {
  final _uuid = const Uuid();

  /// Parses a bank CSV string and returns a structured [CsvImportReport] or [CsvParsingFailure].
  ///
  /// Individual row failures are collected without aborting the entire batch.
  Either<CsvParsingFailure, CsvImportReport> importCsv(String csvString) {
    if (csvString.trim().isEmpty) {
      return const Left(CsvParsingFailure('CSV file is empty or blank.'));
    }

    List<List<dynamic>> rows;
    try {
      rows = const CsvToListConverter(eol: '\n', shouldParseNumbers: false).convert(csvString);
      if (rows.isEmpty || rows.length == 1) {
        // Fallback to \r\n if standard newline conversion yielded a single line or nothing
        final crlfRows = const CsvToListConverter(eol: '\r\n', shouldParseNumbers: false).convert(csvString);
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

    final List<Receipt> successfulReceipts = [];
    final List<CsvRowError> failedRows = [];
    int totalDataRows = 0;

    for (int i = 0; i < rows.length; i++) {
      final row = rows[i];
      final lineNumber = i + 1;

      // Skip completely empty lines
      if (row.isEmpty || row.every((cell) => cell.toString().trim().isEmpty)) {
        continue;
      }

      final rawRowString = row.map((c) => c.toString()).join(', ');

      // Header row detection for row 1
      if (i == 0 && _isLikelyHeaderRow(row)) {
        continue;
      }

      totalDataRows++;

      DateTime? parsedDate;
      double? parsedAmount;
      String description = '';

      for (var cell in row) {
        final cellStr = cell.toString().trim();
        if (cellStr.isEmpty) continue;

        // Try to parse Date if we haven't found one yet
        if (parsedDate == null) {
          final possibleDate = _tryParseDate(cellStr);
          if (possibleDate != null) {
            parsedDate = possibleDate;
            continue;
          }
        }

        // Try to parse Amount if we haven't found one yet
        if (parsedAmount == null) {
          final possibleAmount = _tryParseAmount(cellStr);
          if (possibleAmount != null) {
            parsedAmount = possibleAmount;
            continue;
          }
        }

        // Build description with remaining strings
        if (cellStr.length > 2 && !RegExp(r'^\d+$').hasMatch(cellStr)) {
          description += '$cellStr ';
        }
      }

      // Validation check
      if (parsedDate == null && parsedAmount == null) {
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
      } else if (parsedAmount == null) {
        failedRows.add(CsvRowError(
          lineNumber: lineNumber,
          rawRow: rawRowString,
          reason: 'Missing or unparseable transaction amount.',
        ));
      } else {
        // Valid row
        final finalAmount = parsedAmount.abs();
        final merchant = description.isNotEmpty ? description.trim() : 'Unknown Transaction';

        final receipt = Receipt(
          id: _uuid.v4(),
          merchantName: merchant,
          date: parsedDate,
          totalAmount: finalAmount,
          currency: 'USD',
          items: [
            ReceiptItem(
              description: merchant,
              unitPrice: finalAmount,
              totalPrice: finalAmount,
              quantity: 1,
            ),
          ],
        );
        successfulReceipts.add(receipt);
      }
    }

    return Right(CsvImportReport(
      totalRows: totalDataRows,
      successfulReceipts: successfulReceipts,
      failedRows: failedRows,
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

  bool _isLikelyHeaderRow(List<dynamic> row) {
    final joined = row.map((e) => e.toString().toLowerCase()).join(' ');
    final headerKeywords = ['date', 'amount', 'description', 'merchant', 'trans', 'debit', 'credit', 'balance', 'total'];
    int matchCount = 0;
    for (final kw in headerKeywords) {
      if (joined.contains(kw)) matchCount++;
    }
    // If it contains header keywords and lacks a valid date or amount, it's definitely a header
    if (matchCount >= 1) {
      bool hasDate = false;
      bool hasAmount = false;
      for (final cell in row) {
        final str = cell.toString().trim();
        if (_tryParseDate(str) != null) hasDate = true;
        if (_tryParseAmount(str) != null) hasAmount = true;
      }
      if (!hasDate || !hasAmount) return true;
    }
    return false;
  }

  DateTime? _tryParseDate(String input) {
    // Basic formats: YYYY-MM-DD, MM/DD/YYYY, DD/MM/YYYY
    var d = DateTime.tryParse(input);
    if (d != null && d.year > 2000) return d;

    // Manual attempt for MM/DD/YYYY, DD/MM/YYYY, YYYY.MM.DD, etc.
    final parts = input.split(RegExp(r'[/.-]'));
    if (parts.length == 3) {
      try {
        final p1 = int.parse(parts[0]);
        final p2 = int.parse(parts[1]);
        final p3 = int.parse(parts[2]);

        if (p3 > 2000) {
          if (p1 > 12 && p2 <= 12) {
            return DateTime(p3, p2, p1);
          } else if (p2 > 12 && p1 <= 12) {
            return DateTime(p3, p1, p2);
          } else {
            return DateTime(p3, p1, p2);
          }
        } else if (p1 > 2000) {
          return DateTime(p1, p2, p3);
        }
      } catch (_) {}
    }
    return null;
  }

  double? _tryParseAmount(String input) {
    // Strip quotes and currency symbols
    String cleanStr = input.replaceAll(RegExp(r'[^\d.-]'), '');

    if (cleanStr.isEmpty || cleanStr == '-' || cleanStr == '.') return null;

    final val = double.tryParse(cleanStr);
    if (val != null && val != 0) return val;
    return null;
  }
}
