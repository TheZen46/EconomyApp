import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:t_aidy/features/invoices/data/models/invoice_model.dart';
import 'package:t_aidy/features/invoices/data/providers/invoices_provider.dart';

/// Standard accounting aging bucket for unpaid customer invoices.
enum AgingBucket {
  current, // 0 - 30 days
  overdue30, // 31 - 60 days
  overdue60, // 61 - 90 days
  critical90, // 91+ days
}

/// Detailed aging profile of an unpaid invoice.
class InvoiceAgingItem {
  final InvoiceModel invoice;
  final int daysOutstanding;
  final AgingBucket bucket;
  final bool isOverdue;
  final double accruedLateFee;

  const InvoiceAgingItem({
    required this.invoice,
    required this.daysOutstanding,
    required this.bucket,
    required this.isOverdue,
    required this.accruedLateFee,
  });

  /// Total claimable amount = invoice amount + accrued late interest.
  double get totalClaimableAmount => invoice.amount + accruedLateFee;
}

/// Consolidated portfolio receivables aging summary.
class InvoiceAgingReport {
  final double totalOutstanding;
  final double totalOverdue;
  final double currentAmount;
  final double overdue30Amount;
  final double overdue60Amount;
  final double critical90Amount;
  final double totalLateFeesAccrued;
  final int totalUnpaidCount;
  final int overdueCount;
  final List<InvoiceAgingItem> agingItems;

  const InvoiceAgingReport({
    required this.totalOutstanding,
    required this.totalOverdue,
    required this.currentAmount,
    required this.overdue30Amount,
    required this.overdue60Amount,
    required this.critical90Amount,
    required this.totalLateFeesAccrued,
    required this.totalUnpaidCount,
    required this.overdueCount,
    required this.agingItems,
  });
}

/// Tone/urgency level for automated client dunning reminders.
enum DunningTone {
  politeInquiry, // Pre-due or 1-14 days overdue
  firmReminder, // 15-45 days overdue
  urgentFinalNotice, // 45+ days overdue
}

/// Engine for invoice receivables aging analysis, late fee calculation, and dunning generation.
class InvoiceAgingEngine {
  /// Monthly statutory late payment interest rate (1.5% default = 18% annual APR).
  static const double kDefaultMonthlyLateFeeRate = 0.015;

  /// Analyzes a list of [InvoiceModel]s and produces an [InvoiceAgingReport].
  static InvoiceAgingReport analyzeInvoices(
    List<InvoiceModel> invoices, {
    DateTime? asOfDate,
    double monthlyLateRate = kDefaultMonthlyLateFeeRate,
  }) {
    final referenceDate = asOfDate ?? DateTime.now();

    double totalOutstanding = 0.0;
    double totalOverdue = 0.0;
    double currentSum = 0.0;
    double overdue30Sum = 0.0;
    double overdue60Sum = 0.0;
    double critical90Sum = 0.0;
    double totalLateFees = 0.0;
    int unpaidCount = 0;
    int overdueCount = 0;

    final List<InvoiceAgingItem> items = [];

    for (final inv in invoices) {
      // Only evaluate active unpaid/sent invoices
      if (inv.status != InvoiceStatus.sent && inv.status != InvoiceStatus.draft) {
        continue;
      }

      unpaidCount++;
      totalOutstanding += inv.amount;

      final issueDate = inv.issuedDate;
      final dueDate = inv.dueDate ?? issueDate.add(const Duration(days: 30));
      final daysSinceIssue = referenceDate.difference(issueDate).inDays;
      final daysPastDue = referenceDate.difference(dueDate).inDays;
      final isOverdue = daysPastDue > 0;

      // Determine aging bucket
      AgingBucket bucket;
      if (daysSinceIssue <= 30) {
        bucket = AgingBucket.current;
        currentSum += inv.amount;
      } else if (daysSinceIssue <= 60) {
        bucket = AgingBucket.overdue30;
        overdue30Sum += inv.amount;
      } else if (daysSinceIssue <= 90) {
        bucket = AgingBucket.overdue60;
        overdue60Sum += inv.amount;
      } else {
        bucket = AgingBucket.critical90;
        critical90Sum += inv.amount;
      }

      // Calculate accrued late fee interest if overdue
      double lateFee = 0.0;
      if (isOverdue) {
        overdueCount++;
        totalOverdue += inv.amount;
        final monthsLate = daysPastDue / 30.0;
        lateFee = inv.amount * (monthlyLateRate * monthsLate);
        totalLateFees += lateFee;
      }

      items.add(InvoiceAgingItem(
        invoice: inv,
        daysOutstanding: daysSinceIssue,
        bucket: bucket,
        isOverdue: isOverdue,
        accruedLateFee: lateFee,
      ));
    }

    return InvoiceAgingReport(
      totalOutstanding: totalOutstanding,
      totalOverdue: totalOverdue,
      currentAmount: currentSum,
      overdue30Amount: overdue30Sum,
      overdue60Amount: overdue60Sum,
      critical90Amount: critical90Sum,
      totalLateFeesAccrued: totalLateFees,
      totalUnpaidCount: unpaidCount,
      overdueCount: overdueCount,
      agingItems: items,
    );
  }

  /// Generates contextually tailored dunning reminder text for an overdue invoice.
  static String generateDunningMessage(InvoiceAgingItem item, {DunningTone? tone}) {
    final inv = item.invoice;
    final selectedTone = tone ??
        (item.daysOutstanding > 60
            ? DunningTone.urgentFinalNotice
            : (item.daysOutstanding > 30 ? DunningTone.firmReminder : DunningTone.politeInquiry));

    final amountFormatted = '\$${inv.amount.toStringAsFixed(2)}';
    final claimableFormatted = '\$${item.totalClaimableAmount.toStringAsFixed(2)}';
    final dueDate = inv.dueDate ?? inv.issuedDate.add(const Duration(days: 30));

    switch (selectedTone) {
      case DunningTone.politeInquiry:
        return '''Hi ${inv.clientName},

Hope you're having a great week!

Just a friendly check-in regarding invoice #${inv.invoiceNumber} ($amountFormatted) issued on ${_formatDate(inv.issuedDate)}. It was due on ${_formatDate(dueDate)}.

Please let me know if you need another copy of the invoice or any payment details.

Best regards,''';

      case DunningTone.firmReminder:
        return '''Dear ${inv.clientName},

This is a reminder that invoice #${inv.invoiceNumber} ($amountFormatted) is currently ${item.daysOutstanding} days outstanding (due ${_formatDate(dueDate)}).

Please arrange payment at your earliest convenience to maintain an account in good standing.

If payment has already been sent, please let us know so we can update our ledger.

Sincerely,''';

      case DunningTone.urgentFinalNotice:
        return '''URGENT: Final Notice for Outstanding Invoice #${inv.invoiceNumber}

Dear ${inv.clientName},

Invoice #${inv.invoiceNumber} for the amount of $amountFormatted is now severely past due (${item.daysOutstanding} days outstanding).

In accordance with our service terms, statutory late payment interest of \$${item.accruedLateFee.toStringAsFixed(2)} has accrued, bringing the total outstanding balance to $claimableFormatted.

Please remit payment immediately or contact us within 48 hours to settle this balance.

Regards,''';
    }
  }

  static String _formatDate(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }
}

/// Provider for active invoice aging report.
final invoiceAgingReportProvider = Provider<InvoiceAgingReport>((ref) {
  final invoices = ref.watch(invoicesProvider);
  return InvoiceAgingEngine.analyzeInvoices(invoices);
});

