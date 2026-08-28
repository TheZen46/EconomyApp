import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/receipt.dart';

class NeonHeatmap extends StatelessWidget {
  final List<Receipt> receipts;
  final int weeksToShow;

  const NeonHeatmap({
    super.key,
    required this.receipts,
    this.weeksToShow = 18, // Adjusted for typical width
  });

  @override
  Widget build(BuildContext context) {
    // 1. Process Data
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    final spendingMap = <String, double>{};
    double maxDailySpend = 0.0;

    for (final r in receipts) {
      final key = DateFormat('yyyy-MM-dd').format(r.date);
      spendingMap[key] = (spendingMap[key] ?? 0) + r.totalAmount;
      if (spendingMap[key]! > maxDailySpend) {
        maxDailySpend = spendingMap[key]!;
      }
    }
    if (maxDailySpend == 0) maxDailySpend = 1; 

    // 2. Calculate Grid Alignment (Standard / GitHub Style)
    // Rows: 7 (Sun -> Sat). 
    // Top Row (0) = Sunday. 
    // Columns: weeksToShow.
    // Last Column: The current week containing Today.
    
    // Find the Sunday of the current week.
    // If today is Sunday (weekday=7 in ISO, but let's treat Sun=0 for calc),
    // wait, Dart DateTime.weekday is 1=Mon ... 7=Sun.
    // We want to find the LAST Sunday (or today if today is Sunday).
    // shift = today.weekday % 7. 
    // If today is Sunday(7), shift=0. Start=Today. 
    // If today is Monday(1), shift=1. Start=Yesterday.
    final shift = today.weekday % 7; 
    final currentWeekSunday = today.subtract(Duration(days: shift));
    
    // Start Date of the Grid (Top-Left cell of the first column)
    // This should be (weeksToShow - 1) weeks before currentWeekSunday.
    final gridStartDate = currentWeekSunday.subtract(Duration(days: (weeksToShow - 1) * 7));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface.withAlpha(127),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Spending Pulse',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: AppTheme.textDim,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                ),
              ),
              // Show month range? e.g. "Oct - Jan"
              Text(
                '${DateFormat('MMM').format(gridStartDate)} - ${DateFormat('MMM').format(today)}',
                style: TextStyle(color: AppTheme.textDim.withAlpha(127), fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              const gap = 3.0;
              final totalGap = (weeksToShow - 1) * gap;
              final cellSize = (width - totalGap) / weeksToShow;
              final height = 7 * cellSize + 6 * gap;

              return SizedBox(
                height: height,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(weeksToShow, (weekIndex) {
                    return SizedBox(
                      width: cellSize,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: List.generate(7, (dayIndex) {
                          // Calculate exact date for this cell
                          // date = gridStartDate + (week * 7) + day
                          final date = gridStartDate.add(Duration(days: (weekIndex * 7) + dayIndex));
                          
                          // Check if future
                          if (date.isAfter(today)) {
                             return Container(
                               height: cellSize,
                               decoration: BoxDecoration(
                                 color: Colors.white.withAlpha(5), // Very faint placeholder
                                 shape: BoxShape.circle, // Dot pattern for future? Or just invisible?
                                 // GitHub leaves them empty/invisible usually.
                               ),
                             );
                          }
                          
                          final key = DateFormat('yyyy-MM-dd').format(date);
                          final amount = spendingMap[key] ?? 0.0;
                          final intensity = (amount / maxDailySpend).clamp(0.0, 1.0);
                          
                          Color color;
                          if (amount == 0) {
                             color = Colors.white.withAlpha(12); // Standard empty cell
                          } else {
                             color = Color.lerp(
                                AppTheme.primary.withAlpha(76), 
                                AppTheme.secondary, 
                                intensity
                              )!;
                          }

                          return Tooltip(
                            message: '${DateFormat('EEE, MMM d').format(date)}\n€${amount.toStringAsFixed(2)}',
                            triggerMode: TooltipTriggerMode.tap,
                            decoration: BoxDecoration(
                              color: AppTheme.surface,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white24),
                            ),
                             child: Container(
                              height: cellSize,
                              width: cellSize,
                              decoration: BoxDecoration(
                                color: color,
                                borderRadius: BorderRadius.circular(2),
                                // Optional: GitHub borders cells slightly? No, separated.
                                boxShadow: intensity > 0.6 ? [
                                  BoxShadow(
                                    color: color.withAlpha(102),
                                    blurRadius: 3,
                                  )
                                ] : null,
                              ),
                            ),
                          );
                        }),
                      ),
                    );
                  }),
                ),
              );
            },
          ),
          
          const SizedBox(height: 8),
          
          // Days Label (M W F) - Optional but GitHub has it
          // Or Legend
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text('Less', style: TextStyle(color: AppTheme.textDim.withAlpha(127), fontSize: 10)),
              const SizedBox(width: 4),
              _legendBox(Colors.white.withAlpha(12)),
              const SizedBox(width: 2),
              _legendBox(AppTheme.primary.withAlpha(76)),
              const SizedBox(width: 2),
              _legendBox(AppTheme.secondary),
              const SizedBox(width: 4),
              Text('More', style: TextStyle(color: AppTheme.textDim.withAlpha(127), fontSize: 10)),
            ],
          )
        ],
      ),
    );
  }

  Widget _legendBox(Color color) {
    return Container(
      width: 10, 
      height: 10, 
      decoration: BoxDecoration(
        color: color, 
        borderRadius: BorderRadius.circular(2)
      )
    );
  }
}
