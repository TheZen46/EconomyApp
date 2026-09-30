import 'dart:math';
import 'package:t_aidy/features/receipt_scanning/domain/entities/receipt.dart';

/// Structured suggestion returned by the Bayesian & Markov Categorizer.
class CategoryPrediction {
  final String predictedCategory;
  final String? predictedBoxId;
  final double categoryConfidence; // 0.0 to 1.0
  final double boxConfidence; // 0.0 to 1.0
  final String reasoning;

  const CategoryPrediction({
    required this.predictedCategory,
    this.predictedBoxId,
    required this.categoryConfidence,
    required this.boxConfidence,
    required this.reasoning,
  });

  Map<String, dynamic> toJson() => {
        'predictedCategory': predictedCategory,
        'predictedBoxId': predictedBoxId,
        'categoryConfidence': categoryConfidence,
        'boxConfidence': boxConfidence,
        'reasoning': reasoning,
      };
}

/// [UNIQUE] Discrete Bayesian Prior & Markov Transition Auto-Categorization Engine.
///
/// Learns merchant-to-tax-category distributions and box-transition probabilities
/// purely locally on-device without cloud API calls or heavy neural network weights.
class BayesianCategorizerEngine {
  // Category counts and feature word frequencies: Map<Category, Map<Word, Count>>
  final Map<String, Map<String, int>> _categoryWordCounts = {};
  final Map<String, int> _categoryTotals = {};
  final Set<String> _vocabulary = {};

  // Box association counts: Map<Category, Map<BoxId, Count>>
  final Map<String, Map<String, int>> _categoryToBoxCounts = {};
  final Map<String, int> _boxTotals = {};

  // First-order Markov transition: Map<PreviousBoxId, Map<CurrentBoxId, Count>>
  final Map<String, Map<String, int>> _markovBoxTransitions = {};

  int _totalDocuments = 0;

  int get totalTrainedReceipts => _totalDocuments;
  int get vocabularySize => _vocabulary.length;

  /// Trains the Bayesian model from an existing list of historical receipts.
  void train(List<Receipt> receipts) {
    _categoryWordCounts.clear();
    _categoryTotals.clear();
    _vocabulary.clear();
    _categoryToBoxCounts.clear();
    _boxTotals.clear();
    _markovBoxTransitions.clear();
    _totalDocuments = 0;

    String? lastBoxId;

    for (final receipt in receipts) {
      final category = _extractPrimaryCategory(receipt);
      final boxId = receipt.boxId ?? 'main';

      if (category.isEmpty) continue;

      _totalDocuments++;
      _categoryTotals[category] = (_categoryTotals[category] ?? 0) + 1;
      _boxTotals[boxId] = (_boxTotals[boxId] ?? 0) + 1;

      // Update category to box counts
      _categoryToBoxCounts.putIfAbsent(category, () => {});
      _categoryToBoxCounts[category]![boxId] = (_categoryToBoxCounts[category]![boxId] ?? 0) + 1;

      // Update Markov sequence
      if (lastBoxId != null) {
        _markovBoxTransitions.putIfAbsent(lastBoxId, () => {});
        _markovBoxTransitions[lastBoxId]![boxId] = (_markovBoxTransitions[lastBoxId]![boxId] ?? 0) + 1;
      }
      lastBoxId = boxId;

      // Extract tokens from merchant name and line-item descriptions
      final tokens = _tokenize('${receipt.merchantName} ${receipt.items.map((e) => e.description).join(' ')}');
      _categoryWordCounts.putIfAbsent(category, () => {});

      for (final token in tokens) {
        _vocabulary.add(token);
        _categoryWordCounts[category]![token] = (_categoryWordCounts[category]![token] ?? 0) + 1;
      }
    }
  }

  /// Predicts the optimal Tax Category and Box ID for a new incoming receipt.
  CategoryPrediction predict({
    required String merchantName,
    String? lineItemText,
    String? previousBoxId,
  }) {
    if (_totalDocuments == 0 || _categoryTotals.isEmpty) {
      return const CategoryPrediction(
        predictedCategory: 'General Business Expense',
        predictedBoxId: null,
        categoryConfidence: 0.20,
        boxConfidence: 0.20,
        reasoning: 'Cold-start default (no training history recorded yet).',
      );
    }

    final queryText = '$merchantName ${lineItemText ?? ''}';
    final tokens = _tokenize(queryText);

    // Compute log posterior P(Category | Words) with Laplace smoothing
    final logScores = <String, double>{};
    final vocabSize = max(1, _vocabulary.length);

    for (final category in _categoryTotals.keys) {
      final docCount = _categoryTotals[category]!;
      // Prior P(Category)
      double logPosterior = log(docCount / _totalDocuments);

      final wordCounts = _categoryWordCounts[category] ?? {};
      final totalWordsInCategory = wordCounts.values.fold(0, (a, b) => a + b);

      for (final token in tokens) {
        final count = wordCounts[token] ?? 0;
        // Likelihood with Laplace (+1) smoothing: (count + 1) / (totalWords + vocabSize)
        final wordProb = (count + 1.0) / (totalWordsInCategory + vocabSize);
        logPosterior += log(wordProb);
      }

      logScores[category] = logPosterior;
    }

    // Find best category
    String bestCategory = _categoryTotals.keys.first;
    double maxLogScore = -double.infinity;

    logScores.forEach((cat, score) {
      if (score > maxLogScore) {
        maxLogScore = score;
        bestCategory = cat;
      }
    });

    // Normalize confidence using softmax over top scores
    final maxVal = maxLogScore;
    double sumExp = 0.0;
    final expScores = <String, double>{};
    logScores.forEach((k, v) {
      final e = exp((v - maxVal).clamp(-20.0, 0.0));
      expScores[k] = e;
      sumExp += e;
    });
    final catConfidence = sumExp > 0 ? (expScores[bestCategory]! / sumExp).clamp(0.20, 0.99) : 0.50;

    // Predict Box from Category & Markov Transition
    String? bestBoxId;
    double boxConfidence = 0.50;

    final boxCounts = _categoryToBoxCounts[bestCategory] ?? {};
    if (boxCounts.isNotEmpty) {
      int maxBoxCount = 0;
      boxCounts.forEach((bId, cnt) {
        // Markov booster if consecutive transactions occur in the same workflow box
        double weight = cnt.toDouble();
        if (previousBoxId != null && _markovBoxTransitions[previousBoxId]?[bId] != null) {
          weight += (_markovBoxTransitions[previousBoxId]![bId]! * 0.5);
        }

        if (weight > maxBoxCount) {
          maxBoxCount = weight.toInt();
          bestBoxId = bId;
        }
      });

      final totalBoxInCat = boxCounts.values.fold(0, (a, b) => a + b);
      boxConfidence = totalBoxInCat > 0 ? (boxCounts[bestBoxId] ?? 0) / totalBoxInCat : 0.50;
    }

    final reason = 'Predicted "$bestCategory" with ${(catConfidence * 100).toStringAsFixed(0)}% confidence '
        'based on ${_categoryTotals[bestCategory]} historical occurrences.';

    return CategoryPrediction(
      predictedCategory: bestCategory,
      predictedBoxId: bestBoxId,
      categoryConfidence: catConfidence,
      boxConfidence: boxConfidence.clamp(0.20, 0.99),
      reasoning: reason,
    );
  }

  String _extractPrimaryCategory(Receipt r) {
    if (r.items.isNotEmpty && r.items.first.mainCategory != null && r.items.first.mainCategory!.isNotEmpty) {
      return r.items.first.mainCategory!;
    }
    return 'General Expense';
  }

  List<String> _tokenize(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((t) => t.length > 1)
        .toList();
  }
}

