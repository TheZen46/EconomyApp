import 'dart:convert';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../features/receipt_scanning/domain/entities/receipt.dart';
import '../../features/invoices/data/models/invoice_model.dart';
import '../../features/boxes/data/models/box_model.dart';
import 'audit_dossier_service.dart';
import 'accountant_portal_generator.dart';
import '../utils/csv_utils.dart';

/// Enterprise-grade data export service for the tAIdy platform.
///
/// Facilitates structured export and platform sharing of financial receipts,
/// line-item breakdowns, invoice records, and zero-knowledge CPA portals.
class ExportService {
  /// Exports a collection of [Receipt] entities to a CSV file and opens the platform share sheet.
  Future<File?> exportReceiptsToCsv(
    List<Receipt> receipts, {
    String filePrefix = 'expenses_export',
    String shareSubject = 'tAIdy Expense Export (CSV)',
  }) async {
    if (receipts.isEmpty) return null;

    final csvString = receiptsToCsv(receipts);

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

  /// CSV content of [exportReceiptsToCsv], one row per line item. Text cells
  /// are passed through [CsvUtils.sanitizeCell].
  static String receiptsToCsv(List<Receipt> receipts) {
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

    return const ListToCsvConverter().convert(CsvUtils.sanitizeRows(rows));
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

    final csvString = invoicesToCsv(invoices);

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

  /// CSV content of [exportInvoicesToCsv]. Text cells are passed through
  /// [CsvUtils.sanitizeCell].
  static String invoicesToCsv(List<InvoiceModel> invoices) {
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

    return const ListToCsvConverter().convert(CsvUtils.sanitizeRows(rows));
  }

  static dynamic _sanitizeCsvCell(dynamic value) {
    if (value is String && value.isNotEmpty) {
      if (value.startsWith('=') ||
          value.startsWith('+') ||
          value.startsWith('@') ||
          value.startsWith('\t') ||
          value.startsWith('\r') ||
          (value.startsWith('-') && double.tryParse(value) == null)) {
        return "'$value";
      }
    }
    return value;
  }

  /// Exposed for testing: verifies CSV formula injection sanitization.
  @visibleForTesting
  static dynamic sanitizeCsvCell(dynamic value) => _sanitizeCsvCell(value);

  /// Exports a cryptographically sealed Audit Defense Dossier.
  Future<File?> exportAuditDefenseDossier(
    List<Receipt> receipts, {
    String? boxName,
    int fiscalYear = 2026,
  }) async {
    return await AuditDossierService.exportAndShareDossier(
      receipts: receipts,
      boxName: boxName,
      fiscalYear: fiscalYear,
    );
  }

  /// Exports an air-gapped, zero-knowledge, PII-redacted CPA Audit Portal (.html).
  Future<File?> exportZeroKnowledgeCpaPortal(
    List<Receipt> receipts, {
    List<BoxModel> boxes = const [],
    String clientName = 'tAIdy Freelancer',
    String fiscalYear = '2026',
    String filePrefix = 'tAIdy_CPA_Portal',
  }) async {
    if (receipts.isEmpty) return null;

    final htmlContent = AccountantPortalGenerator.generatePortalHtml(
      receipts: receipts,
      boxes: boxes,
      clientName: clientName,
      fiscalYear: fiscalYear,
    );

    final directory = await getApplicationDocumentsDirectory();
    final path = '${directory.path}/${filePrefix}_${fiscalYear}_${DateTime.now().millisecondsSinceEpoch}.html';
    final file = File(path);
    await file.writeAsString(htmlContent);

    await Share.shareXFiles(
      [XFile(path)],
      subject: 'tAIdy Zero-Knowledge CPA Audit Portal (FY$fiscalYear)',
      text: 'Exported PII-sanitized CPA Audit Portal containing ${receipts.length} receipts.',
    );

    return file;
  }
}
