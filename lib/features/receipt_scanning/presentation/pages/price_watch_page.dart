import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/app_constants.dart';
import '../providers/receipt_provider.dart';
import '../../domain/entities/receipt.dart';

/// Page monitoring grocery and product price volatility, inflation, and historical price changes.
///
/// Groups line-item descriptions across all scanned receipts chronologically, computes
/// historical minimums, maximums, and moving averages, and visualizes price trend directions.
class PriceWatchPage extends ConsumerWidget {
  /// Creates a new [PriceWatchPage] instance.
  const PriceWatchPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final receiptListAsync = ref.watch(receiptListProvider);

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text(
          'Price Watch & Inflation',
          style: GoogleFonts.spaceGrotesk(
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colorScheme.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: receiptListAsync.when(
        data: (receipts) {
          final itemStats = _calculateStats(receipts);
          final currencySymbol = AppConstants.getCurrencySymbol(
            receipts.isNotEmpty ? receipts.first.currency : 'USD',
          );
          
          if (itemStats.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.query_stats_rounded, size: 64, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
                  const SizedBox(height: 16),
                  Text(
                    'No recurring item price data found.\nScan multiple itemized receipts to track inflation trends.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.spaceGrotesk(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: itemStats.length,
            itemBuilder: (context, index) {
              final stat = itemStats[index];
              final isUp = stat.percentChange > 0.5;
              final isDown = stat.percentChange < -0.5;
              final isNeutral = !isUp && !isDown;
              
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colorScheme.outline.withValues(alpha: 0.2)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            stat.name, 
                            style: GoogleFonts.spaceGrotesk(
                              color: colorScheme.onSurface, 
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isNeutral 
                                ? colorScheme.surfaceContainerHighest 
                                : (isUp 
                                    ? colorScheme.error.withValues(alpha: 0.15) 
                                    : const Color(0xFF10B981).withValues(alpha: 0.15)),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!isNeutral) 
                                Icon(
                                  isUp ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, 
                                  size: 14, 
                                  color: isUp ? colorScheme.error : const Color(0xFF10B981),
                                ),
                              Text(
                                isNeutral ? 'Stable' : '${stat.percentChange.abs().toStringAsFixed(1)}%',
                                style: GoogleFonts.jetBrainsMono(
                                  color: isNeutral 
                                      ? colorScheme.onSurfaceVariant 
                                      : (isUp ? colorScheme.error : const Color(0xFF10B981)),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _statColumn('Avg Price', '$currencySymbol${stat.avgPrice.toStringAsFixed(2)}', colorScheme),
                        _statColumn('Min', '$currencySymbol${stat.minPrice.toStringAsFixed(2)}', colorScheme),
                        _statColumn('Max', '$currencySymbol${stat.maxPrice.toStringAsFixed(2)}', colorScheme),
                        _statColumn('Purchases', '${stat.count}x', colorScheme),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err', style: TextStyle(color: colorScheme.error))),
      ),
    );
  }

  Widget _statColumn(String label, String value, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.spaceGrotesk(color: colorScheme.onSurfaceVariant, fontSize: 10)),
        const SizedBox(height: 2),
        Text(value, style: GoogleFonts.jetBrainsMono(color: colorScheme.onSurface, fontSize: 13, fontWeight: FontWeight.w600)),
      ],
    );
  }

  List<_ItemStat> _calculateStats(List<Receipt> receipts) {
    // Map product name -> list of (date, price) observations
    final Map<String, List<_PriceObservation>> itemObservations = {};

    for (final r in receipts) {
      for (final item in r.items) {
        final name = item.description.trim();
        if (name.isNotEmpty && item.unitPrice > 0) {
          final display = name[0].toUpperCase() + name.substring(1).toLowerCase();
          itemObservations.putIfAbsent(display, () => []).add(
            _PriceObservation(date: r.date, price: item.unitPrice),
          );
        }
      }
    }

    final stats = <_ItemStat>[];
    itemObservations.forEach((name, observations) {
      if (observations.length > 1) {
        // Sort chronologically to compute true historical price change
        observations.sort((a, b) => a.date.compareTo(b.date));
        
        final prices = observations.map((o) => o.price).toList();
        final double avg = prices.reduce((a, b) => a + b) / prices.length;
        final double min = prices.reduce((a, b) => a < b ? a : b);
        final double max = prices.reduce((a, b) => a > b ? a : b);
        
        final double firstPrice = observations.first.price;
        final double lastPrice = observations.last.price;
        final double pctChange = firstPrice > 0 ? ((lastPrice - firstPrice) / firstPrice) * 100 : 0.0;

        stats.add(_ItemStat(
          name: name,
          avgPrice: avg,
          minPrice: min,
          maxPrice: max,
          count: observations.length,
          percentChange: pctChange,
        ));
      }
    });

    // Sort by frequency
    stats.sort((a, b) => b.count.compareTo(a.count));
    return stats;
  }
}

class _PriceObservation {
  final DateTime date;
  final double price;

  _PriceObservation({required this.date, required this.price});
}

class _ItemStat {
  final String name;
  final double avgPrice;
  final double minPrice;
  final double maxPrice;
  final int count;
  final double percentChange;

  _ItemStat({
    required this.name,
    required this.avgPrice,
    required this.minPrice,
    required this.maxPrice,
    required this.count,
    required this.percentChange,
  });
}
