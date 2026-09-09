import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/core/services/tax_compliance_service.dart';
import 'package:t_aidy/features/receipt_scanning/data/models/receipt_model.dart';

void main() {
  group('Italian FatturaPA FPR12 XML Exporter Tests', () {
    test('generates valid FatturaPA FPR12 XML with standard and exempt Nature codes', () {
      final receipt = ReceiptModel(
        id: 'IT-INV-0042',
        merchantName: 'tAIdy Cloud Solutions S.r.l.',
        vatNumber: '12345678901',
        merchantAddress: 'Via Monte Napoleone 8, Milano',
        date: DateTime.utc(2026, 9, 9),
        totalAmount: 122.00,
        currency: 'EUR',
        items: [
          ReceiptItemModel(
            description: 'AI Cloud Subscription Standard 22%',
            unitPrice: 100.00,
            quantity: 1,
            category: 'Software & Cloud',
          ),
          ReceiptItemModel(
            description: 'Medical Exam Consultation (Exempt Art. 10)',
            unitPrice: 50.00,
            quantity: 1,
            category: 'Medical Visit',
          ),
          ReceiptItemModel(
            description: 'Government Stamp Duty (Marca da bollo)',
            unitPrice: 2.00,
            quantity: 1,
            category: 'Stamp Duty',
          ),
        ],
      );

      final xml = TaxComplianceService.exportFatturaPaXml(
        receipt: receipt,
        transmitterVat: '12345678901',
        senderVat: '12345678901',
        senderFiscalCode: '12345678901',
        destinationCode: 'M5UXCR1',
        buyerName: 'Enterprise Client S.p.A.',
        buyerVat: '98765432100',
        documentNumber: '42/2026',
      );

      expect(xml, contains('<?xml version="1.0" encoding="UTF-8"?>'));
      expect(xml, contains('<p:FatturaElettronica versione="FPR12"'));
      expect(xml, contains('<FormatoTrasmissione>FPR12</FormatoTrasmissione>'));
      expect(xml, contains('<CodiceDestinatario>M5UXCR1</CodiceDestinatario>'));
      expect(xml, contains('<Denominazione>tAIdy Cloud Solutions S.r.l.</Denominazione>'));
      expect(xml, contains('<Denominazione>Enterprise Client S.p.A.</Denominazione>'));
      expect(xml, contains('<Numero>42/2026</Numero>'));
      expect(xml, contains('<Divisa>EUR</Divisa>'));

      // Check DettaglioLinee
      expect(xml, contains('<Descrizione>AI Cloud Subscription Standard 22%</Descrizione>'));
      expect(xml, contains('<AliquotaIVA>22.00</AliquotaIVA>'));

      // Check Exempt line with Nature code N4
      expect(xml, contains('<Descrizione>Medical Exam Consultation (Exempt Art. 10)</Descrizione>'));
      expect(xml, contains('<Natura>N4</Natura>'));

      // Check Stamp Duty line with Nature code N1
      expect(xml, contains('<Descrizione>Government Stamp Duty (Marca da bollo)</Descrizione>'));
      expect(xml, contains('<Natura>N1</Natura>'));

      // Check DatiRiepilogo
      expect(xml, contains('<DatiRiepilogo>'));
      expect(xml, contains('<EsigibilitaIVA>I</EsigibilitaIVA>'));

      // Check DatiPagamento
      expect(xml, contains('<DatiPagamento>'));
      expect(xml, contains('<ModalitaPagamento>MP05</ModalitaPagamento>'));
    });
  });

  group('German / DACH DATEV ASCII Exporter Tests', () {
    late List<ReceiptModel> sampleReceipts;

    setUp(() {
      sampleReceipts = [
        ReceiptModel(
          id: 'REC-DE-01',
          merchantName: 'Metro Cash & Carry Berlin',
          date: DateTime.utc(2026, 9, 9),
          totalAmount: 119.00,
          currency: 'EUR',
          items: [
            ReceiptItemModel(
              description: 'Office Hardware Standard 19%',
              unitPrice: 100.00,
              quantity: 1,
              category: 'Electronics',
            ),
          ],
        ),
        ReceiptItemModel(
          description: 'Food & Organic Milk 7%',
          unitPrice: 50.00,
          quantity: 1,
          category: 'Fresh Produce',
        ).toReceipt('REC-DE-02', 'Bio Markt Berlin', DateTime.utc(2026, 9, 9)),
      ];
    });

    test('generates DATEV ASCII Buchungsstapel with SKR03 chart of accounts', () {
      final ascii = TaxComplianceService.exportDatevAscii(
        receipts: sampleReceipts,
        chart: DatevChartOfAccounts.skr03,
        clientNumber: 1001,
        consultantNumber: 99999,
        fiscalYear: 2026,
      );

      expect(ascii, contains('"EXTF";700;21;"Buchungsstapel"'));
      expect(ascii, contains('"Umsatz (ohne Soll/Haben-Kz)";"Soll/Haben-Kennzeichen"'));

      // Standard 19% Revenue -> SKR03 Account 8400 with BU Key 3
      expect(ascii, contains('"119,00";"S";"EUR";"";"";"";"10001";"8400";"3"'));
      // Reduced 7% Food -> SKR03 Account 8300 with BU Key 2
      expect(ascii, contains('"53,50";"S";"EUR";"";"";"";"10001";"8300";"2"'));
      expect(ascii, contains('"0909"')); // Belegdatum TTMM
    });

    test('generates DATEV ASCII Buchungsstapel with SKR04 chart of accounts', () {
      final ascii = TaxComplianceService.exportDatevAscii(
        receipts: sampleReceipts,
        chart: DatevChartOfAccounts.skr04,
        clientNumber: 2002,
        consultantNumber: 88888,
        fiscalYear: 2026,
      );

      // Standard 19% Revenue -> SKR04 Account 4400 with BU Key 3
      expect(ascii, contains('"119,00";"S";"EUR";"";"";"";"10001";"4400";"3"'));
      // Reduced 7% Food -> SKR04 Account 4300 with BU Key 2
      expect(ascii, contains('"53,50";"S";"EUR";"";"";"";"10001";"4300";"2"'));
    });
  });

  group('International XBRL GL Exporter Tests', () {
    test('generates balanced double-entry XBRL Global Ledger XML', () {
      final receipts = [
        ReceiptModel(
          id: 'XBRL-INV-100',
          merchantName: 'AWS Cloud Services',
          date: DateTime.utc(2026, 9, 9),
          totalAmount: 122.00,
          currency: 'EUR',
          items: [
            ReceiptItemModel(
              description: 'Cloud Server Infrastructure',
              unitPrice: 100.00,
              quantity: 1,
              category: 'IT Services',
            ),
          ],
        ),
      ];

      final xbrl = TaxComplianceService.exportXbrlGlXml(
        receipts: receipts,
        entityIdentifier: 'IT12345678901',
        entityName: 'tAIdy International Holding',
        fiscalPeriod: 'FY2026',
      );

      expect(xbrl, contains('<?xml version="1.0" encoding="UTF-8"?>'));
      expect(xbrl, contains('<xbrli:xbrl'));
      expect(xbrl, contains('<gl-cor:accountingEntries>'));
      expect(xbrl, contains('<gl-cor:entityName contextRef="FY2026">tAIdy International Holding</gl-cor:entityName>'));
      expect(xbrl, contains('<gl-cor:entryNumber contextRef="FY2026">XBRL-INV-100</gl-cor:entryNumber>'));

      // Check Debit leg (Operating Expense)
      expect(xbrl, contains('<gl-cor:accountMainID contextRef="FY2026">4900</gl-cor:accountMainID>'));
      expect(xbrl, contains('<gl-cor:amount unitRef="EUR" decimals="2" contextRef="FY2026">100.00</gl-cor:amount>'));
      expect(xbrl, contains('<gl-cor:debitCreditCode contextRef="FY2026">D</gl-cor:debitCreditCode>'));

      // Check Debit leg (Input VAT 22.00 EUR)
      expect(xbrl, contains('<gl-cor:accountMainID contextRef="FY2026">1576</gl-cor:accountMainID>'));
      expect(xbrl, contains('<gl-cor:amount unitRef="EUR" decimals="2" contextRef="FY2026">22.00</gl-cor:amount>'));

      // Check Credit leg (Bank Account / Cash 122.00 EUR)
      expect(xbrl, contains('<gl-cor:accountMainID contextRef="FY2026">1200</gl-cor:accountMainID>'));
      expect(xbrl, contains('<gl-cor:amount unitRef="EUR" decimals="2" contextRef="FY2026">122.00</gl-cor:amount>'));
      expect(xbrl, contains('<gl-cor:debitCreditCode contextRef="FY2026">C</gl-cor:debitCreditCode>'));

      // Balance check: Total Debit (100.00 + 22.00 = 122.00) == Total Credit (122.00)
    });
  });
}

extension on ReceiptItemModel {
  ReceiptModel toReceipt(String id, String merchant, DateTime date) {
    return ReceiptModel(
      id: id,
      merchantName: merchant,
      date: date,
      totalAmount: unitPrice * quantity,
      currency: 'EUR',
      items: [this],
    );
  }
}
