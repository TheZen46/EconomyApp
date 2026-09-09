import 'dart:convert';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../features/receipt_scanning/domain/entities/receipt.dart';
import '../../features/invoices/data/models/invoice_model.dart';

/// Enterprise-grade data export service for the tAIdy platform.
///
/// Facilitates structured export and platform sharing of financial receipts,
/// line-item breakdowns, and invoice records in CSV and JSON formats.
class ExportService {
  /// Exports a collection of [Receipt] entities to a CSV file and opens the platform share sheet.
  ///
  /// Flattens line items into individual rows while preserving parent receipt metadata.
  /// Returns the generated [File] containing the CSV data.
  Future<File?> exportReceiptsToCsv(
    List<Receipt> receipts, {
    String filePrefix = 'expenses_export',
    String shareSubject = 'tAIdy Expense Export (CSV)',
  }) async {
    if (receipts.isEmpty) return null;

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
      'Box Context',
    ]);

    // Data Rows
    for (final receipt in receipts) {
      if (receipt.items.isEmpty) {
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
          receipt.boxId ?? 'main',
        ]);
      } else {
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
            item.subCategory ?? item.mainCategory ?? item.category ?? '',
            receipt.vatNumber,
            receipt.merchantAddress,
            receipt.boxId ?? 'main',
          ]);
        }
      }
    }

    final csvString = const ListToCsvConverter().convert(rows);

    final directory = await getApplicationDocumentsDirectory();
    final path = '${directory.path}/${filePrefix}_${DateTime.now().millisecondsSinceEpoch}.csv';
    final file = File(path);
    await file.writeAsString(csvString);

    await Share.shareXFiles(
      [XFile(path)],
      subject: shareSubject,
      text: 'Exported ${receipts.length} receipts from tAIdy.',
    );

    return file;
  }

  /// Exports a collection of [Receipt] entities to an indented JSON file.
  Future<File?> exportReceiptsToJson(
    List<Receipt> receipts, {
    String filePrefix = 'expenses_export',
    String shareSubject = 'tAIdy Expense Export (JSON)',
  }) async {
    if (receipts.isEmpty) return null;

    final dataList = receipts.map((r) => {
      'id': r.id,
      'merchant_name': r.merchantName,
      'date': r.date.toIso8601String(),
      'time': r.time,
      'total_amount': r.totalAmount,
      'currency': r.currency,
      'category': r.category,
      'vat_number': r.vatNumber,
      'merchant_address': r.merchantAddress,
      'box_id': r.boxId,
      'items': r.items.map((i) => {
        'description': i.description,
        'quantity': i.quantity,
        'unit_price': i.unitPrice,
        'total_price': i.totalPrice,
        'necessity': i.necessity.name,
        'main_category': i.mainCategory,
        'sub_category': i.subCategory,
        'is_asset': i.isAsset,
      }).toList(),
    }).toList();

    final jsonString = const JsonEncoder.withIndent('  ').convert({
      'export_timestamp': DateTime.now().toUtc().toIso8601String(),
      'version': '1.0',
      'count': receipts.length,
      'receipts': dataList,
    });

    final directory = await getApplicationDocumentsDirectory();
    final path = '${directory.path}/${filePrefix}_${DateTime.now().millisecondsSinceEpoch}.json';
    final file = File(path);
    await file.writeAsString(jsonString);

    await Share.shareXFiles(
      [XFile(path)],
      subject: shareSubject,
      text: 'Exported ${receipts.length} receipts (JSON) from tAIdy.',
    );

    return file;
  }

  /// Exports a collection of [InvoiceModel] records to a CSV file and opens share sheet.
  Future<File?> exportInvoicesToCsv(
    List<InvoiceModel> invoices, {
    String filePrefix = 'invoices_export',
    String shareSubject = 'tAIdy Invoices Export (CSV)',
  }) async {
    if (invoices.isEmpty) return null;

    final List<List<dynamic>> rows = [];

    // Header Row
    rows.add([
      'Invoice Number',
      'Client Name',
      'Amount',
      'Currency',
      'Status',
      'Issued Date',
      'Due Date',
      'Notes',
    ]);

    for (final inv in invoices) {
      rows.add([
        inv.invoiceNumber,
        inv.clientName,
        inv.amount,
        inv.currency,
        inv.status,
        inv.issuedDate.toIso8601String().split('T').first,
        inv.dueDate != null ? inv.dueDate!.toIso8601String().split('T').first : '',
        inv.notes,
      ]);
    }

    final csvString = const ListToCsvConverter().convert(rows);

    final directory = await getApplicationDocumentsDirectory();
    final path = '${directory.path}/${filePrefix}_${DateTime.now().millisecondsSinceEpoch}.csv';
    final file = File(path);
    await file.writeAsString(csvString);

    await Share.shareXFiles(
      [XFile(path)],
      subject: shareSubject,
      text: 'Exported ${invoices.length} invoices from tAIdy.',
    );

    return file;
  }
}
