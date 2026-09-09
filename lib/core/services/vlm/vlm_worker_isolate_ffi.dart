import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'vlm_ffi_bindings.dart';

/// Commands sent to the persistent VLM Worker Isolate.
sealed class _VlmWorkerCommand {
  final SendPort replyPort;
  const _VlmWorkerCommand(this.replyPort);
}

class _InitCommand extends _VlmWorkerCommand {
  final String modelPath;
  final String? mmprojPath;
  final String? grammarPath;
  final int nThreads;
  final int nGpuLayers;
  final int nCtx;

  const _InitCommand(
    super.replyPort, {
    required this.modelPath,
    this.mmprojPath,
    this.grammarPath,
    this.nThreads = 4,
    this.nGpuLayers = 0,
    this.nCtx = 2048,
  });
}

class _ProcessImageCommand extends _VlmWorkerCommand {
  final Uint8List imageBytes;
  final String? fewShotContext;
  final String? systemPrompt;

  const _ProcessImageCommand(
    super.replyPort, {
    required this.imageBytes,
    this.fewShotContext,
    this.systemPrompt,
  });
}

class _ProcessImageStreamingCommand extends _VlmWorkerCommand {
  final Uint8List imageBytes;
  final String? fewShotContext;
  final String? systemPrompt;

  const _ProcessImageStreamingCommand(
    super.replyPort, {
    required this.imageBytes,
    this.fewShotContext,
    this.systemPrompt,
  });
}

class _ReloadGrammarCommand extends _VlmWorkerCommand {
  final String grammarPath;

  const _ReloadGrammarCommand(super.replyPort, {required this.grammarPath});
}

class _DisposeCommand extends _VlmWorkerCommand {
  const _DisposeCommand(super.replyPort);
}

/// Actor handle wrapping the persistent background worker isolate.
class VlmWorkerIsolate {
  Isolate? _isolate;
  SendPort? _sendPort;
  bool _isReady = false;

  bool get isReady => _isReady;

  /// Spawns the persistent isolate and initializes the native VLM model engine.
  Future<bool> start({
    required String modelPath,
    String? mmprojPath,
    String? grammarPath,
    int nThreads = 4,
    int nGpuLayers = 0,
    int nCtx = 2048,
  }) async {
    if (_isolate != null) {
      await stop();
    }

    final initCompleter = Completer<SendPort>();
    final mainReceivePort = ReceivePort();

    mainReceivePort.listen((message) {
      if (message is SendPort && !initCompleter.isCompleted) {
        initCompleter.complete(message);
      }
    });

    try {
      _isolate = await Isolate.spawn(_isolateEntryPoint, mainReceivePort.sendPort);
      _sendPort = await initCompleter.future.timeout(const Duration(seconds: 10));

      final responsePort = ReceivePort();
      _sendPort!.send(_InitCommand(
        responsePort.sendPort,
        modelPath: modelPath,
        mmprojPath: mmprojPath,
        grammarPath: grammarPath,
        nThreads: nThreads,
        nGpuLayers: nGpuLayers,
        nCtx: nCtx,
      ));

      final result = await responsePort.first.timeout(const Duration(seconds: 30));
      responsePort.close();

      if (result == true) {
        _isReady = true;
        debugPrint('VlmWorkerIsolate: Persistent worker initialized successfully.');
        return true;
      } else {
        debugPrint('VlmWorkerIsolate: Initialization failed on worker isolate.');
        _isReady = false;
        return false;
      }
    } catch (e) {
      debugPrint('VlmWorkerIsolate: Error spawning worker isolate: $e');
      _isReady = false;
      return false;
    } finally {
      mainReceivePort.close();
    }
  }

  /// Sends an image buffer for zero-copy inference inside the persistent worker isolate.
  Future<String?> processImage({
    required Uint8List imageBytes,
    String? fewShotContext,
    String? systemPrompt,
    Duration timeout = const Duration(seconds: 45),
  }) async {
    if (!_isReady || _sendPort == null) {
      debugPrint('VlmWorkerIsolate: Cannot process image - worker is not ready.');
      return null;
    }

    final responsePort = ReceivePort();
    _sendPort!.send(_ProcessImageCommand(
      responsePort.sendPort,
      imageBytes: imageBytes,
      fewShotContext: fewShotContext,
      systemPrompt: systemPrompt,
    ));

    try {
      final response = await responsePort.first.timeout(timeout);
      if (response is String) {
        return response;
      } else {
        debugPrint('VlmWorkerIsolate: Non-string response from worker: $response');
        return null;
      }
    } catch (e) {
      debugPrint('VlmWorkerIsolate: processImage error or timeout: $e');
      return null;
    } finally {
      responsePort.close();
    }
  }

  /// Streams token-by-token generation from the background worker isolate.
  Stream<String> processImageStream({
    required Uint8List imageBytes,
    String? fewShotContext,
    String? systemPrompt,
  }) async* {
    if (!_isReady || _sendPort == null) {
      debugPrint('VlmWorkerIsolate: Cannot process image - worker is not ready.');
      return;
    }

    final responsePort = ReceivePort();
    final controller = StreamController<String>();

    final subscription = responsePort.listen((message) {
      if (message is Map) {
        final type = message['type'];
        if (type == 'token') {
          final token = message['token'] as String;
          if (!controller.isClosed) controller.add(token);
        } else if (type == 'done') {
          if (!controller.isClosed) controller.close();
        } else if (type == 'error') {
          if (!controller.isClosed) {
            controller.addError(Exception(message['error']));
            controller.close();
          }
        }
      }
    });

    _sendPort!.send(_ProcessImageStreamingCommand(
      responsePort.sendPort,
      imageBytes: imageBytes,
      fewShotContext: fewShotContext,
      systemPrompt: systemPrompt,
    ));

    try {
      yield* controller.stream;
    } finally {
      await subscription.cancel();
      responsePort.close();
      if (!controller.isClosed) await controller.close();
    }
  }

  /// Reloads grammar on the persistent engine.
  Future<bool> reloadGrammar(String grammarPath) async {
    if (!_isReady || _sendPort == null) return false;

    final responsePort = ReceivePort();
    _sendPort!.send(_ReloadGrammarCommand(
      responsePort.sendPort,
      grammarPath: grammarPath,
    ));

    try {
      final response = await responsePort.first.timeout(const Duration(seconds: 5));
      return response == true;
    } catch (e) {
      debugPrint('VlmWorkerIsolate: reloadGrammar failed: $e');
      return false;
    } finally {
      responsePort.close();
    }
  }

  /// Gracefully tears down the native engine and shuts down the isolate.
  Future<void> stop() async {
    if (_sendPort != null) {
      final responsePort = ReceivePort();
      try {
        _sendPort!.send(_DisposeCommand(responsePort.sendPort));
        await responsePort.first.timeout(const Duration(seconds: 3));
      } catch (_) {
        // Ignored
      } finally {
        responsePort.close();
      }
    }

    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _sendPort = null;
    _isReady = false;
    debugPrint('VlmWorkerIsolate: Persistent worker isolate stopped.');
  }

  // ── Isolate Entry Point ───────────────────────────────────────────────────

  static void _isolateEntryPoint(SendPort mainSendPort) {
    final isolateReceivePort = ReceivePort();
    mainSendPort.send(isolateReceivePort.sendPort);

    VlmFfiBindings? bindings;
    Pointer<Void> enginePtr = nullptr;

    isolateReceivePort.listen((message) {
      if (message is _InitCommand) {
        try {
          bindings = VlmFfiBindings.load();
          if (bindings == null) {
            message.replyPort.send(false);
            return;
          }

          enginePtr = bindings!.initEngine(
            modelPath: message.modelPath,
            mmprojPath: message.mmprojPath,
            grammarPath: message.grammarPath,
            nThreads: message.nThreads,
            nGpuLayers: message.nGpuLayers,
            nCtx: message.nCtx,
          );

          final ready = bindings!.isReady(enginePtr);
          message.replyPort.send(ready);
        } catch (e) {
          message.replyPort.send(false);
        }
      } else if (message is _ProcessImageCommand) {
        if (bindings == null || enginePtr == nullptr) {
          message.replyPort.send(null);
          return;
        }

        try {
          final json = bindings!.processImage(
            engine: enginePtr,
            imageBytes: message.imageBytes,
            fewShotContext: message.fewShotContext,
            systemPrompt: message.systemPrompt,
          );
          message.replyPort.send(json);
        } catch (e) {
          message.replyPort.send(null);
        }
      } else if (message is _ProcessImageStreamingCommand) {
        if (bindings == null || enginePtr == nullptr) {
          message.replyPort.send({'type': 'error', 'error': 'VLM engine not initialized'});
          return;
        }

        try {
          final stream = bindings!.processImageStream(
            engine: enginePtr,
            imageBytes: message.imageBytes,
            fewShotContext: message.fewShotContext,
            systemPrompt: message.systemPrompt,
          );

          stream.listen(
            (token) {
              message.replyPort.send({'type': 'token', 'token': token});
            },
            onDone: () {
              message.replyPort.send({'type': 'done'});
            },
            onError: (err) {
              message.replyPort.send({'type': 'error', 'error': err.toString()});
            },
          );
        } catch (e) {
          message.replyPort.send({'type': 'error', 'error': e.toString()});
        }
      } else if (message is _ReloadGrammarCommand) {
        if (bindings == null || enginePtr == nullptr) {
          message.replyPort.send(false);
          return;
        }

        final status = bindings!.reloadGrammar(enginePtr, message.grammarPath);
        message.replyPort.send(status == 0);
      } else if (message is _DisposeCommand) {
        if (bindings != null && enginePtr != nullptr) {
          bindings!.freeEngine(enginePtr);
          enginePtr = nullptr;
        }
        message.replyPort.send(true);
        isolateReceivePort.close();
      }
    });
  }
}
