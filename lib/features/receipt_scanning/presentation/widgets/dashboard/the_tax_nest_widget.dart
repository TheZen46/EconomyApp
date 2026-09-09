import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../../../core/constants/app_constants.dart';
import '../../../domain/entities/receipt.dart';

/// Interactive dashboard widget displaying estimated tax reserves (The Tax Nest).
///
/// Computes quarterly and year-to-date tax liability allocations from processed receipts
/// and provides an auto-stash configuration interface for freelance financial planning.
class TheTaxNestWidget extends ConsumerStatefulWidget {
  final List<Receipt> receipts;
  final bool isDark;

  const TheTaxNestWidget({
    super.key,
    required this.receipts,
    required this.isDark,
  });

  @override
  ConsumerState<TheTaxNestWidget> createState() => _TheTaxNestWidgetState();
}

class _TheTaxNestWidgetState extends ConsumerState<TheTaxNestWidget> {
  double _taxRate = AppConstants.defaultTaxRate;
  double _goal = AppConstants.defaultTaxNestGoal;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final fgCol = colorScheme.onSurface;
    final muted = colorScheme.onSurfaceVariant;
    final accent = colorScheme.primary;

    final ytdTotal = widget.receipts.fold(0.0, (sum, r) => sum + r.totalAmount);
    final stashed = ytdTotal * _taxRate;
    final progressPercent = _goal > 0 ? (stashed / _goal * 100).clamp(0.0, 100.0) : 0.0;

    final now = DateTime.now();
    final quarter = ((now.month - 1) ~/ 3) + 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.shield_outlined, color: accent, size: 16),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'THE TAX NEST',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 11,
                        letterSpacing: 1.2,
                        color: muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: accent.withAlpha(25),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${(_taxRate * 100).toInt()}% Auto-Stash',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: accent,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        GestureDetector(
          onTap: () => _showTaxGoalDialog(context, stashed, progressPercent),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '\$${stashed.toStringAsFixed(2)}',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 38,
                  fontWeight: FontWeight.w300,
                  color: fgCol,
                ),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Stashed for Q$quarter ${now.year}',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 13,
                      color: muted,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  Text(
                    '(${progressPercent.toStringAsFixed(0)}% of goal)',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      color: accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 60,
          child: _buildTaxHistoryChart(accent),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: fgCol,
              side: BorderSide(color: colorScheme.outline),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            icon: Icon(Icons.tune, size: 14, color: muted),
            onPressed: () => _showAutoStashConfigSheet(context),
            label: Text(
              'Configure Tax Withholding',
              style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w500, fontSize: 12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTaxHistoryChart(Color accent) {
    final now = DateTime.now();
    // Compute last 6 months' tax stashes from actual receipt data
    final List<double> monthlyStashes = List.generate(6, (i) {
      final monthDate = DateTime(now.year, now.month - 5 + i);
      final monthTotal = widget.receipts
          .where((r) => r.date.year == monthDate.year && r.date.month == monthDate.month)
          .fold(0.0, (sum, r) => sum + r.totalAmount);
      return monthTotal * _taxRate;
    });

    final maxVal = monthlyStashes.fold(100.0, (max, val) => val > max ? val : max);

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              return BarTooltipItem(
                '\$${rod.toY.toStringAsFixed(2)}',
                GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 11),
              );
            },
          ),
        ),
        titlesData: const FlTitlesData(show: false),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        maxY: maxVal * 1.2,
        barGroups: List.generate(6, (i) {
          final val = monthlyStashes[i];
          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: val > 0 ? val : 5.0, // Minimum visual height
                color: accent.withAlpha(80 + i * 28),
                width: 10,
                borderRadius: BorderRadius.circular(3),
              ),
            ],
          );
        }),
      ),
    );
  }

  void _showTaxGoalDialog(BuildContext context, double currentStashed, double progress) {
    final colorScheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Tax Nest Goal',
          style: GoogleFonts.spaceGrotesk(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Target Goal: \$${_goal.toStringAsFixed(2)}',
              style: GoogleFonts.spaceGrotesk(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Text(
              'Current Reserves: \$${currentStashed.toStringAsFixed(2)} (${progress.toStringAsFixed(1)}%)',
              style: GoogleFonts.jetBrainsMono(
                color: colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: (progress / 100.0).clamp(0.0, 1.0),
              backgroundColor: colorScheme.outline,
              valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
              borderRadius: BorderRadius.circular(4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Close', style: GoogleFonts.spaceGrotesk(color: colorScheme.primary)),
          ),
        ],
      ),
    );
  }

  void _showAutoStashConfigSheet(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final fgCol = colorScheme.onSurface;
    final muted = colorScheme.onSurfaceVariant;
    double selectedRate = _taxRate;
    double selectedGoal = _goal;

    showModalBottomSheet(
      context: context,
      backgroundColor: colorScheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
                left: 24,
                right: 24,
                top: 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tax Nest Configuration',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: fgCol,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Set your automatic tax buffer percentage and annual savings target.',
                    style: GoogleFonts.spaceGrotesk(fontSize: 13, color: muted),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Tax Buffer Rate: ${(selectedRate * 100).toInt()}%',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: fgCol,
                    ),
                  ),
                  Slider(
                    value: selectedRate,
                    min: 0.05,
                    max: 0.45,
                    divisions: 8,
                    activeColor: colorScheme.primary,
                    label: '${(selectedRate * 100).toInt()}%',
                    onChanged: (val) => setModalState(() => selectedRate = val),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    initialValue: selectedGoal.toStringAsFixed(0),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: GoogleFonts.jetBrainsMono(color: fgCol),
                    decoration: InputDecoration(
                      labelText: 'Annual Goal Target (\$)',
                      labelStyle: TextStyle(color: muted),
                      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: colorScheme.outline)),
                      focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: colorScheme.primary)),
                    ),
                    onChanged: (v) {
                      final parsed = double.tryParse(v);
                      if (parsed != null && parsed > 0) selectedGoal = parsed;
                    },
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colorScheme.primary,
                        foregroundColor: colorScheme.onPrimary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () {
                        setState(() {
                          _taxRate = selectedRate;
                          _goal = selectedGoal;
                        });
                        Navigator.pop(ctx);
                      },
                      child: Text('Save Settings', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
