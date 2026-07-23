// ignore_for_file: deprecated_member_use, deprecated_member_use_from_same_package, unused_local_variable, unnecessary_underscores, invalid_annotation_target, unused_element, non_constant_identifier_names, use_build_context_synchronously
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../features/receipt_scanning/domain/entities/receipt.dart';

class ExportService {
  Future<void> exportReceiptsToCsv(List<Receipt> receipts) async {
    final List<List<dynamic>> rows = [];

    // Header Row
    rows.add([
      'Date',
      'Time',
      'Merchant',
      'Total Amount',
      'Currency',
      'Primary Category',
      'Item Description',
      'Item Quantity',
      'Item Price',
      'Item Total',
      'Item Category',
      'VAT Number',
      'Address',
    ]);

    // Data Rows
    for (final receipt in receipts) {
      if (receipt.items.isEmpty) {
        // Add single row for receipt even if no items
        rows.add([
          receipt.date.toIso8601String().split('T').first,
          receipt.time,
          receipt.merchantName,
          receipt.totalAmount,
          receipt.currency,
          receipt.category,
          '', '', '', '', '', // Empty item fields
          receipt.vatNumber,
          receipt.merchantAddress,
        ]);
      } else {
        // Flatten items: One row per item, repeating receipt info
        for (final item in receipt.items) {
          rows.add([
            receipt.date.toIso8601String().split('T').first,
            receipt.time,
            receipt.merchantName,
            receipt.totalAmount,
            receipt.currency,
            receipt.category,
            item.description,
            item.quantity,
            item.unitPrice,
            item.totalPrice,
            item.category ?? '',
            receipt.vatNumber,
            receipt.merchantAddress,
          ]);
        }
      }
    }

    final csvString = const ListToCsvConverter().convert(rows);
    
    // Save to file
    final directory = await getApplicationDocumentsDirectory();
    final path = '${directory.path}/expenses_export_${DateTime.now().millisecondsSinceEpoch}.csv';
    final file = File(path);
    await file.writeAsString(csvString);

    // Share
    await Share.shareXFiles([XFile(path)], text: 'Here is your expense export');
  }
}
