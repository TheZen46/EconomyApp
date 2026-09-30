import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/app_constants.dart';
import '../providers/receipt_provider.dart';
import '../../../analytics/data/price_drift_service.dart';

/// Page monitoring product SKU price volatility, inflation trends, and multi-merchant variance.
///
/// Groups line-item descriptions using FastText subword semantic embedding vectors,
/// detects price drift over time, and highlights the cheapest merchant for recurring items.
class PriceWatchPage extends ConsumerStatefulWidget {
  /// Creates a new [PriceWatchPage] instance.
  const PriceWatchPage({super.key});

  @override
  ConsumerState<PriceWatchPage> createState() => _PriceWatchPageState();
}

class _PriceWatchPageState extends ConsumerState<PriceWatchPage> {
  String _searchQuery = '';
  String _activeFilter = 'All'; // 'All', 'Rising', 'Falling', 'Stable'

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final clusters = ref.watch(priceDriftClustersProvider);
    final isPrivacy = ref.watch(privacyModeProvider);
    final receiptsAsync = ref.watch(receiptListProvider);
    final currency = receiptsAsync.valueOrNull?.isNotEmpty == true ? receiptsAsync.valueOrNull!.first.currency : 'USD';

    final filteredClusters = clusters.where((c) {
      final matchesSearch = c.canonicalName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          (c.cheapestMerchant != null && c.cheapestMerchant!.toLowerCase().contains(_searchQuery.toLowerCase()));
      if (!matchesSearch) return false;

      if (_activeFilter == 'Rising') return c.priceTrend == 'up';
      if (_activeFilter == 'Falling') return c.priceTrend == 'down';
      if (_activeFilter == 'Stable') return c.priceTrend == 'stable';
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text(
          'Price Watch & Inflation Radar',
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
      body: Column(
        children: [
          // Search & Filter Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              onChanged: (val) => setState(() => _searchQuery = val),
              style: GoogleFonts.spaceGrotesk(color: colorScheme.onSurface),
              decoration: InputDecoration(
                hintText: 'Search products or merchants...',
                hintStyle: GoogleFonts.spaceGrotesk(color: colorScheme.onSurfaceVariant),
                prefixIcon: Icon(Icons.search, color: colorScheme.onSurfaceVariant),
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest.withAlpha(120),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: colorScheme.outline.withAlpha(60)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: colorScheme.outline.withAlpha(60)),
                ),
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: ['All', 'Rising', 'Falling', 'Stable'].map((filter) {
                final isSelected = _activeFilter == filter;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    selected: isSelected,
                    label: Text(filter),
                    labelStyle: GoogleFonts.spaceGrotesk(
                      color: isSelected ? colorScheme.onPrimary : colorScheme.onSurface,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      fontSize: 12,
                    ),
                    selectedColor: colorScheme.primary,
                    checkmarkColor: colorScheme.onPrimary,
                    onSelected: (_) => setState(() => _activeFilter = filter),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),

          // List of Clustered SKUs
          Expanded(
            child: filteredClusters.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.query_stats_rounded, size: 64, color: colorScheme.onSurfaceVariant.withAlpha(100)),
                        const SizedBox(height: 16),
                        Text(
                          'No recurring product SKU trends found.\nScan multiple itemized receipts to track inflation.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.spaceGrotesk(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: filteredClusters.length,
                    itemBuilder: (context, index) {
                      final cluster = filteredClusters[index];
                      final isUp = cluster.priceTrend == 'up';
                      final isDown = cluster.priceTrend == 'down';
                      final isNeutral = !isUp && !isDown;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainer,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: colorScheme.outline.withAlpha(60)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    cluster.canonicalName,
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
                                            ? colorScheme.error.withAlpha(40)
                                            : const Color(0xFF10B981).withAlpha(40)),
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
                                        isNeutral ? 'Stable' : '${cluster.priceDriftPercent.abs().toStringAsFixed(1)}%',
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
                                _statColumn('Latest', AppConstants.formatAmount(cluster.latestPrice, currency: currency, isPrivacy: isPrivacy), colorScheme),
                                _statColumn('Avg Price', AppConstants.formatAmount(cluster.avgPrice, currency: currency, isPrivacy: isPrivacy), colorScheme),
                                _statColumn('Min / Max', '${AppConstants.formatAmount(cluster.minPrice, currency: currency, isPrivacy: isPrivacy)} / ${AppConstants.formatAmount(cluster.maxPrice, currency: currency, isPrivacy: isPrivacy)}', colorScheme),
                                _statColumn('Purchases', '${cluster.count}x', colorScheme),
                              ],
                            ),
                            if (cluster.cheapestMerchant != null) ...[
                              const Divider(height: 20),
                              Row(
                                children: [
                                  Icon(Icons.storefront_outlined, size: 14, color: const Color(0xFF10B981)),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Cheapest at: ',
                                    style: GoogleFonts.spaceGrotesk(
                                      fontSize: 12,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      '${cluster.cheapestMerchant} (${AppConstants.formatAmount(cluster.lowestPrice ?? cluster.minPrice, currency: currency, isPrivacy: isPrivacy)})',
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: const Color(0xFF10B981),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _statColumn(String label, String value, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.spaceGrotesk(color: colorScheme.onSurfaceVariant, fontSize: 10)),
        const SizedBox(height: 2),
        Text(value, style: GoogleFonts.jetBrainsMono(color: colorScheme.onSurface, fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
