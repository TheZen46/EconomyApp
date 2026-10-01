import 'dart:convert';
import 'package:csv/csv.dart';
import '../../domain/entities/receipt.dart';
import '../../../../core/utils/csv_utils.dart';

/// Represents aggregated VAT / Tax metrics for a specific percentage bracket.
class VatBracketSummary {
  final double ratePercentage;
  final double taxableBase;
  final double vatAmount;
  final double grossTotal;
  final int transactionCount;

  const VatBracketSummary({
    required this.ratePercentage,
    required this.taxableBase,
    required this.vatAmount,
    required this.grossTotal,
    required this.transactionCount,
  });

  Map<String, dynamic> toMap() {
    return {
      'rate_percentage': ratePercentage,
      'taxable_base': taxableBase,
      'vat_amount': vatAmount,
      'gross_total': grossTotal,
      'transaction_count': transactionCount,
    };
  }
}

/// A structured line item within a generated tax summary report.
class TaxReportLineItem {
  final String date;
  final String merchantName;
  final String vatNumber;
  final String receiptId;
  final String category;
  final double ratePercentage;
  final double taxableBase;
  final double vatAmount;
  final double grossTotal;
  final String currency;

  const TaxReportLineItem({
    required this.date,
    required this.merchantName,
    required this.vatNumber,
    required this.receiptId,
    required this.category,
    required this.ratePercentage,
    required this.taxableBase,
    required this.vatAmount,
    required this.grossTotal,
    required this.currency,
  });
}

/// Complete aggregated tax report for a given accounting period.
class TaxReport {
  final DateTime startDate;
  final DateTime endDate;
  final String currency;
  final int totalReceipts;
  final double totalTaxableBase;
  final double totalVatAmount;
  final double totalGrossAmount;
  final List<VatBracketSummary> bracketSummaries;
  final List<TaxReportLineItem> lineItems;
  final DateTime generatedAt;

  const TaxReport({
    required this.startDate,
    required this.endDate,
    required this.currency,
    required this.totalReceipts,
    required this.totalTaxableBase,
    required this.totalVatAmount,
    required this.totalGrossAmount,
    required this.bracketSummaries,
    required this.lineItems,
    required this.generatedAt,
  });
}

/// Service for generating compliance-ready Tax, VAT, and freelance accounting reports.
class TaxReportService {
  /// Default European standard VAT rate mapping if no itemized rate is given.
  static double inferVatRateFromCategory(String? category, [String? subCategory]) {
    final text = '${category ?? ''} ${subCategory ?? ''}'.toLowerCase();
    if (text.contains('fresh produce') ||
        text.contains('bread') ||
        text.contains('milk') ||
        text.contains('fruit') ||
        text.contains('vegetable') ||
        text.contains('pane')) {
      return 4.0; // Reduced basic food VAT (4%)
    } else if (text.contains('protein') ||
        text.contains('meat') ||
        text.contains('pantry') ||
        text.contains('restaurant') ||
        text.contains('dairy') ||
        text.contains('personal care') ||
        text.contains('health') ||
        text.contains('medicine') ||
        text.contains('medical') ||
        text.contains('pharma') ||
        text.contains('farmacia')) {
      return 10.0; // Intermediate food / pharma VAT (10%)
    } else {
      return 22.0; // Standard European/Italian VAT (22%)
    }
  }

  /// Generates an aggregated [TaxReport] from a collection of receipts over a date range.
  static TaxReport generateTaxReport({
    required List<Receipt> receipts,
    DateTime? startDate,
    DateTime? endDate,
    String defaultCurrency = 'EUR',
  }) {
    final now = DateTime.now();
    final start = startDate ?? DateTime(now.year, now.month, 1);
    final end = endDate ?? DateTime(now.year, now.month + 1, 0, 23, 59, 59);

    final filteredReceipts = receipts.where((r) {
      return r.date.isAfter(start.subtract(const Duration(seconds: 1))) &&
          r.date.isBefore(end.add(const Duration(seconds: 1)));
    }).toList();

    final currency = filteredReceipts.isNotEmpty ? filteredReceipts.first.currency : defaultCurrency;

    final bracketMap = <double, _BracketAccumulator>{};
    final lineItems = <TaxReportLineItem>[];

    for (final receipt in filteredReceipts) {
      final dateStr = '${receipt.date.year}-${receipt.date.month.toString().padLeft(2, '0')}-${receipt.date.day.toString().padLeft(2, '0')}';

      if (receipt.items.isEmpty) {
        // Fallback for receipt with no line items
        final rate = inferVatRateFromCategory(receipt.category);
        final gross = receipt.totalAmount;
        final taxable = gross / (1.0 + (rate / 100.0));
        final vat = gross - taxable;

        final acc = bracketMap.putIfAbsent(rate, () => _BracketAccumulator(rate));
        acc.taxableBase += taxable;
        acc.vatAmount += vat;
        acc.grossTotal += gross;
        acc.count += 1;

        lineItems.add(TaxReportLineItem(
          date: dateStr,
          merchantName: receipt.merchantName,
          vatNumber: receipt.vatNumber,
          receiptId: receipt.id,
          category: receipt.category,
          ratePercentage: rate,
          taxableBase: taxable,
          vatAmount: vat,
          grossTotal: gross,
          currency: receipt.currency,
        ));
      } else {
        for (final item in receipt.items) {
          final rate = inferVatRateFromCategory(item.mainCategory, item.subCategory);
          final gross = item.totalPrice;
          final taxable = gross / (1.0 + (rate / 100.0));
          final vat = gross - taxable;

          final acc = bracketMap.putIfAbsent(rate, () => _BracketAccumulator(rate));
          acc.taxableBase += taxable;
          acc.vatAmount += vat;
          acc.grossTotal += gross;
          acc.count += 1;

          lineItems.add(TaxReportLineItem(
            date: dateStr,
            merchantName: receipt.merchantName,
            vatNumber: receipt.vatNumber,
            receiptId: receipt.id,
            category: item.mainCategory ?? receipt.category,
            ratePercentage: rate,
            taxableBase: taxable,
            vatAmount: vat,
            grossTotal: gross,
            currency: receipt.currency,
          ));
        }
      }
    }

    final sortedRates = bracketMap.keys.toList()..sort();
    final summaries = sortedRates.map((r) {
      final acc = bracketMap[r]!;
      return VatBracketSummary(
        ratePercentage: r,
        taxableBase: acc.taxableBase,
        vatAmount: acc.vatAmount,
        grossTotal: acc.grossTotal,
        transactionCount: acc.count,
      );
    }).toList();

    final totalTaxable = summaries.fold<double>(0.0, (sum, s) => sum + s.taxableBase);
    final totalVat = summaries.fold<double>(0.0, (sum, s) => sum + s.vatAmount);
    final totalGross = summaries.fold<double>(0.0, (sum, s) => sum + s.grossTotal);

    return TaxReport(
      startDate: start,
      endDate: end,
      currency: currency,
      totalReceipts: filteredReceipts.length,
      totalTaxableBase: totalTaxable,
      totalVatAmount: totalVat,
      totalGrossAmount: totalGross,
      bracketSummaries: summaries,
      lineItems: lineItems,
      generatedAt: now,
    );
  }

  /// Exports the tax report as standard formatted CSV string for accounting software.
  static String exportToCsv(TaxReport report) {
    final rows = <List<dynamic>>[];

    // 1. Report Header
    rows.add(['tAIdy - Tax & VAT Summary Report']);
    rows.add(['Period', '${report.startDate.toIso8601String().substring(0, 10)} to ${report.endDate.toIso8601String().substring(0, 10)}']);
    rows.add(['Currency', report.currency]);
    rows.add(['Total Receipts', report.totalReceipts]);
    rows.add(['Generated At', report.generatedAt.toIso8601String()]);
    rows.add([]);

    // 2. VAT Bracket Summary Table
    rows.add(['=== VAT BRACKET SUMMARY ===']);
    rows.add(['VAT Rate (%)', 'Taxable Base (Imponibile)', 'VAT Amount (Imposta)', 'Gross Total (Totale)', 'Transaction Count']);
    for (final bracket in report.bracketSummaries) {
      rows.add([
        '${bracket.ratePercentage.toStringAsFixed(1)}%',
        bracket.taxableBase.toStringAsFixed(2),
        bracket.vatAmount.toStringAsFixed(2),
        bracket.grossTotal.toStringAsFixed(2),
        bracket.transactionCount,
      ]);
    }
    rows.add([
      'TOTAL',
      report.totalTaxableBase.toStringAsFixed(2),
      report.totalVatAmount.toStringAsFixed(2),
      report.totalGrossAmount.toStringAsFixed(2),
      report.lineItems.length,
    ]);
    rows.add([]);

    // 3. Itemized Transaction Log
    rows.add(['=== ITEMIZED TRANSACTION LOG ===']);
    rows.add([
      'Date',
      'Merchant Name',
      'VAT / Tax ID',
      'Receipt ID',
      'Category',
      'VAT Rate (%)',
      'Taxable Base',
      'VAT Amount',
      'Gross Total',
      'Currency',
    ]);

    for (final item in report.lineItems) {
      rows.add([
        item.date,
        item.merchantName,
        item.vatNumber,
        item.receiptId,
        item.category,
        '${item.ratePercentage.toStringAsFixed(1)}%',
        item.taxableBase.toStringAsFixed(2),
        item.vatAmount.toStringAsFixed(2),
        item.grossTotal.toStringAsFixed(2),
        item.currency,
      ]);
    }

    // Merchant names and categories come from OCR and imports.
    return const ListToCsvConverter().convert(CsvUtils.sanitizeRows(rows));
  }

  /// Exports the tax report as structured PDF document bytes.
  static List<int> exportToPdfBytes(TaxReport report) {
    // Generate clean text-formatted PDF representation for freelance accounting submissions
    final buffer = StringBuffer();
    buffer.writeln('%PDF-1.4');
    buffer.writeln('%tAIdy Automated Accounting Tax Report');
    buffer.writeln('1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj');
    buffer.writeln('2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj');
    buffer.writeln('3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >> endobj');
    buffer.writeln('5 0 obj << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> endobj');

    final contentStream = StringBuffer();
    contentStream.writeln('BT');
    contentStream.writeln('/F1 16 Tf');
    contentStream.writeln('50 800 Td (tAIdy Tax & VAT Summary Report) Tj');
    contentStream.writeln('/F1 10 Tf');
    contentStream.writeln('0 -20 Td (Period: ${report.startDate.toIso8601String().substring(0, 10)} to ${report.endDate.toIso8601String().substring(0, 10)}) Tj');
    contentStream.writeln('0 -14 Td (Total Receipts: ${report.totalReceipts} | Currency: ${report.currency}) Tj');
    contentStream.writeln('0 -14 Td (Gross Total: ${report.totalGrossAmount.toStringAsFixed(2)} | Taxable: ${report.totalTaxableBase.toStringAsFixed(2)} | VAT: ${report.totalVatAmount.toStringAsFixed(2)}) Tj');
    contentStream.writeln('0 -25 Td (VAT Bracket Summary:) Tj');

    for (final b in report.bracketSummaries) {
      contentStream.writeln('0 -14 Td (  - VAT ${b.ratePercentage.toStringAsFixed(1)}%: Taxable ${b.taxableBase.toStringAsFixed(2)} | VAT ${b.vatAmount.toStringAsFixed(2)} | Gross ${b.grossTotal.toStringAsFixed(2)} [${b.transactionCount} items]) Tj');
    }

    contentStream.writeln('0 -25 Td (Generated automatically by tAIdy Privacy-First AI Expense Tracker) Tj');
    contentStream.writeln('ET');

    final contentStr = contentStream.toString();
    buffer.writeln('4 0 obj << /Length ${contentStr.length} >> stream');
    buffer.write(contentStr);
    buffer.writeln('endstream endobj');
    buffer.writeln('xref');
    buffer.writeln('0 6');
    buffer.writeln('0000000000 65535 f ');
    buffer.writeln('0000000050 00000 n ');
    buffer.writeln('0000000100 00000 n ');
    buffer.writeln('0000000160 00000 n ');
    buffer.writeln('0000000280 00000 n ');
    buffer.writeln('0000000220 00000 n ');
    buffer.writeln('trailer << /Size 6 /Root 1 0 R >>');
    buffer.writeln('startxref');
    buffer.writeln('${buffer.length}');
    buffer.writeln('%%EOF');

    return utf8.encode(buffer.toString());
  }
}

class _BracketAccumulator {
  final double rate;
  double taxableBase = 0.0;
  double vatAmount = 0.0;
  double grossTotal = 0.0;
  int count = 0;

  _BracketAccumulator(this.rate);
}
