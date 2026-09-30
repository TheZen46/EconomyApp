import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:t_aidy/features/receipt_scanning/domain/entities/receipt.dart';
import 'liquidity_cockpit_widget.dart';

class DashboardSummaryCard extends ConsumerWidget {
  final List<Receipt> receipts;
  final bool isDark;

  const DashboardSummaryCard({
    super.key,
    required this.receipts,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LiquidityCockpitWidget(
      receipts: receipts,
      isDark: isDark,
    );
  }
}



