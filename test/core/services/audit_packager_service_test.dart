import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/core/services/audit_packager_service.dart';
import 'package:t_aidy/features/boxes/data/models/box_model.dart';
import 'package:t_aidy/features/receipt_scanning/domain/entities/receipt.dart';

void main() {
  group('AuditPackagerService Tests', () {
    test('creates valid, sealed ZIP archive bundle with Merkle SHA-256 signature', () {
      final sampleBoxes = [
        BoxModel(
          id: 'box-consulting',
          name: 'Consulting Ops',
          budget: 5000.0,
          spent: 1000.0,
          currency: 'USD',
          color: 0xFF10B981,
        ),
      ];

      final sampleReceipts = [
        Receipt(
          id: 'r1',
          merchantName: 'Apple Store',
          totalAmount: 1200.0,
          date: DateTime(2026, 3, 1),
          currency: 'USD',
          boxId: 'box-consulting',
          items: const [
            ReceiptItem(description: 'MacBook Pro Stand', unitPrice: 1200.0, quantity: 1, totalPrice: 1200.0, mainCategory: 'Equipment'),
          ],
        ),
      ];

      final zipBytes = AuditPackagerService.createAuditZipBundle(
        receipts: sampleReceipts,
        boxes: sampleBoxes,
        clientName: 'Jane Doe Consulting',
        fiscalYear: 2026,
      );

      expect(zipBytes.isNotEmpty, true);

      // Decode and verify contents of zip archive
      final zipDecoder = ZipDecoder();
      final archive = zipDecoder.decodeBytes(zipBytes);

      final fileNames = archive.files.map((f) => f.name).toList();
      expect(fileNames.contains('Audit_Dossier_2026.html'), true);
      expect(fileNames.contains('CPA_Review_Portal_2026.html'), true);
      expect(fileNames.contains('merkle_manifest_2026.json'), true);
      expect(fileNames.contains('receipts_ledger_2026.csv'), true);
      expect(fileNames.contains('SIGNATURE.sha256'), true);

      // Verify signature content
      final sigFile = archive.files.firstWhere((f) => f.name == 'SIGNATURE.sha256');
      final sigText = utf8.decode(sigFile.content as List<int>);
      expect(sigText.contains('CRYPTOGRAPHIC AUDIT DEFENSE PACK'), true);
      expect(sigText.contains('MERKLE TREE ROOT DIGEST'), true);
    });

    test('sanitizes CSV formula injection in ledger inside ZIP bundle', () {
      final maliciousReceipts = [
        Receipt(
          id: '=cmd|1',
          merchantName: '=cmd|\' /C calc\'!A0',
          totalAmount: 50.0,
          date: DateTime(2026, 4, 1),
          currency: 'USD',
          boxId: '+malicious_box',
          items: const [
            ReceiptItem(
              description: 'Service',
              unitPrice: 50.0,
              quantity: 1,
              totalPrice: 50.0,
              mainCategory: '@SUM(A1:B1)',
            ),
          ],
        ),
      ];

      final zipBytes = AuditPackagerService.createAuditZipBundle(
        receipts: maliciousReceipts,
        boxes: [],
        fiscalYear: 2026,
      );

      final archive = ZipDecoder().decodeBytes(zipBytes);
      final csvFile = archive.files.firstWhere((f) => f.name == 'receipts_ledger_2026.csv');
      final csvText = utf8.decode(csvFile.content as List<int>);

      // Verify that malicious formulas are neutralised with a leading single quote
      expect(csvText, contains('"\'=cmd|1"'));
      expect(csvText, contains('"\'=cmd|\' /C calc\'!A0"'));
      expect(csvText, contains('"\'@SUM(A1:B1)"'));
      expect(csvText, contains('"\'+malicious_box"'));
    });
  });
}
