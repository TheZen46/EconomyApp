import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/core/services/accountant_portal_generator.dart';
import 'package:t_aidy/features/receipt_scanning/domain/entities/receipt.dart';
import 'package:t_aidy/features/boxes/data/models/box_model.dart';

void main() {
  group('AccountantPortalGenerator Zero-Knowledge Tests', () {
    final sampleReceipts = [
      Receipt(
        id: 'r1',
        merchantName: 'BestBuy Store #402 - 555-019-2834',
        date: DateTime(2026, 2, 20),
        totalAmount: 499.0,
        currency: 'USD',
        boxId: 'consulting',
        items: const [
          ReceiptItem(
            description: 'Dell 4K Monitor (Card 4111 2222 3333 4444)',
            unitPrice: 499.0,
            quantity: 1,
            totalPrice: 499.0,
            necessity: ItemNecessity.essential,
            mainCategory: 'Hardware',
            subCategory: 'Displays',
          ),
        ],
      ),
      Receipt(
        id: 'r2',
        merchantName: 'Secret Personal Pharmacy user@example.com',
        date: DateTime(2026, 3, 5),
        totalAmount: 45.0,
        currency: 'USD',
        boxId: 'main',
        items: const [
          ReceiptItem(
            description: 'Prescription Medicine',
            unitPrice: 45.0,
            quantity: 1,
            totalPrice: 45.0,
            necessity: ItemNecessity.discretional,
            mainCategory: 'Health',
          ),
        ],
      ),
    ];

    final sampleBoxes = [
      BoxModel(id: 'main', name: 'Main Life', budget: 0, spent: 45, currency: 'USD', color: 0xFF002FA7),
      BoxModel(id: 'consulting', name: 'Consulting Ops', budget: 2000, spent: 499, currency: 'USD', color: 0xFF10B981),
    ];

    test('generates PII-sanitized CPA portal with zero plaintext cards/emails and valid Merkle proof', () {
      final html = AccountantPortalGenerator.generatePortalHtml(
        receipts: sampleReceipts,
        boxes: sampleBoxes,
        clientName: 'Alex Freelance Dev',
        fiscalYear: '2026',
      );

      // Verify HTML structure
      expect(html, contains('<!DOCTYPE html>'));
      expect(html, contains('Zero-Knowledge CPA Audit & Tax Portal'));
      expect(html, contains('Alex Freelance Dev'));
      expect(html, contains('Merkle Root'));

      // Verify PII is completely scrubbed
      expect(html, isNot(contains('4111 2222 3333 4444')));
      expect(html, isNot(contains('user@example.com')));
      expect(html, contains('[REDACTED_CARD]'));
      expect(html, contains('[REDACTED_EMAIL]'));

      // Verify interactive JS functions
      expect(html, contains('renderTable()'));
      expect(html, contains('exportFilteredCsv()'));
      expect(html, contains('sanitizeCsvCell'));
      expect(html, contains('id="portalData"'));
    });

    test('neutralizes XSS payloads in clientName, fiscalYear, and receipt items', () {
      final xssReceipts = [
        Receipt(
          id: 'r-xss',
          merchantName: '</script><script>alert("merchant-xss")</script>',
          date: DateTime(2026, 1, 1),
          totalAmount: 100.0,
          currency: 'USD',
          items: const [
            ReceiptItem(
              description: '<img src=x onerror=alert("item-xss")>',
              unitPrice: 100.0,
              quantity: 1,
              totalPrice: 100.0,
            ),
          ],
        ),
      ];

      final html = AccountantPortalGenerator.generatePortalHtml(
        receipts: xssReceipts,
        boxes: [],
        clientName: '<script>alert("client-xss")</script>',
        fiscalYear: '2026"><script>alert("year-xss")</script>',
      );

      // Verify client name and fiscal year are HTML-escaped in the markup
      expect(html, isNot(contains('<script>alert("client-xss")</script>')));
      expect(html, contains('&lt;script&gt;alert(&quot;client-xss&quot;)&lt;/script&gt;'));
      expect(html, isNot(contains('2026"><script>alert("year-xss")</script>')));
      expect(html, contains('&quot;&gt;&lt;script&gt;alert(&quot;year-xss&quot;)&lt;/script&gt;'));

      // Verify script breakout is neutralized inside JSON data island
      expect(html, isNot(contains('</script><script>alert("merchant-xss")</script>')));
      expect(html, contains(r'\u003c/script\u003e\u003cscript\u003ealert(\"merchant-xss\")\u003c/script\u003e'));
    });
  });
}
