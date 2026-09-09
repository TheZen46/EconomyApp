import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/receipt.dart';

class ReceiptCard extends StatelessWidget {
  final Receipt receipt;
  final VoidCallback onTap;

  const ReceiptCard({
    super.key,
    required this.receipt,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final categoryColor = _getCategoryColor(receipt.category);
    final hasAssets = receipt.items.any((i) => i.isAsset);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.surface,
            colorScheme.surface.withOpacity(0.85),
          ],
        ),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Category Pill
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: categoryColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: categoryColor.withOpacity(0.35)),
                  ),
                  child: Text(
                    receipt.category.toUpperCase(),
                    style: GoogleFonts.jetBrainsMono(
                      color: categoryColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                
                // Merchant, Date & Items
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              receipt.merchantName,
                              style: GoogleFonts.spaceGrotesk(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: colorScheme.onSurface,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (hasAssets) ...[
                            const SizedBox(width: 6),
                            const Icon(Icons.shield, color: Color(0xFF10B981), size: 13),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            DateFormat.MMMd().format(receipt.date),
                            style: GoogleFonts.spaceGrotesk(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '•  ${receipt.items.length} ${receipt.items.length == 1 ? 'item' : 'items'}',
                            style: GoogleFonts.spaceGrotesk(
                              color: colorScheme.onSurfaceVariant.withOpacity(0.7),
                              fontSize: 11,
                            ),
                          ),
                          if (receipt.boxId != null && receipt.boxId != 'main') ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppColors.accent.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '📦 ${receipt.boxId}',
                                style: GoogleFonts.spaceGrotesk(
                                  fontSize: 10,
                                  color: AppColors.accent,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                
                // Total Amount
                Text(
                  NumberFormat.currency(
                    symbol: receipt.currency == 'EUR' ? '€' : '\$',
                    decimalDigits: 2,
                  ).format(receipt.totalAmount),
                  style: GoogleFonts.jetBrainsMono(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: const Color(0xFF10B981),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ).animate().fadeIn().slideX(begin: 0.04, end: 0, duration: 300.ms);
  }

  Color _getCategoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'grocery':
      case 'fresh produce':
        return const Color(0xFF10B981); // Emerald
      case 'tech':
      case 'electronics':
        return const Color(0xFF0891B2); // Cyan
      case 'transport':
        return const Color(0xFFEC4899); // Pink
      case 'restaurant':
      case 'dining':
        return const Color(0xFFF59E0B); // Amber
      default:
        return const Color(0xFF818CF8); // Indigo
    }
  }
}
