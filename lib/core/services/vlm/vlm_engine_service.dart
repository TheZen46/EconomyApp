import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dartz/dartz.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../../features/receipt_scanning/data/models/receipt_model.dart';
import '../../../features/receipt_scanning/domain/entities/receipt.dart';
import '../../constants/taxonomy_constants.dart';
import '../../error/failures.dart';
import '../../data_contracts/ai_receipt_parser.dart';
import '../ai_service.dart';
import '../telemetry_service.dart';
import 'episodic_memory_service.dart';
import 'grammar_generator.dart';
import 'vlm_worker_isolate.dart';

/// Next-Generation Vision-Language Model Engine Service.
///
/// Implements [AIService] to provide high-precision, grammar-constrained,
/// on-device receipt intelligence directly from raw receipt images without UI thread blocking.
class VlmEngineService implements AIService {
  final VlmWorkerIsolate _worker = VlmWorkerIsolate();
  final EpisodicMemoryService _episodicMemory = EpisodicMemoryService();
  bool _isInitialized = false;
  Future<bool>? _initializing;
  String? _loadedModelId;
  String? _loadedQuantTier;

  bool get isModelLoaded => _isInitialized && _worker.isReady;
  String? get loadedModelId => _loadedModelId;
  String? get loadedQuantTier => _loadedQuantTier;

  /// Initializes the persistent VLM worker isolate and episodic memory.
  ///
  /// Concurrent calls (for example a scan started while the model is still
  /// loading for a previous one) share a single initialization.
  Future<bool> initialize({
    String? modelPath,
    String? mmprojPath,
    List<String>? customCategories,
  }) {
    return _initializing ??= _initialize(
      modelPath: modelPath,
      mmprojPath: mmprojPath,
      customCategories: customCategories,
    ).whenComplete(() => _initializing = null);
  }

  Future<bool> _initialize({
    String? modelPath,
    String? mmprojPath,
    List<String>? customCategories,
  }) async {
    if (kIsWeb) return false;
    try {
      await _episodicMemory.initialize();

      final docsDir = await getApplicationDocumentsDirectory();
      final modelsDir = Directory('${docsDir.path}/models');

      // 1. Locate GGUF model files
      String resolvedModelPath = modelPath ?? '';
      String? resolvedMmprojPath = mmprojPath;

      if (resolvedModelPath.isEmpty) {
        final qwenFile = File('${modelsDir.path}/qwen2_vl_2b.Q4_K_M.gguf');
        final smolFile = File('${modelsDir.path}/smolvlm_500m.Q4_K_M.gguf');
        final qwenAltFile = File('${modelsDir.path}/Qwen2-VL-2B-Instruct-Q4_K_M.gguf');
        final smolAltFile = File('${modelsDir.path}/SmolVLM-Instruct-Q4_K_M.gguf');
        final mockFile = File('mock_model_v2.gguf');

        if (await qwenFile.exists()) {
          resolvedModelPath = qwenFile.path;
        } else if (await smolFile.exists()) {
          resolvedModelPath = smolFile.path;
        } else if (await qwenAltFile.exists()) {
          resolvedModelPath = qwenAltFile.path;
        } else if (await smolAltFile.exists()) {
          resolvedModelPath = smolAltFile.path;
        } else if (await mockFile.exists()) {
          resolvedModelPath = mockFile.path;
        }
      }

      if (resolvedModelPath.isEmpty) {
        debugPrint('VlmEngineService: No GGUF model found on disk.');
        return false;
      }

      // 2. Locate Multimodal Projector (mmproj) companion file
      if (resolvedMmprojPath == null || resolvedMmprojPath.isEmpty) {
        final parentDir = File(resolvedModelPath).parent.path;
        final candidateNames = [
          'qwen2_vl_2b.mmproj.gguf',
          'smolvlm_500m.mmproj.gguf',
          'mmproj-Qwen2-VL-2B-Instruct-f16.gguf',
          'mmproj-SmolVLM-Instruct-f16.gguf',
        ];
        for (final name in candidateNames) {
          final candidateFile = File('$parentDir/$name');
          if (await candidateFile.exists() && await candidateFile.length() > 0) {
            resolvedMmprojPath = candidateFile.path;
            break;
          }
        }
      }

      final isMock = resolvedModelPath.contains('mock_model');
      if (!isMock &&
          (resolvedMmprojPath == null ||
              !(await File(resolvedMmprojPath).exists()) ||
              await File(resolvedMmprojPath).length() == 0)) {
        debugPrint(
          'VlmEngineService: Multimodal projector (mmproj) not found or empty. '
          'Vision-language models require both model weights and a vision projector.',
        );
        return false;
      }

      // 3. Generate dynamic GBNF grammar
      final grammarsDir = Directory('${docsDir.path}/grammars');
      final grammarFile = await GrammarGenerator.generateAndSave(
        directory: grammarsDir,
        customCategories: customCategories,
      );

      // 4. Start worker isolate
      final success = await _worker.start(
        modelPath: resolvedModelPath,
        mmprojPath: resolvedMmprojPath,
        grammarPath: grammarFile.path,
      );

      _isInitialized = success;
      if (success) {
        _loadedModelId = _inferModelId(resolvedModelPath);
        _loadedQuantTier = _inferQuantTier(resolvedModelPath);
      } else {
        _loadedModelId = null;
        _loadedQuantTier = null;
      }
      return success;
    } catch (e) {
      debugPrint('VlmEngineService: Initialization exception: $e');
      _isInitialized = false;
      _loadedModelId = null;
      _loadedQuantTier = null;
      return false;
    }
  }

  /// Streams token-by-token generation while extracting receipt data.
  Stream<String> streamReceiptTokens(
    String imagePath, {
    Map<String, Map<String, List<TaxonomyItem>>>? taxonomy,
  }) async* {
    if (kIsWeb) return;
    final imageFile = File(imagePath);
    if (!await imageFile.exists()) return;

    if (!_worker.isReady) {
      final initialized = await initialize();
      if (!initialized) return;
    }
    if (_worker.isBusy) {
      throw StateError('The on-device model is still processing the previous receipt.');
    }

    final fewShotContext =
        await _episodicMemory.buildFewShotPromptSection(limit: 3);
    final imageBytes = await imageFile.readAsBytes();

    yield* _worker.processImageStream(
      imageBytes: imageBytes,
      fewShotContext: fewShotContext,
    );
  }

  @override
  Future<Either<Failure, Receipt>> extractReceiptData(
    String imagePath, {
    Map<String, Map<String, List<TaxonomyItem>>>? taxonomy,
  }) async {
    if (kIsWeb) {
      return const Left(AIProcessingFailure('VLM on-device engine not supported on web. Use Gemini Cloud AI.'));
    }
    final imageFile = File(imagePath);
    if (!await imageFile.exists()) {
      return const Left(AIProcessingFailure('Receipt image file not found'));
    }

    try {
      final totalStopwatch = Stopwatch()..start();
      final preStopwatch = Stopwatch()..start();

      // 1. Ensure worker is warm
      if (!_worker.isReady) {
        final initialized = await initialize();
        if (!initialized) {
          return const Left(CacheFailure('VLM model not initialized'));
        }
      }
      if (_worker.isBusy) {
        return const Left(AIProcessingFailure('The on-device model is still processing the previous receipt.'));
      }

      // 2. Retrieve few-shot context from episodic memory
      final fewShotContext =
          await _episodicMemory.buildFewShotPromptSection(limit: 3);

      // 3. Read image bytes into memory buffer
      final imageBytes = await imageFile.readAsBytes();
      preStopwatch.stop();

      // 4. Execute zero-copy inference in background isolate
      final inferStopwatch = Stopwatch()..start();
      final rawJson = await _worker.processImage(
        imageBytes: imageBytes,
        fewShotContext: fewShotContext,
      );
      inferStopwatch.stop();
      totalStopwatch.stop();

      if (rawJson == null || rawJson.trim().isEmpty) {
        return const Left(
            AIProcessingFailure('VLM returned empty or invalid response'));
      }

      // Record performance telemetry (zero PII)
      final estimatedTokens = (rawJson.length / 3.8).ceil().clamp(10, 2048);
      unawaited(TelemetryService.instance.recordInferencePerformance(
        inferenceDurationMs: inferStopwatch.elapsedMilliseconds,
        preprocessingMs: preStopwatch.elapsedMilliseconds,
        tokenCount: estimatedTokens,
        modelId: _loadedModelId ?? 'unknown_vlm',
        quantTier: _loadedQuantTier ?? 'unknown',
        backend: Platform.isWindows ? 'AVX2/OpenMP' : 'NEON/SIMD',
        customMetadata: {
          'image_size_bytes': imageBytes.length,
          'total_latency_ms': totalStopwatch.elapsedMilliseconds,
        },
      ));

      // 5. Decode deterministic JSON directly
      Map<String, dynamic> jsonMap;
      try {
        jsonMap = jsonDecode(rawJson) as Map<String, dynamic>;
      } catch (e) {
        return Left(ParsingFailure('Failed to parse GBNF output: $e', rawJson));
      }

      // 6. Map JSON schema to ReceiptModel entity
      final receiptModel = _mapJsonToReceiptModel(jsonMap, imagePath);
      return Right(receiptModel.toEntity());
    } catch (e, stack) {
      debugPrint('VlmEngineService: Processing error: $e');
      unawaited(TelemetryService.instance.recordCrash(
        error: e,
        stackTrace: stack,
        errorType: 'VlmEngineService.extractReceiptData',
      ));
      return Left(AIProcessingFailure('VLM execution failed: $e'));
    }
  }

  /// Maps native grammar-compliant JSON map into the tAIdy [ReceiptModel].
  ReceiptModel _mapJsonToReceiptModel(
      Map<String, dynamic> json, String imagePath) {
    return AiReceiptParser.parseToModel(json, imagePath: imagePath);
  }

  /// Records a user correction into episodic memory.
  Future<void> recordUserCorrection({
    required String rawName,
    required String correctedName,
    required String mainCategory,
    required String subCategory,
    required String necessity,
    String merchantName = '',
  }) async {
    await _episodicMemory.recordCorrection(
      rawName: rawName,
      correctedName: correctedName,
      mainCategory: mainCategory,
      subCategory: subCategory,
      necessity: necessity,
      merchantName: merchantName,
    );
  }

  /// Benchmarks the local inference pipeline measuring grammar compilation,
  /// episodic memory retrieval, and, if the model is loaded, worker isolate throughput.
  Future<Map<String, dynamic>> benchmarkInference() async {
    final stopwatch = Stopwatch()..start();

    // 1. Benchmark few-shot retrieval
    final memStopwatch = Stopwatch()..start();
    await _episodicMemory.buildFewShotPromptSection(limit: 3);
    memStopwatch.stop();

    // 2. Measure grammar evaluation
    final grammarStopwatch = Stopwatch()..start();
    final docsDir = await getApplicationDocumentsDirectory();
    final grammarsDir = Directory('${docsDir.path}/grammars');
    await GrammarGenerator.generateAndSave(directory: grammarsDir);
    grammarStopwatch.stop();

    double? tokensPerSec;
    int? inferenceLatencyMs;

    // 3. Measure real inference throughput if worker isolate is ready
    if (_worker.isReady) {
      try {
        final inferStopwatch = Stopwatch()..start();
        final dummyPpm = Uint8List.fromList([
          0x50, 0x36, 0x0A, 0x31, 0x20, 0x31, 0x0A, 0x32, 0x35, 0x35, 0x0A, 0x00, 0x00, 0x00
        ]);
        final output = await _worker.processImage(imageBytes: dummyPpm);
        inferStopwatch.stop();
        inferenceLatencyMs = inferStopwatch.elapsedMilliseconds;
        if (output != null && output.isNotEmpty && inferenceLatencyMs > 0) {
          final estimatedTokens = (output.length / 3.8).ceil();
          tokensPerSec = double.parse((estimatedTokens / (inferenceLatencyMs / 1000.0)).toStringAsFixed(1));
        }
      } catch (e) {
        debugPrint('VlmEngineService.benchmarkInference: inference benchmark notice: $e');
      }
    }

    stopwatch.stop();
    final totalMs = stopwatch.elapsedMilliseconds;

    return {
      'latency_ms': totalMs,
      'memory_latency_ms': memStopwatch.elapsedMilliseconds,
      'memory_retrieval_ms': memStopwatch.elapsedMilliseconds,
      'grammar_latency_ms': grammarStopwatch.elapsedMilliseconds,
      'grammar_gen_ms': grammarStopwatch.elapsedMilliseconds,
      'inference_latency_ms': inferenceLatencyMs,
      'tokens_per_sec': tokensPerSec,
      'is_worker_ready': _worker.isReady,
      'loaded_model_id': _loadedModelId,
      'status': _worker.isReady ? (tokensPerSec != null ? 'PASSED' : 'INFERENCE_FAILED') : 'MODEL_NOT_LOADED',
    };
  }

  /// Unloads the model and frees all resources.
  Future<void> unload() async {
    await _worker.stop();
    _isInitialized = false;
    _loadedModelId = null;
    _loadedQuantTier = null;
  }

  static String _inferModelId(String path) {
    final lower = path.toLowerCase();
    if (lower.contains('qwen2_vl') || lower.contains('qwen2-vl')) {
      return 'Qwen2-VL-2B-Instruct';
    } else if (lower.contains('smolvlm')) {
      return 'SmolVLM-500M-Instruct';
    } else if (lower.contains('mock_model')) {
      return 'Mock-VLM-Model';
    }
    final segments = File(path).uri.pathSegments;
    final fileName = segments.isNotEmpty ? segments.last : path;
    return fileName.replaceAll(RegExp(r'\.gguf$', caseSensitive: false), '');
  }

  static String _inferQuantTier(String path) {
    final upper = path.toUpperCase();
    if (upper.contains('Q4_K_M')) return 'Q4_K_M';
    if (upper.contains('Q4_K_S')) return 'Q4_K_S';
    if (upper.contains('Q8_0')) return 'Q8_0';
    if (upper.contains('F16')) return 'F16';
    if (upper.contains('Q5_K_M')) return 'Q5_K_M';
    return 'unknown';
  }
}
