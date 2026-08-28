import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../domain/entities/receipt.dart';
import '../interactive_hover.dart';

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
    final densityData = List.filled(28, 0);
    for (int i = 0; i < 28; i++) {
      final targetDate = now.subtract(Duration(days: 27 - i));
      final count = receipts
          .where((r) =>
              r.date.year == targetDate.year &&
              r.date.month == targetDate.month &&
              r.date.day == targetDate.day)
          .length;
      if (count == 0) {
        densityData[i] = 0;
      } else if (count <= 1) {
        densityData[i] = 1;
      } else if (count <= 3) {
        densityData[i] = 2;
      } else if (count <= 5) {
        densityData[i] = 3;
      } else {
        densityData[i] = 4;
      }
    }

    Color getIntensityColor(int level) {
      switch (level) {
        case 1:
          return accent.withOpacity(0.2);
        case 2:
          return accent.withOpacity(0.4);
        case 3:
          return accent.withOpacity(0.7);
        case 4:
          return accent;
        default:
          return colorScheme.surfaceContainerHighest;
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
                    child: Text('TRANSACTION DENSITY',
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.spaceGrotesk(
                            fontSize: 11, letterSpacing: 1.2, color: muted)),
                  ),
                  const SizedBox(width: 6),
                  Icon(Icons.info_outline,
                      size: 12, color: muted.withOpacity(0.5)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text('28 DAYS',
                style: GoogleFonts.jetBrainsMono(fontSize: 11, color: muted)),
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
              return Center(
                  child: Text(days[i],
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 10, color: muted)));
            }
            final level = densityData[i - 7];
            return Tooltip(
              message: 'Day ${i - 6}: ${['0', '2', '5', '12', '24'][level]}',
              textStyle: GoogleFonts.spaceGrotesk(
                  fontSize: 10,
                  color: colorScheme.surface,
                  fontWeight: FontWeight.bold),
              decoration: BoxDecoration(
                  color: colorScheme.onSurface,
                  borderRadius: BorderRadius.circular(8)),
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
          decoration: BoxDecoration(
              border: Border(
                  top: BorderSide(
                      color: colorScheme.outline))),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('LESS',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 10, letterSpacing: 1.2, color: muted)),
              Row(
                children: [
                  _colorBox(getIntensityColor(0)),
                  _colorBox(getIntensityColor(1)),
                  _colorBox(getIntensityColor(2)),
                  _colorBox(getIntensityColor(3)),
                  _colorBox(getIntensityColor(4)),
                ],
              ),
              Text('MORE',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 10, letterSpacing: 1.2, color: muted)),
            ],
          ),
        )
      ],
    );
  }
}
