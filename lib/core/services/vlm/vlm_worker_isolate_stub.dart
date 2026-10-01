import 'dart:async';
import 'package:flutter/foundation.dart';

/// Web / Unsupported platform stub for VlmWorkerIsolate.
class VlmWorkerIsolate {
  bool get isReady => false;

  Future<bool> start({
    required String modelPath,
    String? mmprojPath,
    String? grammarPath,
    int nThreads = 4,
    int nGpuLayers = 0,
    int nCtx = 2048,
  }) async {
    return false;
  }

  Future<String?> processImage({
    required Uint8List imageBytes,
    String? fewShotContext,
    String? systemPrompt,
    Duration timeout = const Duration(seconds: 45),
  }) async {
    return null;
  }

  Stream<String> processImageStream({
    required Uint8List imageBytes,
    String? fewShotContext,
    String? systemPrompt,
    Duration timeout = const Duration(seconds: 45),
  }) async* {
    yield* const Stream.empty();
  }

  Future<bool> reloadGrammar(String grammarPath) async {
    return false;
  }

  Future<void> stop() async {}
}
