import '../data/models/invoice_model.dart';

/// Monthly revenue velocity metrics for a single calendar month.
class InvoiceMonthlyVelocity {
  final DateTime month;
  final double invoicedAmount;
  final double settledAmount;

  const InvoiceMonthlyVelocity({
    required this.month,
    required this.invoicedAmount,
    required this.settledAmount,
  });
}

/// Portfolio summary statistics derived from an invoice collection.
class InvoiceSummaryStats {
  final double totalOutstanding;
  final double totalOverdue;
  final double totalDraft;
  final int awaitingCount;

  const InvoiceSummaryStats({
    required this.totalOutstanding,
    required this.totalOverdue,
    required this.totalDraft,
    required this.awaitingCount,
  });
}

/// Pure domain calculation engine for invoice filtering, revenue velocity, and KPI generation.
class InvoiceFilterEngine {
  /// Filters an invoice collection by status and search query.
  static List<InvoiceModel> filterInvoices(
    List<InvoiceModel> invoices, {
    String statusFilter = 'All',
    String searchQuery = '',
  }) {
    final query = searchQuery.trim().toLowerCase();

    return invoices.where((i) {
      if (statusFilter != 'All' && i.status != statusFilter) {
        return false;
      }
      if (query.isNotEmpty) {
        final clientMatch = i.clientName.toLowerCase().contains(query);
        final numberMatch = i.invoiceNumber.toLowerCase().contains(query);
        return clientMatch || numberMatch;
      }
      return true;
    }).toList();
  }

  /// Computes monthly revenue velocity (invoiced vs settled) across the trailing [monthCount] months.
  static List<InvoiceMonthlyVelocity> computeMonthlyVelocity(
    List<InvoiceModel> invoices, {
    DateTime? asOfDate,
    int monthCount = 6,
  }) {
    final now = asOfDate ?? DateTime.now();
    final months = List.generate(
      monthCount,
      (i) => DateTime(now.year, now.month - (monthCount - 1) + i),
    );

    return months.map((m) {
      double invoiced = 0.0;
      double settled = 0.0;

      for (final inv in invoices) {
        if (inv.issuedDate.year == m.year && inv.issuedDate.month == m.month) {
          if (inv.status != InvoiceStatus.draft) {
            invoiced += inv.amount;
          }
          if (inv.status == InvoiceStatus.settled) {
            settled += inv.amount;
          }
        }
      }

      return InvoiceMonthlyVelocity(
        month: m,
        invoicedAmount: invoiced,
        settledAmount: settled,
      );
    }).toList();
  }

  /// Calculates aggregated KPI metrics for a list of invoices.
  static InvoiceSummaryStats computeSummaryStats(List<InvoiceModel> invoices) {
    double outstanding = 0.0;
    double overdue = 0.0;
    double draft = 0.0;
    int awaiting = 0;

    for (final inv in invoices) {
      if (inv.status == InvoiceStatus.sent || inv.status == InvoiceStatus.overdue) {
        outstanding += inv.amount;
        awaiting++;
      }
      if (inv.status == InvoiceStatus.overdue) {
        overdue += inv.amount;
      }
      if (inv.status == InvoiceStatus.draft) {
        draft += inv.amount;
      }
    }

    return InvoiceSummaryStats(
      totalOutstanding: outstanding,
      totalOverdue: overdue,
      totalDraft: draft,
      awaitingCount: awaiting,
    );
  }
}
