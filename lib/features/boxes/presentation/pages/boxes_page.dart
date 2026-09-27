import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/providers/boxes_provider.dart';
import '../../data/models/box_model.dart';
import '../widgets/box_creator_sheet.dart';
import '../../../receipt_scanning/domain/entities/receipt.dart';
import '../../../receipt_scanning/presentation/providers/receipt_provider.dart';

/// Page displaying activity contexts ("Boxes") for compartmentalized expense tracking.
///
/// Enables users to switch active spending contexts, configure budgets, visualize
/// 14-day velocity charts, and inspect box-specific receipt histories.
class BoxesPage extends ConsumerStatefulWidget {
  /// Creates a new [BoxesPage] instance.
  const BoxesPage({super.key});

  @override
  ConsumerState<BoxesPage> createState() => _BoxesPageState();
}

class _BoxesPageState extends ConsumerState<BoxesPage> {
  String? _selectedBoxId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final activeId = ref.read(activeBoxIdProvider);
      setState(() {
        _selectedBoxId = activeId;
      });
    });
  }

  void _showBoxCreator(BuildContext context, {String? editBoxId}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => BoxCreatorSheet(editBoxId: editBoxId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final boxes = ref.watch(boxesProvider);
    final activeId = ref.watch(activeBoxIdProvider);
    final receiptsAsync = ref.watch(receiptListProvider);
    final allReceipts = receiptsAsync.valueOrNull ?? [];

    // Responsive layout
    final isWide = MediaQuery.of(context).size.width > 800;

    Widget body = isWide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 1,
                child: _buildBoxList(context, boxes, activeId, allReceipts, colorScheme),
              ),
              const SizedBox(width: 24),
              Expanded(
                flex: 2,
                child: _buildDetailPanel(context, boxes, activeId, allReceipts, colorScheme),
              ),
            ],
          )
        : Column(
            children: [
              Expanded(
                flex: 2,
                child: _buildBoxList(context, boxes, activeId, allReceipts, colorScheme),
              ),
              const SizedBox(height: 16),
              Expanded(
                flex: 3,
                child: _buildDetailPanel(context, boxes, activeId, allReceipts, colorScheme),
              ),
            ],
          );

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colorScheme.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Boxes',
              style: GoogleFonts.spaceGrotesk(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.bold,
                fontSize: 24,
              ),
            ),
            Text(
              'Activity Contexts',
              style: GoogleFonts.spaceGrotesk(
                color: colorScheme.onSurfaceVariant,
                fontSize: 14,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: IconButton(
              onPressed: () => _showBoxCreator(context),
              icon: CircleAvatar(
                backgroundColor: colorScheme.primary,
                radius: 18,
                child: Icon(Icons.add, color: colorScheme.onPrimary, size: 20),
              ),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
        child: body,
      ),
    );
  }

  double _calculateBoxSpent(BoxModel box, List<Receipt> receipts) {
    final matching = receipts.where((r) {
      if (box.id == 'main') {
        return r.boxId == null || r.boxId == 'main';
      }
      return r.boxId == box.id;
    });
    final sum = matching.fold<double>(0.0, (acc, r) => acc + r.totalAmount);
    return sum > 0 ? sum : box.spent;
  }

  Widget _buildBoxList(BuildContext context, List<BoxModel> boxes, String activeId, List<Receipt> allReceipts, ColorScheme colorScheme) {
    return ListView.separated(
      itemCount: boxes.length,
      separatorBuilder: (ctx, idx) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        final box = boxes[index];
        final isSelected = box.id == _selectedBoxId;
        final isActive = box.id == activeId;
        final spent = _calculateBoxSpent(box, allReceipts);

        return GestureDetector(
          onTap: () => setState(() => _selectedBoxId = box.id),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected ? colorScheme.primary : colorScheme.outline.withValues(alpha: 0.3),
                width: isSelected ? 2 : 1,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: colorScheme.primary.withValues(alpha: 0.2),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      )
                    ]
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: Color(box.color),
                      child: Icon(_getIconData(box.icon), color: Colors.white, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            box.name,
                            style: GoogleFonts.spaceGrotesk(
                              color: colorScheme.onSurface,
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            box.id == 'main' ? 'Default Context' : 'Custom Box',
                            style: GoogleFonts.spaceGrotesk(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isActive)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Active',
                          style: GoogleFonts.spaceGrotesk(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${box.currency} ${spent.toStringAsFixed(2)}',
                      style: GoogleFonts.jetBrainsMono(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      box.budget > 0 ? '/ ${box.budget.toStringAsFixed(0)}' : '∞',
                      style: GoogleFonts.jetBrainsMono(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                if (box.budget > 0) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: (spent / box.budget).clamp(0.0, 1.0),
                    backgroundColor: colorScheme.outline.withValues(alpha: 0.2),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      spent > box.budget ? colorScheme.error : colorScheme.primary,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ],
              ],
            ),
          ),
        ).animate().fadeIn(delay: Duration(milliseconds: 50 * index)).slideX(begin: -0.1);
      },
    );
  }

  Widget _buildDetailPanel(
    BuildContext context,
    List<BoxModel> boxes,
    String activeId,
    List<Receipt> allReceipts,
    ColorScheme colorScheme,
  ) {
    if (_selectedBoxId == null) {
      return Center(
        child: Text(
          'Select a box to view details',
          style: GoogleFonts.spaceGrotesk(
            color: colorScheme.onSurfaceVariant,
            fontSize: 16,
          ),
        ),
      );
    }

    final box = boxes.firstWhere((b) => b.id == _selectedBoxId, orElse: () => boxes.first);
    final isActive = box.id == activeId;
    final spent = _calculateBoxSpent(box, allReceipts);
    final remaining = box.budget > 0 ? box.budget - spent : 0.0;
    final isOverBudget = box.budget > 0 && spent > box.budget;

    // Filter receipts belonging to this box
    final boxReceipts = allReceipts.where((r) {
      if (box.id == 'main') {
        return r.boxId == null || r.boxId == 'main';
      }
      return r.boxId == box.id;
    }).toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: Container(
        key: ValueKey(box.id),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Card
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: colorScheme.outline.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: Color(box.color),
                      child: Icon(_getIconData(box.icon), color: Colors.white, size: 28),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            box.name,
                            style: GoogleFonts.spaceGrotesk(
                              color: colorScheme.onSurface,
                              fontWeight: FontWeight.bold,
                              fontSize: 24,
                            ),
                          ),
                          Text(
                            box.keywords.isNotEmpty ? box.keywords : 'No keywords',
                            style: GoogleFonts.spaceGrotesk(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => _showBoxCreator(context, editBoxId: box.id),
                      icon: Icon(Icons.settings_outlined, color: colorScheme.onSurface),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              
              // Activate Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: isActive
                      ? null
                      : () {
                          ref.read(activeBoxIdProvider.notifier).state = box.id;
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    disabledBackgroundColor: colorScheme.surfaceContainerHighest,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    isActive ? 'Currently Active' : 'Activate Box',
                    style: GoogleFonts.spaceGrotesk(
                      color: isActive ? colorScheme.onSurfaceVariant : colorScheme.onPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // KPI Grid
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 2,
                children: [
                  _buildKpiCard('Budget', box.budget > 0 ? '${box.currency} ${box.budget.toStringAsFixed(0)}' : '∞', colorScheme),
                  _buildKpiCard('Spent', '${box.currency} ${spent.toStringAsFixed(2)}', colorScheme),
                  _buildKpiCard('Remaining', box.budget > 0 ? '${box.currency} ${remaining.toStringAsFixed(2)}' : '∞', colorScheme, isOverBudget ? colorScheme.error : null),
                  _buildKpiCard('Pace', isOverBudget ? 'Over Budget' : 'On Track', colorScheme, isOverBudget ? colorScheme.error : const Color(0xFF16a34a)),
                ],
              ),
              const SizedBox(height: 24),

              // Chart Card
              Text(
                'Spending Velocity (14 Days)',
                style: GoogleFonts.spaceGrotesk(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                height: 200,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: colorScheme.outline.withValues(alpha: 0.3),
                  ),
                ),
                child: _buildChart(boxReceipts, colorScheme),
              ),
              const SizedBox(height: 24),

              // Recent Receipts
              Text(
                'Recent Receipts (${boxReceipts.length})',
                style: GoogleFonts.spaceGrotesk(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 16),
              if (boxReceipts.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  alignment: Alignment.center,
                  child: Text(
                    'No receipts recorded for this box yet.',
                    style: GoogleFonts.spaceGrotesk(color: colorScheme.onSurfaceVariant, fontSize: 14),
                  ),
                )
              else
                ...boxReceipts.take(5).map((r) => _buildReceiptRow(context, r, box.currency, colorScheme)),
            ],
          ),
        ),
      ).animate().fadeIn().slideY(begin: 0.05),
    );
  }

  Widget _buildKpiCard(String title, String value, ColorScheme colorScheme, [Color? valueColor]) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            style: GoogleFonts.spaceGrotesk(
              color: colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.jetBrainsMono(
              color: valueColor ?? colorScheme.onSurface,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChart(List<Receipt> boxReceipts, ColorScheme colorScheme) {
    final now = DateTime.now();
    final spots = List.generate(14, (index) {
      final targetDate = now.subtract(Duration(days: 13 - index));
      final daySpend = boxReceipts
          .where((r) =>
              r.date.year == targetDate.year &&
              r.date.month == targetDate.month &&
              r.date.day == targetDate.day)
          .fold(0.0, (sum, r) => sum + r.totalAmount);
      return FlSpot(index.toDouble(), daySpend);
    });

    final maxSpend = spots.fold<double>(0.0, (max, spot) => spot.y > max ? spot.y : max);
    final effectiveMaxY = maxSpend > 0 ? (maxSpend * 1.2).ceilToDouble() : 100.0;

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: effectiveMaxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: effectiveMaxY / 4 > 0 ? effectiveMaxY / 4 : 25,
          getDrawingHorizontalLine: (val) => FlLine(color: colorScheme.outline.withValues(alpha: 0.1), strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          show: true,
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 42,
              getTitlesWidget: (value, meta) {
                return Text(
                  value.toInt().toString(),
                  style: GoogleFonts.jetBrainsMono(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 10,
                  ),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final int idx = value.toInt();
                if (idx % 3 != 0 && idx != 13) return const SizedBox();
                final date = now.subtract(Duration(days: 13 - idx));
                return Text(
                  DateFormat('dd/MM').format(date),
                  style: GoogleFonts.spaceGrotesk(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 10,
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: colorScheme.primary,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  colorScheme.primary.withValues(alpha: 0.3),
                  colorScheme.primary.withValues(alpha: 0.0),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ],
      ),
    ).animate().fade(duration: const Duration(milliseconds: 600));
  }

  Widget _buildReceiptRow(BuildContext context, Receipt receipt, String currency, ColorScheme colorScheme) {
    return GestureDetector(
      onTap: () => context.push('/review', extra: receipt),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: colorScheme.outline.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.receipt_long, color: colorScheme.primary, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    receipt.merchantName.isNotEmpty ? receipt.merchantName : 'Receipt',
                    style: GoogleFonts.spaceGrotesk(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    DateFormat('yyyy-MM-dd').format(receipt.date),
                    style: GoogleFonts.jetBrainsMono(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '$currency ${receipt.totalAmount.toStringAsFixed(2)}',
              style: GoogleFonts.jetBrainsMono(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getIconData(String? iconName) {
    switch (iconName) {
      case 'Briefcase':
        return Icons.work_outline;
      case 'Plane':
        return Icons.flight_takeoff;
      case 'Target':
        return Icons.track_changes;
      case 'Activity':
        return Icons.local_activity_outlined;
      case 'Home':
      default:
        return Icons.home_outlined;
    }
  }
}
