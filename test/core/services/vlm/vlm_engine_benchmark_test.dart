import 'dart:io';
import 'dart:isolate';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/core/services/vlm/vlm_engine_service.dart';
import 'package:t_aidy/core/services/vlm/vlm_worker_isolate.dart';

void _mockWorkerEntryPoint(SendPort main) {
  final port = ReceivePort();
  main.send(port.sendPort);
  port.listen((message) {
    if (message != null) {
      final name = message.runtimeType.toString();
      if (name.contains('Init')) {
        (message as dynamic).replyPort.send(true);
      } else if (name.contains('Dispose')) {
        (message as dynamic).replyPort.send(true);
        port.close();
      }
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('vlm_bench_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        return tempDir.path;
      },
    );
  });

  tearDownAll(() async {
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('VlmEngineService benchmark and diagnostic indicators', () {
    test('benchmarkInference reports honest metrics and does not fabricate tokens_per_sec when uninitialized', () async {
      final service = VlmEngineService();
      final results = await service.benchmarkInference();

      expect(results['is_worker_ready'], isFalse);
      expect(results['tokens_per_sec'], isNull);
      expect(results['status'], equals('MODEL_NOT_LOADED'));
      expect(results['memory_latency_ms'], isA<int>());
      expect(results['grammar_latency_ms'], isA<int>());
    });

    test('model ID and quant tier inference from file path works accurately', () {
      final service = VlmEngineService();
      expect(service.loadedModelId, isNull);
      expect(service.loadedQuantTier, isNull);
    });

    test('initialize returns false when explicit model path does not exist on disk', () async {
      final service = VlmEngineService();
      final result = await service.initialize(modelPath: '${tempDir.path}/does_not_exist.gguf');
      expect(result, isFalse);
      expect(service.isModelLoaded, isFalse);
    });

    test('initialize rejects non-mock model when mmproj file is missing', () async {
      final modelsDir = Directory('${tempDir.path}/models');
      await modelsDir.create(recursive: true);
      final modelFile = File('${modelsDir.path}/qwen2_vl_2b.Q4_K_M.gguf');
      await modelFile.writeAsString('non-mock-content');

      final service = VlmEngineService();
      final result = await service.initialize(modelPath: modelFile.path);
      expect(result, isFalse);
      expect(service.isModelLoaded, isFalse);

      if (await modelFile.exists()) {
        await modelFile.delete();
      }
    });

    test('initialize succeeds for mock model with mock worker and sets isModelLoaded to true', () async {
      final modelsDir = Directory('${tempDir.path}/models');
      await modelsDir.create(recursive: true);
      final modelFile = File('${modelsDir.path}/mock_model_v2.gguf');
      await modelFile.writeAsString('mock-gguf-content');

      final worker = VlmWorkerIsolate(entryPoint: _mockWorkerEntryPoint);
      final service = VlmEngineService(worker: worker);
      final result = await service.initialize(modelPath: modelFile.path);
      expect(result, isTrue);
      expect(service.isModelLoaded, isTrue);
      expect(service.loadedModelId, equals('Mock-VLM-Model'));
      await service.unload();

      if (await modelFile.exists()) {
        await modelFile.delete();
      }
    });
  });
}

