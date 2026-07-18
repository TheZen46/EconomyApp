import 'package:csv/csv.dart';
import 'package:uuid/uuid.dart';
import '../../domain/entities/receipt.dart';

class CsvParserService {
  final _uuid = const Uuid();

  /// Parses a generic bank CSV string and tries to heuristically map it to Receipts
  List<Receipt> parseBankCsv(String csvString) {
    if (csvString.isEmpty) return [];

    List<List<dynamic>> rows = const CsvToListConverter(eol: '\n', shouldParseNumbers: false).convert(csvString);
    if (rows.isEmpty || rows.length == 1) {
       // fallback to \r\n if \n failed
       rows = const CsvToListConverter(eol: '\r\n', shouldParseNumbers: false).convert(csvString);
    }
    
    List<Receipt> receipts = [];

    for (var row in rows) {
      if (row.isEmpty) continue;

      DateTime? parsedDate;
      double? parsedAmount;
      String description = '';

      for (var cell in row) {
        final cellStr = cell.toString().trim();
        if (cellStr.isEmpty) continue;

        // Try to parse Date if we haven't found one
        if (parsedDate == null) {
          final possibleDate = _tryParseDate(cellStr);
          if (possibleDate != null) {
            parsedDate = possibleDate;
            continue;
          }
        }

        // Try to parse Amount if we haven't found one
        if (parsedAmount == null) {
          final possibleAmount = _tryParseAmount(cellStr);
          if (possibleAmount != null) {
             // In banking, negative is usually an expense, positive is income. 
             // We map everything as absolute value expenditure for simplicity, OR keep it negative.
             // EconomyApp tracks everything as an absolute 'totalAmount'. If Income is tracked, we might need a flag.
             parsedAmount = possibleAmount;
             continue;
          }
        }

        // Build description with remaining strings
        if (cellStr.length > 3 && !RegExp(r'^\d+$').hasMatch(cellStr)) {
          description += '$cellStr ';
        }
      }

      // If we successfully found an amount and date, it's a valid row
      if (parsedAmount != null && parsedDate != null) {
         // Bank exports usually list expenses as negative. We want the totalAmount for a receipt.
         final finalAmount = parsedAmount.abs(); 
         final merchant = description.isNotEmpty ? description.trim() : 'Unknown Transaction';

         final receipt = Receipt(
            id: _uuid.v4(),
            merchantName: merchant,
            date: parsedDate,
            totalAmount: finalAmount,
            currency: 'USD', // Assumed base currency
            items: [
              ReceiptItem(
                description: merchant, 
                unitPrice: finalAmount, 
                totalPrice: finalAmount,
                quantity: 1
              )
            ]
         );
         receipts.add(receipt);
      }
    }

    return receipts;
  }

  DateTime? _tryParseDate(String input) {
    // Basic formats: YYYY-MM-DD, MM/DD/YYYY, DD/MM/YYYY
    // Just delegating to DateTime.tryParse (YYYY-MM-DD usually)
    var d = DateTime.tryParse(input);
    if (d != null && d.year > 2000) return d;

    // Manual attempt for MM/DD/YYYY or DD/MM/YYYY
    final parts = input.split(RegExp(r'[/.-]'));
    if (parts.length == 3) {
       try {
         final p1 = int.parse(parts[0]);
         final p2 = int.parse(parts[1]);
         final p3 = int.parse(parts[2]);

         if (p3 > 2000) {
            // Assume MM/DD/YYYY or DD/MM/YYYY. Defaulting to MM/DD
            return DateTime(p3, p1, p2);
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
    
    // Quick validation to prevent matching single digits like "1" or "2"
    if (cleanStr.length < 2) return null;
    
    final val = double.tryParse(cleanStr);
    if (val != null && val != 0) return val;
    return null;
  }
}
