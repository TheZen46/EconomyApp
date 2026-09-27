import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../domain/entities/receipt.dart';
import '../../../data/models/dashboard_config.dart';
import '../../providers/dashboard_provider.dart';
import '../../providers/receipt_provider.dart';
import '../../../../boxes/data/providers/boxes_provider.dart';
import '../../../../boxes/data/models/box_model.dart';
import '../../../../../core/constants/app_constants.dart';
import '../interactive_hover.dart';
import 'dashboard_summary_card.dart';
import 'pulse_widget.dart';
import 'density_heatmap_widget.dart';
import 'recent_receipts_list.dart';
import 'the_tax_nest_widget.dart';
import 'achievements_milestones_widget.dart';
import 'needs_vs_wants_widget.dart';
import 'project_cards_widget.dart';

/// Customizable grid layout for displaying modular dashboard widgets.
///
/// Supports dynamic reordering, column span adjustments, widget visibility toggling,
/// and responsive reflow across mobile, tablet, and desktop breakpoints.
class CustomizableMetricsGrid extends ConsumerStatefulWidget {
  /// All user receipts passed down for aggregation and metrics computation.
  final List<Receipt> receipts;

  /// Whether the UI is currently rendered in dark mode.
  final bool isDark;

  /// Whether the grid is in customization / edit mode.
  final bool isEditMode;

  /// Active search query filter applied to receipts.
  final String searchQuery;

  /// Creates a new [CustomizableMetricsGrid] instance.
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
          child: Wrap(
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
        return AchievementsMilestonesWidget(receipts: widget.receipts, isDark: widget.isDark);
      case DashboardWidgetType.necessityBreakdown:
        return NeedsVsWantsWidget(receipts: widget.receipts, isDark: widget.isDark);
      case DashboardWidgetType.recentTransactions:
        return RecentReceiptsList(receipts: filteredReceipts, isDark: widget.isDark);
      case DashboardWidgetType.taxNest:
        return TheTaxNestWidget(receipts: widget.receipts, isDark: widget.isDark);
      case DashboardWidgetType.projects:
        return ProjectCardsWidget(isDark: widget.isDark);
    }
  }

  Widget _buildBoxes(List<Receipt> receipts) {
    final colorScheme = Theme.of(context).colorScheme;
    final fgCol = colorScheme.onSurface;
    final activeId = ref.watch(activeBoxIdProvider);
    final boxes = ref.watch(boxesProvider);
    final monthlyBudget = ref.watch(monthlyBudgetProvider);
    final isPrivacy = ref.watch(privacyModeProvider);

    String boxName = 'Out of the Box';
    double spent = 0.0;
    double budget = 0.0;

    if (activeId == 'main') {
      spent = receipts.fold(0.0, (sum, r) => sum + r.totalAmount);
      budget = monthlyBudget;
    } else {
      final box = boxes.firstWhere(
        (b) => b.id == activeId,
        orElse: () => boxes.isNotEmpty
            ? boxes.first
            : BoxModel(id: 'main', name: 'Main', budget: 0, spent: 0, currency: 'USD', color: 0),
      );
      boxName = box.name;
      final receiptsSum = receipts.fold(0.0, (sum, r) => sum + r.totalAmount);
      spent = receiptsSum > 0 ? receiptsSum : box.spent;
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
          Text('${AppConstants.formatAmount(spent, isPrivacy: isPrivacy)} spent', style: GoogleFonts.jetBrainsMono(fontSize: 14, color: colorScheme.onSurfaceVariant)),
          if (budget > 0) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: budget > 0 ? (spent / budget).clamp(0.0, 1.0) : 0.0,
              backgroundColor: colorScheme.outline,
              valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
              borderRadius: BorderRadius.circular(4),
            ),
          ]
        ],
      ),
    );
  }
}
