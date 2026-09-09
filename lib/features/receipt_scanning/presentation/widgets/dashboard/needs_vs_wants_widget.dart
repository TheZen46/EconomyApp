import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../domain/entities/receipt.dart';
import '../interactive_hover.dart';

/// Dashboard widget comparing essential spending (Needs) against discretionary spending (Wants).
///
/// Features interactive toggling between percentage allocations and raw currency totals.
class NeedsVsWantsWidget extends StatefulWidget {
  final List<Receipt> receipts;
  final bool isDark;

  const NeedsVsWantsWidget({
    super.key,
    required this.receipts,
    required this.isDark,
  });

  @override
  State<NeedsVsWantsWidget> createState() => _NeedsVsWantsWidgetState();
}

class _NeedsVsWantsWidgetState extends State<NeedsVsWantsWidget> {
  bool _showAmounts = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final fgCol = colorScheme.onSurface;
    final muted = colorScheme.onSurfaceVariant;
    final accent = colorScheme.primary;

    final needsTotal = widget.receipts.fold(0.0, (sum, r) => sum + r.essentialTotal);
    final wantsTotal = widget.receipts.fold(0.0, (sum, r) => sum + (r.totalAmount - r.essentialTotal));
    final total = needsTotal + wantsTotal;

    final needsPercent = total > 0 ? (needsTotal / total * 100).round() : 0;
    final wantsPercent = total > 0 ? (wantsTotal / total * 100).round() : 0;

    final needsFlex = total > 0 ? (needsTotal / total * 100).round() : 50;
    final wantsFlex = total > 0 ? (wantsTotal / total * 100).round() : 50;

    final int safeNeedsFlex = needsFlex > 0 ? needsFlex : 1;
    final int safeWantsFlex = wantsFlex > 0 ? wantsFlex : 1;

    return InteractiveHover(
      onTap: () => setState(() => _showAmounts = !_showAmounts),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'NEEDS VS WANTS',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 11,
                  letterSpacing: 1.2,
                  color: muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                _showAmounts ? 'Tap for %' : 'Tap for \$',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 10,
                  color: muted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ClipRRect(
            borderRadius: BorderRadius.circular(100),
            child: Row(
              children: [
                if (needsFlex > 0)
                  Expanded(
                    flex: safeNeedsFlex,
                    child: Container(
                      height: 16,
                      color: accent,
                    ),
                  ),
                if (needsFlex > 0 && wantsFlex > 0) const SizedBox(width: 6),
                if (wantsFlex > 0)
                  Expanded(
                    flex: safeWantsFlex,
                    child: Container(
                      height: 16,
                      color: colorScheme.surfaceContainerHighest,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 36,
            child: AnimatedCrossFade(
              firstChild: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(width: 8, height: 8, decoration: BoxDecoration(color: accent, shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Needs: $needsPercent%',
                            style: GoogleFonts.spaceGrotesk(fontSize: 12, color: fgCol, fontWeight: FontWeight.w500),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(width: 8, height: 8, decoration: BoxDecoration(color: colorScheme.outline, shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Wants: $wantsPercent%',
                            style: GoogleFonts.spaceGrotesk(fontSize: 12, color: muted),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              secondChild: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      '\$${needsTotal.toStringAsFixed(2)}',
                      style: GoogleFonts.jetBrainsMono(fontSize: 12, fontWeight: FontWeight.bold, color: accent),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      '\$${wantsTotal.toStringAsFixed(2)}',
                      style: GoogleFonts.jetBrainsMono(fontSize: 12, fontWeight: FontWeight.w500, color: muted),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              crossFadeState: _showAmounts ? CrossFadeState.showSecond : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 250),
            ),
          ),
        ],
      ),
    );
  }
}
