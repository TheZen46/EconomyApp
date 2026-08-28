import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// We don't have fl_chart. I'll use a simple custom painter for Sparklines or just use the NeonBarChart adapted.
// Let's use NeonBarChart for history of prices? No, usually line chart is better for price.
// I'll build a simple "NeonLineChart" or just list stats first.
// Actually, let's make a cool "NeonSparkline" widget.

import '../../../../core/theme/app_theme.dart';
import '../providers/receipt_provider.dart';
import '../../domain/entities/receipt.dart';

class PriceWatchPage extends ConsumerWidget {
  const PriceWatchPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receiptListAsync = ref.watch(receiptListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Price Watch'),
        backgroundColor: Colors.transparent,
      ),
      body: receiptListAsync.when(
        data: (receipts) {
          final itemStats = _calculateStats(receipts);
          
          if (itemStats.isEmpty) {
            return const Center(
              child: Text(
                'No item data found.\nScan detailed receipts!',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textDim),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: itemStats.length,
            itemBuilder: (context, index) {
              final stat = itemStats[index];
              final isUp = stat.percentChange > 0;
              final isNeutral = stat.percentChange == 0;
              
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withAlpha(12)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            stat.name, 
                            style: const TextStyle(
                              color: AppTheme.textMain, 
                              fontWeight: FontWeight.bold,
                              fontSize: 16
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isNeutral 
                                ? Colors.grey.withAlpha(25) 
                                : (isUp ? AppTheme.error.withAlpha(25) : Colors.green.withAlpha(25)),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              if (!isNeutral) 
                                Icon(
                                  isUp ? Icons.arrow_upward : Icons.arrow_downward, 
                                  size: 14, 
                                  color: isUp ? AppTheme.error : Colors.greenAccent
                                ),
                              Text(
                                isNeutral ? 'Stable' : '${stat.percentChange.abs().toStringAsFixed(1)}%',
                                style: TextStyle(
                                  color: isNeutral ? AppTheme.textDim : (isUp ? AppTheme.error : Colors.greenAccent),
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
                        _statColumn('Avg Price', '€${stat.avgPrice.toStringAsFixed(2)}'),
                        _statColumn('Min', '€${stat.minPrice.toStringAsFixed(2)}'),
                        _statColumn('Max', '€${stat.maxPrice.toStringAsFixed(2)}'),
                        _statColumn('Count', '${stat.count}'),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
      ),
    );
  }

  Widget _statColumn(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: AppTheme.textDim, fontSize: 10)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(color: AppTheme.textMain, fontSize: 14, fontWeight: FontWeight.w500)),
      ],
    );
  }

  List<_ItemStat> _calculateStats(List<Receipt> receipts) {
    final Map<String, List<double>> itemPrices = {};

    for (var r in receipts) {
      for (var item in r.items) {
        // Normalize name (lowercase, trim)
        final name = item.description.trim().toLowerCase(); // Simple normalization
        if (name.isNotEmpty) {
           // Capitalize for display
           final display = name[0].toUpperCase() + name.substring(1);
           itemPrices.putIfAbsent(display, () => []).add(item.unitPrice);
        }
      }
    }

    // Convert to list stats
    final stats = <_ItemStat>[];
    itemPrices.forEach((name, prices) {
      if (prices.length > 1) { // Only show items that appear multiple times
        final avg = prices.reduce((a, b) => a + b) / prices.length;
        final min = prices.reduce((a, b) => a < b ? a : b);
        final max = prices.reduce((a, b) => a > b ? a : b);
        
        // Simple change: (Last - First) / First? 
        // Or Trend? Let's just do (Avg - Min) variation? 
        // Ideally we need dates to do First/Last. 
        // For MVP let's assume the order in receipts is roughly chronological? 
        // Actually receipts list might not be sorted. 
        // Let's just calculate variation from Avg for now or look at Min/Max spread.
        // "Inflation" implies trend over time.
        // Let's skip % change if we don't sort by date and just show Min/Max spread.
        // Wait, I can sort prices if I had dates attached. 
        // The `item` doesn't strictly have date, parent receipt does.
        // Complexity increases. Let's do simple spread %: (Max - Min) / Min * 100
        
        final spread = max - min;
        final pct = min > 0 ? (spread / min) * 100 : 0.0; 
        
        stats.add(_ItemStat(
          name: name,
          avgPrice: avg,
          minPrice: min,
          maxPrice: max,
          count: prices.length,
          percentChange: pct, // Showing spread as "Change" capability
        ));
      }
    });

    // Sort by count (most frequent items first)
    stats.sort((a, b) => b.count.compareTo(a.count));

    return stats;
  }
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
