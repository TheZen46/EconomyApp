import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../domain/entities/receipt.dart';
import 'monthly_runway_widget.dart';

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
    return MonthlyRunwayWidget(
      receipts: receipts,
      isDark: isDark,
    );
  }
}
