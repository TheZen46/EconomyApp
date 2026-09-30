import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import 'package:t_aidy/features/tax_compliance/domain/audit_risk_score_engine.dart';
import 'package:t_aidy/features/tax_compliance/domain/contractor_compliance_engine.dart';
import 'package:t_aidy/features/tax_compliance/presentation/providers/tax_shield_provider.dart';
import '../../../invoices/data/providers/invoices_provider.dart';
import '../../domain/entities/receipt.dart';

/// Types of contextual interruptions detected autonomously on-device.
enum InterruptionType {
  contractor1099Threshold,
  quarterlyTaxDeadline,
  difAuditRisk,
  unreconciledDiscrepancy,
}

/// [GEMINI ANTIGRAVITY] Contextual Interruption & Predictive Resolution Banner.
///
/// Surfaces non-blocking, inline regulatory and security alerts with 1-tap pre-computed resolutions.
/// Features dark amber (#78350F / #F59E0B) and muted crimson (#7F1D1D / #EF4444) palettes with swipe-to-defer.
class ContextualInterruptionBanner extends ConsumerStatefulWidget {
  final List<Receipt> receipts;
  final VoidCallback? onActionTriggered;

  const ContextualInterruptionBanner({
    super.key,
    required this.receipts,
    this.onActionTriggered,
  });

  @override
  ConsumerState<ContextualInterruptionBanner> createState() => _ContextualInterruptionBannerState();
}

class _ContextualInterruptionBannerState extends ConsumerState<ContextualInterruptionBanner> {
  final Set<String> _dismissedKeys = {};

  @override
  Widget build(BuildContext context) {
    final invoices = ref.watch(invoicesProvider);
    final taxCalc = ref.watch(taxShieldCalculationProvider);
    final currencyFmt = NumberFormat.simpleCurrency(decimalDigits: 0);
    final currentYear = DateTime.now().year;

    // 1. Check 1099-NEC $600 Contractor Threshold Radar
    final contractorSummary = ContractorComplianceEngine.analyzeReceipts(
      receipts: widget.receipts,
      fiscalYear: currentYear,
    );

    if (contractorSummary.missingW9Vendors.isNotEmpty) {
      final vendor = contractorSummary.missingW9Vendors.first;
      final key = 'contractor_1099_${vendor.normalizedName}';
      if (!_dismissedKeys.contains(key)) {
        return _buildBannerCard(
          keyString: key,
          type: InterruptionType.contractor1099Threshold,
          badge: '1099-NEC THRESHOLD EXCEEDED',
          message: 'Contractor "${vendor.vendorName}" reached ${currencyFmt.format(vendor.totalPaidInYear)}. W-9 Missing.',
          actionLabel: 'Request W-9',
          accentColor: const Color(0xFFF59E0B), // Warm amber
          backgroundColor: const Color(0xFF78350F).withValues(alpha: 0.35),
          borderColor: const Color(0xFFF59E0B),
          icon: Icons.badge_outlined,
          onAction: () async {
            widget.onActionTriggered?.call();
            final template = ContractorComplianceEngine.generateW9RequestTemplate(
              vendor: vendor,
              taxYear: currentYear,
            );
            await Clipboard.setData(ClipboardData(text: template));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: const Color(0xFF1E293B),
                  content: Text(
                    'Pre-filled Form W-9 Request Sheet copied to clipboard for ${vendor.vendorName}.',
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                  ),
                  duration: const Duration(seconds: 4),
                  behavior: SnackBarBehavior.floating,
                ),
              );
              try {
                context.push('/tax-compliance');
              } catch (_) {}
            }
          },
        );
      }
    }

    // 2. Check DIF audit risk
    final auditRisk = AuditRiskScoreEngine.evaluateAuditRisk(
      receipts: widget.receipts,
      invoices: invoices,
      fiscalYear: currentYear,
    );

    if (auditRisk.riskFactors.isNotEmpty && !_dismissedKeys.contains('audit_${auditRisk.overallRiskScore}')) {
      final topFactor = auditRisk.riskFactors.first;
      return _buildBannerCard(
        keyString: 'audit_${auditRisk.overallRiskScore}',
        type: InterruptionType.difAuditRisk,
        badge: 'IRS DIF AUDIT RADAR TRIGGER',
        message: topFactor.title,
        actionLabel: 'Review Risk Factor',
        accentColor: const Color(0xFFF59E0B),
        backgroundColor: const Color(0xFF78350F).withValues(alpha: 0.35),
        borderColor: const Color(0xFFF59E0B),
        icon: Icons.warning_amber_rounded,
        onAction: () {
          widget.onActionTriggered?.call();
          try {
            context.push('/tax-compliance');
          } catch (_) {}
        },
      );
    }

    // 3. Check quarterly tax deadline proximity (< 30 days)
    final isDeadlineNear = taxCalc.daysUntilDeadline <= 30 && taxCalc.lockedTaxShield > 0;
    if (isDeadlineNear && !_dismissedKeys.contains('tax_deadline_${taxCalc.currentQuarter}')) {
      final isUrgent = taxCalc.daysUntilDeadline <= 14;
      final accent = isUrgent ? const Color(0xFFEF4444) : const Color(0xFFF59E0B);
      final bg = isUrgent
          ? const Color(0xFF7F1D1D).withValues(alpha: 0.35)
          : const Color(0xFF78350F).withValues(alpha: 0.35);

      return _buildBannerCard(
        keyString: 'tax_deadline_${taxCalc.currentQuarter}',
        type: InterruptionType.quarterlyTaxDeadline,
        badge: 'Q${taxCalc.currentQuarter} ESTIMATED TAX DUE IN ${taxCalc.daysUntilDeadline} DAYS',
        message: 'Statutory reserve: ${currencyFmt.format(taxCalc.lockedTaxShield)} to satisfy Safe Harbor & avoid IRS §6654 penalty.',
        actionLabel: 'Lock ${currencyFmt.format(taxCalc.lockedTaxShield)} Reserve',
        accentColor: accent,
        backgroundColor: bg,
        borderColor: accent,
        icon: Icons.shield_outlined,
        onAction: () {
          widget.onActionTriggered?.call();
          try {
            context.push('/tax-compliance');
          } catch (_) {}
        },
      );
    }

    // No active high-priority interruption
    return const SizedBox.shrink();
  }

  Widget _buildBannerCard({
    required String keyString,
    required InterruptionType type,
    required String badge,
    required String message,
    required String actionLabel,
    required Color accentColor,
    required Color backgroundColor,
    required Color borderColor,
    required IconData icon,
    required VoidCallback onAction,
  }) {
    return Dismissible(
      key: Key(keyString),
      direction: DismissDirection.horizontal,
      onDismissed: (_) {
        setState(() {
          _dismissedKeys.add(keyString);
        });
      },
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.archive_outlined, color: Colors.white70, size: 20),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.archive_outlined, color: Colors.white70, size: 20),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor.withValues(alpha: 0.5), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: accentColor.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: accentColor, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    badge,
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: accentColor,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    message,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor: const Color(0xFF0F172A),
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: onAction,
              child: Text(
                actionLabel,
                style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.close, size: 16, color: Color(0xFF94A3B8)),
              onPressed: () {
                setState(() {
                  _dismissedKeys.add(keyString);
                });
              },
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ),
    );
  }
}
