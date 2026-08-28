import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../domain/entities/receipt.dart';
import '../../providers/receipt_provider.dart';
import '../../../../boxes/data/providers/boxes_provider.dart';
import '../interactive_hover.dart';

class MonthlyRunwayWidget extends ConsumerWidget {
  final List<Receipt> receipts;
  final bool isDark;

  const MonthlyRunwayWidget({
    super.key,
    required this.receipts,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final now = DateTime.now();
    final monthlyBurn = receipts
        .where((r) => r.date.year == now.year && r.date.month == now.month)
        .fold(0.0, (sum, r) => sum + r.totalAmount);
        
    final boxes = ref.watch(boxesProvider);
    final currentBalance = ref.watch(currentBalanceProvider);
    final projectedIncome = ref.watch(projectedIncomeProvider);
    
    // Use user-provided balance if available, otherwise sum remaining box budgets
    double effectiveBalance = currentBalance > 0 
        ? currentBalance 
        : boxes.fold(0.0, (sum, b) => sum + (b.budget - b.spent));
    
    // Add projected income to runway calculation if monthly burn > income
    double netBurn = monthlyBurn - projectedIncome;
    final runwayMonths = netBurn > 0 ? (effectiveBalance / netBurn) : 99.9; // If income > burn, runway is infinite
    
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
        _hoverRow('Calculated Monthly Burn', '\$${monthlyBurn.toStringAsFixed(2)}', fgCol, muted),
        const SizedBox(height: 8),
        _hoverRow('Projected Income', '\$${projectedIncome.toStringAsFixed(2)}', fgCol, muted),
        const SizedBox(height: 8),
        _hoverRow('Current Balance', '\$${effectiveBalance.toStringAsFixed(2)}', fgCol, muted),
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
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Generating forecast...')));
              },
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
