import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/services/vlm/subword_semantic_embedder.dart';
import '../../receipt_scanning/domain/entities/receipt.dart';
import '../../receipt_scanning/presentation/providers/receipt_provider.dart';

/// Single chronological price observation of a product SKU.
class SkuObservation {
  final DateTime date;
  final String merchant;
  final double unitPrice;
  final String receiptId;
  final String rawDescription;

  const SkuObservation({
    required this.date,
    required this.merchant,
    required this.unitPrice,
    required this.receiptId,
    required this.rawDescription,
  });
}

/// Clustered product SKU tracking price volatility, inflation, and multi-merchant variance.
class SkuPriceDriftCluster {
  final String canonicalName;
  final List<SkuObservation> observations;
  final double initialPrice;
  final double latestPrice;
  final double minPrice;
  final double maxPrice;
  final double avgPrice;
  final double priceDriftPercent;
  final double annualizedInflationPercent;
  final String priceTrend; // 'up', 'down', 'stable'
  final String? cheapestMerchant;
  final double? lowestPrice;
  final String? highestMerchant;
  final double? highestPrice;

  const SkuPriceDriftCluster({
    required this.canonicalName,
    required this.observations,
    required this.initialPrice,
    required this.latestPrice,
    required this.minPrice,
    required this.maxPrice,
    required this.avgPrice,
    required this.priceDriftPercent,
    required this.annualizedInflationPercent,
    required this.priceTrend,
    this.cheapestMerchant,
    this.lowestPrice,
    this.highestMerchant,
    this.highestPrice,
  });

  int get count => observations.length;
}

/// Service computing on-device episodic SKU price drift and semantic clustering.
class PriceDriftService {
  PriceDriftService._();

  /// Cosine similarity threshold for grouping distinct SKU descriptions into one canonical product.
  static const double kSemanticClusterThreshold = 0.45;

  /// Analyzes all line items across receipts and clusters them by semantic vector similarity.
  static List<SkuPriceDriftCluster> analyzePriceDrift(List<Receipt> receipts) {
    if (receipts.isEmpty) return [];

    // Collect all valid line items
    final allItems = <_RawItemObservation>[];
    for (final r in receipts) {
      for (final item in r.items) {
        final desc = item.description.trim();
        if (desc.isNotEmpty && item.unitPrice > 0) {
          allItems.add(_RawItemObservation(
            description: desc,
            unitPrice: item.unitPrice,
            date: r.date,
            merchant: r.merchantName.trim().isEmpty ? 'General Store' : r.merchantName.trim(),
            receiptId: r.id,
            vector: SubwordSemanticEmbedder.embed(desc),
          ));
        }
      }
    }

    if (allItems.isEmpty) return [];

    // Cluster items using FastText subword semantic embedding vectors
    final clusters = <_ItemClusterBuilder>[];

    for (final obs in allItems) {
      _ItemClusterBuilder? bestCluster;
      double bestSim = 0.0;

      for (final cluster in clusters) {
        final sim = SubwordSemanticEmbedder.cosineSimilarity(obs.vector, cluster.centerVector);
        if (sim >= kSemanticClusterThreshold && sim > bestSim) {
          bestSim = sim;
          bestCluster = cluster;
        }
      }

      if (bestCluster != null) {
        bestCluster.add(obs);
      } else {
        clusters.add(_ItemClusterBuilder(obs));
      }
    }

    // Convert cluster builders to finalized immutable models
    final results = <SkuPriceDriftCluster>[];

    for (final cluster in clusters) {
      if (cluster.observations.length < 2) {
        continue;
      }

      // Sort observations chronologically
      cluster.observations.sort((a, b) => a.date.compareTo(b.date));

      final observations = cluster.observations.map((o) => SkuObservation(
        date: o.date,
        merchant: o.merchant,
        unitPrice: o.unitPrice,
        receiptId: o.receiptId,
        rawDescription: o.description,
      )).toList();

      final prices = observations.map((o) => o.unitPrice).toList();
      final double initial = observations.first.unitPrice;
      final double latest = observations.last.unitPrice;
      final double min = prices.reduce((a, b) => a < b ? a : b);
      final double max = prices.reduce((a, b) => a > b ? a : b);
      final double avg = prices.reduce((a, b) => a + b) / prices.length;

      final double driftPct = initial > 0 ? ((latest - initial) / initial) * 100 : 0.0;

      // Annualized inflation calculation based on timespan
      final daysDiff = observations.last.date.difference(observations.first.date).inDays;
      final annualized = (daysDiff > 14 && initial > 0)
          ? (driftPct / daysDiff) * 365.0
          : driftPct;

      String trend = 'stable';
      if (driftPct > 1.5) {
        trend = 'up';
      } else if (driftPct < -1.5) {
        trend = 'down';
      }

      // Merchant price comparison
      final merchantLatest = <String, double>{};
      for (final obs in observations) {
        merchantLatest[obs.merchant] = obs.unitPrice;
      }

      String? cheapestMerch;
      double lowestP = double.infinity;
      String? highestMerch;
      double highestP = -1.0;

      merchantLatest.forEach((merchant, price) {
        if (price < lowestP) {
          lowestP = price;
          cheapestMerch = merchant;
        }
        if (price > highestP) {
          highestP = price;
          highestMerch = merchant;
        }
      });

      results.add(SkuPriceDriftCluster(
        canonicalName: cluster.canonicalName,
        observations: observations,
        initialPrice: initial,
        latestPrice: latest,
        minPrice: min,
        maxPrice: max,
        avgPrice: avg,
        priceDriftPercent: driftPct,
        annualizedInflationPercent: annualized,
        priceTrend: trend,
        cheapestMerchant: cheapestMerch,
        lowestPrice: lowestP.isFinite ? lowestP : null,
        highestMerchant: highestMerch,
        highestPrice: highestP >= 0 ? highestP : null,
      ));
    }

    results.sort((a, b) {
      final driftComp = b.priceDriftPercent.abs().compareTo(a.priceDriftPercent.abs());
      if (driftComp != 0) return driftComp;
      return b.count.compareTo(a.count);
    });

    return results;
  }

  /// Evaluates price trend percentage for a specific single receipt item against historical clusters.
  static double? getPriceTrendForItem(String description, double currentPrice, List<Receipt> allReceipts) {
    if (description.trim().isEmpty || currentPrice <= 0 || allReceipts.isEmpty) return null;

    final targetVector = SubwordSemanticEmbedder.embed(description);
    final matchingPrices = <double>[];

    for (final r in allReceipts) {
      for (final item in r.items) {
        if (item.unitPrice <= 0) continue;
        final itemVector = SubwordSemanticEmbedder.embed(item.description);
        final sim = SubwordSemanticEmbedder.cosineSimilarity(targetVector, itemVector);
        if (sim >= kSemanticClusterThreshold) {
          matchingPrices.add(item.unitPrice);
        }
      }
    }

    if (matchingPrices.length < 2) return null;

    final avgHistorical = matchingPrices.reduce((a, b) => a + b) / matchingPrices.length;
    if (avgHistorical <= 0) return null;

    return ((currentPrice - avgHistorical) / avgHistorical) * 100.0;
  }
}

class _RawItemObservation {
  final String description;
  final double unitPrice;
  final DateTime date;
  final String merchant;
  final String receiptId;
  final Float32List vector;

  _RawItemObservation({
    required this.description,
    required this.unitPrice,
    required this.date,
    required this.merchant,
    required this.receiptId,
    required this.vector,
  });
}

class _ItemClusterBuilder {
  final List<_RawItemObservation> observations = [];
  final Map<String, int> _nameFrequencies = {};
  late Float32List centerVector;

  _ItemClusterBuilder(_RawItemObservation initial) {
    centerVector = Float32List.fromList(initial.vector);
    add(initial);
  }

  void add(_RawItemObservation obs) {
    observations.add(obs);
    _nameFrequencies[obs.description] = (_nameFrequencies[obs.description] ?? 0) + 1;

    final dim = centerVector.length;
    for (int i = 0; i < dim; i++) {
      centerVector[i] = (centerVector[i] * (observations.length - 1) + obs.vector[i]) / observations.length;
    }
  }

  String get canonicalName {
    String best = observations.first.description;
    int highestFreq = -1;
    _nameFrequencies.forEach((name, freq) {
      if (freq > highestFreq) {
        highestFreq = freq;
        best = name;
      }
    });
    return best[0].toUpperCase() + best.substring(1);
  }
}

/// Riverpod provider delivering real-time SKU price drift and inflation clusters.
final priceDriftClustersProvider = Provider<List<SkuPriceDriftCluster>>((ref) {
  final receiptsAsync = ref.watch(receiptListProvider);
  final receipts = receiptsAsync.valueOrNull ?? [];
  return PriceDriftService.analyzePriceDrift(receipts);
});
