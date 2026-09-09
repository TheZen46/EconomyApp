import 'dart:async';
import 'package:flutter/foundation.dart';

/// Web / Unsupported platform stub for VlmFfiBindings.
class VlmFfiBindings {
  VlmFfiBindings._();

  static VlmFfiBindings? load() {
    return null;
  }

  dynamic initEngine({
    required String modelPath,
    String? mmprojPath,
    String? grammarPath,
    int nThreads = 4,
    int nGpuLayers = 0,
    int nCtx = 2048,
  }) {
    return null;
  }

  void freeEngine(dynamic engine) {}

  bool isReady(dynamic engine) => false;

  int reloadGrammar(dynamic engine, String grammarPath) => -1;

  String getLastError(dynamic engine) => 'VLM Engine FFI is not supported on web';

  String? processImage({
    required dynamic engine,
    required Uint8List imageBytes,
    String? fewShotContext,
    String? systemPrompt,
    int maxOutputLen = 65536,
  }) {
    return null;
  }

  Stream<String> processImageStream({
    required dynamic engine,
    required Uint8List imageBytes,
    String? fewShotContext,
    String? systemPrompt,
  }) async* {
    yield* const Stream.empty();
  }

  Uint8List? applyClahe(Uint8List imageBytes, {double clipLimit = 3.0}) => null;

  ({String token, bool isDone})? popToken(dynamic engine) => null;

  ({int totalBlocks, int allocatedBlocks, double hitRatePct}) getKvCacheStats(
          dynamic engine) =>
      (totalBlocks: 0, allocatedBlocks: 0, hitRatePct: 0.0);

  double benchmarkClahe({int width = 3840, int height = 2160}) => 0.0;
}
