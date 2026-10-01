import 'dart:async';
import 'dart:ffi';
import 'dart:io';
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
///
/// Native calls in the worker are synchronous, so the worker cannot react to
/// any message while it loads a model or runs inference. The handle therefore:
/// - serializes [start]: concurrent callers share one start, and a new start
///   waits until a previous worker has been torn down;
/// - tears a worker down by sending a dispose command and waiting for its
///   acknowledgement, which arrives once the native call in progress returns,
///   so that the model is freed before the isolate is killed;
/// - accepts one request at a time ([isBusy]): a request whose caller timed
///   out still occupies the worker until the worker answers it.
class VlmWorkerIsolate {
  VlmWorkerIsolate({@visibleForTesting void Function(SendPort)? entryPoint})
      : _entryPoint = entryPoint ?? _isolateEntryPoint;

  final void Function(SendPort) _entryPoint;

  Isolate? _isolate;
  SendPort? _sendPort;
  bool _isReady = false;
  Future<bool>? _starting;
  Future<void>? _retiring;
  ReceivePort? _activeRequestPort;

  /// Upper bound for the dispose acknowledgement of a worker that is still
  /// inside a native call (for example a model load that timed out).
  static const Duration disposeAckTimeout = Duration(minutes: 5);

  /// Number of isolates spawned by this handle.
  @visibleForTesting
  int spawnCount = 0;

  bool get isReady => _isReady;

  /// Whether a request is still being processed by the worker.
  bool get isBusy => _activeRequestPort != null;

  /// Completes when the teardown of a previous worker has finished.
  @visibleForTesting
  Future<void> get retired => _retiring ?? Future.value();

  /// Time allowed for the model to load: 30 seconds plus 30 seconds per GiB
  /// of model file, so that large models on slower devices are not reported
  /// as failures while they are still loading.
  static Duration initTimeoutFor(String modelPath) {
    var bytes = 0;
    try {
      bytes = File(modelPath).lengthSync();
    } catch (_) {}
    final gib = bytes / (1 << 30);
    return Duration(seconds: 30 + (30 * gib).ceil());
  }

  /// Spawns the persistent isolate and initializes the native VLM model engine.
  ///
  /// Concurrent calls share the start in progress. [initTimeout] defaults to
  /// [initTimeoutFor] the model.
  Future<bool> start({
    required String modelPath,
    String? mmprojPath,
    String? grammarPath,
    int nThreads = 4,
    int nGpuLayers = 0,
    int nCtx = 2048,
    Duration? initTimeout,
  }) {
    return _starting ??= _start(
      modelPath: modelPath,
      mmprojPath: mmprojPath,
      grammarPath: grammarPath,
      nThreads: nThreads,
      nGpuLayers: nGpuLayers,
      nCtx: nCtx,
      initTimeout: initTimeout ?? initTimeoutFor(modelPath),
    ).whenComplete(() => _starting = null);
  }

  Future<bool> _start({
    required String modelPath,
    String? mmprojPath,
    String? grammarPath,
    required int nThreads,
    required int nGpuLayers,
    required int nCtx,
    required Duration initTimeout,
  }) async {
    if (_isolate != null) {
      await stop();
    }
    // A worker that failed to start may still be loading its model; never hold
    // two models in memory at once.
    await retired;

    final initCompleter = Completer<SendPort>();
    final mainReceivePort = ReceivePort();

    mainReceivePort.listen((message) {
      if (message is SendPort && !initCompleter.isCompleted) {
        initCompleter.complete(message);
      }
    });

    try {
      spawnCount++;
      _isolate = await Isolate.spawn(_entryPoint, mainReceivePort.sendPort);
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

      final Object? result;
      try {
        result = await responsePort.first.timeout(initTimeout);
      } finally {
        responsePort.close();
      }

      if (result == true) {
        _isReady = true;
        debugPrint('VlmWorkerIsolate: Persistent worker initialized successfully.');
        return true;
      }
      debugPrint('VlmWorkerIsolate: Initialization failed on worker isolate.');
    } catch (e) {
      debugPrint('VlmWorkerIsolate: Error starting worker isolate: $e');
    } finally {
      mainReceivePort.close();
    }

    _retireWorker();
    return false;
  }

  /// Detaches the current worker and tears it down in the background.
  void _retireWorker() {
    final isolate = _isolate;
    final sendPort = _sendPort;
    _isolate = null;
    _sendPort = null;
    _isReady = false;
    _releaseActiveRequest();
    if (isolate == null) return;

    final previous = _retiring ?? Future.value();
    _retiring = previous.then((_) => _disposeAndKill(isolate, sendPort, disposeAckTimeout));
  }

  static Future<void> _disposeAndKill(Isolate isolate, SendPort? sendPort, Duration ackTimeout) async {
    if (sendPort != null) {
      final responsePort = ReceivePort();
      try {
        sendPort.send(_DisposeCommand(responsePort.sendPort));
        await responsePort.first.timeout(ackTimeout);
      } catch (_) {
        debugPrint('VlmWorkerIsolate: Worker did not acknowledge dispose; killing it.');
      } finally {
        responsePort.close();
      }
    }
    isolate.kill(priority: Isolate.immediate);
  }

  /// Opens the reply port of a new request, or returns null when the worker
  /// is not ready or still processing an earlier request.
  ReceivePort? _beginRequest() {
    if (!_isReady || _sendPort == null) {
      debugPrint('VlmWorkerIsolate: Cannot process image - worker is not ready.');
      return null;
    }
    if (isBusy) {
      debugPrint('VlmWorkerIsolate: Rejecting request - the previous one is still running.');
      return null;
    }
    return _activeRequestPort = ReceivePort();
  }

  void _endRequest(ReceivePort port) {
    port.close();
    if (identical(_activeRequestPort, port)) _activeRequestPort = null;
  }

  void _releaseActiveRequest() {
    final port = _activeRequestPort;
    if (port != null) _endRequest(port);
  }

  /// Sends an image buffer for zero-copy inference inside the persistent worker isolate.
  ///
  /// Returns null when the worker is not ready, is busy with another request,
  /// fails, or does not answer within [timeout]. After a timeout the worker
  /// stays busy until it answers.
  Future<String?> processImage({
    required Uint8List imageBytes,
    String? fewShotContext,
    String? systemPrompt,
    Duration timeout = const Duration(seconds: 45),
  }) async {
    final responsePort = _beginRequest();
    if (responsePort == null) return null;

    final reply = Completer<Object?>();
    responsePort.listen(
      (message) {
        if (!reply.isCompleted) reply.complete(message);
        _endRequest(responsePort);
      },
      onDone: () {
        if (!reply.isCompleted) reply.complete(null);
      },
    );
    _sendPort!.send(_ProcessImageCommand(
      responsePort.sendPort,
      imageBytes: imageBytes,
      fewShotContext: fewShotContext,
      systemPrompt: systemPrompt,
    ));

    try {
      final response = await reply.future.timeout(timeout);
      if (response is String) {
        return response;
      } else {
        debugPrint('VlmWorkerIsolate: Non-string response from worker: $response');
        return null;
      }
    } catch (e) {
      debugPrint('VlmWorkerIsolate: processImage error or timeout: $e');
      return null;
    }
  }

  /// Streams token-by-token generation from the background worker isolate.
  ///
  /// Completes without tokens when the worker is not ready or busy. After a
  /// timeout the worker stays busy until it reports the end of generation.
  Stream<String> processImageStream({
    required Uint8List imageBytes,
    String? fewShotContext,
    String? systemPrompt,
    Duration timeout = const Duration(seconds: 45),
  }) async* {
    final responsePort = _beginRequest();
    if (responsePort == null) return;

    final controller = StreamController<String>();

    responsePort.listen(
      (message) {
        if (message is Map) {
          final type = message['type'];
          if (type == 'token') {
            final token = message['token'] as String;
            if (!controller.isClosed) controller.add(token);
          } else if (type == 'done') {
            if (!controller.isClosed) controller.close();
            _endRequest(responsePort);
          } else if (type == 'error') {
            if (!controller.isClosed) {
              controller.addError(Exception(message['error']));
              controller.close();
            }
            _endRequest(responsePort);
          }
        }
      },
      onDone: () {
        if (!controller.isClosed) controller.close();
      },
    );

    _sendPort!.send(_ProcessImageStreamingCommand(
      responsePort.sendPort,
      imageBytes: imageBytes,
      fewShotContext: fewShotContext,
      systemPrompt: systemPrompt,
    ));

    try {
      // Same limit as processImage: a worker that stops answering must not
      // leave the caller waiting forever.
      yield* controller.stream.timeout(
        timeout,
        onTimeout: (sink) {
          sink.addError(TimeoutException('No response from the VLM worker', timeout));
          sink.close();
        },
      );
    } finally {
      // The reply port stays open until the worker finishes, so that the
      // worker is not handed a new request while it is still generating.
      if (!controller.isClosed) await controller.close();
    }
  }

  /// Reloads grammar on the persistent engine.
  Future<bool> reloadGrammar(String grammarPath) async {
    if (!_isReady || _sendPort == null || isBusy) return false;

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

  /// Tears down the native engine and shuts down the isolate. The isolate is
  /// killed only after the worker acknowledged the dispose command, or after
  /// a short grace period when it does not answer.
  Future<void> stop() async {
    final isolate = _isolate;
    final sendPort = _sendPort;
    _isolate = null;
    _sendPort = null;
    _isReady = false;
    _releaseActiveRequest();
    if (isolate != null) {
      await _disposeAndKill(isolate, sendPort, const Duration(seconds: 3));
    }
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
