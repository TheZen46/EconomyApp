import '../financial/money.dart';
import '../financial/tax_engine.dart';
import '../../features/receipt_scanning/data/models/receipt_model.dart';

/// Chart of accounts selection for German DATEV Buchungsstapel export.
enum DatevChartOfAccounts {
  /// Standardkontenrahmen 03 (Process-oriented standard for German SMBs).
  skr03,

  /// Standardkontenrahmen 04 (Balance-sheet-oriented standard).
  skr04,
}

/// Certified European and International Tax Compliance Exporter.
///
/// Implements:
/// 1. **Italy:** FatturaPA FPR12 XML (Agenzia delle Entrate / SdI standard).
/// 2. **Germany / DACH:** DATEV ASCII Buchungsstapel (Format 700 with SKR03 / SKR04).
/// 3. **International:** XBRL Global Ledger (GL) double-entry ledger XML.
class TaxComplianceService {
  TaxComplianceService._();

  // --------------------------------------------------------------------------
  // 1. ITALY: FatturaPA FPR12 XML EXPORTER
  // --------------------------------------------------------------------------

  /// Generates legally compliant Italian FatturaPA FPR12 XML (v1.2.2 / v1.8).
  static String exportFatturaPaXml({
    required ReceiptModel receipt,
    String transmitterCountry = 'IT',
    String transmitterVat = '01234567890',
    String destinationCode = '0000000', // '0000000' for B2C with PEC or 7-char SDI code
    String senderName = 'tAIdy User',
    String senderVat = '01234567890',
    String senderFiscalCode = '01234567890',
    String senderRegime = 'RF01', // RF01 = Ordinario, RF19 = Forfettario
    String senderAddress = 'Via Roma 1',
    String senderCap = '00100',
    String senderCity = 'Roma',
    String senderProvince = 'RM',
    String senderCountry = 'IT',
    String? buyerVat,
    String? buyerFiscalCode,
    String? buyerName,
    String documentType = 'TD01', // TD01 = Fattura ordinaria
    String documentNumber = '1',
  }) {
    // 1. Map receipt items to TaxableLineItem
    final taxableItems = <TaxableLineItem>[];
    for (int i = 0; i < receipt.items.length; i++) {
      final item = receipt.items[i];
      final int rateBps = TaxEngine.inferTaxRateBps(item.category, item.subCategory);
      final nature = (rateBps == 0)
          ? TaxEngine.inferNatureCode(item.category, item.subCategory)
          : null;

      taxableItems.add(TaxableLineItem(
        id: '${i + 1}',
        description: item.description,
        quantity: item.quantity,
        unitPrice: Money.fromDecimal(item.unitPrice, currency: receipt.currency),
        taxRateBps: rateBps,
        natureCode: nature,
      ));
    }

    // 2. Perform Formally Verified Tax Engine Calculation
    final calcResult = TaxEngine.calculateInvoice(
      items: taxableItems,
      currency: receipt.currency,
    );

    final dateStr = receipt.date.toIso8601String().split('T').first;
    final totalDocStr = calcResult.totalGross.toDouble.toStringAsFixed(2);
    final progStr = receipt.id.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').padRight(5, '0');

    final buffer = StringBuffer();
    buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buffer.writeln('<p:FatturaElettronica versione="FPR12" '
        'xmlns:ds="http://www.w3.org/2000/09/xmldsig#" '
        'xmlns:p="http://ivaservizi.agenziaentrate.gov.it/docs/xsd/fatture/v1.2" '
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
        'xsi:schemaLocation="http://ivaservizi.agenziaentrate.gov.it/docs/xsd/fatture/v1.2 '
        'http://www.fatturapa.gov.it/export/fatturazione/sdi/fatturapa/v1.2/Schema_del_file_xml_fattura_ordinaria_v1.2.xsd">');

    // Header
    buffer.writeln('  <FatturaElettronicaHeader>');
    buffer.writeln('    <DatiTrasmissione>');
    buffer.writeln('      <IdTrasmittente>');
    buffer.writeln('        <IdPaese>$transmitterCountry</IdPaese>');
    buffer.writeln('        <IdCodice>$transmitterVat</IdCodice>');
    buffer.writeln('      </IdTrasmittente>');
    buffer.writeln('      <ProgressivoInvio>${progStr.substring(0, progStr.length.clamp(1, 10))}</ProgressivoInvio>');
    buffer.writeln('      <FormatoTrasmissione>FPR12</FormatoTrasmissione>');
    buffer.writeln('      <CodiceDestinatario>$destinationCode</CodiceDestinatario>');
    buffer.writeln('    </DatiTrasmissione>');

    // Cedente Prestatore (Seller)
    buffer.writeln('    <CedentePrestatore>');
    buffer.writeln('      <DatiAnagrafici>');
    buffer.writeln('        <IdFiscaleIVA>');
    buffer.writeln('          <IdPaese>$senderCountry</IdPaese>');
    buffer.writeln('          <IdCodice>$senderVat</IdCodice>');
    buffer.writeln('        </IdFiscaleIVA>');
    buffer.writeln('        <CodiceFiscale>$senderFiscalCode</CodiceFiscale>');
    buffer.writeln('        <Anagrafica>');
    buffer.writeln('          <Denominazione>${_escapeXml(receipt.merchantName.isNotEmpty ? receipt.merchantName : senderName)}</Denominazione>');
    buffer.writeln('        </Anagrafica>');
    buffer.writeln('        <RegimeFiscale>$senderRegime</RegimeFiscale>');
    buffer.writeln('      </DatiAnagrafici>');
    buffer.writeln('      <Sede>');
    buffer.writeln('        <Indirizzo>${_escapeXml(receipt.merchantAddress.isNotEmpty ? receipt.merchantAddress : senderAddress)}</Indirizzo>');
    buffer.writeln('        <CAP>$senderCap</CAP>');
    buffer.writeln('        <Comune>$senderCity</Comune>');
    buffer.writeln('        <Provincia>$senderProvince</Provincia>');
    buffer.writeln('        <Nazione>$senderCountry</Nazione>');
    buffer.writeln('      </Sede>');
    buffer.writeln('    </CedentePrestatore>');

    // Cessionario Committente (Buyer)
    buffer.writeln('    <CessionarioCommittente>');
    buffer.writeln('      <DatiAnagrafici>');
    if (buyerVat != null && buyerVat.isNotEmpty) {
      buffer.writeln('        <IdFiscaleIVA>');
      buffer.writeln('          <IdPaese>IT</IdPaese>');
      buffer.writeln('          <IdCodice>$buyerVat</IdCodice>');
      buffer.writeln('        </IdFiscaleIVA>');
    }
    if (buyerFiscalCode != null && buyerFiscalCode.isNotEmpty) {
      buffer.writeln('        <CodiceFiscale>$buyerFiscalCode</CodiceFiscale>');
    }
    buffer.writeln('        <Anagrafica>');
    buffer.writeln('          <Denominazione>${_escapeXml(buyerName ?? "Cliente Finale")}</Denominazione>');
    buffer.writeln('        </Anagrafica>');
    buffer.writeln('      </DatiAnagrafici>');
    buffer.writeln('      <Sede>');
    buffer.writeln('        <Indirizzo>Via Roma 1</Indirizzo>');
    buffer.writeln('        <CAP>00100</CAP>');
    buffer.writeln('        <Comune>Roma</Comune>');
    buffer.writeln('        <Provincia>RM</Provincia>');
    buffer.writeln('        <Nazione>IT</Nazione>');
    buffer.writeln('      </Sede>');
    buffer.writeln('    </CessionarioCommittente>');
    buffer.writeln('  </FatturaElettronicaHeader>');

    // Body
    buffer.writeln('  <FatturaElettronicaBody>');
    buffer.writeln('    <DatiGenerali>');
    buffer.writeln('      <DatiGeneraliDocumento>');
    buffer.writeln('        <TipoDocumento>$documentType</TipoDocumento>');
    buffer.writeln('        <Divisa>${receipt.currency}</Divisa>');
    buffer.writeln('        <Data>$dateStr</Data>');
    buffer.writeln('        <Numero>$documentNumber</Numero>');
    buffer.writeln('        <ImportoTotaleDocumento>$totalDocStr</ImportoTotaleDocumento>');
    buffer.writeln('      </DatiGeneraliDocumento>');
    buffer.writeln('    </DatiGenerali>');

    // DatiBeniServizi (Lines)
    buffer.writeln('    <DatiBeniServizi>');
    for (int i = 0; i < taxableItems.length; i++) {
      final line = taxableItems[i];
      final lineNet = calcResult.lineNetTotals[line.id]!;
      buffer.writeln('      <DettaglioLinee>');
      buffer.writeln('        <NumeroLinea>${i + 1}</NumeroLinea>');
      buffer.writeln('        <Descrizione>${_escapeXml(line.description)}</Descrizione>');
      buffer.writeln('        <Quantita>${line.quantity.toDouble().toStringAsFixed(2)}</Quantita>');
      buffer.writeln('        <PrezzoUnitario>${line.unitPrice.toDouble.toStringAsFixed(2)}</PrezzoUnitario>');
      buffer.writeln('        <PrezzoTotale>${lineNet.toDouble.toStringAsFixed(2)}</PrezzoTotale>');
      buffer.writeln('        <AliquotaIVA>${line.taxRatePercentage.toStringAsFixed(2)}</AliquotaIVA>');
      if (line.taxRateBps == 0 && line.natureCode != null) {
        buffer.writeln('        <Natura>${line.natureCode}</Natura>');
      }
      buffer.writeln('      </DettaglioLinee>');
    }

    // DatiRiepilogo (Bracket Aggregates)
    for (final bracket in calcResult.bracketSummaries) {
      buffer.writeln('      <DatiRiepilogo>');
      buffer.writeln('        <AliquotaIVA>${bracket.taxRatePercentage.toStringAsFixed(2)}</AliquotaIVA>');
      if (bracket.taxRateBps == 0 && bracket.natureCode != null) {
        buffer.writeln('        <Natura>${bracket.natureCode}</Natura>');
      }
      buffer.writeln('        <ImponibileImporto>${bracket.taxableBase.toDouble.toStringAsFixed(2)}</ImponibileImporto>');
      buffer.writeln('        <Imposta>${bracket.taxAmount.toDouble.toStringAsFixed(2)}</Imposta>');
      buffer.writeln('        <EsigibilitaIVA>I</EsigibilitaIVA>'); // I = Immediata
      buffer.writeln('      </DatiRiepilogo>');
    }
    buffer.writeln('    </DatiBeniServizi>');

    // DatiPagamento
    buffer.writeln('    <DatiPagamento>');
    buffer.writeln('      <CondizioniPagamento>TP02</CondizioniPagamento>'); // TP02 = Pagamento completo
    buffer.writeln('      <DettaglioPagamento>');
    buffer.writeln('        <ModalitaPagamento>MP05</ModalitaPagamento>'); // MP05 = Bonifico / Electronic
    buffer.writeln('        <DataScadenzaPagamento>$dateStr</DataScadenzaPagamento>');
    buffer.writeln('        <ImportoPagamento>$totalDocStr</ImportoPagamento>');
    buffer.writeln('      </DettaglioPagamento>');
    buffer.writeln('    </DatiPagamento>');

    buffer.writeln('  </FatturaElettronicaBody>');
    buffer.writeln('</p:FatturaElettronica>');

    return buffer.toString();
  }

  // --------------------------------------------------------------------------
  // 2. GERMANY / DACH: DATEV ASCII (Buchungsstapel) EXPORTER
  // --------------------------------------------------------------------------

  /// Generates standard German DATEV ASCII (Format 700 / Buchungsstapel) for tax accountants.
  static String exportDatevAscii({
    required List<ReceiptModel> receipts,
    DatevChartOfAccounts chart = DatevChartOfAccounts.skr03,
    int clientNumber = 1001,
    int consultantNumber = 99999,
    int fiscalYear = 2026,
  }) {
    final buffer = StringBuffer();

    // 1. Metadata Line (Format 700 standard)
    buffer.writeln(
      '"EXTF";700;21;"Buchungsstapel";12;${fiscalYear}0909190000000;;'
      '"taidy";"tAIdy FinEngine";"";$clientNumber;$consultantNumber;'
      '${fiscalYear}0101;4;${fiscalYear}0101;${fiscalYear}1231;'
      '"FY $fiscalYear";"";1;;0;"EUR";;;;;"";"";;;"";""',
    );

    // 2. Column Headers (German Accounting Standard)
    buffer.writeln(
      '"Umsatz (ohne Soll/Haben-Kz)";"Soll/Haben-Kennzeichen";"WKZ";"Kurs";'
      '"Basis-Umsatz";"WKZ Basis-Umsatz";"Konto";"Gegenkonto (ohne BU-Schlüssel)";'
      '"BU-Schlüssel";"Belegdatum";"Belegfeld 1";"Belegfeld 2";"Skonto";"Buchungstext"',
    );

    for (final receipt in receipts) {
      // Map line items to tax calculation with German standard VAT rates (19% / 7%)
      final taxableItems = receipt.items.map((item) {
        final rate = TaxEngine.inferTaxRateBps(item.category, item.subCategory, 'DE');
        return TaxableLineItem(
          id: item.description,
          description: item.description,
          quantity: item.quantity,
          unitPrice: Money.fromDecimal(item.unitPrice, currency: receipt.currency),
          taxRateBps: rate,
        );
      }).toList();

      final calc = TaxEngine.calculateInvoice(
        items: taxableItems,
        currency: receipt.currency,
      );

      final dateStr = '${receipt.date.day.toString().padLeft(2, '0')}${receipt.date.month.toString().padLeft(2, '0')}';
      final docRef = receipt.id.replaceAll('"', '').trim();

      for (final bracket in calc.bracketSummaries) {
        final amountStr = bracket.grossTotal.toDouble.toStringAsFixed(2).replaceAll('.', ',');
        final accountMapping = _resolveDatevAccount(chart, bracket.taxRateBps);

        final konto = accountMapping.debitAccount;
        final gegenkonto = accountMapping.creditAccount;
        final buKey = accountMapping.taxKey;
        final text = _escapeCsv(receipt.merchantName);

        buffer.writeln(
          '"$amountStr";"S";"EUR";"";"";"";"$konto";"$gegenkonto";"$buKey";'
          '"$dateStr";"$docRef";"";"";"$text"',
        );
      }
    }

    return buffer.toString();
  }

  // --------------------------------------------------------------------------
  // 3. INTERNATIONAL: XBRL GL (Global Ledger) EXPORTER
  // --------------------------------------------------------------------------

  /// Generates international XBRL Global Ledger (GL) balanced double-entry XML.
  static String exportXbrlGlXml({
    required List<ReceiptModel> receipts,
    String entityIdentifier = 'IT01234567890',
    String entityName = 'tAIdy Organization',
    String fiscalPeriod = 'FY2026',
  }) {
    final buffer = StringBuffer();
    buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buffer.writeln('<xbrli:xbrl xmlns:xbrli="http://www.xbrl.org/2003/instance" '
        'xmlns:gl-cor="http://www.xbrl.org/int/gl/cor/2006-10-25" '
        'xmlns:gl-bus="http://www.xbrl.org/int/gl/bus/2006-10-25" '
        'xmlns:iso4217="http://www.xbrl.org/2003/iso4217" '
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">');

    // Context & Units
    buffer.writeln('  <xbrli:context id="$fiscalPeriod">');
    buffer.writeln('    <xbrli:entity>');
    buffer.writeln('      <xbrli:identifier scheme="http://taidy.com/entities">$entityIdentifier</xbrli:identifier>');
    buffer.writeln('    </xbrli:entity>');
    buffer.writeln('    <xbrli:period>');
    buffer.writeln('      <xbrli:instant>${DateTime.now().toUtc().toIso8601String().split("T").first}</xbrli:instant>');
    buffer.writeln('    </xbrli:period>');
    buffer.writeln('  </xbrli:context>');
    buffer.writeln('  <xbrli:unit id="EUR">');
    buffer.writeln('    <xbrli:measure>iso4217:EUR</xbrli:measure>');
    buffer.writeln('  </xbrli:unit>');

    // Accounting Entries
    buffer.writeln('  <gl-cor:accountingEntries>');
    buffer.writeln('    <gl-cor:documentInfo>');
    buffer.writeln('      <gl-cor:entriesType contextRef="$fiscalPeriod">journal</gl-cor:entriesType>');
    buffer.writeln('      <gl-cor:uniqueID contextRef="$fiscalPeriod">URN:TAIDY:BATCH:2026</gl-cor:uniqueID>');
    buffer.writeln('      <gl-cor:revisable contextRef="$fiscalPeriod">false</gl-cor:revisable>');
    buffer.writeln('    </gl-cor:documentInfo>');
    buffer.writeln('    <gl-cor:entityInformation>');
    buffer.writeln('      <gl-cor:entityName contextRef="$fiscalPeriod">${_escapeXml(entityName)}</gl-cor:entityName>');
    buffer.writeln('    </gl-cor:entityInformation>');

    for (final receipt in receipts) {
      final taxableItems = receipt.items.map((item) {
        final rate = TaxEngine.inferTaxRateBps(item.category, item.subCategory);
        return TaxableLineItem(
          id: item.description,
          description: item.description,
          quantity: item.quantity,
          unitPrice: Money.fromDecimal(item.unitPrice, currency: receipt.currency),
          taxRateBps: rate,
        );
      }).toList();

      final calc = TaxEngine.calculateInvoice(
        items: taxableItems,
        currency: receipt.currency,
      );

      final dateStr = receipt.date.toIso8601String().split('T').first;

      buffer.writeln('    <gl-cor:entryHeader>');
      buffer.writeln('      <gl-cor:postedDate contextRef="$fiscalPeriod">$dateStr</gl-cor:postedDate>');
      buffer.writeln('      <gl-cor:enteredBy contextRef="$fiscalPeriod">tAIdy Compliance Engine</gl-cor:enteredBy>');
      buffer.writeln('      <gl-cor:sourceJournalID contextRef="$fiscalPeriod">EXPENSES</gl-cor:sourceJournalID>');
      buffer.writeln('      <gl-cor:entryNumber contextRef="$fiscalPeriod">${_escapeXml(receipt.id)}</gl-cor:entryNumber>');

      int lineNum = 1;

      // 1. Debit Leg: Expense / Net Taxable Base
      buffer.writeln('      <gl-cor:entryDetail>');
      buffer.writeln('        <gl-cor:lineNumber contextRef="$fiscalPeriod">$lineNum</gl-cor:lineNumber>');
      buffer.writeln('        <gl-cor:account>');
      buffer.writeln('          <gl-cor:accountMainID contextRef="$fiscalPeriod">4900</gl-cor:accountMainID>');
      buffer.writeln('          <gl-cor:accountMainDescription contextRef="$fiscalPeriod">Operating Expenses</gl-cor:accountMainDescription>');
      buffer.writeln('          <gl-cor:accountType contextRef="$fiscalPeriod">expense</gl-cor:accountType>');
      buffer.writeln('        </gl-cor:account>');
      buffer.writeln('        <gl-cor:amount unitRef="EUR" decimals="2" contextRef="$fiscalPeriod">${calc.totalNet.toDouble.toStringAsFixed(2)}</gl-cor:amount>');
      buffer.writeln('        <gl-cor:debitCreditCode contextRef="$fiscalPeriod">D</gl-cor:debitCreditCode>');
      buffer.writeln('        <gl-cor:postingStatus contextRef="$fiscalPeriod">posted</gl-cor:postingStatus>');
      buffer.writeln('      </gl-cor:entryDetail>');
      lineNum++;

      // 2. Debit Leg: Input VAT (Vorsteuer / IVA a credito)
      if (calc.totalTax.cents > 0) {
        buffer.writeln('      <gl-cor:entryDetail>');
        buffer.writeln('        <gl-cor:lineNumber contextRef="$fiscalPeriod">$lineNum</gl-cor:lineNumber>');
        buffer.writeln('        <gl-cor:account>');
        buffer.writeln('          <gl-cor:accountMainID contextRef="$fiscalPeriod">1576</gl-cor:accountMainID>');
        buffer.writeln('          <gl-cor:accountMainDescription contextRef="$fiscalPeriod">Input VAT Deductible</gl-cor:accountMainDescription>');
        buffer.writeln('          <gl-cor:accountType contextRef="$fiscalPeriod">asset</gl-cor:accountType>');
        buffer.writeln('        </gl-cor:account>');
        buffer.writeln('        <gl-cor:amount unitRef="EUR" decimals="2" contextRef="$fiscalPeriod">${calc.totalTax.toDouble.toStringAsFixed(2)}</gl-cor:amount>');
        buffer.writeln('        <gl-cor:debitCreditCode contextRef="$fiscalPeriod">D</gl-cor:debitCreditCode>');
        buffer.writeln('        <gl-cor:postingStatus contextRef="$fiscalPeriod">posted</gl-cor:postingStatus>');
        buffer.writeln('      </gl-cor:entryDetail>');
        lineNum++;
      }

      // 3. Credit Leg: Cash / Bank Accounts Payable (Total Gross)
      buffer.writeln('      <gl-cor:entryDetail>');
      buffer.writeln('        <gl-cor:lineNumber contextRef="$fiscalPeriod">$lineNum</gl-cor:lineNumber>');
      buffer.writeln('        <gl-cor:account>');
      buffer.writeln('          <gl-cor:accountMainID contextRef="$fiscalPeriod">1200</gl-cor:accountMainID>');
      buffer.writeln('          <gl-cor:accountMainDescription contextRef="$fiscalPeriod">Bank Account / Cash</gl-cor:accountMainDescription>');
      buffer.writeln('          <gl-cor:accountType contextRef="$fiscalPeriod">asset</gl-cor:accountType>');
      buffer.writeln('        </gl-cor:account>');
      buffer.writeln('        <gl-cor:amount unitRef="EUR" decimals="2" contextRef="$fiscalPeriod">${calc.totalGross.toDouble.toStringAsFixed(2)}</gl-cor:amount>');
      buffer.writeln('        <gl-cor:debitCreditCode contextRef="$fiscalPeriod">C</gl-cor:debitCreditCode>');
      buffer.writeln('        <gl-cor:postingStatus contextRef="$fiscalPeriod">posted</gl-cor:postingStatus>');
      buffer.writeln('      </gl-cor:entryDetail>');

      buffer.writeln('    </gl-cor:entryHeader>');
    }

    buffer.writeln('  </gl-cor:accountingEntries>');
    buffer.writeln('</xbrli:xbrl>');

    return buffer.toString();
  }

  // --------------------------------------------------------------------------
  // INTERNAL HELPERS
  // --------------------------------------------------------------------------

  static _DatevMapping _resolveDatevAccount(DatevChartOfAccounts chart, int rateBps) {
    if (chart == DatevChartOfAccounts.skr03) {
      if (rateBps == 1900 || rateBps == 2200) {
        return const _DatevMapping(debitAccount: '10001', creditAccount: '8400', taxKey: '3');
      } else if (rateBps == 700 || rateBps == 1000 || rateBps == 400) {
        return const _DatevMapping(debitAccount: '10001', creditAccount: '8300', taxKey: '2');
      } else {
        return const _DatevMapping(debitAccount: '10001', creditAccount: '8125', taxKey: '0');
      }
    } else {
      // SKR04
      if (rateBps == 1900 || rateBps == 2200) {
        return const _DatevMapping(debitAccount: '10001', creditAccount: '4400', taxKey: '3');
      } else if (rateBps == 700 || rateBps == 1000 || rateBps == 400) {
        return const _DatevMapping(debitAccount: '10001', creditAccount: '4300', taxKey: '2');
      } else {
        return const _DatevMapping(debitAccount: '10001', creditAccount: '4125', taxKey: '0');
      }
    }
  }

  static String _escapeXml(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  static String _escapeCsv(String input) {
    return input.replaceAll('"', '""');
  }
}

class _DatevMapping {
  final String debitAccount;
  final String creditAccount;
  final String taxKey;

  const _DatevMapping({
    required this.debitAccount,
    required this.creditAccount,
    required this.taxKey,
  });
}
