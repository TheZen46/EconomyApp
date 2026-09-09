import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../receipt_scanning/presentation/providers/receipt_provider.dart';
import '../../data/models/box_model.dart';
import '../../data/providers/boxes_provider.dart';
import '../../domain/burn_rate_calculator.dart';

/// State provider for active rolling velocity window in the Pulse HUD.
final pulseVelocityWindowProvider = StateProvider<VelocityWindow>((ref) => VelocityWindow.days7);

/// A Cyberpunk / Modern FinTech Burn-Rate HUD Widget.
///
/// Displays real-time spend velocity, projected month-end budget burn,
/// and dynamic risk status gauges (On-Track / Warning / Over-Budget).
class PulseWidget extends ConsumerWidget {
  final BoxModel? box;

  const PulseWidget({
    super.key,
    this.box,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    final selectedWindow = ref.watch(pulseVelocityWindowProvider);
    final activeBoxId = ref.watch(activeBoxIdProvider);
    final boxes = ref.watch(boxesProvider);
    final receiptsAsync = ref.watch(receiptListProvider);

    final currentBox = box ?? boxes.cast<BoxModel?>().firstWhere(
          (b) => b?.id == activeBoxId,
          orElse: () => null,
        );

    return receiptsAsync.when(
      data: (receipts) {
        final metrics = BurnRateCalculator.calculate(
          box: currentBox,
          receipts: receipts,
          window: selectedWindow,
        );

        return _buildHudCard(context, ref, metrics, colorScheme, textTheme);
      },
      loading: () => _buildLoadingCard(colorScheme),
      error: (err, stack) => const SizedBox.shrink(),
    );
  }

  Widget _buildHudCard(
    BuildContext context,
    WidgetRef ref,
    BurnRateMetrics metrics,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    final currencyFormatter = NumberFormat.currency(symbol: _getCurrencySymbol(metrics.currency));
    final statusColor = _getStatusColor(metrics.status, colorScheme);
    final statusBadge = _buildStatusBadge(metrics.status, colorScheme);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: statusColor.withValues(alpha: 0.35),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: statusColor.withValues(alpha: 0.08),
            blurRadius: 16,
            spreadRadius: 2,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Header: HUD Label + Status Badge
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.speed_rounded,
                        size: 20,
                        color: statusColor,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'BURN-RATE HUD',
                        style: textTheme.labelMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          letterSpacing: 1.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  statusBadge,
                ],
              ),
              const SizedBox(height: 16),

              // 2. Main Row: HUD Circular Meter + Spend Velocity Readouts
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Circular Pulse Gauge
                  SizedBox(
                    width: 90,
                    height: 90,
                    child: CustomPaint(
                      painter: _HudGaugePainter(
                        consumptionRatio: metrics.budgetConsumptionRatio,
                        statusColor: statusColor,
                        trackColor: colorScheme.surfaceContainerHighest,
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${metrics.projectedPercentage.toStringAsFixed(0)}%',
                              style: textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurface,
                              ),
                            ),
                            Text(
                              'PROJ.',
                              style: textTheme.labelSmall?.copyWith(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 20),

                  // Velocity & EOM Forecast Readouts
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Daily Velocity',
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          '${currencyFormatter.format(metrics.dailyVelocity)} / day',
                          style: textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: colorScheme.onSurface,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Text(
                              'Projected EOM: ',
                              style: textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            Text(
                              currencyFormatter.format(metrics.projectedEomSpend),
                              style: textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: statusColor,
                              ),
                            ),
                          ],
                        ),
                        if (metrics.budget > 0)
                          Text(
                            metrics.projectedDelta > 0
                              ? '+${currencyFormatter.format(metrics.projectedDelta)} over budget'
                              : '${currencyFormatter.format(metrics.projectedDelta.abs())} under budget',
                            style: textTheme.labelSmall?.copyWith(
                              color: metrics.projectedDelta > 0 ? colorScheme.error : colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              const Divider(height: 1),
              const SizedBox(height: 12),

              // 3. Footer: Window Chips & Remaining Days Countdown
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Rolling Window Selector
                  Row(
                    children: VelocityWindow.values.map((w) {
                      final isSelected = w == metrics.window;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: InkWell(
                          onTap: () => ref.read(pulseVelocityWindowProvider.notifier).state = w,
                          borderRadius: BorderRadius.circular(12),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: isSelected ? statusColor : colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${w.days}d',
                              style: textTheme.labelSmall?.copyWith(
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                color: isSelected ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),

                  // Days Remaining Countdown
                  Row(
                    children: [
                      Icon(
                        Icons.calendar_month_outlined,
                        size: 14,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${metrics.remainingDaysInMonth}d left in month',
                        style: textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(BudgetHealthStatus status, ColorScheme colorScheme) {
    final String label;
    final Color bgColor;
    final Color textColor;
    final IconData icon;

    switch (status) {
      case BudgetHealthStatus.onTrack:
        label = 'ON-TRACK';
        bgColor = colorScheme.primaryContainer;
        textColor = colorScheme.onPrimaryContainer;
        icon = Icons.check_circle_outline_rounded;
        break;
      case BudgetHealthStatus.warning:
        label = 'WARNING';
        bgColor = colorScheme.tertiaryContainer;
        textColor = colorScheme.onTertiaryContainer;
        icon = Icons.warning_amber_rounded;
        break;
      case BudgetHealthStatus.overBudget:
        label = 'OVER-BUDGET';
        bgColor = colorScheme.errorContainer;
        textColor = colorScheme.onErrorContainer;
        icon = Icons.error_outline_rounded;
        break;
      case BudgetHealthStatus.noBudget:
        label = 'NO BUDGET';
        bgColor = colorScheme.surfaceContainerHighest;
        textColor = colorScheme.onSurfaceVariant;
        icon = Icons.info_outline_rounded;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: textColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(BudgetHealthStatus status, ColorScheme colorScheme) {
    switch (status) {
      case BudgetHealthStatus.onTrack:
        return colorScheme.primary;
      case BudgetHealthStatus.warning:
        return colorScheme.tertiary;
      case BudgetHealthStatus.overBudget:
        return colorScheme.error;
      case BudgetHealthStatus.noBudget:
        return colorScheme.outline;
    }
  }

  String _getCurrencySymbol(String currency) {
    switch (currency.toUpperCase()) {
      case 'EUR':
        return '€';
      case 'GBP':
        return '£';
      case 'JPY':
        return '¥';
      default:
        return '\$';
    }
  }

  Widget _buildLoadingCard(ColorScheme colorScheme) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      height: 140,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Center(
        child: CircularProgressIndicator.adaptive(),
      ),
    );
  }
}

/// Custom painter rendering the Cyberpunk-styled radial HUD gauge.
class _HudGaugePainter extends CustomPainter {
  final double consumptionRatio;
  final Color statusColor;
  final Color trackColor;

  _HudGaugePainter({
    required this.consumptionRatio,
    required this.statusColor,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - 12) / 2;

    // Track Paint
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0
      ..strokeCap = StrokeCap.round;

    // Progress Paint
    final progressPaint = Paint()
      ..color = statusColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0
      ..strokeCap = StrokeCap.round;

    const startAngle = -math.pi * 0.75;
    const sweepAngle = math.pi * 1.5;

    // Draw background track
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      trackPaint,
    );

    // Draw active progress arc
    final progressSweep = sweepAngle * consumptionRatio.clamp(0.0, 1.0);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      progressSweep,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _HudGaugePainter oldDelegate) {
    return oldDelegate.consumptionRatio != consumptionRatio ||
        oldDelegate.statusColor != statusColor ||
        oldDelegate.trackColor != trackColor;
  }
}
