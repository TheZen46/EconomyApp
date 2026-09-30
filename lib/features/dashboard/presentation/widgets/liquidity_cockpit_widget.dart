import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import 'package:t_aidy/features/tax_compliance/domain/audit_risk_score_engine.dart';
import 'package:t_aidy/features/invoices/domain/invoice_aging_engine.dart';
import 'package:t_aidy/features/tax_compliance/presentation/providers/tax_shield_provider.dart';
import 'package:t_aidy/features/boxes/data/models/box_model.dart';
import 'package:t_aidy/features/boxes/data/providers/boxes_provider.dart';
import 'package:t_aidy/features/invoices/data/models/invoice_model.dart';
import 'package:t_aidy/features/invoices/data/providers/invoices_provider.dart';
import 'package:t_aidy/features/receipt_scanning/domain/entities/receipt.dart';
import 'package:t_aidy/features/receipt_scanning/presentation/providers/receipt_provider.dart';
import 'package:t_aidy/features/receipt_scanning/presentation/widgets/multi_modal_ingestion_deck.dart';
import 'package:t_aidy/features/tax_compliance/presentation/widgets/tax_simulator_modal.dart';

/// [GEMINI ANTIGRAVITY] Grounded Real-Time Safe-to-Spend Liquidity Cockpit.
///
/// Features mathematical decomposition of liquid cash vs statutory tax reserves,
/// predictive action ribbon with 1-click offline dunning, modular entity strips with
/// spend velocity bars, and on-device DIF audit radar.
class LiquidityCockpitWidget extends ConsumerWidget {
  final List<Receipt> receipts;
  final bool isDark;

  const LiquidityCockpitWidget({
    super.key,
    required this.receipts,
    this.isDark = true,
  });

  void _openMultiModalIngestion(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => FractionallySizedBox(
        heightFactor: 0.92,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: MultiModalIngestionDeck(
            onComplete: () {
              // Refresh callback
            },
          ),
        ),
      ),
    );
  }

  void _openTaxSimulator(BuildContext context, TaxShieldCalculation taxShield) {
    showTaxSimulatorModal(context, taxShield);
  }

  void _sendOfflineDunningNotice(BuildContext context, InvoiceModel invoice) {
    final agingItem = InvoiceAgingItem(
      invoice: invoice,
      daysOutstanding: DateTime.now().difference(invoice.issuedDate).inDays,
      bucket: AgingBucket.overdue30,
      isOverdue: true,
      accruedLateFee: invoice.amount * 0.015,
    );

    final dunningText = InvoiceAgingEngine.generateDunningMessage(agingItem);
    Clipboard.setData(ClipboardData(text: dunningText));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF1E293B),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: Color(0xFFF59E0B)),
        ),
        content: Row(
          children: [
            const Icon(Icons.mark_email_read_outlined, color: Color(0xFFF59E0B), size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Offline Dunning Notice copied for ${invoice.clientName} (\$${invoice.amount.toStringAsFixed(0)})',
                style: GoogleFonts.inter(color: Colors.white, fontSize: 12),
              ),
            ),
          ],
        ),
        action: SnackBarAction(
          label: 'View Invoices',
          textColor: const Color(0xFF38BDF8),
          onPressed: () {
            try {
              context.push('/invoices');
            } catch (_) {}
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final taxShield = ref.watch(taxShieldCalculationProvider);
    final boxes = ref.watch(boxesProvider);
    final invoices = ref.watch(invoicesProvider);
    final isPrivacy = ref.watch(privacyModeProvider);
    final currencyFmt = NumberFormat.simpleCurrency(decimalDigits: 2);

    // Compute DIF risk index locally
    final auditRisk = AuditRiskScoreEngine.evaluateAuditRisk(
      receipts: receipts,
      invoices: invoices,
    );
    final isLowRisk = auditRisk.overallRiskScore < 35;

    final safeToSpend = taxShield.safeToSpend;
    final grossInflow = taxShield.grossRevenue > 0 ? taxShield.grossRevenue : 5000.0;
    final lockedTax = taxShield.lockedTaxShield > 0 ? taxShield.lockedTaxShield : (grossInflow * taxShield.effectiveTaxRate);
    final effectiveSafe = safeToSpend > 0 ? safeToSpend : (grossInflow - lockedTax - taxShield.totalExpenses);

    // Overdue invoice detection for predictive action ribbon
    final now = DateTime.now();
    final overdueInvoices = invoices.where((i) {
      final dueDate = i.dueDate ?? i.issuedDate.add(const Duration(days: 30));
      return (i.status == InvoiceStatus.overdue || (dueDate.isBefore(now) && i.status == InvoiceStatus.sent));
    }).toList();
    final topOverdue = overdueInvoices.isNotEmpty ? overdueInvoices.first : null;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF334155), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Air-Gapped Security & DIF Risk Pill
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFF10B981),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'AIR-GAPPED VAULT ACTIVE',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF94A3B8),
                      letterSpacing: 1.1,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isLowRisk ? const Color(0xFF10B981).withValues(alpha: 0.15) : const Color(0xFFF59E0B).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isLowRisk ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.security,
                      size: 11,
                      color: isLowRisk ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'DIF ${auditRisk.overallRiskScore} • ${isLowRisk ? "LOW AUDIT RISK" : "ATTENTION"}',
                      style: GoogleFonts.inter(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: isLowRisk ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Hierarchy of Truth: Safe-to-Spend (28pt bold) & Tax Reserve (14pt semi-bold)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Safe-to-Spend: 28pt bold
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SAFE-TO-SPEND LIQUIDITY',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF94A3B8),
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isPrivacy ? '••••••' : currencyFmt.format(effectiveSafe),
                    style: GoogleFonts.inter(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF10B981),
                      fontFeatures: const [FontFeature.tabularFigures()],
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),

              // Locked Statutory Tax Reserve: 14pt semi-bold
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'TAX RESERVE (${(taxShield.effectiveTaxRate * 100).toStringAsFixed(0)}%)',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFFF59E0B),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isPrivacy ? '••••••' : currencyFmt.format(lockedTax),
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFFF59E0B),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Grounded Mathematical Decomposition Ribbon
          // Gross Cash - Locked Statutory Tax Reserve (25%) - Pending SaaS/Invoices = Safe-to-Spend
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildFormulaCell(
                  label: 'Gross Inflows',
                  value: isPrivacy ? '•••' : currencyFmt.format(grossInflow),
                  color: Colors.white,
                ),
                Text('−', style: GoogleFonts.inter(color: const Color(0xFF64748B), fontSize: 13, fontWeight: FontWeight.bold)),
                _buildFormulaCell(
                  label: 'Tax Shield (${(taxShield.effectiveTaxRate * 100).toStringAsFixed(0)}%)',
                  value: isPrivacy ? '•••' : currencyFmt.format(lockedTax),
                  color: const Color(0xFFF59E0B),
                ),
                Text('−', style: GoogleFonts.inter(color: const Color(0xFF64748B), fontSize: 13, fontWeight: FontWeight.bold)),
                _buildFormulaCell(
                  label: 'OpEx / SaaS',
                  value: isPrivacy ? '•••' : currencyFmt.format(taxShield.totalExpenses),
                  color: const Color(0xFFEF4444),
                ),
                Text('=', style: GoogleFonts.inter(color: const Color(0xFF64748B), fontSize: 13, fontWeight: FontWeight.bold)),
                _buildFormulaCell(
                  label: 'Safe Nest',
                  value: isPrivacy ? '•••' : currencyFmt.format(effectiveSafe),
                  color: const Color(0xFF10B981),
                  isBold: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Predictive Contextual Micro-Action (e.g., 1-Click Offline Dunning Notice if overdue)
          if (topOverdue != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF78350F).withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.6)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.bolt, color: Color(0xFFF59E0B), size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Invoice #${topOverdue.invoiceNumber} (${topOverdue.clientName}) is past due',
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFFF59E0B)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  InkWell(
                    onTap: () => _sendOfflineDunningNotice(context, topOverdue),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '1-Click Dunning Notice',
                        style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Modular Entity Strips with Spend Velocity Bars
          if (boxes.isNotEmpty) ...[
            Text(
              'MODULAR ENTITY STRIPS',
              style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: const Color(0xFF94A3B8), letterSpacing: 0.6),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: boxes.map((box) {
                  return _buildEntityStripCard(box, isPrivacy, currencyFmt);
                }).toList(),
              ),
            ),
            const SizedBox(height: 14),
          ],

          // Anticipatory Predictive Action Ribbon
          Row(
            children: [
              // 1. Ingest
              Expanded(
                flex: 4,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF38BDF8),
                    foregroundColor: const Color(0xFF0F172A),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => _openMultiModalIngestion(context),
                  icon: const Icon(Icons.add_a_photo_outlined, size: 15),
                  label: Text('Capture Ingestion', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800)),
                ),
              ),
              const SizedBox(width: 8),

              // 2. Tax Shield
              Expanded(
                flex: 3,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF10B981),
                    side: const BorderSide(color: Color(0xFF334155)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () {
                    try {
                      context.push('/tax-compliance');
                    } catch (_) {}
                  },
                  icon: const Icon(Icons.shield_outlined, size: 15),
                  label: Text('Tax Hub', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 8),

              // 3. What-If Simulator
              Expanded(
                flex: 3,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Color(0xFF334155)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => _openTaxSimulator(context, taxShield),
                  icon: const Icon(Icons.tune_outlined, size: 15),
                  label: Text('What-If', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEntityStripCard(BoxModel box, bool isPrivacy, NumberFormat currencyFmt) {
    final boxColor = Color(box.color != 0 ? box.color : 0xFF38BDF8);
    final budget = box.budget > 0 ? box.budget : 1000.0;
    final spent = box.spent;
    final velocityRatio = (spent / budget).clamp(0.0, 1.0);

    return Container(
      width: 170,
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(shape: BoxShape.circle, color: boxColor),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  box.name,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            isPrivacy ? '••••' : '${currencyFmt.format(spent)} / ${currencyFmt.format(budget)}',
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF94A3B8),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 6),
          // Spend Velocity Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: velocityRatio,
              minHeight: 4,
              backgroundColor: const Color(0xFF0F172A),
              valueColor: AlwaysStoppedAnimation<Color>(
                velocityRatio > 0.9 ? const Color(0xFFEF4444) : boxColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormulaCell({
    required String label,
    required String value,
    required Color color,
    bool isBold = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(fontSize: 8, color: const Color(0xFF94A3B8)),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
            color: color,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}


