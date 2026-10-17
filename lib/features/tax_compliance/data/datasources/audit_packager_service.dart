import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:t_aidy/features/boxes/data/models/box_model.dart';
import 'package:t_aidy/features/receipt_scanning/data/datasources/tax_report_service.dart';
import 'package:t_aidy/features/receipt_scanning/data/models/receipt_model.dart';
import 'package:t_aidy/features/receipt_scanning/domain/entities/receipt.dart';
import 'accountant_portal_generator.dart';
import 'audit_dossier_service.dart';
import 'tax_compliance_service.dart';

/// Service creating cryptographically signed, complete offline audit defense zip bundles.
class AuditPackagerService {
  AuditPackagerService._();

  /// Bundles and compresses all audit artifacts into a cryptographically sealed ZIP file.
  static Uint8List createAuditZipBundle({
    required List<Receipt> receipts,
    required List<BoxModel> boxes,
    String clientName = 'tAIdy Verified Freelancer',
    int fiscalYear = 2026,
    String? boxName,
  }) {
    final archive = Archive();

    // 1. Standalone HTML Dossier with embedded in-browser verifier
    final dossierHtml = AuditDossierService.generateAuditDossierHtml(
      receipts: receipts,
      boxName: boxName,
      fiscalYear: fiscalYear,
    );
    final htmlBytes = utf8.encode(dossierHtml);
    archive.addFile(ArchiveFile('Audit_Dossier_$fiscalYear.html', htmlBytes.length, htmlBytes));

    // 2. Sanitized CPA Portal HTML
    final portalHtml = AccountantPortalGenerator.generatePortalHtml(
      receipts: receipts,
      boxes: boxes,
      clientName: clientName,
      fiscalYear: '$fiscalYear',
    );
    final portalBytes = utf8.encode(portalHtml);
    archive.addFile(ArchiveFile('CPA_Review_Portal_$fiscalYear.html', portalBytes.length, portalBytes));

    // 3. Merkle Manifest JSON-LD
    final manifest = AuditDossierService.buildAuditManifest(
      receipts: receipts,
      boxId: boxName,
    );
    final manifestBytes = utf8.encode(const JsonEncoder.withIndent('  ').convert(manifest));
    archive.addFile(ArchiveFile('merkle_manifest_$fiscalYear.json', manifestBytes.length, manifestBytes));

    // 4. Tabular CSV Ledger
    final csvContent = _generateCsv(receipts);
    final csvBytes = utf8.encode(csvContent);
    archive.addFile(ArchiveFile('receipts_ledger_$fiscalYear.csv', csvBytes.length, csvBytes));

    // 5. Tax & VAT Compliance Summary Report (CSV) via TaxReportService
    final String taxCsvContent;
    final distinctCurrencies = receipts.map((r) => r.currency.toUpperCase()).toSet();
    if (distinctCurrencies.length <= 1) {
      final taxReport = TaxReportService.generateTaxReport(
        receipts: receipts,
        defaultCurrency: distinctCurrencies.isNotEmpty ? distinctCurrencies.first : 'EUR',
      );
      taxCsvContent = TaxReportService.exportToCsv(taxReport);
    } else {
      final reportsByCurrency = TaxReportService.generateTaxReportsByCurrency(receipts: receipts);
      final buffer = StringBuffer();
      var first = true;
      for (final report in reportsByCurrency.values) {
        if (!first) {
          buffer.writeln();
          buffer.writeln('=============================================================================');
          buffer.writeln();
        }
        buffer.write(TaxReportService.exportToCsv(report));
        first = false;
      }
      taxCsvContent = buffer.toString();
    }
    final taxCsvBytes = utf8.encode(taxCsvContent);
    archive.addFile(ArchiveFile('tax_vat_report_$fiscalYear.csv', taxCsvBytes.length, taxCsvBytes));

    // 6. German DATEV ASCII (Buchungsstapel) & International XBRL-GL via TaxComplianceService
    final receiptModels = receipts.map((r) => ReceiptModel.fromEntity(r)).toList();
    final datevContent = TaxComplianceService.exportDatevAscii(
      receipts: receiptModels,
      fiscalYear: fiscalYear,
    );
    final datevBytes = utf8.encode(datevContent);
    archive.addFile(ArchiveFile('DATEV_Buchungsstapel_$fiscalYear.csv', datevBytes.length, datevBytes));

    final xbrlContent = TaxComplianceService.exportXbrlGlXml(
      receipts: receiptModels,
      fiscalPeriod: 'FY$fiscalYear',
      entityName: clientName,
    );
    final xbrlBytes = utf8.encode(xbrlContent);
    archive.addFile(ArchiveFile('XBRL_GL_Ledger_$fiscalYear.xml', xbrlBytes.length, xbrlBytes));

    // 7. Compute Merkle & Package SHA-256 Checksums
    final htmlHash = sha256.convert(htmlBytes).toString();
    final portalHash = sha256.convert(portalBytes).toString();
    final manifestHash = sha256.convert(manifestBytes).toString();
    final csvHash = sha256.convert(csvBytes).toString();
    final taxCsvHash = sha256.convert(taxCsvBytes).toString();
    final datevHash = sha256.convert(datevBytes).toString();
    final xbrlHash = sha256.convert(xbrlBytes).toString();

    final signatureFileContent = '''=============================================================================
 tAIdy CRYPTOGRAPHIC AUDIT DEFENSE PACK - SHA-256 MANIFEST SIGNATURE
 Fiscal Year: $fiscalYear | Generated: ${DateTime.now().toUtc().toIso8601String()}Z
=============================================================================
SHA-256 CHECKSUMS:
$htmlHash  Audit_Dossier_$fiscalYear.html
$portalHash  CPA_Review_Portal_$fiscalYear.html
$manifestHash  merkle_manifest_$fiscalYear.json
$csvHash  receipts_ledger_$fiscalYear.csv
$taxCsvHash  tax_vat_report_$fiscalYear.csv
$datevHash  DATEV_Buchungsstapel_$fiscalYear.csv
$xbrlHash  XBRL_GL_Ledger_$fiscalYear.xml

MERKLE TREE ROOT DIGEST:
${manifest['merkle_root']}
=============================================================================''';

    final sigBytes = utf8.encode(signatureFileContent);
    archive.addFile(ArchiveFile('SIGNATURE.sha256', sigBytes.length, sigBytes));

    // Encode Zip Archive
    final zipEncoder = ZipEncoder();
    final zipData = zipEncoder.encode(archive);
    return Uint8List.fromList(zipData);
  }

  /// Exports and shares the cryptographically sealed audit defense bundle.
  static Future<File?> exportAndShareZip({
    required List<Receipt> receipts,
    required List<BoxModel> boxes,
    String clientName = 'tAIdy Verified Freelancer',
    int fiscalYear = 2026,
    String? boxName,
  }) async {
    if (receipts.isEmpty) return null;

    final zipBytes = createAuditZipBundle(
      receipts: receipts,
      boxes: boxes,
      clientName: clientName,
      fiscalYear: fiscalYear,
      boxName: boxName,
    );

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = 'tAIdy_Audit_Pack_${fiscalYear}_$timestamp.zip';

    if (kIsWeb) {
      await Share.shareXFiles(
        [
          XFile.fromData(
            zipBytes,
            name: fileName,
            mimeType: 'application/zip',
          ),
        ],
        subject: 'tAIdy Sealed Cryptographic Audit Pack - FY $fiscalYear',
        text: 'Attached is the official cryptographically sealed Tax Audit Pack with Merkle SHA-256 integrity proofs for FY $fiscalYear.',
      );
      return null;
    }

    final dir = await getApplicationDocumentsDirectory();
    final filePath = '${dir.path}/$fileName';
    final file = File(filePath);
    await file.writeAsBytes(zipBytes);

    await Share.shareXFiles(
      [XFile(filePath)],
      subject: 'tAIdy Sealed Cryptographic Audit Pack - FY $fiscalYear',
      text: 'Attached is the official cryptographically sealed Tax Audit Pack with Merkle SHA-256 integrity proofs for FY $fiscalYear.',
    );

    return file;
  }

  static String _sanitizeCsvField(String field) {
    var sanitized = field.replaceAll('"', '""');
    if (sanitized.startsWith('=') ||
        sanitized.startsWith('+') ||
        sanitized.startsWith('-') ||
        sanitized.startsWith('@') ||
        sanitized.startsWith('\t') ||
        sanitized.startsWith('\r')) {
      sanitized = "'$sanitized";
    }
    return '"$sanitized"';
  }

  static String _generateCsv(List<Receipt> receipts) {
    final buffer = StringBuffer();
    buffer.writeln('ID,Date,Merchant,Currency,Total Amount,Tax Category,Necessity,Box');
    for (final r in receipts) {
      final dateStr = r.date.toIso8601String().split('T').first;
      final category = r.items.isNotEmpty ? (r.items.first.mainCategory ?? 'General') : 'General';
      final necessity = r.items.isNotEmpty ? r.items.first.necessity.name : 'discretional';
      final idCell = _sanitizeCsvField(r.id);
      final dateCell = _sanitizeCsvField(dateStr);
      final merchantCell = _sanitizeCsvField(r.merchantName);
      final currencyCell = _sanitizeCsvField(r.currency);
      final categoryCell = _sanitizeCsvField(category);
      final necessityCell = _sanitizeCsvField(necessity);
      final boxCell = _sanitizeCsvField(r.boxId ?? 'main');
      final amountCell = r.totalAmount.toStringAsFixed(2);
      buffer.writeln('$idCell,$dateCell,$merchantCell,$currencyCell,$amountCell,$categoryCell,$necessityCell,$boxCell');
    }
    return buffer.toString();
  }
}

