import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../core/theme/app_theme.dart';

class NeonBarChart extends StatelessWidget {
  final List<double> data;
  final List<String> labels;
  final double height;

  const NeonBarChart({
    super.key,
    required this.data,
    required this.labels,
    this.height = 150,
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const SizedBox();

    final maxVal = data.reduce((curr, next) => curr > next ? curr : next);
    // Avoid division by zero
    final safeMax = maxVal == 0 ? 1 : maxVal;

    return Container(
      height: height,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface.withAlpha(127),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withAlpha(12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'LAST 7 DAYS',
            style: const TextStyle(
              color: AppTheme.textDim,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(data.length, (index) {
              final value = data[index];
              final percentage = value / safeMax;
              final label = labels[index];
              
              return Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // The Bar
                  Container(
                    width: 12,
                    height: (height * 0.5) * percentage, // Max 50% of container height (was 60% causing overflow)
                    decoration: BoxDecoration(
                      color: percentage == 1.0 ? AppTheme.secondary : AppTheme.primary.withAlpha(127),
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: percentage == 1.0 
                        ? [BoxShadow(color: AppTheme.secondary.withAlpha(127), blurRadius: 8)] 
                        : [],
                    ),
                  ).animate().scaleY(
                    begin: 0, 
                    end: 1, 
                    duration: (600 + (index * 100)).ms, 
                    curve: Curves.easeOutQuart,
                    alignment: Alignment.bottomCenter
                  ),
                  const SizedBox(height: 8),
                  // The Label
                  Text(
                    label,
                    style: const TextStyle(
                      color: AppTheme.textDim,
                      fontSize: 10,
                    ),
                  ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }
}
