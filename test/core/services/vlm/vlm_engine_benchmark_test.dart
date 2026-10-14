import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/core/services/vlm/vlm_engine_service.dart';

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
  });
}
