import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import '../../../../core/theme/app_theme.dart';
import '../providers/receipt_provider.dart';
import '../widgets/monthly_spend_card.dart';
import '../widgets/neon_bar_chart.dart';
import '../widgets/neon_heatmap.dart';
import '../widgets/receipt_card.dart';
import '../widgets/achievements_widget.dart';
import '../widgets/necessity_breakdown_widget.dart';
import '../providers/category_provider.dart';
import '../widgets/ai_status_indicator.dart';
import '../../domain/entities/receipt.dart';
import '../../../../core/services/gamification_service.dart';
import '../../data/models/dashboard_config.dart';
import '../providers/dashboard_provider.dart';

enum SummaryRange { day, week, month, year }
enum ChartRange { week, month, year }

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  String? _selectedCategory;
  SummaryRange _summaryRange = SummaryRange.month;
  ChartRange _chartRange = ChartRange.week;
  
  final TextEditingController _searchController = TextEditingController(); // Search
  bool _isSearching = false; // Search toggle
  bool _isEditMode = false; // Dashboard Edit Mode
  // final List<String> _categories = ['Grocery', 'Tech', 'Transport', 'Restaurant']; // Removed in favor of AppConstants

  @override
  Widget build(BuildContext context) {
    final receiptListAsync = ref.watch(receiptListProvider);
    final monthlyBudget = ref.watch(monthlyBudgetProvider);
    final dashboardItems = ref.watch(dashboardProvider);
    final notifier = ref.read(dashboardProvider.notifier);

    // Identify hidden items
    final visibleItems = dashboardItems.where((i) => i.isVisible).toList();
    final hiddenItems = dashboardItems.where((i) => !i.isVisible).toList();

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: _isSearching 
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: AppTheme.textMain),
                decoration: const InputDecoration(
                  hintText: 'Search merchant...',
                  hintStyle: TextStyle(color: AppTheme.textDim),
                  border: InputBorder.none,
                ),
                onChanged: (val) => setState(() {}),
              )
            : Text(_isEditMode ? 'Edit Layout' : 'tAIdy'),
        backgroundColor: _isEditMode ? AppTheme.surface.withOpacity(0.9) : Colors.transparent,
        leading: _isSearching 
            ? IconButton(
                icon: const Icon(Icons.close, color: AppTheme.textDim), 
                onPressed: () {
                   setState(() {
                     _isSearching = false;
                     _searchController.clear();
                   });
                },
              )
            : null,
        flexibleSpace: _isEditMode ? null : Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppTheme.background.withOpacity(0.9),
                Colors.transparent,
              ],
            ),
          ),
        ),
        actions: [
          if (!_isEditMode) ...[
            IconButton(
               icon: Icon(_isSearching ? Icons.check : Icons.search, color: AppTheme.textMain),
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
          ] else ...[
             // Reset Button in Edit Mode
             IconButton(
               icon: const Icon(Icons.restore, color: AppTheme.textDim),
               tooltip: 'Reset Layout',
               onPressed: () {
                  notifier.reset();
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Layout reset!')));
               },
             ),
          ],
          
          if (!_isSearching) ...[
            // Toggle Edit Mode
            IconButton(
              tooltip: _isEditMode ? 'Done' : 'Customize Dashboard',
              icon: Icon(
                _isEditMode ? Icons.check_circle : Icons.dashboard_customize_outlined, 
                color: _isEditMode ? AppTheme.primary : AppTheme.secondary
              ),
              onPressed: () => setState(() => _isEditMode = !_isEditMode),
            ),
            
            if (!_isEditMode) ...[
              IconButton(
                icon: const Icon(Icons.settings_outlined, color: AppTheme.textMain),
                onPressed: () => context.push('/settings'),
              ),
              IconButton(
                tooltip: 'Price Watch',
                icon: const Icon(Icons.analytics_outlined, color: AppTheme.secondary),
                onPressed: () => context.push('/price_watch'),
              ),
              IconButton(
                tooltip: 'Import Bank CSV',
                icon: const Icon(Icons.upload_file_rounded, color: AppTheme.primary),
                onPressed: () async {
                  final result = await FilePicker.pickFiles(
                    type: FileType.custom,
                    allowedExtensions: ['csv'],
                    withData: true,
                  );
                  if (result != null && result.files.single.bytes != null) {
                    final csvString = utf8.decode(result.files.single.bytes!);
                    final parser = ref.read(csvParserServiceProvider);
                    final addedCount = await ref.read(receiptListProvider.notifier).importCsvTransactions(csvString, parser);
                    if (context.mounted) {
                       ScaffoldMessenger.of(context).showSnackBar(
                         SnackBar(content: Text('Imported $addedCount transactions'), backgroundColor: AppTheme.primary),
                       );
                    }
                  } else if (result != null && result.files.single.path != null) {
                     // Fallback for native devices if withData fails
                     // Using dynamic to bypass dart:io static web checks
                  }
                },
              ),
              IconButton(
                icon: const Icon(Icons.download_rounded, color: AppTheme.textMain),
                onPressed: () {
                // Get current receipts using the existing provider logic
                final asyncReceipts = ref.read(receiptListProvider);
                asyncReceipts.whenData((receipts) {
                  if (receipts.isNotEmpty) {
                    ref.read(exportServiceProvider).exportReceiptsToCsv(receipts);
                    ScaffoldMessenger.of(context).showSnackBar(
                       const SnackBar(content: Text('Generating CSV Report...'), backgroundColor: AppTheme.primary),
                    );
                  } else {
                     ScaffoldMessenger.of(context).showSnackBar(
                       const SnackBar(content: Text('No receipts to export'), backgroundColor: AppTheme.error),
                    );
                  }
                });
              },
            ),
           ],
          ],
        ],
      ),
      body: receiptListAsync.when(
        data: (receipts) {
          // 1. Calculate Summary Spend
          final now = DateTime.now();
          double summaryTotal = 0.0;
          String summaryLabel = '';

          switch (_summaryRange) {
            case SummaryRange.day:
              summaryTotal = receipts
                  .where((r) => r.date.year == now.year && r.date.month == now.month && r.date.day == now.day)
                  .fold(0.0, (sum, item) => sum + item.totalAmount);
              summaryLabel = 'Today';
              break;
            case SummaryRange.week:
              final start = now.subtract(const Duration(days: 7));
              summaryTotal = receipts
                  .where((r) => r.date.isAfter(start))
                  .fold(0.0, (sum, item) => sum + item.totalAmount);
              summaryLabel = 'Last 7 Days';
              break;
            case SummaryRange.month:
              summaryTotal = receipts
                  .where((r) => r.date.year == now.year && r.date.month == now.month)
                  .fold(0.0, (sum, item) => sum + item.totalAmount);
              summaryLabel = 'This Month';
              break;
            case SummaryRange.year:
              summaryTotal = receipts
                  .where((r) => r.date.year == now.year)
                  .fold(0.0, (sum, item) => sum + item.totalAmount);
              summaryLabel = 'This Year';
              break;
          }

          // 2. Calculate Chart Data
          final List<double> chartData = [];
          final List<String> chartLabels = [];

          switch (_chartRange) {
            case ChartRange.week:
              for (int i = 6; i >= 0; i--) {
                final day = now.subtract(Duration(days: i));
                final dailySum = receipts
                    .where((r) => r.date.year == day.year && 
                                  r.date.month == day.month && 
                                  r.date.day == day.day)
                    .fold(0.0, (sum, item) => sum + item.totalAmount);
                chartData.add(dailySum);
                chartLabels.add(DateFormat('E').format(day).substring(0, 1));
              }
              break;
            case ChartRange.month:
               for (int i = 3; i >= 0; i--) {
                 final end = now.subtract(Duration(days: i * 7));
                 final start = end.subtract(const Duration(days: 6));
                 final weekSum = receipts
                    .where((r) => r.date.isAfter(start.subtract(const Duration(seconds: 1))) && 
                                  r.date.isBefore(end.add(const Duration(days: 1)))) // Inclusiveish
                    .fold(0.0, (sum, item) => sum + item.totalAmount);
                 chartData.add(weekSum);
                 chartLabels.add('W${4-i}');
               }
               break;
            case ChartRange.year:
               for (int i = 5; i >= 0; i--) {
                 final month = DateTime(now.year, now.month - i, 1);
                 final monthSum = receipts
                    .where((r) => r.date.year == month.year && r.date.month == month.month)
                    .fold(0.0, (sum, item) => sum + item.totalAmount);
                 chartData.add(monthSum);
                 chartLabels.add(DateFormat('MMM').format(month).substring(0, 1));
               }
               break;
          }
          
          // Filter Logic
          final searchQuery = _searchController.text.toLowerCase();
          final filteredReceipts = receipts.where((r) {
            final matchesCategory = _selectedCategory == null || r.category.toLowerCase() == _selectedCategory!.toLowerCase();
            final matchesSearch = searchQuery.isEmpty || r.merchantName.toLowerCase().contains(searchQuery);
            return matchesCategory && matchesSearch;
          }).toList();

          // Calculate dynamic budget based on range
          double? adjustedBudget;
          if (monthlyBudget > 0) {
            switch (_summaryRange) {
              case SummaryRange.day: adjustedBudget = monthlyBudget / 30; break;
              case SummaryRange.week: adjustedBudget = monthlyBudget / 4; break;
              case SummaryRange.month: adjustedBudget = monthlyBudget; break;
              case SummaryRange.year: adjustedBudget = monthlyBudget * 12; break;
            }
          }

          // 3. Build Body Content
          Widget buildItem(DashboardItem item) {
             final content = _buildDashboardWidget(item, context, summaryLabel, summaryTotal, adjustedBudget, chartData, chartLabels, receipts, filteredReceipts);
             
             if (!_isEditMode) return content;

             // Edit Mode Wrapper
             return Stack(
               clipBehavior: Clip.none,
               children: [
                 // Used AbsorbPointer so hits are captured (for dragging) but children don't respond
                 AbsorbPointer(
                   child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: AppTheme.primary.withOpacity(0.3), width: 1),
                        borderRadius: BorderRadius.circular(16),
                        color: AppTheme.surface.withOpacity(0.3),
                      ),
                      padding: const EdgeInsets.all(8),
                      child: content
                   ),
                 ),
                 
                 // Remove Button
                 Positioned(
                   top: -8,
                   right: -8,
                   child: GestureDetector(
                     onTap: () {
                        final index = dashboardItems.indexOf(item);
                        notifier.toggleVisibility(index);
                     },
                     child: Container(
                       padding: const EdgeInsets.all(6),
                       decoration: const BoxDecoration(
                         color: AppTheme.error,
                         shape: BoxShape.circle,
                       ),
                       child: const Icon(Icons.remove, color: Colors.white, size: 16),
                     ),
                   ),
                 ),
               ],
             );
          }

          if (_isEditMode) {
            return Column(
              children: [
                Expanded(
                  child: ReorderableListView(
                    buildDefaultDragHandles: false,
                    padding: const EdgeInsets.fromLTRB(16, 100, 16, 100),
                    onReorder: (oldIndex, newIndex) {
                       int realOldIndex = dashboardItems.indexOf(visibleItems[oldIndex]);
                       int realNewIndex = newIndex >= visibleItems.length 
                           ? dashboardItems.indexOf(visibleItems.last) + 1 
                           : dashboardItems.indexOf(visibleItems[newIndex]);
                       
                       notifier.reorder(realOldIndex, realNewIndex);
                    },
                    children: [
                      for (int i = 0; i < visibleItems.length; i++)
                         FastDragListener(
                           key: ValueKey(visibleItems[i].id),
                           index: i,
                           child: Container(
                             margin: const EdgeInsets.only(bottom: 24),
                             child: buildItem(visibleItems[i]),
                           ),
                         ),
                    ],
                  ),
                ),
                // Hidden Items Section
                if (hiddenItems.isNotEmpty)
                  Container(
                    color: AppTheme.surface,
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Hidden Items', style: TextStyle(color: AppTheme.textDim, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: hiddenItems.map((item) => ActionChip(
                            avatar: const Icon(Icons.add, size: 16, color: AppTheme.background),
                            label: Text(item.title),
                            backgroundColor: AppTheme.primary,
                            labelStyle: const TextStyle(color: AppTheme.background),
                            onPressed: () {
                               final index = dashboardItems.indexOf(item);
                               notifier.toggleVisibility(index);
                            },
                          )).toList(),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          } else {
            // Normal Mode
            return  ListView(
              padding: const EdgeInsets.fromLTRB(16, 100, 16, 100),
              children: [
                for (final item in visibleItems) 
                  Container(
                    margin: const EdgeInsets.only(bottom: 24),
                    child: buildItem(item), // buildItem just returns content in normal mode
                  ),
              ],
            );
          }
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
      ),
      bottomNavigationBar: null,
      floatingActionButton: _isEditMode ? null : Padding(
        padding: const EdgeInsets.only(bottom: 24.0, left: 24, right: 24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Left Side: Glowing AI Status
            const Expanded(
              child: Align(
                alignment: Alignment.bottomLeft,
                child: AIStatusIndicator(),
              ),
            ),
            
            // Center: Massive Neon Floating Button
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppTheme.primary,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primary.withOpacity(0.4),
                    blurRadius: 32,
                    spreadRadius: 4,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: IconButton(
                icon: const Icon(Icons.camera_alt, color: Colors.white, size: 32),
                onPressed: () => context.push('/scan'),
              ),
            ).animate().scale(delay: 500.ms, curve: Curves.elasticOut),
            
            // Right Side: Empty Spacer for symmetrical flex alignment
            const Expanded(child: SizedBox()),
          ],
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  // Refactored to return SINGLE Widget (Column)
  Widget _buildDashboardWidget(
    DashboardItem item,
    BuildContext context,
    String summaryLabel,
    double summaryTotal,
    double? adjustedBudget,
    List<double> chartData,
    List<String> chartLabels,
    List<Receipt> receipts,
    List<Receipt> filteredReceipts,
  ) {
    switch (item.type) {
      case DashboardWidgetType.summary:
        return Column(
          children: [
             Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Total Spent ($summaryLabel)', style: const TextStyle(color: AppTheme.textDim, fontSize: 13)),
                  // Disable dropdown in edit mode? Handled by IgnorePointer in build
                  DropdownButton<SummaryRange>(
                    value: _summaryRange,
                    dropdownColor: AppTheme.surface,
                    underline: const SizedBox(),
                    icon: const Icon(Icons.arrow_drop_down, color: AppTheme.primary),
                    items: SummaryRange.values.map((e) => DropdownMenuItem(
                      value: e,
                      child: Text(e.name.toUpperCase(), style: const TextStyle(color: AppTheme.textMain, fontSize: 12)),
                    )).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _summaryRange = val);
                    },
                  ),
                ],
              ),
              MonthlySpendCard(
                totalAmount: summaryTotal,
                budgetLimit: adjustedBudget,
              ).animate().slideY(begin: -0.2, end: 0, duration: 600.ms, curve: Curves.easeOut),
          ],
        );
      case DashboardWidgetType.chart:
        return Column(
          children: [
             Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                   Text('Activity Trend', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                   DropdownButton<ChartRange>(
                    value: _chartRange,
                    dropdownColor: AppTheme.surface,
                    underline: const SizedBox(),
                    icon: const Icon(Icons.show_chart, color: AppTheme.secondary),
                    items: ChartRange.values.map((e) => DropdownMenuItem(
                      value: e,
                      child: Text(e.name.toUpperCase(), style: const TextStyle(color: AppTheme.secondary, fontSize: 12)),
                    )).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _chartRange = val);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              NeonBarChart(
                data: chartData,
                labels: chartLabels,
              ).animate().fadeIn(delay: 100.ms),
          ],
        );
      case DashboardWidgetType.heatmap:
        return NeonHeatmap(receipts: receipts).animate().fadeIn(delay: 150.ms);
      case DashboardWidgetType.achievements:
        return AchievementsWidget(
                achievements: GamificationService.calculateAchievements(receipts, ref.watch(monthlyBudgetProvider)),
          ).animate().fadeIn(delay: 200.ms);
      case DashboardWidgetType.recentTransactions:
        return Column(
          children: [
             Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                   Text('Recent Transactions', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                   // Category Filter
                   Container(
                     padding: const EdgeInsets.symmetric(horizontal: 12),
                     decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white10),
                     ),
                     child: DropdownButton<String?>(
                      value: _selectedCategory,
                      dropdownColor: AppTheme.surface,
                      underline: const SizedBox(),
                      icon: const Icon(Icons.filter_list, color: AppTheme.primary, size: 18),
                      hint: const Text('Filter', style: TextStyle(color: AppTheme.textDim, fontSize: 13)),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('All', style: TextStyle(color: AppTheme.textMain, fontSize: 13)),
                        ),
                        ...ref.watch(categoryListProvider).map((c) => DropdownMenuItem(
                          value: c,
                          child: Text(c, style: TextStyle(color: AppTheme.textMain, fontSize: 13)),
                        )),
                      ],
                      onChanged: (val) {
                         setState(() => _selectedCategory = val);
                      },
                    ),
                   ),
                ],
              ).animate().fadeIn(delay: 200.ms),
              const SizedBox(height: 16),
              
              if (filteredReceipts.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 48),
                    child: Column(
                      children: [
                        const Icon(Icons.receipt_long, size: 64, color: AppTheme.textDim),
                        const SizedBox(height: 16),
                        Text(
                          _selectedCategory == null ? 'No receipts yet' : 'No receipts in $_selectedCategory', 
                          style: const TextStyle(color: AppTheme.textDim)
                        ),
                      ],
                    ),
                  ),
                )
              else
                ...filteredReceipts.map((receipt) => Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: ReceiptCard(
                    receipt: receipt,
                    onTap: () => context.push('/review', extra: receipt),
                  ),
                )), // ReceiptCard is already a Widget, map returns generic Iterable, toList ensures list of widgets.
                // Wait, ...spread inside Column children list is valid.
          ],
        );
      case DashboardWidgetType.monthlyBudget:
          return const SizedBox.shrink();
      case DashboardWidgetType.necessityBreakdown:
          return const NecessityBreakdownWidget().animate().fadeIn(delay: 200.ms);
    }
  }

}

class FastDragListener extends StatefulWidget {
  final Widget child;
  final int index;
  final Duration delay;

  const FastDragListener({
    super.key,
    required this.child,
    required this.index,
    this.delay = const Duration(milliseconds: 150),
  });

  @override
  State<FastDragListener> createState() => _FastDragListenerState();
}

class _FastDragListenerState extends State<FastDragListener> {
  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (event) {
        // Create a custom recognizer with the desired delay
        final recognizer = DelayedMultiDragGestureRecognizer(delay: widget.delay);
        
        final sliverList = SliverReorderableList.maybeOf(context);
        if (sliverList != null) {
          sliverList.startItemDragReorder(
            index: widget.index,
            event: event,
            recognizer: recognizer,
          );
        } else {
          final list = ReorderableList.maybeOf(context);
          list?.startItemDragReorder(
            index: widget.index,
            event: event,
            recognizer: recognizer,
          );
        }
      },
      child: widget.child,
    );
  }
}
