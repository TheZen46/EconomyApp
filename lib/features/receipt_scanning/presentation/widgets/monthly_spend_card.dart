import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../core/theme/app_theme.dart';

class MonthlySpendCard extends StatelessWidget {
  final double totalAmount;
  final double? budgetLimit;

  const MonthlySpendCard({super.key, required this.totalAmount, this.budgetLimit});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        // Glassmorphic Gradient
        gradient: LinearGradient(
          colors: [
            AppTheme.surface, 
            AppTheme.background, 
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.primary.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This Month',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppTheme.textDim,
                  letterSpacing: 1.2,
                ),
          ),
          const SizedBox(height: 8),
          
          // Counting Text Animation
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: totalAmount),
            duration: const Duration(milliseconds: 1500),
            curve: Curves.easeOutExpo,
            builder: (context, value, child) {
               return Text(
                '€${value.toStringAsFixed(2)}',
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w300, // Light weight
                      color: AppTheme.textMain,
                    ),
              );
            },
          ),
          
          if (budgetLimit != null && budgetLimit! > 0) ...[
            const SizedBox(height: 16),
             Builder(builder: (context) {
               final pct = (totalAmount / budgetLimit!).clamp(0.0, 1.0);
               final isOver = totalAmount > budgetLimit!;
               final color = pct < 0.5 ? Colors.greenAccent 
                           : pct < 0.85 ? Colors.amberAccent 
                           : AppTheme.error;
                           
               return Column(
                 crossAxisAlignment: CrossAxisAlignment.start,
                 children: [
                   Row(
                     mainAxisAlignment: MainAxisAlignment.spaceBetween,
                     children: [
                       Text(
                         '${(pct * 100).toStringAsFixed(0)}% of Budget',
                         style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
                       ),
                       Text(
                         'Limit: €${budgetLimit!.toStringAsFixed(0)}',
                         style: const TextStyle(color: AppTheme.textDim, fontSize: 12),
                       ),
                     ],
                   ),
                   const SizedBox(height: 8),
                   ClipRRect(
                     borderRadius: BorderRadius.circular(4),
                     child: LinearProgressIndicator(
                       value: pct,
                       backgroundColor: Colors.white10,
                       valueColor: AlwaysStoppedAnimation<Color>(color),
                       minHeight: 6,
                     ),
                   )
                   .animate() // Entry animation
                   .slideX(begin: -1, duration: 1000.ms, curve: Curves.easeOutExpo)
                   .animate( // Over-budget shimmer loop
                     onPlay: (controller) => isOver ? controller.repeat() : null,
                   )
                   .shimmer(
                     duration: 1500.ms, 
                     color: isOver ? Colors.white.withOpacity(0.6) : Colors.transparent
                   ), 
                 ],
               );
             }),
          ]
        ],
      ),
    );
  }
}
