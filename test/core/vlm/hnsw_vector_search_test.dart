import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/core/services/vlm/subword_semantic_embedder.dart';
import 'package:t_aidy/core/services/vlm/hnsw_index.dart';
import 'package:t_aidy/core/services/vlm/episodic_memory_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SubwordSemanticEmbedder Tests', () {
    test('produces 128-dimensional L2-normalized unit vector (||e||_2 == 1.0)', () {
      final vec = SubwordSemanticEmbedder.embed('ESSELUNGA MILANO CORSO LODI');
      expect(vec.length, equals(128));

      double sumSq = 0.0;
      for (final v in vec) {
        sumSq += v * v;
      }
      expect(math.sqrt(sumSq), closeTo(1.0, 1e-5));
    });

    test('exhibits high cosine similarity for subword morphological variations / typos', () {
      final v1 = SubwordSemanticEmbedder.embed('Esselunga SpA');
      final v2 = SubwordSemanticEmbedder.embed('ESSELUNG SPA');
      final v3 = SubwordSemanticEmbedder.embed('Chevron Gas Station Houston');

      final simClose = SubwordSemanticEmbedder.cosineSimilarity(v1, v2);
      final distClose = SubwordSemanticEmbedder.cosineDistance(v1, v2);
      final simFar = SubwordSemanticEmbedder.cosineSimilarity(v1, v3);

      expect(simClose, greaterThan(0.70));
      expect(distClose, closeTo(1.0 - simClose, 1e-5));
      expect(simFar, lessThan(0.35));
    });

    test('binary vector serialization is exactly 512 bytes with lossless roundtrip', () {
      final vec = SubwordSemanticEmbedder.embed('Latte Fresco Intero 1L');
      final bytes = SubwordSemanticEmbedder.vectorToBytes(vec);
      expect(bytes.length, equals(512));

      final restored = SubwordSemanticEmbedder.bytesToVector(bytes);
      expect(restored.length, equals(128));
      for (int i = 0; i < 128; i++) {
        expect(restored[i], closeTo(vec[i], 1e-6));
      }
    });
  });

  group('HNSWIndex Vector Graph Engine Tests', () {
    test('builds multi-layer graph and retrieves exact nearest neighbors', () {
      final index = HNSWIndex(dim: 128, m: 16, m0: 32, efConstruction: 64, efSearch: 32);

      // Insert 100 synthetic normalized vectors
      final vectors = <int, Float32List>{};
      for (int i = 0; i < 100; i++) {
        final vec = SubwordSemanticEmbedder.embed('Merchant name variation #$i with special category');
        vectors[i] = vec;
        index.addPoint(i, vec);
      }

      expect(index.count, equals(100));
      expect(index.maxLevel, greaterThanOrEqualTo(0));

      // Exact query for vector 42
      final hits = index.searchKnn(vectors[42]!, 3, maxDistance: 0.22);
      expect(hits, isNotEmpty);
      expect(hits.first.id, equals(42));
      expect(hits.first.distance, closeTo(0.0, 1e-5));
      expect(hits.first.similarity, closeTo(1.0, 1e-5));
    });

    test('confidence cutoff threshold gate (tau = 0.78, D_C <= 0.22) filters out noisy distractors', () {
      final index = HNSWIndex(dim: 128, m: 16, m0: 32, efConstruction: 64, efSearch: 32);

      final vApple = SubwordSemanticEmbedder.embed('Apple Store Fifth Ave');
      final vPizza = SubwordSemanticEmbedder.embed('Pizzeria Da Michele Napoli Pizza Margherita');
      final vTire = SubwordSemanticEmbedder.embed('Goodyear Tire Auto Service Center');

      index.addPoint(1, vApple);
      index.addPoint(2, vPizza);
      index.addPoint(3, vTire);

      // Query semantically close to Apple Store
      final queryApple = SubwordSemanticEmbedder.embed('Apple Store Fifth Avenue');
      final appleHits = index.searchKnn(queryApple, 3, maxDistance: 0.22);
      expect(appleHits, isNotEmpty);
      expect(appleHits.first.id, equals(1));

      // Query unrelated to all indexed points with strict cutoff
      final queryUnrelated = SubwordSemanticEmbedder.embed('Dentist Dental Care Cleaning Clinic');
      final unrelatedHits = index.searchKnn(queryUnrelated, 3, maxDistance: 0.22);
      expect(unrelatedHits, isEmpty); // Properly rejected by cutoff gate!
    });

    test('binary serialization to hnsw_rag.bin satisfies roundtrip fidelity', () async {
      final index = HNSWIndex(dim: 128, m: 16, m0: 32, efConstruction: 64, efSearch: 32);

      for (int i = 0; i < 50; i++) {
        final vec = SubwordSemanticEmbedder.embed('Item #$i Grocery Product');
        index.addPoint(i, vec);
      }

      final tempDir = Directory.systemTemp.createTempSync('hnsw_test');
      final binFile = File('${tempDir.path}/hnsw_rag.bin');

      await index.saveToFile(binFile);
      expect(await binFile.exists(), isTrue);
      expect(binFile.lengthSync(), greaterThan(50 * 512));

      final loadedIndex = HNSWIndex(dim: 128, m: 16, m0: 32);
      final loaded = await loadedIndex.loadFromFile(binFile);
      expect(loaded, isTrue);
      expect(loadedIndex.count, equals(50));

      final targetVec = SubwordSemanticEmbedder.embed('Item #10 Grocery Product');
      final hits = loadedIndex.searchKnn(targetVec, 1, maxDistance: 0.22);
      expect(hits, isNotEmpty);
      expect(hits.first.id, equals(10));

      tempDir.deleteSync(recursive: true);
    });

    test('graph memory overhead is strictly <= 12 KB per 1,000 vectors', () {
      final index = HNSWIndex(dim: 128, m: 16, m0: 32, efConstruction: 64, efSearch: 32);

      for (int i = 0; i < 1000; i++) {
        final vec = SubwordSemanticEmbedder.embed('Receipt line item product sample number $i');
        index.addPoint(i, vec);
      }

      final totalBytes = index.saveToBytes().length;
      final vectorPayloadBytes = 1000 * 128 * 4; // 512,000 bytes
      final graphStructureBytes = totalBytes - vectorPayloadBytes - 40; // Subtract header & vectors

      final graphOverheadKb = graphStructureBytes / 1024.0;
      // ignore: avoid_print
      print('HNSW Graph Structure Overhead (1,000 items): ${graphOverheadKb.toStringAsFixed(2)} KB');

      // Must strictly not exceed 12 KB
      expect(graphOverheadKb, lessThanOrEqualTo(12.0));
    });
  });

  group('EpisodicMemoryService (HNSW RAG Integration & Sub-2ms Search) Tests', () {
    late EpisodicMemoryService memoryService;

    setUp(() async {
      memoryService = EpisodicMemoryService();
      await memoryService.initialize(inMemory: true);
    });

    tearDown(() {
      memoryService.dispose();
    });

    test('records corrections and builds differential token delta prompt context', () async {
      await memoryService.recordCorrection(
        rawName: 'BARILLA SPAGHETTI 500G',
        correctedName: 'Spaghetti Barilla',
        mainCategory: 'Pantry & Bakery',
        subCategory: 'Grains & Pasta',
        necessity: 'essential',
        merchantName: 'Esselunga SpA',
      );

      await memoryService.recordCorrection(
        rawName: 'OATLY OAT DRINK 1L',
        correctedName: 'Oat Milk 1L',
        mainCategory: 'Proteins & Dairy',
        subCategory: 'Dairy & Alternatives',
        necessity: 'essential',
        merchantName: 'Esselunga SpA',
      );

      final deltaPrompt = await memoryService.buildDifferentialPromptDelta(
        merchantName: 'ESSELUNGA MILANO',
        limit: 3,
      );

      expect(deltaPrompt, isNotEmpty);
      expect(deltaPrompt, contains('<|delta_exemplars_start|>'));
      expect(deltaPrompt, contains('<|delta_exemplars_end|>'));
      expect(deltaPrompt, contains('BARILLA SPAGHETTI 500G'));
      expect(deltaPrompt, contains('Spaghetti Barilla'));
    });

    test('sub-2ms HNSW query latency benchmark across 5,000 stored corrections', () async {
      final dummyMerchants = ['Esselunga', 'Conad', 'Coop', 'Lidl', 'Aldi', 'Carrefour'];
      final dummyCategories = ['Fresh Produce', 'Proteins & Dairy', 'Household & Living', 'Pantry & Bakery'];

      for (int i = 0; i < 5000; i++) {
        await memoryService.recordCorrection(
          rawName: 'CORRECTION ITEM ENTRY #$i',
          correctedName: 'Corrected Item #$i',
          mainCategory: dummyCategories[i % dummyCategories.length],
          subCategory: 'General',
          necessity: 'essential',
          merchantName: dummyMerchants[i % dummyMerchants.length],
        );
      }

      final stats = await memoryService.getStats();
      expect(stats['corrections'], equals(5000));
      expect(stats['hnsw_nodes'], equals(5000));

      // Warmup query
      await memoryService.queryRelevantCorrections(merchantName: 'Esselunga Milano', limit: 3);

      final stopwatch = Stopwatch()..start();
      const numQueries = 30;

      for (int i = 0; i < numQueries; i++) {
        final res = await memoryService.queryRelevantCorrections(
          merchantName: 'Esselunga Milano',
          itemNames: ['CORRECTION ITEM ENTRY #${i * 100}'],
          limit: 3,
        );
        expect(res, isNotEmpty);
      }

      stopwatch.stop();
      final avgLatencyMs = stopwatch.elapsedMicroseconds / (numQueries * 1000.0);
      // ignore: avoid_print
      print('Average HNSW Vector Search Latency (5,000 items): ${avgLatencyMs.toStringAsFixed(3)} ms');

      // Verify sub-2ms target
      expect(avgLatencyMs, lessThan(2.0));
    });
  });
}
