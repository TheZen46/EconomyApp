import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../domain/entities/receipt.dart';
import '../../providers/receipt_provider.dart';
import '../../../../boxes/data/providers/boxes_provider.dart';
import '../../../../../core/constants/app_constants.dart';
import '../interactive_hover.dart';

/// Widget that computes and visualizes the user's monthly runway and cash flow health.
///
/// Calculates real burn rate from current month's receipts, factors in liquid
/// balances and projected recurring incomes, and enables interactive scenario forecasting.
class MonthlyRunwayWidget extends ConsumerWidget {
  /// The collection of receipts used to compute burn metrics.
  final List<Receipt> receipts;

  /// Whether the UI is currently rendered in dark mode.
  final bool isDark;

  /// Creates a new [MonthlyRunwayWidget] instance.
  const MonthlyRunwayWidget({
    super.key,
    required this.receipts,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isPrivacy = ref.watch(privacyModeProvider);

    final now = DateTime.now();
    final monthlyBurn = receipts
        .where((r) => r.date.year == now.year && r.date.month == now.month)
        .fold(0.0, (sum, r) => sum + r.totalAmount);
        
    final boxes = ref.watch(boxesProvider);
    final currentBalance = ref.watch(currentBalanceProvider);
    final projectedIncome = ref.watch(projectedIncomeProvider);
    
    // Use user-provided balance if available, otherwise sum remaining box budgets
    final double effectiveBalance = currentBalance > 0 
        ? currentBalance 
        : boxes.fold(0.0, (sum, b) => sum + (b.budget - b.spent));
    
    // Add projected income to runway calculation if monthly burn > income
    final double netBurn = monthlyBurn - projectedIncome;
    final double runwayMonths = netBurn > 0 ? (effectiveBalance / netBurn) : 99.9; // If income >= burn, runway is infinite
    
    final fgCol = colorScheme.onSurface;
    final muted = colorScheme.onSurfaceVariant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'MONTHLY RUNWAY',
              style: GoogleFonts.spaceGrotesk(fontSize: 11, letterSpacing: 1.2, color: muted),
            ),
            IconButton(
              icon: Icon(Icons.edit, size: 14, color: muted),
              onPressed: () => _showRunwaySettingsSheet(context, ref),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: runwayMonths > 99 ? 99.9 : runwayMonths),
          duration: 1.seconds,
          curve: Curves.easeOut,
          builder: (context, val, child) {
            String display = monthlyBurn <= 0 ? '--' : val.toStringAsFixed(1);
            if (val >= 99.9) display = '99+';
            return Text(
              display,
              style: GoogleFonts.jetBrainsMono(fontSize: 48, fontWeight: FontWeight.bold, color: fgCol),
            );
          },
        ),
        const SizedBox(height: 24),
        _hoverRow('Calculated Monthly Burn', AppConstants.formatAmount(monthlyBurn, isPrivacy: isPrivacy), fgCol, muted),
        const SizedBox(height: 8),
        _hoverRow('Projected Income', AppConstants.formatAmount(projectedIncome, isPrivacy: isPrivacy), fgCol, muted),
        const SizedBox(height: 8),
        _hoverRow('Current Balance', AppConstants.formatAmount(effectiveBalance, isPrivacy: isPrivacy), fgCol, muted),
        const SizedBox(height: 24),
        InteractiveHover(
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: fgCol,
                side: BorderSide(color: colorScheme.outline),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: () => _showForecastDialog(
                context,
                monthlyBurn: monthlyBurn,
                projectedIncome: projectedIncome,
                effectiveBalance: effectiveBalance,
                netBurn: netBurn,
                runwayMonths: runwayMonths,
                isPrivacy: isPrivacy,
              ),
              child: Text('Generate Forecast', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w600)),
            ),
          ),
        )
      ],
    );
  }

  Widget _hoverRow(String label, String value, Color fgCol, Color muted) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: GoogleFonts.spaceGrotesk(color: muted)),
        Text(value, style: GoogleFonts.jetBrainsMono(color: fgCol, fontWeight: FontWeight.w500)),
      ],
    );
  }

  void _showForecastDialog(
    BuildContext context, {
    required double monthlyBurn,
    required double projectedIncome,
    required double effectiveBalance,
    required double netBurn,
    required double runwayMonths,
    bool isPrivacy = false,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final fgCol = colorScheme.onSurface;
    final muted = colorScheme.onSurfaceVariant;

    final double netMonthlyCashflow = projectedIncome - monthlyBurn;
    final double balance3M = effectiveBalance + (netMonthlyCashflow * 3);
    final double balance6M = effectiveBalance + (netMonthlyCashflow * 6);
    final double balance12M = effectiveBalance + (netMonthlyCashflow * 12);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.auto_graph_rounded, color: colorScheme.primary, size: 22),
            const SizedBox(width: 10),
            Text(
              'Liquidity & Burn Forecast',
              style: GoogleFonts.spaceGrotesk(fontSize: 18, fontWeight: FontWeight.bold, color: fgCol),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: netMonthlyCashflow >= 0
                      ? colorScheme.primary.withValues(alpha: 0.1)
                      : colorScheme.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: netMonthlyCashflow >= 0
                      ? colorScheme.primary.withValues(alpha: 0.3)
                      : colorScheme.error.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      netMonthlyCashflow >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                      color: netMonthlyCashflow >= 0 ? colorScheme.primary : colorScheme.error,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        netMonthlyCashflow >= 0
                            ? 'Net Positive Cashflow (+ ${AppConstants.formatAmount(netMonthlyCashflow, isPrivacy: isPrivacy)}/mo)'
                            : 'Deficit Burn Rate (- ${AppConstants.formatAmount(-netMonthlyCashflow, isPrivacy: isPrivacy)}/mo)',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: fgCol,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'PROJECTED LIQUIDITY BALANCES',
                style: GoogleFonts.spaceGrotesk(fontSize: 10, letterSpacing: 1.2, color: muted, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              _buildForecastRow('3-Month Horizon', balance3M, colorScheme, isPrivacy: isPrivacy),
              const Divider(height: 16),
              _buildForecastRow('6-Month Horizon', balance6M, colorScheme, isPrivacy: isPrivacy),
              const Divider(height: 16),
              _buildForecastRow('12-Month Horizon', balance12M, colorScheme, isPrivacy: isPrivacy),
              const SizedBox(height: 16),
              Text(
                runwayMonths >= 99.9
                    ? 'At current rates, liquidity is self-sustaining indefinitely.'
                    : 'Estimated depletion runway: ${runwayMonths.toStringAsFixed(1)} months remaining.',
                style: GoogleFonts.spaceGrotesk(fontSize: 12, color: muted, fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Close', style: GoogleFonts.spaceGrotesk(color: colorScheme.primary, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildForecastRow(String horizon, double balance, ColorScheme colorScheme, {bool isPrivacy = false}) {
    final bool isPositive = balance >= 0;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(horizon, style: GoogleFonts.spaceGrotesk(fontSize: 13, color: colorScheme.onSurfaceVariant)),
        Text(
          AppConstants.formatAmount(balance, isPrivacy: isPrivacy),
          style: GoogleFonts.jetBrainsMono(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: isPositive ? colorScheme.onSurface : colorScheme.error,
          ),
        ),
      ],
    );
  }

  void _showRunwaySettingsSheet(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final fgCol = colorScheme.onSurface;
    final muted = colorScheme.onSurfaceVariant;
    final bgCol = colorScheme.surface;
    
    double currentBalance = ref.read(currentBalanceProvider);
    double projectedIncome = ref.read(projectedIncomeProvider);

    showModalBottomSheet(
      context: context,
      backgroundColor: bgCol,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 24, right: 24, top: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Monthly Runway Settings', style: GoogleFonts.spaceGrotesk(fontSize: 20, fontWeight: FontWeight.bold, color: fgCol)),
              const SizedBox(height: 24),
              TextFormField(
                initialValue: currentBalance == 0 ? '' : currentBalance.toStringAsFixed(2),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: TextStyle(color: fgCol),
                decoration: InputDecoration(
                  labelText: 'Current Liquid Balance (\$)',
                  labelStyle: TextStyle(color: muted),
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: colorScheme.outline)),
                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: colorScheme.primary)),
                ),
                onChanged: (v) => currentBalance = double.tryParse(v) ?? 0.0,
              ),
              const SizedBox(height: 16),
              TextFormField(
                initialValue: projectedIncome == 0 ? '' : projectedIncome.toStringAsFixed(2),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: TextStyle(color: fgCol),
                decoration: InputDecoration(
                  labelText: 'Projected Monthly Income (\$)',
                  labelStyle: TextStyle(color: muted),
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: colorScheme.outline)),
                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: colorScheme.primary)),
                ),
                onChanged: (v) => projectedIncome = double.tryParse(v) ?? 0.0,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: colorScheme.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  onPressed: () {
                    ref.read(currentBalanceProvider.notifier).setBalance(currentBalance);
                    ref.read(projectedIncomeProvider.notifier).setIncome(projectedIncome);
                    Navigator.pop(ctx);
                  },
                  child: Text('Save Settings', style: GoogleFonts.spaceGrotesk(color: colorScheme.onPrimary, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }
}
