import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_animate/flutter_animate.dart';
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
    // Determine color based on category
    final categoryColor = _getCategoryColor(receipt.category);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        // Glassmorphic Gradient: Level 1 -> Level 0
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.surface, AppTheme.background],
        ),
        // Glass Edge
        border: Border.all(color: Colors.white.withOpacity(0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
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
                // Category Pill (replacing circle icon)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: categoryColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: categoryColor.withOpacity(0.3)),
                  ),
                  child: Text(
                    receipt.category.toUpperCase(),
                    style: TextStyle(
                      color: categoryColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                
                // Merchant & Date
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        receipt.merchantName,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textMain,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        DateFormat.MMMd().format(receipt.date),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppTheme.textDim,
                            ),
                      ),
                    ],
                  ),
                ),
                
                // Total Amount
                Text(
                  NumberFormat.currency(
                    symbol: receipt.currency == 'EUR' ? '€' : '\$',
                    decimalDigits: 2,
                  ).format(receipt.totalAmount),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w300, // Light weight for numbers
                        color: AppTheme.secondary,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    ).animate().fadeIn().slideX(begin: 0.05, end: 0, duration: 400.ms);
  }

  Color _getCategoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'grocery': return const Color(0xFF4ADE80); // Neon Green
      case 'tech': return const Color(0xFF38BDF8);    // Sky Blue
      case 'transport': return const Color(0xFFF472B6);
      case 'restaurant': return const Color(0xFFFACC15);
      default: return const Color(0xFF94A3B8);
    }
  }
}
