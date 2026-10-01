import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/core/services/vlm/vlm_worker_isolate_ffi.dart';

// Fake workers. The command classes are private to the worker library, so the
// fakes identify them by type name and reply through their public replyPort.
String _kind(Object? message) => message.runtimeType.toString();
SendPort _reply(Object? message) => (message as dynamic).replyPort as SendPort;

/// Loads instantly and answers image requests after 300 ms.
void _slowInferenceWorker(SendPort main) {
  final port = ReceivePort();
  main.send(port.sendPort);
  port.listen((message) {
    switch (_kind(message)) {
      case '_InitCommand':
        _reply(message).send(true);
      case '_ProcessImageCommand':
        Timer(const Duration(milliseconds: 300), () => _reply(message).send('{"ok":true}'));
      case '_DisposeCommand':
        _reply(message).send(true);
        port.close();
    }
  });
}

/// Takes 400 ms to load the model, longer than the init timeout in the tests.
void _slowInitWorker(SendPort main) {
  final port = ReceivePort();
  main.send(port.sendPort);
  var initialized = false;
  port.listen((message) {
    switch (_kind(message)) {
      case '_InitCommand':
        Timer(const Duration(milliseconds: 400), () {
          initialized = true;
          _reply(message).send(true);
        });
      case '_DisposeCommand':
        // Acknowledge only once the load has finished, as the native worker
        // does: it cannot handle messages during the synchronous load.
        Timer.periodic(const Duration(milliseconds: 20), (timer) {
          if (!initialized) return;
          timer.cancel();
          _reply(message).send(true);
          port.close();
        });
    }
  });
}

void main() {
  final image = Uint8List.fromList([1, 2, 3]);

  test('concurrent starts share one worker isolate', () async {
    final worker = VlmWorkerIsolate(entryPoint: _slowInferenceWorker);
    addTearDown(worker.stop);

    final results = await Future.wait([
      worker.start(modelPath: 'model.gguf'),
      worker.start(modelPath: 'model.gguf'),
      worker.start(modelPath: 'model.gguf'),
    ]);

    expect(results, [true, true, true]);
    expect(worker.spawnCount, 1);
  });

  test('an init timeout tears the worker down after it acknowledges dispose', () async {
    final worker = VlmWorkerIsolate(entryPoint: _slowInitWorker);
    addTearDown(worker.stop);

    final started = await worker.start(modelPath: 'model.gguf', initTimeout: const Duration(milliseconds: 100));
    expect(started, isFalse);
    expect(worker.isReady, isFalse);

    // The teardown waits for the load in progress to finish.
    final stopwatch = Stopwatch()..start();
    await worker.retired.timeout(const Duration(seconds: 5));
    expect(stopwatch.elapsedMilliseconds, greaterThan(150));

    // A new start spawns a fresh worker only after the old one is gone.
    final restarted = await worker.start(modelPath: 'model.gguf', initTimeout: const Duration(seconds: 2));
    expect(restarted, isTrue);
    expect(worker.spawnCount, 2);
  });

  test('a new request is rejected while the worker is still busy', () async {
    final worker = VlmWorkerIsolate(entryPoint: _slowInferenceWorker);
    addTearDown(worker.stop);
    expect(await worker.start(modelPath: 'model.gguf'), isTrue);

    // The caller gives up, but the worker keeps processing.
    final first = await worker.processImage(imageBytes: image, timeout: const Duration(milliseconds: 50));
    expect(first, isNull);
    expect(worker.isBusy, isTrue);
    expect(await worker.processImage(imageBytes: image), isNull);

    // Once the worker answers, it accepts requests again.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(worker.isBusy, isFalse);
    expect(await worker.processImage(imageBytes: image), '{"ok":true}');
  });
}
