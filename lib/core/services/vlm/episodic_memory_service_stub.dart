import 'dart:typed_data';
import 'subword_semantic_embedder.dart';

/// Represents a single historical user correction for episodic memory with optional embedding.
class EpisodicCorrection {
  final int? id;
  final String rawName;
  final String correctedName;
  final String mainCategory;
  final String subCategory;
  final String necessity;
  final String merchantName;
  final int timestamp;
  final Float32List? embedding;
  final double similarityScore;

  const EpisodicCorrection({
    this.id,
    required this.rawName,
    required this.correctedName,
    required this.mainCategory,
    required this.subCategory,
    required this.necessity,
    required this.merchantName,
    required this.timestamp,
    this.embedding,
    this.similarityScore = 0.0,
  });

  Map<String, dynamic> toMap() {
    return {
      'raw_name': rawName,
      'corrected_name': correctedName,
      'main_category': mainCategory,
      'sub_category': subCategory,
      'necessity': necessity,
      'merchant_name': merchantName,
      'created_at': timestamp,
      if (embedding != null) 'embedding': SubwordSemanticEmbedder.vectorToBytes(embedding!),
    };
  }
}

/// Web / In-Memory stub for EpisodicMemoryService with HNSW vector search.
class EpisodicMemoryService {
  final List<EpisodicCorrection> _corrections = [];
  final List<Map<String, dynamic>> _exemplars = [];
  bool _initialized = false;

  bool get isInitialized => _initialized;

  Future<void> initialize({dynamic baseDirectory, bool inMemory = false}) async {
    _initialized = true;
  }

  Future<void> recordCorrection({
    required String rawName,
    required String correctedName,
    required String mainCategory,
    required String subCategory,
    required String necessity,
    String merchantName = '',
  }) async {
    final combinedText = '$merchantName $rawName $correctedName'.trim();
    final embedding = SubwordSemanticEmbedder.embed(combinedText);

    _corrections.insert(
      0,
      EpisodicCorrection(
        id: _corrections.length + 1,
        rawName: rawName.trim(),
        correctedName: correctedName.trim(),
        mainCategory: mainCategory.trim(),
        subCategory: subCategory.trim(),
        necessity: necessity.trim(),
        merchantName: merchantName.trim(),
        timestamp: DateTime.now().millisecondsSinceEpoch,
        embedding: embedding,
      ),
    );
  }

  Future<void> recordReceiptExemplar({
    required String merchantName,
    required String receiptJson,
  }) async {
    final embedding = SubwordSemanticEmbedder.embed(merchantName);
    _exemplars.insert(0, {
      'merchant_name': merchantName.trim(),
      'receipt_json': receiptJson.trim(),
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'embedding': embedding,
    });
  }

  Future<List<EpisodicCorrection>> queryRelevantCorrections({
    String? merchantName,
    List<String>? itemNames,
    int limit = 3,
    double maxDistance = 0.80,
  }) async {
    final queryParts = <String>[];
    if (merchantName != null && merchantName.isNotEmpty) {
      queryParts.add(merchantName.trim());
    }
    if (itemNames != null && itemNames.isNotEmpty) {
      queryParts.addAll(itemNames.map((e) => e.trim()).where((e) => e.isNotEmpty));
    }

    final queryString = queryParts.join(' ').trim();
    if (queryString.isEmpty) {
      return _corrections.take(limit).toList();
    }

    final queryVec = SubwordSemanticEmbedder.embed(queryString);

    final scored = _corrections.map((c) {
      final candVec = c.embedding ?? SubwordSemanticEmbedder.embed('${c.merchantName} ${c.rawName} ${c.correctedName}');
      final dist = SubwordSemanticEmbedder.cosineDistance(queryVec, candVec);
      final sim = SubwordSemanticEmbedder.cosineSimilarity(queryVec, candVec);

      return (
        correction: EpisodicCorrection(
          id: c.id,
          rawName: c.rawName,
          correctedName: c.correctedName,
          mainCategory: c.mainCategory,
          subCategory: c.subCategory,
          necessity: c.necessity,
          merchantName: c.merchantName,
          timestamp: c.timestamp,
          embedding: candVec,
          similarityScore: sim,
        ),
        distance: dist,
      );
    }).where((pair) => pair.distance <= maxDistance).toList();

    scored.sort((a, b) => a.distance.compareTo(b.distance));
    if (scored.isNotEmpty) {
      return scored.take(limit).map((s) => s.correction).toList();
    }
    return _corrections.take(limit).toList();
  }

  Future<String?> buildFewShotPromptSection({
    String? merchantName,
    List<String>? itemNames,
    int limit = 3,
    double maxDistance = 0.22,
  }) async {
    final corrections = await queryRelevantCorrections(
      merchantName: merchantName,
      itemNames: itemNames,
      limit: limit,
      maxDistance: maxDistance,
    );

    if (corrections.isEmpty) return null;

    final buffer = StringBuffer('### Historical Few-Shot Corrections & Taxonomy Exemplars:\n');
    for (final c in corrections) {
      buffer.writeln(
        '- Raw item: "${c.rawName}" -> Normalized: "${c.correctedName}", '
        'Category: "${c.mainCategory}" / "${c.subCategory}", '
        'Necessity: ${c.necessity}'
        '${c.merchantName.isNotEmpty ? ' (Merchant: ${c.merchantName})' : ''}',
      );
    }
    return buffer.toString();
  }

  Future<String> buildDifferentialPromptDelta({
    String? merchantName,
    List<String>? itemNames,
    int limit = 3,
  }) async {
    final section = await buildFewShotPromptSection(
      merchantName: merchantName,
      itemNames: itemNames,
      limit: limit,
    );
    if (section == null || section.isEmpty) return '';
    return '<|delta_exemplars_start|>\n$section<|delta_exemplars_end|>\n';
  }

  Future<Map<String, int>> getStats() async {
    return {
      'corrections': _corrections.length,
      'exemplars': _exemplars.length,
      'hnsw_nodes': _corrections.length,
    };
  }

  Future<void> clearAll() async {
    _corrections.clear();
    _exemplars.clear();
  }

  void dispose() {
    _corrections.clear();
    _exemplars.clear();
    _initialized = false;
  }
}
