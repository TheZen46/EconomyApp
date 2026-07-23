import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:math';

import '../../data/providers/boxes_provider.dart';
import '../../data/models/box_model.dart';
import '../widgets/box_creator_sheet.dart';

class BoxesPage extends ConsumerStatefulWidget {
  const BoxesPage({Key? key}) : super(key: key);

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
    final isDark = theme.brightness == Brightness.dark;
    final boxes = ref.watch(boxesProvider);
    final activeId = ref.watch(activeBoxIdProvider);

    final bg = isDark ? const Color(0xFF0A0A0A) : const Color(0xFFFAFAFA);
    final accent = const Color(0xFF002FA7);

    // Responsive layout
    final isWide = MediaQuery.of(context).size.width > 800;

    Widget body = isWide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 1,
                child: _buildBoxList(context, boxes, activeId, isDark),
              ),
              const SizedBox(width: 24),
              Expanded(
                flex: 2,
                child: _buildDetailPanel(context, boxes, activeId, isDark),
              ),
            ],
          )
        : Column(
            children: [
              Expanded(
                flex: 2,
                child: _buildBoxList(context, boxes, activeId, isDark),
              ),
              const SizedBox(height: 16),
              Expanded(
                flex: 3,
                child: _buildDetailPanel(context, boxes, activeId, isDark),
              ),
            ],
          );

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: isDark ? Colors.white : Colors.black),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Boxes',
              style: GoogleFonts.spaceGrotesk(
                color: isDark ? Colors.white : Colors.black,
                fontWeight: FontWeight.bold,
                fontSize: 24,
              ),
            ),
            Text(
              'Activity Contexts',
              style: GoogleFonts.spaceGrotesk(
                color: isDark ? Colors.white70 : Colors.black54,
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
                backgroundColor: accent,
                radius: 18,
                child: const Icon(Icons.add, color: Colors.white, size: 20),
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

  Widget _buildBoxList(BuildContext context, List<BoxModel> boxes, String activeId, bool isDark) {
    return ListView.separated(
      itemCount: boxes.length,
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        final box = boxes[index];
        final isSelected = box.id == _selectedBoxId;
        final isActive = box.id == activeId;

        return GestureDetector(
          onTap: () => setState(() => _selectedBoxId = box.id),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF121212) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected ? const Color(0xFF002FA7).withOpacity(0.5) : (isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.05)),
                width: isSelected ? 2 : 1,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: const Color(0xFF002FA7).withOpacity(0.2),
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
                              color: isDark ? Colors.white : Colors.black,
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            box.id == 'main' ? 'Default Context' : 'Custom Box',
                            style: GoogleFonts.spaceGrotesk(
                              color: isDark ? Colors.white54 : Colors.black45,
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
                          color: const Color(0xFF002FA7).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Active',
                          style: GoogleFonts.spaceGrotesk(
                            color: const Color(0xFF002FA7),
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
                      '${box.currency} ${box.spent.toStringAsFixed(2)}',
                      style: GoogleFonts.jetBrainsMono(
                        color: isDark ? Colors.white : Colors.black,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      box.budget > 0 ? '/ ${box.budget.toStringAsFixed(0)}' : '∞',
                      style: GoogleFonts.jetBrainsMono(
                        color: isDark ? Colors.white54 : Colors.black45,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                if (box.budget > 0) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: (box.spent / box.budget).clamp(0.0, 1.0),
                    backgroundColor: isDark ? Colors.white12 : Colors.black12,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      box.spent > box.budget ? Colors.red : const Color(0xFF002FA7),
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

  Widget _buildDetailPanel(BuildContext context, List<BoxModel> boxes, String activeId, bool isDark) {
    if (_selectedBoxId == null) {
      return Center(
        child: Text(
          'Select a box to view details',
          style: GoogleFonts.spaceGrotesk(
            color: isDark ? Colors.white54 : Colors.black54,
            fontSize: 16,
          ),
        ),
      );
    }

    final box = boxes.firstWhere((b) => b.id == _selectedBoxId, orElse: () => boxes.first);
    final isActive = box.id == activeId;
    final remaining = box.budget > 0 ? box.budget - box.spent : 0.0;
    final isOverBudget = box.budget > 0 && box.spent > box.budget;

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
                  color: isDark ? const Color(0xFF0F0F0F) : Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04),
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
                              color: isDark ? Colors.white : Colors.black,
                              fontWeight: FontWeight.bold,
                              fontSize: 24,
                            ),
                          ),
                          Text(
                            box.keywords.isNotEmpty ? box.keywords : 'No keywords',
                            style: GoogleFonts.spaceGrotesk(
                              color: isDark ? Colors.white54 : Colors.black54,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => _showBoxCreator(context, editBoxId: box.id),
                      icon: Icon(Icons.settings_outlined, color: isDark ? Colors.white : Colors.black),
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
                    backgroundColor: const Color(0xFF002FA7),
                    disabledBackgroundColor: isDark ? Colors.white12 : Colors.black12,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    isActive ? 'Currently Active' : 'Activate Box',
                    style: GoogleFonts.spaceGrotesk(
                      color: isActive ? (isDark ? Colors.white54 : Colors.black54) : Colors.white,
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
                  _buildKpiCard('Budget', box.budget > 0 ? '${box.currency} ${box.budget.toStringAsFixed(0)}' : '∞', isDark),
                  _buildKpiCard('Spent', '${box.currency} ${box.spent.toStringAsFixed(2)}', isDark),
                  _buildKpiCard('Remaining', box.budget > 0 ? '${box.currency} ${remaining.toStringAsFixed(2)}' : '∞', isDark, isOverBudget ? Colors.red : null),
                  _buildKpiCard('Pace', isOverBudget ? 'Over Budget' : 'On Track', isDark, isOverBudget ? Colors.red : const Color(0xFF16a34a)),
                ],
              ),
              const SizedBox(height: 24),

              // Chart Card
              Text(
                'Spending Velocity (14 Days)',
                style: GoogleFonts.spaceGrotesk(
                  color: isDark ? Colors.white : Colors.black,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                height: 200,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F0F0F) : Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04),
                  ),
                ),
                child: _buildChart(isDark),
              ),
              const SizedBox(height: 24),

              // Recent Receipts
              Text(
                'Recent Receipts',
                style: GoogleFonts.spaceGrotesk(
                  color: isDark ? Colors.white : Colors.black,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 16),
              ...List.generate(3, (index) => _buildReceiptRow(index, isDark)),
            ],
          ),
        ),
      ).animate().fadeIn().slideY(begin: 0.05),
    );
  }

  Widget _buildKpiCard(String title, String value, bool isDark, [Color? valueColor]) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F0F0F) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            style: GoogleFonts.spaceGrotesk(
              color: isDark ? Colors.white54 : Colors.black54,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.jetBrainsMono(
              color: valueColor ?? (isDark ? Colors.white : Colors.black),
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChart(bool isDark) {
    // Mock data for 14 days
    final random = Random(42);
    final spots = List.generate(14, (index) {
      return FlSpot(index.toDouble(), random.nextDouble() * 100 + 20);
    });

    return LineChart(
      LineChartData(
        gridData: FlGridData(show: false),
        titlesData: FlTitlesData(
          show: true,
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) {
                return Text(
                  value.toInt().toString(),
                  style: GoogleFonts.jetBrainsMono(
                    color: isDark ? Colors.white54 : Colors.black54,
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
                if (value % 3 != 0) return const SizedBox();
                return Text(
                  'Day ${value.toInt() + 1}',
                  style: GoogleFonts.spaceGrotesk(
                    color: isDark ? Colors.white54 : Colors.black54,
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
            color: const Color(0xFF002FA7),
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF002FA7).withOpacity(0.3),
                  const Color(0xFF002FA7).withOpacity(0.0),
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

  Widget _buildReceiptRow(int index, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F0F0F) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isDark ? Colors.white12 : Colors.black.withOpacity(0.05),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.receipt_long, color: isDark ? Colors.white70 : Colors.black87, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Receipt Placeholder ${index + 1}',
                  style: GoogleFonts.spaceGrotesk(
                    color: isDark ? Colors.white : Colors.black,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '2026-07-2${index + 1}',
                  style: GoogleFonts.jetBrainsMono(
                    color: isDark ? Colors.white54 : Colors.black54,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '\$${(index + 1) * 24.50}',
            style: GoogleFonts.jetBrainsMono(
              color: isDark ? Colors.white : Colors.black,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ],
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
