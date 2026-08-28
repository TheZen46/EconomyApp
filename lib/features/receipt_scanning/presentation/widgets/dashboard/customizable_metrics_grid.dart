import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../../domain/entities/receipt.dart';
import '../../../data/models/dashboard_config.dart';
import '../../providers/dashboard_provider.dart';
import '../../../../boxes/data/providers/boxes_provider.dart';
import '../../../../boxes/data/models/box_model.dart';
import '../../../../invoices/data/providers/invoices_provider.dart';
import '../interactive_hover.dart';
import 'gamification_header.dart';
import 'dashboard_summary_card.dart';
import 'pulse_widget.dart';
import 'density_heatmap_widget.dart';
import 'recent_receipts_list.dart';

class CustomizableMetricsGrid extends ConsumerStatefulWidget {
  final List<Receipt> receipts;
  final bool isDark;
  final bool isEditMode;
  final String searchQuery;

  const CustomizableMetricsGrid({
    super.key,
    required this.receipts,
    required this.isDark,
    required this.isEditMode,
    this.searchQuery = '',
  });

  @override
  ConsumerState<CustomizableMetricsGrid> createState() => _CustomizableMetricsGridState();
}

class _CustomizableMetricsGridState extends ConsumerState<CustomizableMetricsGrid> {
  bool _showNeedsAmounts = false;

  final Map<DashboardWidgetType, int> _widgetSpans = {
    DashboardWidgetType.summary: 2,
    DashboardWidgetType.chart: 3,
    DashboardWidgetType.monthlyBudget: 1,
    DashboardWidgetType.heatmap: 1,
    DashboardWidgetType.achievements: 1,
    DashboardWidgetType.necessityBreakdown: 1,
    DashboardWidgetType.recentTransactions: 3,
    DashboardWidgetType.taxNest: 1,
    DashboardWidgetType.projects: 3,
  };

  @override
  Widget build(BuildContext context) {
    final dashboardItems = ref.watch(dashboardProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Filter receipts by search query
    final query = widget.searchQuery.toLowerCase();
    final filteredReceipts = widget.receipts.where((r) {
      return query.isEmpty || r.merchantName.toLowerCase().contains(query);
    }).toList();

    // Ensure boxes widget exists in dashboard items
    final allItems = List<DashboardItem>.from(dashboardItems);
    if (!allItems.any((i) => i.type == DashboardWidgetType.monthlyBudget)) {
      allItems.insert(0, DashboardItem(id: 'boxes', type: DashboardWidgetType.monthlyBudget, title: 'Boxes', isVisible: true));
    }

    if (widget.isEditMode) {
      return _buildEditMode(context, allItems, dashboardItems, filteredReceipts, colorScheme);
    }

    return _buildNormalGrid(context, allItems, filteredReceipts);
  }

  Widget _buildEditMode(
    BuildContext context,
    List<DashboardItem> allItems,
    List<DashboardItem> dashboardItems,
    List<Receipt> filteredReceipts,
    ColorScheme colorScheme,
  ) {
    final visibleItems = allItems.where((i) => i.isVisible).toList();
    final hiddenItems = allItems.where((i) => !i.isVisible).toList();

    return Column(
      children: [
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            itemCount: visibleItems.length,
            onReorder: (oldIndex, newIndex) {
              int realOld = dashboardItems.indexOf(visibleItems[oldIndex]);
              int realNew = newIndex >= visibleItems.length
                  ? dashboardItems.indexOf(visibleItems.last) + 1
                  : dashboardItems.indexOf(visibleItems[newIndex]);
              ref.read(dashboardProvider.notifier).reorder(realOld, realNew);
            },
            itemBuilder: (ctx, i) {
              final item = visibleItems[i];
              return _buildEditModeCard(item, filteredReceipts, colorScheme);
            },
          ),
        ),
        if (hiddenItems.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            color: colorScheme.surfaceContainer,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hidden Widgets',
                  style: GoogleFonts.spaceGrotesk(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: hiddenItems.map((item) {
                    return ActionChip(
                      avatar: const Icon(Icons.add, size: 16),
                      label: Text(item.title, style: GoogleFonts.spaceGrotesk()),
                      onPressed: () {
                        final idx = dashboardItems.indexOf(item);
                        ref.read(dashboardProvider.notifier).toggleVisibility(idx);
                      },
                    );
                  }).toList(),
                )
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildEditModeCard(
    DashboardItem item,
    List<Receipt> filteredReceipts,
    ColorScheme colorScheme,
  ) {
    final accent = colorScheme.primary;

    return Container(
      key: ValueKey(item.id),
      margin: const EdgeInsets.only(bottom: 24),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          IgnorePointer(
            child: Container(
              margin: const EdgeInsets.only(left: 48),
              child: HoverCardWrapper(
                isDark: widget.isDark,
                child: _buildWidgetContent(item, filteredReceipts),
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 40,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Icon(Icons.drag_indicator, color: colorScheme.onSurfaceVariant),
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 56,
            child: Container(
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colorScheme.outline),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4))
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [1, 2, 3].map((size) {
                  final currentSize = _widgetSpans[item.type] ?? 1;
                  final isSelected = currentSize == size;
                  return GestureDetector(
                    onTap: () => setState(() => _widgetSpans[item.type] = size),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: isSelected ? accent : Colors.transparent,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$size',
                        style: GoogleFonts.jetBrainsMono(
                          color: isSelected ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: GestureDetector(
              onTap: () {
                final idx = ref.read(dashboardProvider).indexOf(item);
                ref.read(dashboardProvider.notifier).toggleVisibility(idx);
              },
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: colorScheme.error,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4))
                  ],
                ),
                alignment: Alignment.center,
                child: Icon(Icons.remove, color: colorScheme.onError, size: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNormalGrid(
    BuildContext context,
    List<DashboardItem> allItems,
    List<Receipt> filteredReceipts,
  ) {
    final visibleItems = allItems.where((i) => i.isVisible).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final maxCols = width >= 900 ? 3 : (width >= 600 ? 2 : 1);
        const double gap = 16.0;
        const double pad = 24.0;
        final availableWidth = width - (pad * 2);
        final colWidth = (availableWidth - (gap * (maxCols - 1))) / maxCols;

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(pad, pad, pad, 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GamificationHeader(
                receipts: widget.receipts,
                isDark: widget.isDark,
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: gap,
                runSpacing: gap,
                children: visibleItems.map((item) {
                  int span = _widgetSpans[item.type] ?? 1;
                  if (span > maxCols) span = maxCols;
                  double itemWidth = (colWidth * span) + (gap * (span - 1));

                  return SizedBox(
                    width: itemWidth,
                    child: HoverCardWrapper(
                      isDark: widget.isDark,
                      child: _buildWidgetContent(item, filteredReceipts),
                    ).animate().fadeIn().slideY(begin: 0.1, curve: Curves.easeOut),
                  );
                }).toList(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildWidgetContent(DashboardItem item, List<Receipt> filteredReceipts) {
    switch (item.type) {
      case DashboardWidgetType.summary:
        return DashboardSummaryCard(receipts: widget.receipts, isDark: widget.isDark);
      case DashboardWidgetType.chart:
        return PulseWidget(receipts: widget.receipts, isDark: widget.isDark);
      case DashboardWidgetType.monthlyBudget:
        return _buildBoxes(widget.receipts);
      case DashboardWidgetType.heatmap:
        return DensityHeatmapWidget(receipts: widget.receipts, isDark: widget.isDark);
      case DashboardWidgetType.achievements:
        return _buildAchievements(widget.receipts);
      case DashboardWidgetType.necessityBreakdown:
        return _buildNeedsVsWants(widget.receipts);
      case DashboardWidgetType.recentTransactions:
        return RecentReceiptsList(receipts: filteredReceipts, isDark: widget.isDark);
      case DashboardWidgetType.taxNest:
        return _buildTaxNest(widget.receipts);
      case DashboardWidgetType.projects:
        return _buildProjectCards();
    }
  }

  Widget _buildBoxes(List<Receipt> receipts) {
    final colorScheme = Theme.of(context).colorScheme;
    final fgCol = colorScheme.onSurface;
    final activeId = ref.watch(activeBoxIdProvider);
    final boxes = ref.watch(boxesProvider);

    String boxName = 'Out of the Box';
    double spent = 0.0;
    double budget = 0.0;

    if (activeId == 'main') {
      spent = receipts.fold(0.0, (sum, r) => sum + r.totalAmount);
    } else {
      final box = boxes.firstWhere(
        (b) => b.id == activeId,
        orElse: () => boxes.isNotEmpty
            ? boxes.first
            : BoxModel(id: 'main', name: 'Main', budget: 0, spent: 0, currency: 'USD', color: 0),
      );
      boxName = box.name;
      spent = box.spent;
      budget = box.budget;
    }

    return GestureDetector(
      onTap: () => context.push('/boxes'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'NEW',
                  style: GoogleFonts.spaceGrotesk(
                    color: colorScheme.onPrimary,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Icon(Icons.arrow_forward_ios, size: 14, color: colorScheme.onSurfaceVariant),
            ],
          ),
          const SizedBox(height: 16),
          Text(boxName, style: GoogleFonts.spaceGrotesk(fontSize: 16, fontWeight: FontWeight.w600, color: fgCol)),
          const SizedBox(height: 8),
          Text('\$${spent.toStringAsFixed(2)} spent', style: GoogleFonts.jetBrainsMono(fontSize: 14, color: colorScheme.onSurfaceVariant)),
          if (budget > 0) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: (spent / budget).clamp(0.0, 1.0),
              backgroundColor: colorScheme.outline,
              valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
              borderRadius: BorderRadius.circular(4),
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildAchievements(List<Receipt> receipts) {
    final colorScheme = Theme.of(context).colorScheme;
    final fgCol = colorScheme.onSurface;
    final muted = colorScheme.onSurfaceVariant;
    final accent = colorScheme.primary;

    final now = DateTime.now();
    final monthlyBurn = receipts.where((r) => r.date.year == now.year && r.date.month == now.month).fold(0.0, (sum, r) => sum + r.totalAmount);
    final boxes = ref.watch(boxesProvider);
    final activeId = ref.watch(activeBoxIdProvider);
    final activeBox = activeId == 'main' || boxes.isEmpty
        ? (boxes.isNotEmpty ? boxes.first : BoxModel(id: 'main', name: 'Main', budget: 0, spent: 0, currency: 'USD', color: 0))
        : boxes.firstWhere((b) => b.id == activeId, orElse: () => boxes.isNotEmpty ? boxes.first : BoxModel(id: 'main', name: 'Main', budget: 0, spent: 0, currency: 'USD', color: 0));

    final ytdTotal = receipts.fold(0.0, (sum, r) => sum + r.totalAmount);
    final stashed = ytdTotal * 0.22;

    final hasReceipts = receipts.isNotEmpty;
    final isUnderBudget = (monthlyBurn < activeBox.budget) && (activeBox.budget > 0);
    final hasStash = stashed > 0;

    final achievements = [
      {'title': 'First Scan', 'status': hasReceipts ? 'Achieved' : 'Pending', 'date': hasReceipts ? DateFormat('dd MMM').format(receipts.last.date) : '--', 'active': hasReceipts},
      {'title': 'Under Budget', 'status': isUnderBudget ? 'Achieved' : 'In Progress', 'date': isUnderBudget ? DateFormat('MMM yyyy').format(now) : '--', 'active': isUnderBudget},
      {'title': 'Tax Prep Started', 'status': hasStash ? 'Achieved' : 'Pending', 'date': hasStash ? DateFormat('dd MMM').format(now) : '--', 'active': hasStash},
    ];
    final achievedCount = achievements.where((a) => a['active'] == true).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('MILESTONES', style: GoogleFonts.spaceGrotesk(fontSize: 11, letterSpacing: 1.2, color: muted)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text('$achievedCount/3', style: GoogleFonts.jetBrainsMono(fontSize: 11, color: muted)),
            ),
          ],
        ),
        const SizedBox(height: 24),
        ...achievements.map((a) {
          final active = a['active'] as bool;
          return Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 12,
                  decoration: BoxDecoration(
                    color: active ? accent : colorScheme.outline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(a['title'] as String, style: GoogleFonts.spaceGrotesk(fontSize: 13, fontWeight: FontWeight.w400, color: fgCol)),
                      const SizedBox(height: 2),
                      Text(a['status'] as String, style: GoogleFonts.spaceGrotesk(fontSize: 11, color: muted)),
                    ],
                  ),
                ),
                Text(a['date'] as String, style: GoogleFonts.jetBrainsMono(fontSize: 12, color: muted)),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildNeedsVsWants(List<Receipt> receipts) {
    final colorScheme = Theme.of(context).colorScheme;
    final fgCol = colorScheme.onSurface;
    final muted = colorScheme.onSurfaceVariant;
    final accent = colorScheme.primary;

    final needsTotal = receipts.fold(0.0, (sum, r) => sum + r.essentialTotal);
    final wantsTotal = receipts.fold(0.0, (sum, r) => sum + (r.totalAmount - r.essentialTotal));
    final total = needsTotal + wantsTotal;

    final needsPercent = total > 0 ? (needsTotal / total * 100).round() : 0;
    final wantsPercent = total > 0 ? (wantsTotal / total * 100).round() : 0;

    final needsFlex = total > 0 ? (needsTotal / total * 100).round() : 50;
    final wantsFlex = total > 0 ? (wantsTotal / total * 100).round() : 50;

    final int safeNeedsFlex = needsFlex > 0 ? needsFlex : 1;
    final int safeWantsFlex = wantsFlex > 0 ? wantsFlex : 1;

    return InteractiveHover(
      onTap: () => setState(() => _showNeedsAmounts = !_showNeedsAmounts),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('NEEDS VS WANTS', style: GoogleFonts.spaceGrotesk(fontSize: 11, letterSpacing: 1.2, color: muted)),
          const SizedBox(height: 24),
          ClipRRect(
            borderRadius: BorderRadius.circular(100),
            child: Row(
              children: [
                if (needsFlex > 0) Expanded(flex: safeNeedsFlex, child: Container(height: 16, color: accent)),
                if (needsFlex > 0 && wantsFlex > 0) const SizedBox(width: 8),
                if (wantsFlex > 0) Expanded(flex: safeWantsFlex, child: Container(height: 16, color: colorScheme.surfaceContainerHighest)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 40,
            child: AnimatedCrossFade(
              firstChild: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Needs: $needsPercent%', style: GoogleFonts.spaceGrotesk(fontSize: 12, color: muted)),
                  Text('Wants: $wantsPercent%', style: GoogleFonts.spaceGrotesk(fontSize: 12, color: muted)),
                ],
              ),
              secondChild: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('\$${needsTotal.toStringAsFixed(0)}', style: GoogleFonts.jetBrainsMono(fontSize: 12, color: fgCol)),
                  Text('\$${wantsTotal.toStringAsFixed(0)}', style: GoogleFonts.jetBrainsMono(fontSize: 12, color: fgCol)),
                ],
              ),
              crossFadeState: _showNeedsAmounts ? CrossFadeState.showSecond : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 300),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaxNest(List<Receipt> receipts) {
    final colorScheme = Theme.of(context).colorScheme;
    final fgCol = colorScheme.onSurface;
    final muted = colorScheme.onSurfaceVariant;
    final accent = colorScheme.primary;

    final ytdTotal = receipts.fold(0.0, (sum, r) => sum + r.totalAmount);
    final stashed = ytdTotal * 0.22;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.shield_outlined, color: accent, size: 16),
            const SizedBox(width: 8),
            Text('THE TAX NEST', style: GoogleFonts.spaceGrotesk(fontSize: 11, letterSpacing: 1.2, color: muted)),
          ],
        ),
        const SizedBox(height: 24),
        GestureDetector(
          onTap: () => ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Tax Nest Goal: \$12,000 (${(stashed / 12000 * 100).clamp(0, 100).toStringAsFixed(0)}% achieved)')),
          ),
          child: Text(
            '\$${stashed.toStringAsFixed(2)}',
            style: GoogleFonts.jetBrainsMono(fontSize: 40, fontWeight: FontWeight.w300, color: fgCol),
          ),
        ),
        const SizedBox(height: 4),
        Text('Stashed for Q2 ${DateTime.now().year}', style: GoogleFonts.spaceGrotesk(fontSize: 13, color: muted, fontWeight: FontWeight.w300)),
        const SizedBox(height: 24),
        SizedBox(
          height: 60,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              barTouchData: BarTouchData(enabled: false),
              titlesData: const FlTitlesData(show: false),
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              maxY: 10000,
              barGroups: List.generate(6, (i) {
                final values = [2400.0, 3200.0, 4100.0, 5800.0, 7200.0, 8950.0];
                return BarChartGroupData(x: i, barRods: [
                  BarChartRodData(
                    toY: values[i],
                    color: accent.withAlpha(51 + i * 30),
                    width: 8,
                    borderRadius: BorderRadius.circular(2),
                  )
                ]);
              }),
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: muted,
              side: BorderSide(color: colorScheme.outline),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Auto-stash configuration opened.')),
            ),
            child: Text('Auto-stash settings', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w400)),
          ),
        ),
      ],
    );
  }

  Widget _buildProjectCards() {
    final colorScheme = Theme.of(context).colorScheme;
    final fgCol = colorScheme.onSurface;
    final muted = colorScheme.onSurfaceVariant;
    final accent = colorScheme.primary;

    final invoices = ref.watch(invoicesProvider).take(4).toList();

    Color statusColor(String s) {
      switch (s.toLowerCase()) {
        case 'settled': return widget.isDark ? Colors.white70 : Colors.black87;
        case 'sent': return accent;
        case 'overdue': return colorScheme.error;
        default: return muted;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('ACTIVE INVOICES', style: GoogleFonts.spaceGrotesk(fontSize: 11, letterSpacing: 1.2, color: muted)),
            GestureDetector(
              onTap: () => context.push('/invoices'),
              child: Row(
                children: [
                  Text('View all', style: GoogleFonts.spaceGrotesk(fontSize: 11, color: muted, letterSpacing: 1.0)),
                  Icon(Icons.arrow_outward, size: 12, color: muted),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (invoices.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text('No active invoices', style: GoogleFonts.spaceGrotesk(color: muted)),
            ),
          )
        else
          ...invoices.map((inv) {
            final statusStr = inv.status;
            final status = statusStr.substring(0, 1).toUpperCase() + statusStr.substring(1);
            final amount = inv.amount;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      Container(
                        width: 3, height: 16,
                        decoration: BoxDecoration(color: statusColor(status), borderRadius: BorderRadius.circular(2)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Expanded(
                                child: Text(inv.clientName, style: GoogleFonts.spaceGrotesk(fontSize: 13, color: fgCol, fontWeight: FontWeight.w400)),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: statusColor(status).withAlpha(26),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(status, style: GoogleFonts.spaceGrotesk(fontSize: 10, color: statusColor(status), fontWeight: FontWeight.w500)),
                              ),
                            ]),
                            const SizedBox(height: 4),
                            Row(children: [
                              Text(inv.invoiceNumber, style: GoogleFonts.jetBrainsMono(fontSize: 11, color: muted)),
                              Container(
                                margin: const EdgeInsets.symmetric(horizontal: 6),
                                width: 3, height: 3,
                                decoration: BoxDecoration(shape: BoxShape.circle, color: muted),
                              ),
                              Text(DateFormat('MMM dd').format(inv.issuedDate), style: GoogleFonts.spaceGrotesk(fontSize: 11, color: muted)),
                            ]),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text('\$${amount.toStringAsFixed(2)}', style: GoogleFonts.jetBrainsMono(fontSize: 13, color: fgCol, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
                Divider(height: 1, color: colorScheme.outline),
              ],
            );
          }),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: muted,
              side: BorderSide(color: colorScheme.outline),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: () => context.push('/invoices'),
            child: Text('Create New Invoice', style: GoogleFonts.spaceGrotesk(fontSize: 12, letterSpacing: 1.0, fontWeight: FontWeight.w400)),
          ),
        ),
      ],
    );
  }
}
