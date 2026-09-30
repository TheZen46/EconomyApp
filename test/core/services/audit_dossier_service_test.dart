import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/core/services/audit_dossier_service.dart';
import 'package:t_aidy/features/receipt_scanning/domain/entities/receipt.dart';

void main() {
  group('AuditDossierService Tests', () {
    final sampleReceipts = [
      Receipt(
        id: 'rec-001',
        merchantName: 'Apple Store Regent St',
        date: DateTime(2026, 3, 15),
        totalAmount: 1299.99,
        currency: 'USD',
        merchantAddress: 'Regent St, London',
        items: const [
          ReceiptItem(
            description: 'MacBook Pro M-Chip',
            unitPrice: 1299.99,
            quantity: 1,
            totalPrice: 1299.99,
            necessity: ItemNecessity.essential,
            mainCategory: 'Hardware',
            subCategory: 'Computers',
            isAsset: true,
          ),
        ],
      ),
      Receipt(
        id: 'rec-002',
        merchantName: 'Starbucks Coffee',
        date: DateTime(2026, 3, 16),
        totalAmount: 8.50,
        currency: 'USD',
        items: const [
          ReceiptItem(
            description: 'Caramel Macchiato',
            unitPrice: 8.50,
            quantity: 1,
            totalPrice: 8.50,
            necessity: ItemNecessity.discretional,
            mainCategory: 'Dining',
          ),
        ],
      ),
    ];

    test('generates self-contained HTML audit dossier with Merkle root', () {
      final html = AuditDossierService.generateDossierHtml(
        receipts: sampleReceipts,
        boxName: 'Consulting Ops',
        fiscalYear: 2026,
      );

      expect(html, contains('<!DOCTYPE html>'));
      expect(html, contains('Official Tax Audit Defense Dossier'));
      expect(html, contains('Apple Store Regent St'));
      expect(html, contains('MacBook Pro M-Chip'));
      expect(html, contains('Merkle-Root SHA-256 Digital Verification Seal'));
      expect(html, contains('https://schema.org/TaxAuditManifest'));
      expect(html, contains('id="auditManifestData"'));
      expect(html, contains('crypto.subtle.digest'));
      expect(html, contains('computeMerkleRoot'));
    });

    test('neutralizes XSS in boxName and fiscalYear within dossier', () {
      final html = AuditDossierService.generateDossierHtml(
        receipts: sampleReceipts,
        boxName: '<script>alert("box-xss")</script>',
        fiscalYear: 2026,
      );

      expect(html, isNot(contains('<script>alert("box-xss")</script>')));
      expect(html, contains('&lt;script&gt;alert(&quot;box-xss&quot;)&lt;/script&gt;'));
    });

    test('handles empty receipts list gracefully', () {
      final html = AuditDossierService.generateDossierHtml(
        receipts: [],
        fiscalYear: 2026,
      );

      expect(html, contains('<!DOCTYPE html>'));
      expect(html, contains('Official Tax Audit Defense Dossier'));
      expect(html, contains('Itemized Receipt Audit Log (0 Documents)'));
      expect(html, contains('computeMerkleRoot'));
    });
  });
}
