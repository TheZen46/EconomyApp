// ignore_for_file: deprecated_member_use
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';

import '../providers/receipt_provider.dart';
import '../providers/category_provider.dart';
import '../providers/dashboard_provider.dart';
import '../../domain/entities/receipt.dart';
import '../../data/models/dashboard_config.dart';

import '../../../settings/presentation/providers/llm_provider.dart';
import '../../../settings/presentation/pages/settings_page.dart';
import '../../../boxes/data/providers/boxes_provider.dart';
import '../../../boxes/data/models/box_model.dart';
import '../../../invoices/data/providers/invoices_provider.dart';
import '../../../../core/theme/theme_notifier.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  bool _isEditMode = false;
  String? _selectedCategory;
  bool _showNeedsAmounts = false;

  final Map<DashboardWidgetType, int> _widgetSpans = {
    DashboardWidgetType.summary: 2,
    DashboardWidgetType.chart: 3,
    DashboardWidgetType.monthlyBudget: 1, // Mapped to Boxes
    DashboardWidgetType.heatmap: 1,
    DashboardWidgetType.achievements: 1,
    DashboardWidgetType.necessityBreakdown: 1,
    DashboardWidgetType.recentTransactions: 3,
    DashboardWidgetType.taxNest: 1,
    DashboardWidgetType.projects: 3,
  };

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeProvider);
    final isDark = themeMode == ThemeMode.dark;
    
    final receiptListAsync = ref.watch(receiptListProvider);
    final dashboardItems = ref.watch(dashboardProvider);
    
    final bgCol = isDark ? const Color(0xFF0A0A0A) : const Color(0xFFFFFFFF);
    final fgCol = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF1A1A1A);
    final accent = const Color(0xFF002FA7);

    return Scaffold(
      backgroundColor: bgCol,
      appBar: AppBar(
        backgroundColor: bgCol,
        elevation: 0,
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: GoogleFonts.spaceGrotesk(color: fgCol),
                decoration: InputDecoration(
                  hintText: 'Search merchant...',
                  hintStyle: GoogleFonts.spaceGrotesk(color: fgCol.withOpacity(0.5)),
                  border: InputBorder.none,
                ),
                onChanged: (_) => setState(() {}),
              ).animate().fadeIn().slideX(begin: 0.05)
            : Text(
                _isEditMode ? 'Edit Layout' : 'tAIdy',
                style: GoogleFonts.spaceGrotesk(
                  color: fgCol,
                  fontWeight: FontWeight.w500,
                  fontSize: 24,
                ),
              ),
        leading: _isSearching
            ? IconButton(
                icon: Icon(Icons.close, color: fgCol),
                onPressed: () {
                  setState(() {
                    _isSearching = false;
                    _searchController.clear();
                  });
                },
              )
            : null,
        actions: [
          if (_isEditMode) ...[
            TextButton.icon(
              onPressed: () {
                ref.read(dashboardProvider.notifier).reset();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Layout reset!')),
                );
              },
              icon: Icon(Icons.restore, color: fgCol),
              label: Text('Reset', style: GoogleFonts.spaceGrotesk(color: fgCol)),
            ),
            IconButton(
              icon: Icon(Icons.check_circle, color: accent),
              onPressed: () => setState(() => _isEditMode = false),
            ),
          ] else if (!_isSearching) ...[
            IconButton(
              icon: Icon(Icons.search, color: fgCol),
              onPressed: () => setState(() => _isSearching = true),
            ),
            IconButton(
              icon: Icon(Icons.shield_outlined, color: fgCol),
              onPressed: () => context.push('/vault'),
            ),
            IconButton(
              icon: Icon(Icons.dashboard_customize, color: fgCol),
              onPressed: () => setState(() => _isEditMode = true),
            ),
            IconButton(
              icon: Icon(Icons.visibility_off_outlined, color: fgCol),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Privacy mode toggled.')));
              },
            ),
            IconButton(
              icon: Icon(Icons.download, color: fgCol),
              onPressed: _exportCsv,
            ),
            IconButton(
              icon: Icon(Icons.settings, color: fgCol),
              onPressed: () => _showSettingsPanel(context),
            ),
          ] else ...[
            IconButton(
              icon: Icon(Icons.check, color: fgCol),
              onPressed: () => FocusManager.instance.primaryFocus?.unfocus(),
            ),
          ],
        ].animate(interval: 30.ms).fadeIn(duration: 200.ms).slideY(begin: 0.1, duration: 200.ms),
      ),
      body: receiptListAsync.when(
        data: (receipts) => _buildBody(context, receipts, dashboardItems, isDark),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err', style: TextStyle(color: fgCol))),
      ),
      bottomNavigationBar: _isEditMode ? null : _buildBottomNav(isDark, accent),
    );
  }

  Widget _buildBody(BuildContext context, List<Receipt> receipts, List<DashboardItem> dashboardItems, bool isDark) {
    // Filter logic
    final query = _searchController.text.toLowerCase();
    final filteredReceipts = receipts.where((r) {
      final matchCat = _selectedCategory == null || r.category.toLowerCase() == _selectedCategory!.toLowerCase();
      final matchSearch = query.isEmpty || r.merchantName.toLowerCase().contains(query);
      return matchCat && matchSearch;
    }).toList();

    // Inject Boxes widget if it's completely missing from config (as fallback)
    final allItems = List<DashboardItem>.from(dashboardItems);
    if (!allItems.any((i) => i.type == DashboardWidgetType.monthlyBudget)) {
      allItems.insert(0, DashboardItem(id: 'boxes', type: DashboardWidgetType.monthlyBudget, title: 'Boxes', isVisible: true));
    }

    if (_isEditMode) {
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
                return _buildEditModeCard(item, receipts, filteredReceipts, isDark);
              },
            ),
          ),
          if (hiddenItems.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              color: isDark ? const Color(0xFF151515) : const Color(0xFFF9F9F9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Hidden Widgets', style: GoogleFonts.spaceGrotesk(color: isDark ? Colors.white70 : Colors.black54, fontWeight: FontWeight.bold)),
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

    // Normal mode: Grid via Wrap
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
                child: _buildCardWrapper(
                  isDark: isDark,
                  child: _buildWidgetContent(item, receipts, filteredReceipts, isDark),
                ).animate().fadeIn().slideY(begin: 0.1, curve: Curves.easeOut),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Widget _buildEditModeCard(DashboardItem item, List<Receipt> receipts, List<Receipt> filteredReceipts, bool isDark) {
    final fgCol = isDark ? Colors.white : Colors.black;
    final accent = const Color(0xFF002FA7);
    
    return Container(
      key: ValueKey(item.id),
      margin: const EdgeInsets.only(bottom: 24),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Render the actual widget but disable interactions
          IgnorePointer(
            child: Container(
              margin: const EdgeInsets.only(left: 48),
              foregroundDecoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.1), width: 2),
              ),
              child: Opacity(
                opacity: 0.8,
                child: _buildCardWrapper(
                  isDark: isDark,
                  child: _buildWidgetContent(item, receipts, filteredReceipts, isDark),
                ),
              ),
            ),
          ),
          // Drag handle on the left
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Icon(Icons.drag_indicator, color: fgCol.withOpacity(0.2)),
              ),
            ),
          ),
          // Overlay controls (Size selector and Remove)
          Positioned(
            top: 8,
            right: 56,
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.1)),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4))
                ]
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [1, 2, 3].map((size) {
                  final currentSize = _widgetSpans[item.type] ?? 1;
                  final isSelected = currentSize == size;
                  return GestureDetector(
                    onTap: () {
                      setState(() => _widgetSpans[item.type] = size);
                    },
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: isSelected ? accent : Colors.transparent,
                      ),
                      alignment: Alignment.center,
                      child: Text('$size', style: GoogleFonts.jetBrainsMono(
                        color: isSelected ? Colors.white : fgCol.withOpacity(0.5),
                        fontSize: 12,
                      )),
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
                  color: const Color(0xFFEF4444),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4))
                  ]
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.remove, color: Colors.white, size: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardWrapper({required Widget child, required bool isDark}) {
    return HoverCardWrapper(isDark: isDark, child: child);
  }

  Widget _buildWidgetContent(DashboardItem item, List<Receipt> receipts, List<Receipt> filteredReceipts, bool isDark) {
    switch (item.type) {
      case DashboardWidgetType.summary:
        return _buildMonthlyRunway(receipts, isDark);
      case DashboardWidgetType.chart:
        return _buildThePulse(receipts, isDark);
      case DashboardWidgetType.monthlyBudget:
        return _buildBoxes(receipts, isDark);
      case DashboardWidgetType.heatmap:
        return _buildDensityHeatmap(receipts, isDark);
      case DashboardWidgetType.achievements:
        return _buildAchievements(receipts, isDark);
      case DashboardWidgetType.necessityBreakdown:
        return _buildNeedsVsWants(receipts, isDark);
      case DashboardWidgetType.recentTransactions:
        return _buildRecentTransactions(filteredReceipts, isDark);
      case DashboardWidgetType.taxNest:
        return _buildTaxNest(receipts, isDark);
      case DashboardWidgetType.projects:
        return _buildProjectCards(isDark);
    }
  }

  void _showRunwaySettingsSheet(BuildContext context, bool isDark) {
    final fgCol = isDark ? Colors.white : Colors.black;
    final bgCol = isDark ? const Color(0xFF151515) : Colors.white;
    
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
                  labelStyle: TextStyle(color: fgCol.withOpacity(0.5)),
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: fgCol.withOpacity(0.2))),
                  focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF002FA7))),
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
                  labelStyle: TextStyle(color: fgCol.withOpacity(0.5)),
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: fgCol.withOpacity(0.2))),
                  focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF002FA7))),
                ),
                onChanged: (v) => projectedIncome = double.tryParse(v) ?? 0.0,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF002FA7), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  onPressed: () {
                    ref.read(currentBalanceProvider.notifier).setBalance(currentBalance);
                    ref.read(projectedIncomeProvider.notifier).setIncome(projectedIncome);
                    Navigator.pop(ctx);
                  },
                  child: Text('Save Settings', style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMonthlyRunway(List<Receipt> receipts, bool isDark) {
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
    
    final fgCol = isDark ? Colors.white : Colors.black;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'MONTHLY RUNWAY',
              style: GoogleFonts.spaceGrotesk(fontSize: 11, letterSpacing: 1.2, color: fgCol.withOpacity(0.5)),
            ),
            IconButton(
              icon: Icon(Icons.edit, size: 14, color: fgCol.withOpacity(0.5)),
              onPressed: () => _showRunwaySettingsSheet(context, isDark),
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
        _hoverRow('Calculated Monthly Burn', '\$${monthlyBurn.toStringAsFixed(2)}', fgCol),
        const SizedBox(height: 8),
        _hoverRow('Projected Income', '\$${projectedIncome.toStringAsFixed(2)}', fgCol),
        const SizedBox(height: 8),
        _hoverRow('Current Balance', '\$${effectiveBalance.toStringAsFixed(2)}', fgCol),
        const SizedBox(height: 24),
        InteractiveHover(
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: fgCol,
                side: BorderSide(color: fgCol.withOpacity(0.2)),
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

  Widget _hoverRow(String label, String value, Color fgCol) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: GoogleFonts.spaceGrotesk(color: fgCol.withOpacity(0.7))),
        Text(value, style: GoogleFonts.jetBrainsMono(color: fgCol, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildThePulse(List<Receipt> receipts, bool isDark) {
    final fgCol = isDark ? Colors.white : Colors.black;
    final muted = fgCol.withOpacity(0.5);
    final accent = const Color(0xFF002FA7);
    
    // Real data: trailing 12 months
    final now = DateTime.now();
    final List<double> data = List.filled(12, 0.0);
    final List<String> months = List.filled(12, '');
    
    for (int i = 0; i < 12; i++) {
      final targetDate = DateTime(now.year, now.month - 11 + i);
      final monthReceipts = receipts.where((r) => r.date.year == targetDate.year && r.date.month == targetDate.month);
      data[i] = monthReceipts.fold(0.0, (sum, r) => sum + r.totalAmount);
      months[i] = DateFormat('MMM').format(targetDate);
    }
    
    final spots = data.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value)).toList();
    final average = data.isNotEmpty ? (data.reduce((a, b) => a + b) / 12) : 0.0;
    final peak = data.isNotEmpty ? data.reduce((a, b) => a > b ? a : b) : 0.0;
    final maxY = peak == 0 ? 1000.0 : peak * 1.2;
    final yInterval = maxY / 5 > 0 ? maxY / 5 : 1000.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.show_chart, size: 16, color: accent),
                const SizedBox(width: 8),
                Text('THE PULSE', style: GoogleFonts.spaceGrotesk(fontSize: 11, letterSpacing: 1.2, color: muted)),
              ],
            ),
            Expanded(
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 16,
                runSpacing: 8,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Average', style: GoogleFonts.spaceGrotesk(fontSize: 11, color: muted)),
                      Text('\$${average.toStringAsFixed(0)}', style: GoogleFonts.jetBrainsMono(fontSize: 15, color: fgCol)),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Peak', style: GoogleFonts.spaceGrotesk(fontSize: 11, color: muted)),
                      Text('\$${peak.toStringAsFixed(0)}', style: GoogleFonts.jetBrainsMono(fontSize: 15, color: fgCol)),
                    ],
                  ),
                ].animate(interval: 100.ms).fadeIn().slideY(begin: 0.1),
              ),
            ),
          ],
        ),
        const SizedBox(height: 32),
        SizedBox(
          height: 240,
          child: LineChart(
            LineChartData(
              gridData: const FlGridData(show: false),
              titlesData: FlTitlesData(
                show: true,
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 30,
                    interval: 1,
                    getTitlesWidget: (value, meta) {
                      if (value.toInt() % 2 != 0) return const SizedBox(); // Prevent overcrowding and right overflow
                      if (value.toInt() >= 0 && value.toInt() < months.length) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(months[value.toInt()], style: GoogleFonts.spaceGrotesk(color: muted, fontSize: 11)),
                        );
                      }
                      return const SizedBox();
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: yInterval,
                    reservedSize: 40,
                    getTitlesWidget: (value, meta) {
                      if (value == 0) return const SizedBox();
                      if (value >= 1000) return Text('\$${(value/1000).toStringAsFixed(0)}k', style: GoogleFonts.jetBrainsMono(color: muted, fontSize: 11));
                      return Text('\$${value.toStringAsFixed(0)}', style: GoogleFonts.jetBrainsMono(color: muted, fontSize: 11));
                    },
                  ),
                ),
              ),
              borderData: FlBorderData(show: false),
              minX: 0,
              maxX: 11,
              minY: 0,
              maxY: maxY,
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  color: accent,
                  barWidth: 1.5,
                  isStrokeCapRound: true,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      colors: [accent.withOpacity(0.15), accent.withOpacity(0.0)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ],
              lineTouchData: LineTouchData(
                getTouchedSpotIndicator: (LineChartBarData barData, List<int> spotIndexes) {
                  return spotIndexes.map((index) {
                    return TouchedSpotIndicatorData(
                      const FlLine(color: Color(0xFF002FA7), strokeWidth: 1),
                      FlDotData(show: true, getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(radius: 4, color: const Color(0xFF002FA7), strokeWidth: 2, strokeColor: isDark ? const Color(0xFF1A1A1A) : Colors.white)),
                    );
                  }).toList();
                },
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (touchedSpot) => isDark ? const Color(0xFF1A1A1A) : Colors.white,
                  getTooltipItems: (touchedSpots) {
                    return touchedSpots.map((spot) => LineTooltipItem(
                      '\$${spot.y.toInt()}',
                      GoogleFonts.jetBrainsMono(color: fgCol, fontSize: 13),
                    )).toList();
                  }
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.only(top: 24),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04)))),
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    'Monthly project income — Trailing 12 months', 
                    style: GoogleFonts.spaceGrotesk(fontSize: 13, color: muted),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.keyboard_arrow_down, size: 14, color: muted),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBoxes(List<Receipt> receipts, bool isDark) {
    final fgCol = isDark ? Colors.white : Colors.black;
    final activeId = ref.watch(activeBoxIdProvider);
    final boxes = ref.watch(boxesProvider);
    
    String boxName = 'Out of the Box';
    double spent = 0.0;
    double budget = 0.0;

    if (activeId == 'main') {
      spent = receipts.fold(0.0, (sum, r) => sum + r.totalAmount);
    } else {
      final box = boxes.firstWhere((b) => b.id == activeId, orElse: () => boxes.isNotEmpty ? boxes.first : BoxModel(id: 'main', name: 'Main', budget: 0, spent: 0, currency: 'USD', color: 0));
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
                  color: const Color(0xFF002FA7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('NEW', style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
              Icon(Icons.arrow_forward_ios, size: 14, color: fgCol.withOpacity(0.5)),
            ],
          ),
          const SizedBox(height: 16),
          Text(boxName, style: GoogleFonts.spaceGrotesk(fontSize: 16, fontWeight: FontWeight.w600, color: fgCol)),
          const SizedBox(height: 8),
          Text('\$${spent.toStringAsFixed(2)} spent', style: GoogleFonts.jetBrainsMono(fontSize: 14, color: fgCol.withOpacity(0.7))),
          if (budget > 0) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: (spent / budget).clamp(0.0, 1.0),
              backgroundColor: fgCol.withOpacity(0.1),
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF002FA7)),
              borderRadius: BorderRadius.circular(4),
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildDensityHeatmap(List<Receipt> receipts, bool isDark) {
    final fgCol = isDark ? Colors.white : Colors.black;
    final muted = fgCol.withOpacity(0.5);
    final accent = const Color(0xFF002FA7);
    
    // Calculate trailing 28 days
    final now = DateTime.now();
    final densityData = List.filled(28, 0);
    for (int i = 0; i < 28; i++) {
      final targetDate = now.subtract(Duration(days: 27 - i));
      final count = receipts.where((r) => r.date.year == targetDate.year && r.date.month == targetDate.month && r.date.day == targetDate.day).length;
      if (count == 0) densityData[i] = 0;
      else if (count <= 1) densityData[i] = 1;
      else if (count <= 3) densityData[i] = 2;
      else if (count <= 5) densityData[i] = 3;
      else densityData[i] = 4;
    }

    Color getIntensityColor(int level) {
      switch(level) {
        case 1: return accent.withOpacity(0.2);
        case 2: return accent.withOpacity(0.4);
        case 3: return accent.withOpacity(0.7);
        case 4: return accent;
        default: return isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text('TRANSACTION DENSITY', style: GoogleFonts.spaceGrotesk(fontSize: 11, letterSpacing: 1.2, color: muted)),
                const SizedBox(width: 6),
                Icon(Icons.info_outline, size: 12, color: muted.withOpacity(0.5)),
              ],
            ),
            Text('28 DAYS', style: GoogleFonts.jetBrainsMono(fontSize: 11, color: muted)),
          ],
        ),
        const SizedBox(height: 24),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 1,
          ),
          itemCount: 35, // 7 days labels + 28 blocks
          itemBuilder: (ctx, i) {
            if (i < 7) {
              final days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
              return Center(child: Text(days[i], style: GoogleFonts.spaceGrotesk(fontSize: 10, color: fgCol.withOpacity(0.3))));
            }
            final level = densityData[i - 7];
            return Tooltip(
              message: 'Day ${i - 6}: ${['0', '2', '5', '12', '24'][level]}',
              textStyle: GoogleFonts.spaceGrotesk(fontSize: 10, color: isDark ? Colors.black : Colors.white, fontWeight: FontWeight.bold),
              decoration: BoxDecoration(color: isDark ? Colors.white : Colors.black, borderRadius: BorderRadius.circular(8)),
              verticalOffset: 16,
              preferBelow: false,
              child: InteractiveHover(
                child: Container(
                  decoration: BoxDecoration(
                    color: getIntensityColor(level),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.only(top: 16),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04)))),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('LESS', style: GoogleFonts.spaceGrotesk(fontSize: 10, letterSpacing: 1.2, color: fgCol.withOpacity(0.4))),
              Row(
                children: [
                  _colorBox(getIntensityColor(0)),
                  _colorBox(getIntensityColor(1)),
                  _colorBox(getIntensityColor(2)),
                  _colorBox(getIntensityColor(3)),
                  _colorBox(getIntensityColor(4)),
                ],
              ),
              Text('MORE', style: GoogleFonts.spaceGrotesk(fontSize: 10, letterSpacing: 1.2, color: fgCol.withOpacity(0.4))),
            ],
          ),
        )
      ],
    );
  }
  
  Widget _colorBox(Color c) => Container(margin: const EdgeInsets.symmetric(horizontal: 2), width: 8, height: 8, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2)));

  Widget _buildAchievements(List<Receipt> receipts, bool isDark) {
    final fgCol = isDark ? Colors.white : Colors.black;
    final muted = fgCol.withOpacity(0.5);
    final accent = const Color(0xFF002FA7);

    final now = DateTime.now();
    final monthlyBurn = receipts.where((r) => r.date.year == now.year && r.date.month == now.month).fold(0.0, (sum, r) => sum + r.totalAmount);
    final boxes = ref.watch(boxesProvider);
    final activeId = ref.watch(activeBoxIdProvider);
    final activeBox = activeId == 'main' || boxes.isEmpty ? (boxes.isNotEmpty ? boxes.first : BoxModel(id: 'main', name: 'Main', budget: 0, spent: 0, currency: 'USD', color: 0)) : boxes.firstWhere((b) => b.id == activeId, orElse: () => boxes.isNotEmpty ? boxes.first : BoxModel(id: 'main', name: 'Main', budget: 0, spent: 0, currency: 'USD', color: 0));
    
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
                color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05),
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
                    color: active ? accent : fgCol.withOpacity(0.1),
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
                Text(a['date'] as String, style: GoogleFonts.jetBrainsMono(fontSize: 12, color: fgCol.withOpacity(0.3))),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildNeedsVsWants(List<Receipt> receipts, bool isDark) {
    final fgCol = isDark ? Colors.white : Colors.black;
    final muted = fgCol.withOpacity(0.5);
    final accent = const Color(0xFF002FA7);
    
    // Calculate Needs vs Wants
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
                if (wantsFlex > 0) Expanded(flex: safeWantsFlex, child: Container(height: 16, color: isDark ? Colors.white.withOpacity(0.2) : Colors.black.withOpacity(0.2))),
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
                  Text('Needs: $needsPercent%', style: GoogleFonts.spaceGrotesk(fontSize: 12, color: fgCol.withOpacity(0.6))),
                  Text('Wants: $wantsPercent%', style: GoogleFonts.spaceGrotesk(fontSize: 12, color: fgCol.withOpacity(0.4))),
                ],
              ),
              secondChild: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('\$${needsTotal.toStringAsFixed(0)}', style: GoogleFonts.jetBrainsMono(fontSize: 12, color: fgCol.withOpacity(0.8))),
                  Text('\$${wantsTotal.toStringAsFixed(0)}', style: GoogleFonts.jetBrainsMono(fontSize: 12, color: fgCol.withOpacity(0.8))),
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

  Widget _buildRecentTransactions(List<Receipt> filteredReceipts, bool isDark) {
    final fgCol = isDark ? Colors.white : Colors.black;
    final categories = ref.watch(categoryListProvider);
    
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text('Recent Transactions', style: GoogleFonts.spaceGrotesk(fontSize: 18, fontWeight: FontWeight.bold, color: fgCol), overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(20),
              ),
              child: DropdownButton<String?>(
                value: _selectedCategory,
                dropdownColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
                underline: const SizedBox(),
                icon: Icon(Icons.filter_list, color: fgCol.withOpacity(0.5), size: 18),
                hint: Text('Filter', style: GoogleFonts.spaceGrotesk(color: fgCol.withOpacity(0.5), fontSize: 13)),
                items: [
                  DropdownMenuItem(
                    value: null,
                    child: Text('All', style: GoogleFonts.spaceGrotesk(color: fgCol, fontSize: 13)),
                  ),
                  ...categories.map((c) => DropdownMenuItem(
                    value: c,
                    child: Text(c, style: GoogleFonts.spaceGrotesk(color: fgCol, fontSize: 13)),
                  )),
                ],
                onChanged: (val) => setState(() => _selectedCategory = val),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (filteredReceipts.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Column(
              children: [
                Icon(Icons.receipt_long, size: 48, color: fgCol.withOpacity(0.2)),
                const SizedBox(height: 16),
                Text('No receipts yet', style: GoogleFonts.spaceGrotesk(color: fgCol.withOpacity(0.5))),
              ],
            ),
          )
        else
          ...filteredReceipts.take(5).map((r) => _buildReceiptRow(r, isDark)),
      ],
    );
  }

  Widget _buildReceiptRow(Receipt r, bool isDark) {
    final fgCol = isDark ? Colors.white : Colors.black;
    return InkWell(
      onTap: () => context.push('/review', extra: r),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.merchantName, style: GoogleFonts.spaceGrotesk(fontSize: 15, fontWeight: FontWeight.w500, color: fgCol)),
                const SizedBox(height: 4),
                Text(DateFormat('MMM dd, yyyy').format(r.date), style: GoogleFonts.spaceGrotesk(fontSize: 12, color: fgCol.withOpacity(0.5))),
              ],
            ),
            Text('\$${r.totalAmount.toStringAsFixed(2)}', style: GoogleFonts.jetBrainsMono(fontSize: 15, fontWeight: FontWeight.w600, color: fgCol)),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNav(bool isDark, Color accent) {
    final fgCol = isDark ? Colors.white : Colors.black;
    final isLlmActive = ref.watch(isLlmLoadedProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 24.0, left: 24.0, right: 24.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF151515) : const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: fgCol.withOpacity(0.05)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isLlmActive ? Colors.greenAccent : Colors.grey,
                    ),
                  ).animate(onPlay: (ctrl) => ctrl.repeat(reverse: true)).scale(begin: const Offset(0.8, 0.8), end: const Offset(1.2, 1.2), duration: 1.seconds),
                  const SizedBox(width: 8),
                  Text(isLlmActive ? 'AI Core Active' : 'AI Offline', style: GoogleFonts.spaceGrotesk(fontSize: 12, color: fgCol.withOpacity(0.7))),
                ],
              ),
            ),
            InteractiveHover(
              onTap: () => context.push('/scan'),
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent,
                  boxShadow: [
                    BoxShadow(color: accent.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 8)),
                  ],
                ),
                child: const Center(
                  child: Icon(Icons.camera_alt, color: Colors.white, size: 32),
                ),
              ).animate().scale(delay: 500.ms, curve: Curves.elasticOut),
            ),
            const SizedBox(width: 120), // Spacer for balance
          ],
        ),
      ),
    );
  }

  // ── Tax Nest widget ──────────────────────────────────────────────────────────
  Widget _buildTaxNest(List<Receipt> receipts, bool isDark) {
    final fgCol = isDark ? Colors.white : Colors.black;
    final muted = fgCol.withAlpha(102); // ~40%
    final accent = const Color(0xFF002FA7);

    // Accumulate YTD total from all receipts as a rough tax stash simulation
    final ytdTotal = receipts.fold(0.0, (sum, r) => sum + r.totalAmount);
    final stashed = ytdTotal * 0.22; // ~22% simulated tax set-aside

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.shield_outlined, color: accent, size: 16),
            const SizedBox(width: 8),
            Text('THE TAX NEST',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 11, letterSpacing: 1.2, color: muted)),
          ],
        ),
        const SizedBox(height: 24),
        GestureDetector(
          onTap: () => ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Tax Nest Goal: \$12,000 (${(stashed / 12000 * 100).clamp(0, 100).toStringAsFixed(0)}% achieved)'))),
          child: Text(
            '\$${stashed.toStringAsFixed(2)}',
            style: GoogleFonts.jetBrainsMono(
                fontSize: 40, fontWeight: FontWeight.w300, color: fgCol),
          ),
        ),
        const SizedBox(height: 4),
        Text('Stashed for Q2 ${DateTime.now().year}',
            style: GoogleFonts.spaceGrotesk(fontSize: 13, color: muted, fontWeight: FontWeight.w300)),
        const SizedBox(height: 24),
        // Mini sparkline area chart (simplified as a bar row)
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
              side: BorderSide(color: fgCol.withAlpha(26)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Auto-stash configuration opened.'))),
            child: Text('Auto-stash settings', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w400)),
          ),
        ),
      ],
    );
  }

  // ── Project Cards (Active Invoices preview) ──────────────────────────────────
  Widget _buildProjectCards(bool isDark) {
    final fgCol = isDark ? Colors.white : Colors.black;
    final muted = fgCol.withAlpha(102);
    final border = isDark ? Colors.white.withAlpha(15) : Colors.black.withAlpha(10);
    final accent = const Color(0xFF002FA7);

    final invoices = ref.watch(invoicesProvider).take(4).toList();

    Color statusColor(String s) {
      switch (s.toLowerCase()) {
        case 'settled': return isDark ? Colors.white70 : Colors.black87;
        case 'sent': return accent;
        case 'overdue': return const Color(0xFFD4183D);
        default: return muted;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('ACTIVE INVOICES',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 11, letterSpacing: 1.2, color: muted)),
            GestureDetector(
              onTap: () => context.push('/invoices'),
              child: Row(
                children: [
                  Text('View all',
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 11, color: muted,
                          letterSpacing: 1.0)),
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
                                child: Text(inv.clientName,
                                    style: GoogleFonts.spaceGrotesk(
                                        fontSize: 13, color: fgCol,
                                        fontWeight: FontWeight.w400)),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: statusColor(status).withAlpha(26),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(status,
                                    style: GoogleFonts.spaceGrotesk(
                                        fontSize: 10, color: statusColor(status),
                                        letterSpacing: 0.8, fontWeight: FontWeight.w500)),
                              ),
                            ]),
                            const SizedBox(height: 4),
                            Row(children: [
                              Text(inv.invoiceNumber,
                                  style: GoogleFonts.jetBrainsMono(
                                      fontSize: 11, color: muted)),
                              Container(
                                margin: const EdgeInsets.symmetric(horizontal: 6),
                                width: 3, height: 3,
                                decoration: BoxDecoration(
                                    shape: BoxShape.circle, color: muted),
                              ),
                              Text(DateFormat('MMM dd').format(inv.issuedDate),
                                  style: GoogleFonts.spaceGrotesk(
                                      fontSize: 11, color: muted)),
                            ]),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text('\$${amount.toStringAsFixed(2)}',
                          style: GoogleFonts.jetBrainsMono(
                              fontSize: 13, color: fgCol,
                              fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
                Divider(height: 1, color: border),
              ],
            );
          }),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: muted,
              side: BorderSide(color: fgCol.withAlpha(26)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: () => context.push('/invoices'),
            child: Text('Create New Invoice',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 12, letterSpacing: 1.0, fontWeight: FontWeight.w400)),
          ),
        ),
      ],
    );
  }

  // ── Settings overlay (slide from right + blur backdrop) ───────────────────
  void _showSettingsPanel(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Settings',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 380),
      pageBuilder: (ctx, _, __) => const SettingsPanelWidget(),
      transitionBuilder: (ctx, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return Stack(
          children: [
            // ── Blurred + darkened backdrop ──────────────────────────────
            AnimatedBuilder(
              animation: curved,
              builder: (_, __) => BackdropFilter(
                filter: ui.ImageFilter.blur(
                  sigmaX: 12 * curved.value,
                  sigmaY: 12 * curved.value,
                ),
                child: GestureDetector(
                  onTap: () => Navigator.of(ctx).pop(),
                  child: Container(
                    color: Colors.black.withAlpha((120 * curved.value).round()),
                  ),
                ),
              ),
            ),
            // ── Panel sliding in from right ──────────────────────────────
            SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(1.0, 0.0),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          ],
        );
      },
    );
  }

  Future<void> _importCsv() async {
    final result = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['csv']);
    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      final csvString = await file.readAsString();
      final parser = ref.read(csvParserServiceProvider);
      final addedCount = await ref.read(receiptListProvider.notifier).importCsvTransactions(csvString, parser);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Imported $addedCount transactions')));
    }
  }

  void _exportCsv() {
    final asyncReceipts = ref.read(receiptListProvider);
    asyncReceipts.whenData((receipts) {
      if (receipts.isNotEmpty) {
        ref.read(exportServiceProvider).exportReceiptsToCsv(receipts);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Generating CSV Report...')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No receipts to export')));
      }
    });
  }
}

class HoverCardWrapper extends StatefulWidget {
  final Widget child;
  final bool isDark;
  const HoverCardWrapper({super.key, required this.child, required this.isDark});

  @override
  State<HoverCardWrapper> createState() => _HoverCardWrapperState();
}

class _HoverCardWrapperState extends State<HoverCardWrapper> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: widget.isDark ? const Color(0xFF0F0F0F) : Colors.white,
          border: Border.all(
            color: _isHovered 
              ? (widget.isDark ? Colors.white.withOpacity(0.15) : Colors.black.withOpacity(0.15))
              : (widget.isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04)),
            width: _isHovered ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: _isHovered ? [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, 10),
            )
          ] : [],
        ),
        child: widget.child,
      ),
    );
  }
}

class InteractiveHover extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  const InteractiveHover({super.key, required this.child, this.onTap});
  
  @override
  State<InteractiveHover> createState() => _InteractiveHoverState();
}

class _InteractiveHoverState extends State<InteractiveHover> {
  bool _isHovered = false;
  bool _isPressed = false;
  
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _isPressed ? 0.95 : (_isHovered ? 1.05 : 1.0),
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      ),
    );
  }
}
