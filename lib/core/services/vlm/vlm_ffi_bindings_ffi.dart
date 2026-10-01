import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

// ── Native C ABI Typedefs ───────────────────────────────────────────────────

typedef ReceiptEngineInitNative = Pointer<Void> Function(
    Pointer<Utf8> modelPath,
    Pointer<Utf8> mmprojPath,
    Pointer<Utf8> grammarPath,
    Int32 nThreads,
    Int32 nGpuLayers,
    Int32 nCtx);
typedef ReceiptEngineInitDart = Pointer<Void> Function(
    Pointer<Utf8> modelPath,
    Pointer<Utf8> mmprojPath,
    Pointer<Utf8> grammarPath,
    int nThreads,
    int nGpuLayers,
    int nCtx);

typedef ReceiptEngineFreeNative = Void Function(Pointer<Void> engine);
typedef ReceiptEngineFreeDart = void Function(Pointer<Void> engine);

typedef ReceiptEngineIsReadyNative = Int32 Function(Pointer<Void> engine);
typedef ReceiptEngineIsReadyDart = int Function(Pointer<Void> engine);

typedef ReceiptEngineProcessImageNative = Int32 Function(
    Pointer<Void> engine,
    Pointer<Uint8> imageBytes,
    Size imageLen,
    Pointer<Utf8> fewShotContext,
    Pointer<Utf8> systemPrompt,
    Pointer<Utf8> outputBuffer,
    Size maxOutputLen);
typedef ReceiptEngineProcessImageDart = int Function(
    Pointer<Void> engine,
    Pointer<Uint8> imageBytes,
    int imageLen,
    Pointer<Utf8> fewShotContext,
    Pointer<Utf8> systemPrompt,
    Pointer<Utf8> outputBuffer,
    int maxOutputLen);

typedef ReceiptTokenCallbackNative = Void Function(
    Pointer<Utf8> token, Int32 isDone, Pointer<Void> userData);

typedef ReceiptEngineProcessImageStreamingNative = Int32 Function(
    Pointer<Void> engine,
    Pointer<Uint8> imageBytes,
    Size imageLen,
    Pointer<Utf8> fewShotContext,
    Pointer<Utf8> systemPrompt,
    Pointer<NativeFunction<ReceiptTokenCallbackNative>> callback,
    Pointer<Void> userData);
typedef ReceiptEngineProcessImageStreamingDart = int Function(
    Pointer<Void> engine,
    Pointer<Uint8> imageBytes,
    int imageLen,
    Pointer<Utf8> fewShotContext,
    Pointer<Utf8> systemPrompt,
    Pointer<NativeFunction<ReceiptTokenCallbackNative>> callback,
    Pointer<Void> userData);

typedef ReceiptEngineReloadGrammarNative = Int32 Function(
    Pointer<Void> engine, Pointer<Utf8> grammarPath);
typedef ReceiptEngineReloadGrammarDart = int Function(
    Pointer<Void> engine, Pointer<Utf8> grammarPath);

typedef ReceiptEngineGetLastErrorNative = Pointer<Utf8> Function(
    Pointer<Void> engine);
typedef ReceiptEngineGetLastErrorDart = Pointer<Utf8> Function(
    Pointer<Void> engine);

typedef ReceiptEngineApplyClaheNative = Int32 Function(
    Pointer<Uint8> inBytes,
    Size inLen,
    Pointer<Uint8> outBytes,
    Size outLen,
    Float clipLimit);
typedef ReceiptEngineApplyClaheDart = int Function(
    Pointer<Uint8> inBytes,
    int inLen,
    Pointer<Uint8> outBytes,
    int outLen,
    double clipLimit);

typedef ReceiptEnginePopTokenNative = Int32 Function(
    Pointer<Void> engine,
    Pointer<Utf8> outBuf,
    Size maxLen,
    Pointer<Int32> outIsDone);
typedef ReceiptEnginePopTokenDart = int Function(
    Pointer<Void> engine,
    Pointer<Utf8> outBuf,
    int maxLen,
    Pointer<Int32> outIsDone);

typedef ReceiptEngineGetKvCacheStatsNative = Void Function(
    Pointer<Void> engine,
    Pointer<Size> outTotalBlocks,
    Pointer<Size> outAllocatedBlocks,
    Pointer<Float> outHitRate);
typedef ReceiptEngineGetKvCacheStatsDart = void Function(
    Pointer<Void> engine,
    Pointer<Size> outTotalBlocks,
    Pointer<Size> outAllocatedBlocks,
    Pointer<Float> outHitRate);

typedef ReceiptEngineBenchmarkClaheNative = Double Function(
    Int32 width, Int32 height);
typedef ReceiptEngineBenchmarkClaheDart = double Function(
    int width, int height);

/// High-performance FFI Bindings for the native VLM receipt engine.
class VlmFfiBindings {
  final DynamicLibrary _lib;

  late final ReceiptEngineInitDart _init;
  late final ReceiptEngineFreeDart _free;
  late final ReceiptEngineIsReadyDart _isReady;
  late final ReceiptEngineProcessImageDart _processImage;
  late final ReceiptEngineProcessImageStreamingDart _processImageStreaming;
  late final ReceiptEngineReloadGrammarDart _reloadGrammar;
  late final ReceiptEngineGetLastErrorDart _getLastError;
  ReceiptEngineApplyClaheDart? _applyClahe;
  ReceiptEnginePopTokenDart? _popToken;
  ReceiptEngineGetKvCacheStatsDart? _getKvCacheStats;
  ReceiptEngineBenchmarkClaheDart? _benchmarkClahe;

  VlmFfiBindings._(this._lib) {
    _init = _lib
        .lookup<NativeFunction<ReceiptEngineInitNative>>('receipt_engine_init')
        .asFunction();
    _free = _lib
        .lookup<NativeFunction<ReceiptEngineFreeNative>>('receipt_engine_free')
        .asFunction();
    _isReady = _lib
        .lookup<NativeFunction<ReceiptEngineIsReadyNative>>(
            'receipt_engine_is_ready')
        .asFunction();
    _processImage = _lib
        .lookup<NativeFunction<ReceiptEngineProcessImageNative>>(
            'receipt_engine_process_image')
        .asFunction();
    _processImageStreaming = _lib
        .lookup<NativeFunction<ReceiptEngineProcessImageStreamingNative>>(
            'receipt_engine_process_image_streaming')
        .asFunction();
    _reloadGrammar = _lib
        .lookup<NativeFunction<ReceiptEngineReloadGrammarNative>>(
            'receipt_engine_reload_grammar')
        .asFunction();
    _getLastError = _lib
        .lookup<NativeFunction<ReceiptEngineGetLastErrorNative>>(
            'receipt_engine_get_last_error')
        .asFunction();

    try {
      _applyClahe = _lib
          .lookup<NativeFunction<ReceiptEngineApplyClaheNative>>(
              'receipt_engine_apply_clahe')
          .asFunction();
    } catch (_) {}

    try {
      _popToken = _lib
          .lookup<NativeFunction<ReceiptEnginePopTokenNative>>(
              'receipt_engine_pop_token')
          .asFunction();
    } catch (_) {}

    try {
      _getKvCacheStats = _lib
          .lookup<NativeFunction<ReceiptEngineGetKvCacheStatsNative>>(
              'receipt_engine_get_kv_cache_stats')
          .asFunction();
    } catch (_) {}

    try {
      _benchmarkClahe = _lib
          .lookup<NativeFunction<ReceiptEngineBenchmarkClaheNative>>(
              'receipt_engine_benchmark_clahe')
          .asFunction();
    } catch (_) {}
  }

  /// Loads the platform-specific shared library.
  static VlmFfiBindings? load() {
    try {
      DynamicLibrary lib;
      if (Platform.isAndroid) {
        lib = DynamicLibrary.open('libreceipt_engine.so');
      } else if (Platform.isWindows) {
        try {
          lib = DynamicLibrary.open('receipt_engine.dll');
        } catch (_) {
          lib = DynamicLibrary.process();
        }
      } else if (Platform.isLinux) {
        lib = DynamicLibrary.open('libreceipt_engine.so');
      } else if (Platform.isMacOS || Platform.isIOS) {
        try {
          lib = DynamicLibrary.open('libreceipt_engine.dylib');
        } catch (_) {
          lib = DynamicLibrary.process();
        }
      } else {
        return null;
      }
      return VlmFfiBindings._(lib);
    } catch (e) {
      debugPrint('VlmFfiBindings: Could not load native library: $e');
      return null;
    }
  }

  Pointer<Void> initEngine({
    required String modelPath,
    String? mmprojPath,
    String? grammarPath,
    int nThreads = 4,
    int nGpuLayers = 0,
    int nCtx = 2048,
  }) {
    final mPathPtr = modelPath.toNativeUtf8();
    final mmPathPtr =
        mmprojPath != null ? mmprojPath.toNativeUtf8() : nullptr;
    final gPathPtr =
        grammarPath != null ? grammarPath.toNativeUtf8() : nullptr;

    try {
      return _init(mPathPtr, mmPathPtr, gPathPtr, nThreads, nGpuLayers, nCtx);
    } finally {
      calloc.free(mPathPtr);
      if (mmPathPtr != nullptr) calloc.free(mmPathPtr);
      if (gPathPtr != nullptr) calloc.free(gPathPtr);
    }
  }

  void freeEngine(Pointer<Void> engine) {
    if (engine != nullptr) {
      _free(engine);
    }
  }

  bool isReady(Pointer<Void> engine) {
    if (engine == nullptr) return false;
    return _isReady(engine) == 1;
  }

  int reloadGrammar(Pointer<Void> engine, String grammarPath) {
    if (engine == nullptr) return -1;
    final gPathPtr = grammarPath.toNativeUtf8();
    try {
      return _reloadGrammar(engine, gPathPtr);
    } finally {
      calloc.free(gPathPtr);
    }
  }

  String getLastError(Pointer<Void> engine) {
    if (engine == nullptr) return 'Null engine pointer';
    final ptr = _getLastError(engine);
    if (ptr == nullptr) return '';
    return ptr.toDartString();
  }

  /// Executes zero-copy native inference on the image bytes.
  String? processImage({
    required Pointer<Void> engine,
    required Uint8List imageBytes,
    String? fewShotContext,
    String? systemPrompt,
    int maxOutputLen = 65536,
  }) {
    if (engine == nullptr || imageBytes.isEmpty) return null;

    final imageBuffer = calloc<Uint8>(imageBytes.length);
    final outputBuffer = calloc<Uint8>(maxOutputLen);
    final fewShotPtr =
        fewShotContext != null ? fewShotContext.toNativeUtf8() : nullptr;
    final sysPromptPtr =
        systemPrompt != null ? systemPrompt.toNativeUtf8() : nullptr;

    try {
      imageBuffer
          .asTypedList(imageBytes.length)
          .setAll(0, imageBytes);

      final status = _processImage(
        engine,
        imageBuffer,
        imageBytes.length,
        fewShotPtr,
        sysPromptPtr,
        outputBuffer.cast<Utf8>(),
        maxOutputLen,
      );

      if (status != 0) {
        final err = getLastError(engine);
        debugPrint('VlmFfiBindings: Process image failed ($status): $err');
        return null;
      }

      return outputBuffer.cast<Utf8>().toDartString();
    } finally {
      calloc.free(imageBuffer);
      calloc.free(outputBuffer);
      if (fewShotPtr != nullptr) calloc.free(fewShotPtr);
      if (sysPromptPtr != nullptr) calloc.free(sysPromptPtr);
    }
  }

  /// Streams token-by-token generation synchronously via native callback.
  /// Runs native inference and yields the generated tokens.
  ///
  /// The native call is synchronous on the calling isolate, so tokens are
  /// collected while it runs and yielded after it returns; the stream always
  /// completes, and a non-zero native status becomes a [StateError] event.
  Stream<String> processImageStream({
    required Pointer<Void> engine,
    required Uint8List imageBytes,
    String? fewShotContext,
    String? systemPrompt,
  }) async* {
    if (engine == nullptr || imageBytes.isEmpty) return;

    final tokens = <String>[];
    final imageBuffer = calloc<Uint8>(imageBytes.length);
    final fewShotPtr =
        fewShotContext != null ? fewShotContext.toNativeUtf8() : nullptr;
    final sysPromptPtr =
        systemPrompt != null ? systemPrompt.toNativeUtf8() : nullptr;
    final nativeCallback = NativeCallable<ReceiptTokenCallbackNative>.isolateLocal(
      (Pointer<Utf8> tokenPtr, int isDone, Pointer<Void> userData) {
        if (tokenPtr != nullptr) {
          final token = tokenPtr.toDartString();
          if (token.isNotEmpty) tokens.add(token);
        }
      },
    );

    final int status;
    try {
      imageBuffer
          .asTypedList(imageBytes.length)
          .setAll(0, imageBytes);

      status = _processImageStreaming(
        engine,
        imageBuffer,
        imageBytes.length,
        fewShotPtr,
        sysPromptPtr,
        nativeCallback.nativeFunction,
        nullptr,
      );
    } finally {
      nativeCallback.close();
      calloc.free(imageBuffer);
      if (fewShotPtr != nullptr) calloc.free(fewShotPtr);
      if (sysPromptPtr != nullptr) calloc.free(sysPromptPtr);
    }

    if (status != 0) {
      throw StateError('Streaming inference failed ($status): ${getLastError(engine)}');
    }
    for (final token in tokens) {
      yield token;
    }
  }

  /// Enhances thermal receipt contrast using SIMD CLAHE.
  Uint8List? applyClahe(Uint8List imageBytes, {double clipLimit = 3.0}) {
    if (_applyClahe == null || imageBytes.isEmpty) return null;

    final inBuffer = calloc<Uint8>(imageBytes.length);
    final maxOutLen = imageBytes.length * 4; // Sufficient scratchpad
    final outBuffer = calloc<Uint8>(maxOutLen);

    try {
      inBuffer.asTypedList(imageBytes.length).setAll(0, imageBytes);
      final bytesWritten = _applyClahe!(
        inBuffer,
        imageBytes.length,
        outBuffer,
        maxOutLen,
        clipLimit,
      );

      if (bytesWritten <= 0) return null;
      return Uint8List.fromList(outBuffer.asTypedList(bytesWritten));
    } finally {
      calloc.free(inBuffer);
      calloc.free(outBuffer);
    }
  }

  /// Dequeues a token chunk from the SPSC lock-free ring buffer.
  ({String token, bool isDone})? popToken(Pointer<Void> engine) {
    if (_popToken == null || engine == nullptr) return null;

    final outBuf = calloc<Uint8>(128).cast<Utf8>();
    final isDonePtr = calloc<Int32>();

    try {
      final popped = _popToken!(engine, outBuf, 128, isDonePtr);
      if (popped == 1) {
        return (token: outBuf.toDartString(), isDone: isDonePtr.value == 1);
      }
      return null;
    } finally {
      calloc.free(outBuf);
      calloc.free(isDonePtr);
    }
  }

  /// Retrieves virtual Paged KV-Cache statistics.
  ({int totalBlocks, int allocatedBlocks, double hitRatePct}) getKvCacheStats(
      Pointer<Void> engine) {
    if (_getKvCacheStats == null || engine == nullptr) {
      return (totalBlocks: 0, allocatedBlocks: 0, hitRatePct: 0.0);
    }

    final totalPtr = calloc<Size>();
    final allocPtr = calloc<Size>();
    final hitRatePtr = calloc<Float>();

    try {
      _getKvCacheStats!(engine, totalPtr, allocPtr, hitRatePtr);
      return (
        totalBlocks: totalPtr.value,
        allocatedBlocks: allocPtr.value,
        hitRatePct: hitRatePtr.value,
      );
    } finally {
      calloc.free(totalPtr);
      calloc.free(allocPtr);
      calloc.free(hitRatePtr);
    }
  }

  /// Benchmarks SIMD CLAHE execution latency on high-res receipt images.
  double benchmarkClahe({int width = 3840, int height = 2160}) {
    if (_benchmarkClahe == null) return 0.0;
    return _benchmarkClahe!(width, height);
  }
}
