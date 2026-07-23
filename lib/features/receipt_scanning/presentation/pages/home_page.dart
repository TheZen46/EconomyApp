// ignore_for_file: deprecated_member_use
import 'dart:io';
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
import '../../../boxes/data/providers/boxes_provider.dart';
import '../../../../core/theme/theme_notifier.dart';
import '../../../../core/services/gamification_service.dart';

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
              )
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
          if (!_isEditMode) ...[
            IconButton(
              icon: Icon(_isSearching ? Icons.check : Icons.search, color: fgCol),
              onPressed: () {
                setState(() {
                  if (!_isSearching) {
                    _isSearching = true;
                  } else {
                    FocusManager.instance.primaryFocus?.unfocus();
                  }
                });
              },
            ),
            IconButton(
              icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode, color: fgCol),
              onPressed: () => ref.read(themeProvider.notifier).toggle(),
            ),
          ] else ...[
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
          ],
          if (!_isSearching) ...[
            IconButton(
              icon: Icon(
                _isEditMode ? Icons.check_circle : Icons.dashboard_customize,
                color: _isEditMode ? accent : fgCol,
              ),
              onPressed: () => setState(() => _isEditMode = !_isEditMode),
            ),
            if (!_isEditMode) ...[
              IconButton(
                icon: Icon(Icons.settings, color: fgCol),
                onPressed: () => context.push('/settings'),
              ),
              IconButton(
                icon: Icon(Icons.upload_file, color: fgCol),
                onPressed: _importCsv,
              ),
              IconButton(
                icon: Icon(Icons.download, color: fgCol),
                onPressed: _exportCsv,
              ),
            ],
          ],
        ],
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

    // In Edit mode, show ReorderableListView with Hidden items section
    if (_isEditMode) {
      final visibleItems = dashboardItems.where((i) => i.isVisible).toList();
      final hiddenItems = dashboardItems.where((i) => !i.isVisible).toList();

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
                return _buildEditModeCard(item, isDark);
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
    final visibleItems = dashboardItems.where((i) => i.isVisible).toList();
    
    // Inject Boxes widget if it's completely missing from config (as fallback)
    if (!dashboardItems.any((i) => i.type == DashboardWidgetType.monthlyBudget)) {
      visibleItems.insert(0, DashboardItem(id: 'boxes', type: DashboardWidgetType.monthlyBudget, title: 'Boxes', isVisible: true));
    }

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

  Widget _buildEditModeCard(DashboardItem item, bool isDark) {
    return Container(
      key: ValueKey(item.id),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F0F0F) : Colors.white,
        border: Border.all(color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListTile(
        leading: Icon(Icons.drag_indicator, color: isDark ? Colors.white54 : Colors.black54),
        title: Text(item.title, style: GoogleFonts.spaceGrotesk(color: isDark ? Colors.white : Colors.black)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Size selector
            DropdownButton<int>(
              value: _widgetSpans[item.type] ?? 1,
              underline: const SizedBox(),
              items: [1, 2, 3].map((val) => DropdownMenuItem(
                value: val,
                child: Text('$val Col', style: GoogleFonts.spaceGrotesk(color: isDark ? Colors.white : Colors.black, fontSize: 12)),
              )).toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() => _widgetSpans[item.type] = val);
                }
              },
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.remove_circle, color: Colors.redAccent),
              onPressed: () {
                final idx = ref.read(dashboardProvider).indexOf(item);
                ref.read(dashboardProvider.notifier).toggleVisibility(idx);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardWrapper({required Widget child, required bool isDark}) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F0F0F) : Colors.white,
        border: Border.all(color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
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
    }
  }

  Widget _buildMonthlyRunway(List<Receipt> receipts, bool isDark) {
    final now = DateTime.now();
    final monthlyBurn = receipts
        .where((r) => r.date.year == now.year && r.date.month == now.month)
        .fold(0.0, (sum, r) => sum + r.totalAmount);
        
    final boxes = ref.watch(boxesProvider);
    double totalBalance = boxes.fold(0.0, (sum, b) => sum + (b.budget - b.spent));
    if (totalBalance <= 0) totalBalance = 15000.0; // Mock fallback
    
    final runwayMonths = monthlyBurn > 0 ? (totalBalance / monthlyBurn) : 0.0;
    final fgCol = isDark ? Colors.white : Colors.black;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'MONTHLY RUNWAY',
          style: GoogleFonts.spaceGrotesk(fontSize: 11, letterSpacing: 1.2, color: fgCol.withOpacity(0.5)),
        ),
        const SizedBox(height: 16),
        Text(
          runwayMonths > 99 ? '∞' : runwayMonths.toStringAsFixed(1),
          style: GoogleFonts.jetBrainsMono(fontSize: 48, fontWeight: FontWeight.bold, color: fgCol),
        ),
        const SizedBox(height: 24),
        _hoverRow('Calculated Monthly Burn', '\$${monthlyBurn.toStringAsFixed(2)}', fgCol),
        const SizedBox(height: 8),
        _hoverRow('Avg Spend / Day', '\$${(monthlyBurn / now.day).toStringAsFixed(2)}', fgCol),
        const SizedBox(height: 24),
        SizedBox(
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
    final now = DateTime.now();
    final List<BarChartGroupData> barGroups = [];
    double maxY = 0;
    
    for (int i = 6; i >= 0; i--) {
      final day = now.subtract(Duration(days: i));
      final dailySum = receipts
          .where((r) => r.date.year == day.year && r.date.month == day.month && r.date.day == day.day)
          .fold(0.0, (sum, item) => sum + item.totalAmount);
      if (dailySum > maxY) maxY = dailySum;
      
      barGroups.add(BarChartGroupData(
        x: 6 - i,
        barRods: [
          BarChartRodData(
            toY: dailySum,
            color: const Color(0xFF002FA7),
            width: 16,
            borderRadius: BorderRadius.circular(4),
          )
        ],
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('The Pulse', style: GoogleFonts.spaceGrotesk(fontSize: 18, fontWeight: FontWeight.bold, color: fgCol)),
        Text('Activity Trend', style: GoogleFonts.spaceGrotesk(fontSize: 12, color: fgCol.withOpacity(0.5))),
        const SizedBox(height: 24),
        SizedBox(
          height: 180,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: maxY == 0 ? 100 : maxY * 1.2,
              barTouchData: BarTouchData(enabled: false),
              titlesData: FlTitlesData(
                show: true,
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (val, meta) {
                      final day = now.subtract(Duration(days: 6 - val.toInt()));
                      return Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(DateFormat('E').format(day).substring(0, 1), 
                          style: GoogleFonts.spaceGrotesk(color: fgCol.withOpacity(0.5), fontSize: 12)),
                      );
                    },
                  ),
                ),
                leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              gridData: FlGridData(show: false),
              borderData: FlBorderData(show: false),
              barGroups: barGroups,
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
      final box = boxes.firstWhere((b) => b.id == activeId, orElse: () => boxes.first);
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
    final now = DateTime.now();
    // 4 weeks * 7 days
    final startDate = now.subtract(const Duration(days: 27)); 
    final List<int> counts = List.filled(28, 0);
    
    int maxCount = 1;
    for (final r in receipts) {
      if (r.date.isAfter(startDate.subtract(const Duration(days: 1)))) {
        final diff = r.date.difference(startDate).inDays;
        if (diff >= 0 && diff < 28) {
          counts[diff]++;
          if (counts[diff] > maxCount) maxCount = counts[diff];
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('TRANSACTION DENSITY', style: GoogleFonts.spaceGrotesk(fontSize: 11, letterSpacing: 1.2, color: fgCol.withOpacity(0.5))),
        const SizedBox(height: 16),
        SizedBox(
          height: 100, // 4 rows
          child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              crossAxisSpacing: 4,
              mainAxisSpacing: 4,
            ),
            itemCount: 28,
            itemBuilder: (ctx, i) {
              final count = counts[i];
              final ratio = count / maxCount;
              double opacity = 0.04;
              if (count > 0) {
                if (ratio <= 0.25) {
                  opacity = 0.2;
                } else if (ratio <= 0.5) {
                  opacity = 0.4;
                } else if (ratio <= 0.75) {
                  opacity = 0.7;
                } else {
                  opacity = 1.0;
                }
              }
              return Container(
                decoration: BoxDecoration(
                  color: count == 0 ? fgCol.withOpacity(0.04) : const Color(0xFF002FA7).withOpacity(opacity),
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text('Less ', style: GoogleFonts.spaceGrotesk(fontSize: 10, color: fgCol.withOpacity(0.5))),
            _colorBox(fgCol.withOpacity(0.04)),
            _colorBox(const Color(0xFF002FA7).withOpacity(0.2)),
            _colorBox(const Color(0xFF002FA7).withOpacity(0.4)),
            _colorBox(const Color(0xFF002FA7).withOpacity(0.7)),
            _colorBox(const Color(0xFF002FA7)),
            Text(' More', style: GoogleFonts.spaceGrotesk(fontSize: 10, color: fgCol.withOpacity(0.5))),
          ],
        )
      ],
    );
  }
  
  Widget _colorBox(Color c) => Container(margin: const EdgeInsets.symmetric(horizontal: 2), width: 8, height: 8, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2)));

  Widget _buildAchievements(List<Receipt> receipts, bool isDark) {
    final fgCol = isDark ? Colors.white : Colors.black;
    final budget = ref.watch(monthlyBudgetProvider);
    final achievements = GamificationService.calculateAchievements(receipts, budget).take(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('MILESTONES', style: GoogleFonts.spaceGrotesk(fontSize: 11, letterSpacing: 1.2, color: fgCol.withOpacity(0.5))),
        const SizedBox(height: 16),
        ...achievements.map((a) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 32,
                decoration: BoxDecoration(
                  color: a.isUnlocked ? const Color(0xFF002FA7) : fgCol.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              Icon(a.icon, size: 20, color: a.isUnlocked ? a.color : fgCol.withOpacity(0.3)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a.name, style: GoogleFonts.spaceGrotesk(fontSize: 14, fontWeight: FontWeight.w500, color: fgCol)),
                    Text(a.description, style: GoogleFonts.spaceGrotesk(fontSize: 12, color: fgCol.withOpacity(0.5))),
                  ],
                ),
              )
            ],
          ),
        )),
      ],
    );
  }

  Widget _buildNeedsVsWants(List<Receipt> receipts, bool isDark) {
    final fgCol = isDark ? Colors.white : Colors.black;
    double essential = receipts.fold(0.0, (s, r) => s + r.essentialTotal);
    double discretional = receipts.fold(0.0, (s, r) => s + (r.totalAmount - r.essentialTotal - r.junkTotal));
    double junk = receipts.fold(0.0, (s, r) => s + r.junkTotal);
    double total = essential + discretional + junk;
    if (total == 0) total = 1; // avoid div by zero
    
    return GestureDetector(
      onTap: () => setState(() => _showNeedsAmounts = !_showNeedsAmounts),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('NEEDS VS WANTS', style: GoogleFonts.spaceGrotesk(fontSize: 11, letterSpacing: 1.2, color: fgCol.withOpacity(0.5))),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Row(
              children: [
                Expanded(flex: (essential/total * 100).toInt(), child: Container(height: 12, color: const Color(0xFF002FA7))),
                Expanded(flex: (discretional/total * 100).toInt(), child: Container(height: 12, color: const Color(0xFF002FA7).withOpacity(0.5))),
                Expanded(flex: (junk/total * 100).toInt(), child: Container(height: 12, color: fgCol.withOpacity(0.2))),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _legendItem('Essential', essential, essential/total, const Color(0xFF002FA7), fgCol),
          const SizedBox(height: 8),
          _legendItem('Discretional', discretional, discretional/total, const Color(0xFF002FA7).withOpacity(0.5), fgCol),
          const SizedBox(height: 8),
          _legendItem('Junk', junk, junk/total, fgCol.withOpacity(0.2), fgCol),
        ],
      ),
    );
  }
  
  Widget _legendItem(String label, double amt, double ratio, Color c, Color fgCol) {
    final val = _showNeedsAmounts ? '\$${amt.toStringAsFixed(0)}' : '${(ratio*100).toInt()}%';
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Text(label, style: GoogleFonts.spaceGrotesk(fontSize: 13, color: fgCol)),
          ],
        ),
        Text(val, style: GoogleFonts.jetBrainsMono(fontSize: 13, color: fgCol)),
      ],
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
            Text('Recent Transactions', style: GoogleFonts.spaceGrotesk(fontSize: 18, fontWeight: FontWeight.bold, color: fgCol)),
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
            FloatingActionButton(
              onPressed: () => context.push('/scan'),
              backgroundColor: accent,
              elevation: 0,
              shape: const CircleBorder(),
              child: const Icon(Icons.camera_alt, color: Colors.white, size: 28),
            ).animate().scale(delay: 500.ms, curve: Curves.elasticOut),
            const SizedBox(width: 120), // Spacer for balance
          ],
        ),
      ),
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
