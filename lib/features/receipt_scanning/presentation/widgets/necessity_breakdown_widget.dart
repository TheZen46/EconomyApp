// ignore_for_file: deprecated_member_use, deprecated_member_use_from_same_package, unused_local_variable, unnecessary_underscores, invalid_annotation_target, unused_element, non_constant_identifier_names, use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/receipt.dart';
import '../providers/receipt_provider.dart';

class NecessityBreakdownWidget extends ConsumerWidget {
  const NecessityBreakdownWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receiptsAsync = ref.watch(receiptListProvider);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withAlpha(12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(51),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: receiptsAsync.when(
        data: (receipts) => _buildContent(context, receipts),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const SizedBox(),
      ),
    );
  }

  Widget _buildContent(BuildContext context, List<Receipt> receipts) {
    // Filter for current month
    final now = DateTime.now();
    final currentMonthReceipts = receipts.where((r) => 
      r.date.year == now.year && r.date.month == now.month
    ).toList();

    double total = 0;
    double essential = 0;
    double discretional = 0;
    double junk = 0;
    double unknown = 0;

    for (var r in currentMonthReceipts) {
      for (var item in r.items) {
        total += item.totalPrice;
        switch (item.necessity) {
          case ItemNecessity.essential: essential += item.totalPrice; break;
          case ItemNecessity.discretional: discretional += item.totalPrice; break;
          case ItemNecessity.junk: junk += item.totalPrice; break;
          case ItemNecessity.unknown: unknown += item.totalPrice; break;
        }
      }
    }

    if (total == 0) {
      return const Center(
        child: Text('No spending this month yet.', style: TextStyle(color: AppTheme.textDim)),
      );
    }

    final essentialPct = (essential / total);
    final discretionalPct = (discretional / total);
    final junkPct = (junk / total);
    final unknownPct = (unknown / total);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Financial Health', style: TextStyle(color: AppTheme.textMain, fontWeight: FontWeight.bold, fontSize: 16)),
            Text(DateFormat('MMMM').format(now), style: const TextStyle(color: AppTheme.textDim, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 16),
        
        // Multi-colored Bar
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 12,
            child: Row(
              children: [
                if (essentialPct > 0) Expanded(flex: (essentialPct * 100).round(), child: Container(color: Colors.greenAccent)),
                if (discretionalPct > 0) Expanded(flex: (discretionalPct * 100).round(), child: Container(color: Colors.amberAccent)),
                if (junkPct > 0) Expanded(flex: (junkPct * 100).round(), child: Container(color: Colors.redAccent)),
                if (unknownPct > 0) Expanded(flex: (unknownPct * 100).round(), child: Container(color: Colors.grey)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Legend / Stats
        _buildLegendItem('Essential', essential, essentialPct, Colors.greenAccent),
        const SizedBox(height: 8),
        _buildLegendItem('Discretional', discretional, discretionalPct, Colors.amberAccent),
        const SizedBox(height: 8),
        _buildLegendItem('Junk', junk, junkPct, Colors.redAccent),
        if (unknown > 0) ...[
          const SizedBox(height: 8),
          _buildLegendItem('Uncategorized', unknown, unknownPct, Colors.grey),
        ],

        if (junkPct > 0.2) ...[
           const SizedBox(height: 16),
           Container(
             padding: const EdgeInsets.all(8),
             decoration: BoxDecoration(
               color: AppTheme.error.withAlpha(25),
               borderRadius: BorderRadius.circular(8),
               border: Border.all(color: AppTheme.error.withAlpha(76)),
             ),
             child: Row(
               children: [
                 const Icon(Icons.warning_amber_rounded, color: AppTheme.error, size: 16),
                 const SizedBox(width: 8),
                 Expanded(child: Text('High Junk spending! (${(junkPct*100).toStringAsFixed(0)}%)', style: const TextStyle(color: AppTheme.error, fontSize: 12))),
               ],
             ),
           )
        ]
      ],
    );
  }

  Widget _buildLegendItem(String label, double amount, double pct, Color color) {
    return Row(
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: const TextStyle(color: AppTheme.textDim, fontSize: 13))),
        Text('${(pct * 100).toStringAsFixed(0)}% ', style: const TextStyle(color: AppTheme.textMain, fontWeight: FontWeight.bold, fontSize: 13)),
        Text('(${NumberFormat.currency(symbol: '€', decimalDigits: 0).format(amount)})', style: const TextStyle(color: AppTheme.textDim, fontSize: 13)),
      ],
    );
  }
}
