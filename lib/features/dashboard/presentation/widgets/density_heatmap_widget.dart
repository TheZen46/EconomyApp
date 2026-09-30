import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:t_aidy/features/receipt_scanning/domain/entities/receipt.dart';
import 'package:t_aidy/features/receipt_scanning/presentation/widgets/interactive_hover.dart';

/// Interactive 28-day transaction density heatmap (GitHub-style activity calendar).
///
/// Accurately aligns calendar days to Monday-Sunday columns, displays exact
/// transaction counts in tooltips, and reflects spending cadence at a glance.
class DensityHeatmapWidget extends StatelessWidget {
  final List<Receipt> receipts;
  final bool isDark;

  const DensityHeatmapWidget({
    super.key,
    required this.receipts,
    required this.isDark,
  });

  Widget _colorBox(Color c) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: c,
          borderRadius: BorderRadius.circular(2),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final muted = colorScheme.onSurfaceVariant;
    final accent = colorScheme.primary;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Align with Monday-Sunday columns across 4 complete calendar weeks (28 days)
    final currentWeekMonday = today.subtract(Duration(days: today.weekday - 1));
    final startMonday = currentWeekMonday.subtract(const Duration(days: 21));

    final dates = List.generate(28, (i) => startMonday.add(Duration(days: i)));
    final counts = List.filled(28, 0);
    final levels = List.filled(28, 0);

    for (int i = 0; i < 28; i++) {
      final targetDate = dates[i];
      if (targetDate.isAfter(today)) {
        counts[i] = -1; // Marker for upcoming / future days
        levels[i] = 0;
        continue;
      }
      final dayReceipts = receipts.where((r) =>
          r.date.year == targetDate.year &&
          r.date.month == targetDate.month &&
          r.date.day == targetDate.day);
      final count = dayReceipts.length;
      counts[i] = count;
      if (count == 0) {
        levels[i] = 0;
      } else if (count == 1) {
        levels[i] = 1;
      } else if (count <= 3) {
        levels[i] = 2;
      } else if (count <= 5) {
        levels[i] = 3;
      } else {
        levels[i] = 4;
      }
    }

    Color getIntensityColor(int level) {
      switch (level) {
        case 1:
          return accent.withOpacity(0.25);
        case 2:
          return accent.withOpacity(0.5);
        case 3:
          return accent.withOpacity(0.75);
        case 4:
          return accent;
        default:
          return colorScheme.surfaceContainerHighest.withOpacity(0.4);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      'TRANSACTION DENSITY',
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 11,
                        letterSpacing: 1.2,
                        color: muted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.info_outline,
                    size: 12,
                    color: muted.withOpacity(0.5),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '4 WEEKS',
              style: GoogleFonts.jetBrainsMono(fontSize: 11, color: muted),
            ),
          ],
        ),
        const SizedBox(height: 20),
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
              return Center(
                child: Text(
                  days[i],
                  style: GoogleFonts.spaceGrotesk(fontSize: 10, color: muted),
                ),
              );
            }
            final targetDate = dates[i - 7];
            final count = counts[i - 7];
            final level = levels[i - 7];

            final String tooltipMsg;
            if (count < 0) {
              tooltipMsg = '${DateFormat('EEE, d MMM').format(targetDate)}: Upcoming';
            } else if (count == 0) {
              tooltipMsg = '${DateFormat('EEE, d MMM').format(targetDate)}: No transactions';
            } else {
              tooltipMsg = '${DateFormat('EEE, d MMM').format(targetDate)}: $count transaction${count == 1 ? '' : 's'}';
            }

            return Tooltip(
              message: tooltipMsg,
              textStyle: GoogleFonts.spaceGrotesk(
                fontSize: 10,
                color: colorScheme.surface,
                fontWeight: FontWeight.bold,
              ),
              decoration: BoxDecoration(
                color: colorScheme.onSurface,
                borderRadius: BorderRadius.circular(8),
              ),
              verticalOffset: 16,
              preferBelow: false,
              child: InteractiveHover(
                child: Container(
                  decoration: BoxDecoration(
                    color: getIntensityColor(level),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.only(top: 14),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: colorScheme.outline.withOpacity(0.5)),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'LESS',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 10,
                  letterSpacing: 1.2,
                  color: muted,
                ),
              ),
              Row(
                children: [
                  _colorBox(getIntensityColor(0)),
                  _colorBox(getIntensityColor(1)),
                  _colorBox(getIntensityColor(2)),
                  _colorBox(getIntensityColor(3)),
                  _colorBox(getIntensityColor(4)),
                ],
              ),
              Text(
                'MORE',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 10,
                  letterSpacing: 1.2,
                  color: muted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}


