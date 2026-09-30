import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import 'package:t_aidy/features/tax_compliance/domain/audit_risk_score_engine.dart';
import 'package:t_aidy/features/boxes/domain/box_pnl_engine.dart';
import 'package:t_aidy/features/analytics/domain/cash_flow_forecasting_engine.dart';
import 'package:t_aidy/features/tax_compliance/domain/contractor_compliance_engine.dart';
import 'package:t_aidy/features/analytics/domain/subscription_detector_engine.dart';
import 'package:t_aidy/features/tax_compliance/domain/tax_calendar_engine.dart';
import 'package:t_aidy/features/tax_compliance/presentation/providers/tax_shield_provider.dart';
import 'package:t_aidy/features/tax_compliance/data/datasources/accountant_portal_generator.dart';
import 'package:t_aidy/features/tax_compliance/data/datasources/audit_dossier_service.dart';
import 'package:t_aidy/features/tax_compliance/data/datasources/audit_packager_service.dart';
import 'package:t_aidy/features/analytics/domain/financial_flow_engine.dart';
import 'package:t_aidy/features/tax_compliance/domain/home_office_apportionment_engine.dart';
import 'package:t_aidy/features/tax_compliance/domain/qbi_deduction_engine.dart';
import '../../../boxes/data/models/box_model.dart';
import '../../../boxes/data/providers/boxes_provider.dart';
import '../../../invoices/data/models/invoice_model.dart';
import '../../../invoices/data/providers/invoices_provider.dart';
import '../../../receipt_scanning/domain/entities/receipt.dart';
import '../../../receipt_scanning/presentation/providers/receipt_provider.dart';
import 'package:t_aidy/features/analytics/presentation/widgets/capital_flow_topology_widget.dart';

/// Tax & Compliance Command Center
///
/// Unifies statutory estimated quarterly deadlines, contractor 1099-NEC
/// threshold radar, recurring SaaS radar, multi-box P&L balance sheets,
/// 90-day cash flow forecasts, and statutory IRS audit risk index into a single dashboard.
class TaxComplianceHubPage extends ConsumerStatefulWidget {
  const TaxComplianceHubPage({super.key});

  @override
  ConsumerState<TaxComplianceHubPage> createState() => _TaxComplianceHubPageState();
}

class _TaxComplianceHubPageState extends ConsumerState<TaxComplianceHubPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 7, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final receipts = ref.watch(receiptListProvider).valueOrNull ?? [];
    final boxes = ref.watch(boxesProvider);
    final invoices = ref.watch(invoicesProvider);
    final taxCalc = ref.watch(taxShieldCalculationProvider);

    final currentYear = DateTime.now().year;
    final calendarEvents = TaxCalendarEngine.generateFiscalCalendar(
      year: currentYear,
      jurisdiction: 'USA',
      annualLockedTaxReserve: taxCalc.lockedTaxShield,
      referenceDate: DateTime.now(),
    );
    final contractorSummary = ContractorComplianceEngine.analyzeReceipts(
      receipts: receipts,
      fiscalYear: currentYear,
    );
    final recurringSummary = SubscriptionDetectorEngine.analyzeReceipts(receipts);
    final pnlReport = BoxPnlEngine.generateReport(
      boxes: boxes,
      invoices: invoices,
      receipts: receipts,
      mileageTrips: const [],
    );

    final cashForecast = CashFlowForecastingEngine.generateForecast(
      startingBalance: taxCalc.safeToSpend,
      invoices: invoices,
      receipts: receipts,
      scheduledTaxes: calendarEvents,
      activeSubscriptions: recurringSummary.activeSubscriptions,
      forecastDays: 90,
    );

    final auditRisk = AuditRiskScoreEngine.evaluateAuditRisk(
      receipts: receipts,
      invoices: invoices,
      fiscalYear: currentYear,
    );

    // Flow Topology calculations
    final boxInflows = <String, double>{};
    final defaultBoxName = boxes.isNotEmpty ? boxes.first.name : 'Main Box';
    for (final inv in invoices) {
      if (inv.status == InvoiceStatus.settled) {
        boxInflows[defaultBoxName] = (boxInflows[defaultBoxName] ?? 0.0) + inv.amount;
      }
    }
    final boxExpenses = <String, double>{};
    for (final r in receipts) {
      final bName = boxes.firstWhere(
        (b) => b.id == r.boxId,
        orElse: () => boxes.isNotEmpty
            ? boxes.first
            : BoxModel(id: 'main', name: 'Main', budget: 0, spent: 0, currency: 'USD', color: 0, icon: ''),
      ).name;
      boxExpenses[bName] = (boxExpenses[bName] ?? 0.0) + r.totalAmount;
    }

    final flowGraph = FinancialFlowEngine.computeTopology(
      totalGrossInflow: taxCalc.grossRevenue,
      boxInflows: boxInflows,
      boxExpenses: boxExpenses,
      taxWithholdingRate: taxCalc.effectiveTaxRate,
    );

    const homeSpace = HomeOfficeSpace(
      totalHomeSqFt: 1500,
      dedicatedOfficeSqFt: 250,
      isExclusiveUse: true,
      isRegularUse: true,
      isPrincipalPlaceOfBusiness: true,
    );

    const homeExpenses = HouseholdExpenses(
      rentPaid: 18000,
      utilitiesElectricAndGas: 2400,
      internetMonthlyFee: 1200,
      internetBusinessUsagePercent: 0.85,
    );

    final homeOfficeResult = HomeOfficeApportionmentEngine.calculate(
      space: homeSpace,
      expenses: homeExpenses,
      effectiveTaxRate: taxCalc.effectiveTaxRate,
    );

    final qbiResult = QbiDeductionEngine.calculate(
      QbiCalculationParams(
        netQualifiedBusinessIncome: taxCalc.netTaxableIncome,
        totalTaxableIncome: taxCalc.grossRevenue > 0 ? taxCalc.grossRevenue : taxCalc.netTaxableIncome,
        filingStatus: TaxFilingStatus.single,
        tradeType: BusinessTradeType.nonSstb,
        taxYear: currentYear,
      ),
      marginalTaxRate: taxCalc.effectiveTaxRate,
    );

    final currencyFmt = NumberFormat.currency(symbol: '\$', decimalDigits: 2);

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        title: Text(
          'Tax & Compliance Command Center',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: Colors.white,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Export Sealed Cryptographic Audit Pack (.zip)',
            icon: const Icon(Icons.archive_outlined, color: Color(0xFF38BDF8)),
            onPressed: () async {
              await AuditPackagerService.exportAndShareZip(
                receipts: receipts,
                boxes: boxes,
                clientName: 'tAIdy Verified User',
                fiscalYear: currentYear,
              );
            },
          ),
          IconButton(
            tooltip: 'Export Accountant Portal (PII-Sanitized)',
            icon: const Icon(Icons.shield_outlined, color: Color(0xFF10B981)),
            onPressed: () {
              final html = AccountantPortalGenerator.generatePortalHtml(
                receipts: receipts,
                boxes: boxes,
                clientName: 'tAIdy Freelance Client',
                fiscalYear: '$currentYear',
              );
              Share.share(html, subject: 'Sanitized CPA Tax Portal ($currentYear)');
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: const Color(0xFF38BDF8),
          indicatorWeight: 3,
          labelColor: const Color(0xFF38BDF8),
          unselectedLabelColor: Colors.white60,
          labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13),
          tabs: const [
            Tab(icon: Icon(Icons.calendar_month, size: 18), text: 'Quarterly Deadlines'),
            Tab(icon: Icon(Icons.badge_outlined, size: 18), text: '1099-NEC Radar'),
            Tab(icon: Icon(Icons.radar, size: 18), text: 'SaaS Subscriptions'),
            Tab(icon: Icon(Icons.account_balance, size: 18), text: 'Entity P&L'),
            Tab(icon: Icon(Icons.trending_up, size: 18), text: 'Cash Runway'),
            Tab(icon: Icon(Icons.security, size: 18), text: 'Audit Shield'),
            Tab(icon: Icon(Icons.account_tree_outlined, size: 18), text: 'Flow & 8829 Home Office'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // 1. Statutory Quarterly Deadlines & Safe Harbor
          _buildQuarterlyTab(context, calendarEvents, taxCalc, currencyFmt, currentYear),

          // 2. Contractor 1099-NEC Threshold Radar
          _buildContractorTab(context, contractorSummary, currencyFmt),

          // 3. Recurring SaaS Radar
          _buildSaaSRadarTab(context, recurringSummary, currencyFmt),

          // 4. Multi-Box Entity P&L
          _buildPnLTab(context, pnlReport, currencyFmt),

          // 5. Cash Flow & Solvency Runway
          _buildCashRunwayTab(context, cashForecast, currencyFmt),

          // 6. Audit Shield & IRS Risk Score
          _buildAuditShieldTab(context, auditRisk, receipts, boxes, currentYear),

          // 7. Capital Flow Topology, Form 8829 Home Office & Section 199A QBI
          _buildFlowAndHomeOfficeTab(
            context,
            flowGraph,
            homeOfficeResult,
            qbiResult,
            receipts,
            invoices,
            boxes,
            currencyFmt,
          ),
        ],
      ),
    );
  }

  Widget _buildQuarterlyTab(
    BuildContext context,
    List<TaxCalendarEvent> events,
    TaxShieldCalculation taxCalc,
    NumberFormat fmt,
    int year,
  ) {
    TaxCalendarEvent? next;
    for (final e in events) {
      if (!e.isOverdue) {
        next = e;
        break;
      }
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Next Estimated Tax Deadline',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: Colors.white70,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: (next?.daysRemaining ?? 0) <= 30
                          ? const Color(0xFFEF4444).withValues(alpha: 0.2)
                          : const Color(0xFF10B981).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      next != null ? '${next.daysRemaining} days left' : 'All passed',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: (next?.daysRemaining ?? 0) <= 30
                            ? const Color(0xFFF87171)
                            : const Color(0xFF34D399),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                next != null
                    ? '${next.title}: ${DateFormat('MMMM dd, yyyy').format(next.dueDate)}'
                    : 'Year-End Complete',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Quarterly Estimated Payment: ${fmt.format(next?.estimatedPaymentAmount ?? 0.0)}',
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF38BDF8),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF38BDF8),
                  foregroundColor: const Color(0xFF0F172A),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.download, size: 18),
                label: const Text('Export .ics Tax Calendar', style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: () {
                  if (events.isNotEmpty) {
                    final ics = events.first.toIcsFormat();
                    Share.share(ics, subject: 'statutory_tax_calendar_$year.ics');
                  }
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Statutory Schedule ($year)',
          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
        ),
        const SizedBox(height: 12),
        ...events.map((d) {
          final isPassed = d.isOverdue;
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: d == next
                    ? const Color(0xFF38BDF8)
                    : isPassed
                        ? Colors.white10
                        : Colors.white24,
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: isPassed
                      ? Colors.grey.withValues(alpha: 0.2)
                      : const Color(0xFF38BDF8).withValues(alpha: 0.2),
                  child: Icon(
                    Icons.event,
                    color: isPassed ? Colors.grey : const Color(0xFF38BDF8),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        d.title,
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: isPassed ? Colors.white54 : Colors.white,
                        ),
                      ),
                      Text(
                        'Due ${DateFormat('MMM dd, yyyy').format(d.dueDate)} • Estimated: ${fmt.format(d.estimatedPaymentAmount)}',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: isPassed ? Colors.white38 : Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isPassed)
                  const Icon(Icons.check_circle_outline, color: Colors.grey, size: 20)
                else
                  Text(
                    '${d.daysRemaining}d',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: const Color(0xFF38BDF8),
                    ),
                  ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildContractorTab(
    BuildContext context,
    ContractorComplianceReport summary,
    NumberFormat fmt,
  ) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                title: 'Total Subcontractors',
                value: '${summary.vendors.length}',
                color: const Color(0xFF38BDF8),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricCard(
                title: '1099-NEC Required',
                value: '${summary.totalVendorsRequiring1099}',
                color: const Color(0xFFF59E0B),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricCard(
                title: 'Missing W-9',
                value: '${summary.missingW9Vendors.length}',
                color: const Color(0xFFEF4444),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          'Vendor Disbursements (${summary.fiscalYear})',
          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
        ),
        const SizedBox(height: 12),
        if (summary.vendors.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'No subcontractor or vendor payments recorded for ${summary.fiscalYear}.',
              style: GoogleFonts.inter(color: Colors.white60),
            ),
          )
        else
          ...summary.vendors.map((v) {
            final progress = (v.totalPaidInYear / 600.0).clamp(0.0, 1.0);
            final requires1099 = v.status == Contractor1099Status.requires1099 || v.status == Contractor1099Status.w9Collected;
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: requires1099
                      ? (v.isW9OnFile ? const Color(0xFF10B981) : const Color(0xFFEF4444))
                      : Colors.white10,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        v.vendorName,
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        fmt.format(v.totalPaidInYear),
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: requires1099 ? const Color(0xFFF59E0B) : Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: Colors.white12,
                      valueColor: AlwaysStoppedAnimation(
                        requires1099 ? const Color(0xFFF59E0B) : const Color(0xFF38BDF8),
                      ),
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        requires1099
                            ? 'Form 1099-NEC Threshold Crossed (≥ \$600)'
                            : '${fmt.format(v.distanceToThreshold)} until 1099 limit',
                        style: GoogleFonts.inter(fontSize: 12, color: Colors.white60),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: v.isW9OnFile
                              ? const Color(0xFF10B981).withValues(alpha: 0.2)
                              : const Color(0xFFEF4444).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          v.isW9OnFile ? 'W-9 On File' : 'W-9 Missing',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: v.isW9OnFile ? const Color(0xFF34D399) : const Color(0xFFF87171),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _buildSaaSRadarTab(
    BuildContext context,
    SubscriptionReport summary,
    NumberFormat fmt,
  ) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                title: 'Monthly SaaS Burn',
                value: fmt.format(summary.totalMonthlySaaSExpense),
                color: const Color(0xFF38BDF8),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricCard(
                title: 'Annualized SaaS',
                value: fmt.format(summary.totalAnnualSaaSBurn),
                color: const Color(0xFFA855F7),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricCard(
                title: 'Active Subs',
                value: '${summary.totalSubscriptionCount}',
                color: const Color(0xFF10B981),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          'Detected Recurring Services',
          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
        ),
        const SizedBox(height: 12),
        if (summary.activeSubscriptions.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'No recurring subscriptions detected yet.',
              style: GoogleFonts.inter(color: Colors.white60),
            ),
          )
        else
          ...summary.activeSubscriptions.map((s) {
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: s.hasPriceIncreased ? const Color(0xFFF59E0B) : Colors.white10,
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: const Color(0xFFA855F7).withValues(alpha: 0.2),
                    child: const Icon(Icons.repeat, color: Color(0xFFA855F7), size: 20),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              s.merchantName,
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: Colors.white,
                              ),
                            ),
                            if (s.hasPriceIncreased) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'Price Hike +${fmt.format(s.priceIncreaseAmount)}',
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFFFBBF24),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        Text(
                          '${s.cadence.name.toUpperCase()} • Last Billed ${DateFormat('MMM dd, yyyy').format(s.lastObservedDate)}',
                          style: GoogleFonts.inter(fontSize: 12, color: Colors.white60),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    fmt.format(s.latestAmount),
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _buildPnLTab(
    BuildContext context,
    PortfolioPnlReport report,
    NumberFormat fmt,
  ) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Multi-Box Entity Performance',
          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
        ),
        const SizedBox(height: 12),
        if (report.boxStatements.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'No active boxes found.',
              style: GoogleFonts.inter(color: Colors.white60),
            ),
          )
        else
          ...report.boxStatements.map((pnl) {
            final isProfitable = pnl.netOperatingProfit >= 0;
            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        pnl.box.name,
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: Colors.white,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isProfitable
                              ? const Color(0xFF10B981).withValues(alpha: 0.2)
                              : const Color(0xFFEF4444).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${pnl.profitMarginPercent.toStringAsFixed(1)}% margin',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: isProfitable ? const Color(0xFF34D399) : const Color(0xFFF87171),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white12, height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Revenue', style: GoogleFonts.inter(fontSize: 13, color: Colors.white70)),
                      Text(fmt.format(pnl.grossRevenue), style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: const Color(0xFF34D399))),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Costs (Expenses + Mileage)', style: GoogleFonts.inter(fontSize: 13, color: Colors.white70)),
                      Text(fmt.format(pnl.totalCosts), style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: const Color(0xFFF87171))),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Net Operating Profit', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14, color: Colors.white)),
                      Text(
                        fmt.format(pnl.netOperatingProfit),
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: isProfitable ? const Color(0xFF34D399) : const Color(0xFFF87171),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _buildCashRunwayTab(
    BuildContext context,
    CashFlowForecastResult forecast,
    NumberFormat fmt,
  ) {
    final hasRisk = forecast.hasSolvencyRisk;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: hasRisk
                  ? [const Color(0xFF450A0A), const Color(0xFF1E293B)]
                  : [const Color(0xFF064E3B), const Color(0xFF1E293B)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: hasRisk
                  ? const Color(0xFFEF4444).withValues(alpha: 0.5)
                  : const Color(0xFF10B981).withValues(alpha: 0.5),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '90-Day Cash Runway Forecast',
                    style: GoogleFonts.inter(fontSize: 14, color: Colors.white70),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: hasRisk ? const Color(0xFFEF4444).withValues(alpha: 0.2) : const Color(0xFF10B981).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      hasRisk ? 'Solvency Risk Detected' : 'Healthy Liquidity',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: hasRisk ? const Color(0xFFF87171) : const Color(0xFF34D399),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '${forecast.runwayDaysWithoutNewRevenue} Days of Runway',
                style: GoogleFonts.inter(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Projected Min Cash: ${fmt.format(forecast.minProjectedBalance)} on ${DateFormat('MMM dd').format(forecast.minBalanceDate)}',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: hasRisk ? const Color(0xFFFCA5A5) : const Color(0xFF6EE7B7),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                title: 'Pending Receivables',
                value: fmt.format(forecast.expectedReceivablesTotal),
                color: const Color(0xFF34D399),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricCard(
                title: 'Committed Outflows',
                value: fmt.format(forecast.committedOutflowsTotal),
                color: const Color(0xFFF87171),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricCard(
                title: 'Avg Daily Burn',
                value: fmt.format(forecast.averageDailyBurn),
                color: const Color(0xFF38BDF8),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (forecast.alerts.isNotEmpty) ...[
          Text(
            'Solvency Alerts & Actions',
            style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
          ),
          const SizedBox(height: 12),
          ...forecast.alerts.take(3).map((a) {
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a.description,
                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Action: ${a.recommendedMitigation}',
                    style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF38BDF8)),
                  ),
                ],
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _buildAuditShieldTab(
    BuildContext context,
    AuditRiskAssessment risk,
    List<Receipt> receipts,
    List<BoxModel> boxes,
    int year,
  ) {
    Color badgeColor = const Color(0xFF10B981);
    if (risk.overallRiskScore >= 40) {
      badgeColor = const Color(0xFFEF4444);
    } else if (risk.overallRiskScore >= 20) {
      badgeColor = const Color(0xFFF59E0B);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Audit Risk Gauge Card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: badgeColor.withValues(alpha: 0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'IRS Statutory Audit Risk Index',
                    style: GoogleFonts.inter(fontSize: 14, color: Colors.white70),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: badgeColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${risk.riskLevel} Risk (${risk.overallRiskScore}/100)',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: badgeColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                risk.hasDefensibleAuditReadiness
                    ? 'Cryptographically Defensible Ledger 🛡️'
                    : 'Potential Audit Triggers Detected ⚠️',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (risk.overallRiskScore / 100.0).clamp(0.0, 1.0),
                  backgroundColor: Colors.white12,
                  valueColor: AlwaysStoppedAnimation(badgeColor),
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: const Color(0xFF0F172A),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.verified_user, size: 18),
                label: const Text('Export Merkle Audit Dossier (.html)', style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: () async {
                  await AuditDossierService.exportAndShareDossier(
                    receipts: receipts,
                    fiscalYear: year,
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                title: 'Round Number %',
                value: '${(risk.roundNumbersRatio * 100).toStringAsFixed(0)}%',
                color: risk.roundNumbersRatio > 0.35 ? const Color(0xFFF59E0B) : const Color(0xFF34D399),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricCard(
                title: 'Meals vs Revenue',
                value: '${(risk.mealsToRevenueRatio * 100).toStringAsFixed(0)}%',
                color: risk.mealsToRevenueRatio > 0.20 ? const Color(0xFFEF4444) : const Color(0xFF34D399),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricCard(
                title: 'Missing W-9s',
                value: '${risk.contractorsMissingW9Count}',
                color: risk.contractorsMissingW9Count > 0 ? const Color(0xFFEF4444) : const Color(0xFF34D399),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          'Statutory Audit Triggers & Mitigation Guidance',
          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
        ),
        const SizedBox(height: 12),
        if (risk.riskFactors.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'No high-risk audit flags detected in your ledger.',
              style: GoogleFonts.inter(color: const Color(0xFF34D399), fontWeight: FontWeight.w600),
            ),
          )
        else
          ...risk.riskFactors.map((f) {
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    f.title,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    f.description,
                    style: GoogleFonts.inter(fontSize: 12, color: Colors.white70),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.lightbulb_outline, size: 16, color: Color(0xFF38BDF8)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            f.mitigationAdvice,
                            style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF38BDF8)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _buildFlowAndHomeOfficeTab(
    BuildContext context,
    FinancialFlowGraph flowGraph,
    HomeOfficeDeductionResult homeOffice,
    QbiCalculationResult qbiResult,
    List<Receipt> receipts,
    List<InvoiceModel> invoices,
    List<BoxModel> boxes,
    NumberFormat currencyFmt,
  ) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Capital Allocation Flow (Sankey / Waterfall)',
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Air-gapped real-time vector visualization of gross income, box routing, statutory withholding shields, and free cash flow. Tap any node or ribbon to isolate matching receipts.',
          style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8)),
        ),
        const SizedBox(height: 12),

        // 1. Vector Flow Topology Canvas Widget with interactive node tap isolation
        CapitalFlowTopologyWidget(
          flowGraph: flowGraph,
          onNodeTapped: (node) {
            _showIsolatedReceiptsModal(
              context,
              node,
              receipts,
              invoices,
              boxes,
              currencyFmt,
            );
          },
        ),

        const SizedBox(height: 24),

        // 2. Form 8829 Home Office Apportionment Optimizer Card
        Row(
          children: [
            const Icon(Icons.home_work_outlined, color: Color(0xFF38BDF8), size: 20),
            const SizedBox(width: 8),
            Text(
              'IRS Form 8829 Home Office Optimizer',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Dual-method optimization comparing Simplified (\$5/sq ft) vs. Actual Expense ratio with telecom/utility allocation.',
          style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8)),
        ),
        const SizedBox(height: 12),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF334155)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Optimal Tax Shield Deduction',
                        style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        currencyFmt.format(homeOffice.optimalDeduction),
                        style: GoogleFonts.inter(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF10B981),
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF10B981)),
                    ),
                    child: Text(
                      '${homeOffice.recommendedMethod} METHOD',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF10B981),
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(color: Color(0xFF334155), height: 24),

              // Dual-Method Comparison Grid
              Row(
                children: [
                  Expanded(
                    child: _buildMetricCard(
                      title: 'Simplified (\$5/sq ft)',
                      value: currencyFmt.format(homeOffice.simplifiedMethodDeduction),
                      color: const Color(0xFF94A3B8),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildMetricCard(
                      title: 'Actual Expenses Ratio',
                      value: currencyFmt.format(homeOffice.actualMethodDeduction),
                      color: const Color(0xFF38BDF8),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Audit Rationale Box
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF475569)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline, size: 16, color: Color(0xFF38BDF8)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        homeOffice.auditDefenseRATIONALE,
                        style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFFCBD5E1)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // 3. IRC § 199A Qualified Business Income (QBI) Pass-Through Optimizer Card
        Row(
          children: [
            const Icon(Icons.calculate_outlined, color: Color(0xFF10B981), size: 20),
            const SizedBox(width: 8),
            Text(
              'IRC § 199A QBI Pass-Through Optimizer',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Dual-method statutory calculation: 20% Net QBI deduction vs. W-2 wage & UBIA limitation formulas under TCJA.',
          style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8)),
        ),
        const SizedBox(height: 12),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF334155)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Allowable Section 199A Deduction',
                        style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        currencyFmt.format(qbiResult.allowableQbiDeduction),
                        style: GoogleFonts.inter(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF10B981),
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF10B981)),
                    ),
                    child: Text(
                      '20% PASS-THROUGH SHIELD',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF10B981),
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(color: Color(0xFF334155), height: 24),

              // Dual-Method Comparison Grid
              Row(
                children: [
                  Expanded(
                    child: _buildMetricCard(
                      title: 'Tentative 20% QBI',
                      value: currencyFmt.format(qbiResult.grossTentativeDeduction),
                      color: const Color(0xFF38BDF8),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildMetricCard(
                      title: 'Estimated Tax Savings',
                      value: currencyFmt.format(qbiResult.taxSavings),
                      color: const Color(0xFF8B5CF6),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Audit Defense Rationale Box
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF475569)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.shield_outlined, size: 16, color: Color(0xFF10B981)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        qbiResult.auditDefenseNotes,
                        style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFFCBD5E1)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showIsolatedReceiptsModal(
    BuildContext context,
    FlowNode node,
    List<Receipt> receipts,
    List<InvoiceModel> invoices,
    List<BoxModel> boxes,
    NumberFormat currencyFmt,
  ) {
    final matchingReceipts = <Receipt>[];
    final matchingInvoices = <InvoiceModel>[];

    if (node.category == 'source') {
      matchingInvoices.addAll(invoices.where((i) => i.status == InvoiceStatus.settled));
    } else if (node.category == 'box') {
      final box = boxes.firstWhere(
        (b) => b.name.toLowerCase() == node.label.toLowerCase() || b.id == node.id,
        orElse: () => BoxModel(id: '', name: '', budget: 0, spent: 0, currency: 'USD', color: 0),
      );
      matchingReceipts.addAll(receipts.where((r) => r.boxId == box.id || r.boxId == node.id));
      matchingInvoices.addAll(invoices.where((i) => i.status == InvoiceStatus.settled));
    } else if (node.category == 'tax') {
      matchingReceipts.addAll(receipts);
    } else if (node.category == 'expense') {
      matchingReceipts.addAll(receipts);
    } else {
      matchingReceipts.addAll(receipts);
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: Color(node.colorHex),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Isolated Flow: ${node.label}',
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    currencyFmt.format(node.value),
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Color(node.colorHex),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Underlying verified transactions allocating capital to this flow node.',
                style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8)),
              ),
              const Divider(color: Color(0xFF334155), height: 24),
              Expanded(
                child: matchingReceipts.isEmpty && matchingInvoices.isEmpty
                    ? Center(
                        child: Text(
                          'No individual ledger items mapped to this node.',
                          style: GoogleFonts.inter(color: const Color(0xFF94A3B8)),
                        ),
                      )
                    : ListView(
                        children: [
                          if (matchingInvoices.isNotEmpty) ...[
                            Text(
                              'Settled Invoices',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF38BDF8),
                              ),
                            ),
                            const SizedBox(height: 8),
                            ...matchingInvoices.map((inv) => Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1E293B),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: const Color(0xFF334155)),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            inv.clientName,
                                            style: GoogleFonts.inter(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 14,
                                              color: Colors.white,
                                            ),
                                          ),
                                          Text(
                                            'Invoice ${inv.invoiceNumber}',
                                            style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8)),
                                          ),
                                        ],
                                      ),
                                      Text(
                                        currencyFmt.format(inv.amount),
                                        style: GoogleFonts.inter(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                          color: const Color(0xFF10B981),
                                        ),
                                      ),
                                    ],
                                  ),
                                )),
                          ],
                          if (matchingReceipts.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text(
                              'Allocated Receipts & Expenses',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFFF59E0B),
                              ),
                            ),
                            const SizedBox(height: 8),
                            ...matchingReceipts.map((r) => Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1E293B),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: const Color(0xFF334155)),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              r.merchantName.isNotEmpty ? r.merchantName : 'Receipt #${r.id}',
                                              style: GoogleFonts.inter(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 14,
                                                color: Colors.white,
                                              ),
                                            ),
                                            Text(
                                              DateFormat('MMM dd, yyyy').format(r.date),
                                              style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8)),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Text(
                                        currencyFmt.format(r.totalAmount),
                                        style: GoogleFonts.inter(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                          color: const Color(0xFFF87171),
                                        ),
                                      ),
                                    ],
                                  ),
                                )),
                          ],
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMetricCard({required String title, required String value, required Color color}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: GoogleFonts.inter(fontSize: 11, color: Colors.white60)),
          const SizedBox(height: 6),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

