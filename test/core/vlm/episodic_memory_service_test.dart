import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/core/services/vlm/episodic_memory_service.dart';
import 'package:t_aidy/core/services/vlm/semantic_hasher.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SemanticHasher (128-d Dense Vector Embedder) Tests', () {
    test('produces 128-dimensional unit vector with L2 norm == 1.0', () {
      final vec = SemanticHasher.embed('Esselunga Milano');
      expect(vec.length, equals(128));

      double sumSq = 0.0;
      for (final v in vec) {
        sumSq += v * v;
      }
      expect(math.sqrt(sumSq), closeTo(1.0, 0.001));
    });

    test('exhibits high cosine similarity for semantically close strings', () {
      final v1 = SemanticHasher.embed('Esselunga SpA');
      final v2 = SemanticHasher.embed('ESSELUNG MILANO');
      final v3 = SemanticHasher.embed('Target Superstore Dallas Texas');

      final simClose = SemanticHasher.cosineSimilarity(v1, v2);
      final simFar = SemanticHasher.cosineSimilarity(v1, v3);

      expect(simClose, greaterThan(0.40));
      expect(simFar, lessThan(simClose));
    });

    test('serializes and deserializes vector bytes seamlessly', () {
      final original = SemanticHasher.embed('Latte Fresco Intero 1L');
      final bytes = SemanticHasher.vectorToBytes(original);
      expect(bytes.length, equals(128 * 4)); // 512 bytes

      final restored = SemanticHasher.bytesToVector(bytes);
      expect(restored.length, equals(128));
      for (int i = 0; i < 128; i++) {
        expect(restored[i], closeTo(original[i], 1e-6));
      }
    });
  });

  group('EpisodicMemoryService (Hybrid Semantic RAG) Tests', () {
    late EpisodicMemoryService memoryService;

    setUp(() async {
      memoryService = EpisodicMemoryService();
      await memoryService.initialize(inMemory: true);
    });

    tearDown(() {
      memoryService.dispose();
    });

    test('querying "ESSELUNG MILANO" retrieves historical corrections for "Esselunga SpA"', () async {
      await memoryService.recordCorrection(
        rawName: 'PASTA BARILLA N5 500G',
        correctedName: 'Spaghetti Barilla',
        mainCategory: 'Pantry & Bakery',
        subCategory: 'Grains & Pasta',
        necessity: 'essential',
        merchantName: 'Esselunga SpA',
      );

      await memoryService.recordCorrection(
        rawName: 'LEVI JEANS 501',
        correctedName: 'Jeans 501',
        mainCategory: 'Clothing',
        subCategory: 'Apparel',
        necessity: 'discretional',
        merchantName: 'Target USA',
      );

      final results = await memoryService.queryRelevantCorrections(
        merchantName: 'ESSELUNG MILANO',
        limit: 3,
      );

      expect(results, isNotEmpty);
      expect(results.first.merchantName, equals('Esselunga SpA'));
      expect(results.first.rawName, equals('PASTA BARILLA N5 500G'));
      expect(results.first.similarityScore, greaterThan(0.20));
    });

    test('builds formatted few-shot prompt section for VLM prompt injection', () async {
      await memoryService.recordCorrection(
        rawName: 'APPLE MACBOOK AIR M3',
        correctedName: 'MacBook Air M3',
        mainCategory: 'Electronics & Hardware',
        subCategory: 'Laptops',
        necessity: 'discretional',
        merchantName: 'Apple Store',
      );

      final fewShotSection = await memoryService.buildFewShotPromptSection(
        merchantName: 'Apple Store',
        limit: 3,
      );

      expect(fewShotSection, isNotNull);
      expect(fewShotSection, contains('### Historical Few-Shot Corrections'));
      expect(fewShotSection, contains('APPLE MACBOOK AIR M3'));
      expect(fewShotSection, contains('Electronics & Hardware'));
    });

    test('retrieves accurate statistics and clears data cleanly', () async {
      await memoryService.recordCorrection(
        rawName: 'BANANE BIO',
        correctedName: 'Banane Bio',
        mainCategory: 'Fresh Produce',
        subCategory: 'Fruit',
        necessity: 'essential',
        merchantName: 'Esselunga',
      );

      await memoryService.recordReceiptExemplar(
        merchantName: 'Esselunga',
        receiptJson: '{"merchant_name":"Esselunga","total_amount":12.50}',
      );

      final stats = await memoryService.getStats();
      expect(stats['corrections'], equals(1));
      expect(stats['exemplars'], equals(1));

      await memoryService.clearAll();
      final statsAfter = await memoryService.getStats();
      expect(statsAfter['corrections'], equals(0));
      expect(statsAfter['exemplars'], equals(0));
    });

    test('average retrieval latency is under 5ms for 5,000 stored corrections', () async {
      // Seed 5,000 items in batch
      final dummyMerchants = ['Conad', 'Coop', 'Carrefour', 'Lidl', 'Aldi', 'Walmart', 'Tesco'];
      final dummyCategories = ['Fresh Produce', 'Proteins & Dairy', 'Snacks & Drinks', 'Household & Living'];

      for (int i = 0; i < 5000; i++) {
        await memoryService.recordCorrection(
          rawName: 'ITEM DESCRIPTION #$i SAMPLE',
          correctedName: 'Item #$i',
          mainCategory: dummyCategories[i % dummyCategories.length],
          subCategory: 'General',
          necessity: 'essential',
          merchantName: dummyMerchants[i % dummyMerchants.length],
        );
      }

      final stats = await memoryService.getStats();
      expect(stats['corrections'], equals(5000));

      // Warmup query
      await memoryService.queryRelevantCorrections(merchantName: 'Coop Milano', limit: 3);

      // Benchmark 20 iterations
      final stopwatch = Stopwatch()..start();
      const iterations = 20;

      for (int i = 0; i < iterations; i++) {
        final queryRes = await memoryService.queryRelevantCorrections(
          merchantName: 'Conad Centro',
          itemNames: ['ITEM DESCRIPTION #$i'],
          limit: 3,
        );
        expect(queryRes, isNotEmpty);
      }

      stopwatch.stop();
      final avgLatencyMs = stopwatch.elapsedMilliseconds / iterations;
      // ignore: avoid_print
      print('Average Hybrid RAG Retrieval Latency (5,000 items): ${avgLatencyMs.toStringAsFixed(3)} ms');

      expect(avgLatencyMs, lessThan(5.0));
    });
  });
}
