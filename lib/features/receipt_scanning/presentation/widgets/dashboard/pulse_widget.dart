import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../domain/entities/receipt.dart';

class PulseWidget extends StatelessWidget {
  final List<Receipt> receipts;
  final bool isDark;

  const PulseWidget({
    super.key,
    required this.receipts,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final fgCol = colorScheme.onSurface;
    final muted = colorScheme.onSurfaceVariant;
    final accent = colorScheme.primary;
    
    // Real data: trailing 12 months
    final now = DateTime.now();
    final List<double> data = List.filled(12, 0.0);
    final List<String> months = List.filled(12, '');
    
    double essentialSpend = 0.0;
    double discretionalSpend = 0.0;
    double junkSpend = 0.0;

    for (int i = 0; i < 12; i++) {
      final targetDate = DateTime(now.year, now.month - 11 + i);
      final monthReceipts = receipts.where((r) => r.date.year == targetDate.year && r.date.month == targetDate.month);
      data[i] = monthReceipts.fold(0.0, (sum, r) => sum + r.totalAmount);
      months[i] = DateFormat('MMM').format(targetDate);
    }

    // Tally 3-tier necessity taxonomy
    for (final receipt in receipts) {
      for (final item in receipt.items) {
        switch (item.necessity) {
          case ItemNecessity.essential:
            essentialSpend += item.totalPrice;
            break;
          case ItemNecessity.discretional:
            discretionalSpend += item.totalPrice;
            break;
          case ItemNecessity.junk:
            junkSpend += item.totalPrice;
            break;
          case ItemNecessity.unknown:
            discretionalSpend += item.totalPrice;
            break;
        }
      }
    }
    
    final totalNecessity = (essentialSpend + discretionalSpend + junkSpend);
    final essentialPct = totalNecessity > 0 ? (essentialSpend / totalNecessity) : 0.0;
    final discretionalPct = totalNecessity > 0 ? (discretionalSpend / totalNecessity) : 0.0;
    final junkPct = totalNecessity > 0 ? (junkSpend / totalNecessity) : 0.0;

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
        const SizedBox(height: 24),
        
        // ─── 3-Tier Necessity Taxonomy Telemetry HUD ────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainer.withOpacity(0.5),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colorScheme.outline.withOpacity(0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('AI NECESSITY BREAKDOWN', style: GoogleFonts.spaceGrotesk(fontSize: 10, letterSpacing: 1.1, color: muted, fontWeight: FontWeight.w600)),
                  Text('${(essentialPct * 100).toStringAsFixed(0)}% Essential', style: GoogleFonts.jetBrainsMono(fontSize: 10, color: const Color(0xFF10B981), fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  height: 6,
                  child: Row(
                    children: [
                      if (essentialPct > 0)
                        Expanded(
                          flex: (essentialPct * 100).toInt().clamp(1, 100),
                          child: Container(color: const Color(0xFF10B981)),
                        ),
                      if (discretionalPct > 0)
                        Expanded(
                          flex: (discretionalPct * 100).toInt().clamp(1, 100),
                          child: Container(color: const Color(0xFF0891B2)),
                        ),
                      if (junkPct > 0)
                        Expanded(
                          flex: (junkPct * 100).toInt().clamp(1, 100),
                          child: Container(color: const Color(0xFFEC4899)),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _necessityBadge('Essential', '\$${essentialSpend.toStringAsFixed(0)}', const Color(0xFF10B981)),
                  _necessityBadge('Discretional', '\$${discretionalSpend.toStringAsFixed(0)}', const Color(0xFF0891B2)),
                  _necessityBadge('Junk', '\$${junkSpend.toStringAsFixed(0)}', const Color(0xFFEC4899)),
                ],
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 24),
        SizedBox(
          height: 200,
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
                      if (value.toInt() % 2 != 0) return const SizedBox();
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
                  barWidth: 2.0,
                  isStrokeCapRound: true,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      colors: [accent.withOpacity(0.20), accent.withOpacity(0.0)],
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
                      FlLine(color: accent, strokeWidth: 1),
                      FlDotData(show: true, getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(radius: 4, color: accent, strokeWidth: 2, strokeColor: colorScheme.surface)),
                    );
                  }).toList();
                },
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (touchedSpot) => colorScheme.surface,
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
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.only(top: 16),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: colorScheme.outline))),
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    'Monthly project burn & income — Trailing 12 months', 
                    style: GoogleFonts.spaceGrotesk(fontSize: 12, color: muted),
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

  Widget _necessityBadge(String label, String value, Color color) {
    return Row(
      children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
        const SizedBox(width: 4),
        Text('$label: ', style: GoogleFonts.spaceGrotesk(fontSize: 10, color: Colors.grey)),
        Text(value, style: GoogleFonts.jetBrainsMono(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }
}
