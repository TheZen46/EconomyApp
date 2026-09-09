import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/core/services/telemetry_service.dart';

void main() {
  late Directory tempDir;
  late TelemetryService telemetryService;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('telemetry_test_');
    telemetryService = TelemetryService(baseDirectory: tempDir);
    await telemetryService.initialize(baseDirectory: tempDir);
  });

  tearDown(() async {
    await telemetryService.clearLogs();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('TelemetryService Performance Tracing', () {
    test('records VLM inference performance metric accurately', () async {
      final metric = await telemetryService.recordInferencePerformance(
        inferenceDurationMs: 250,
        preprocessingMs: 15,
        tokenCount: 50,
        modelId: 'Qwen2-VL-2B-Instruct',
        quantTier: 'Q4_K_M',
        backend: 'AVX2/SIMD',
        memoryRssDeltaBytes: 1048576,
        customMetadata: {'batch_size': 1},
      );

      expect(metric.inferenceDurationMs, equals(250));
      expect(metric.preprocessingMs, equals(15));
      expect(metric.tokenCount, equals(50));
      // 50 tokens in 250ms = 200 tokens/sec
      expect(metric.tokensPerSecond, equals(200.0));
      expect(metric.modelId, equals('Qwen2-VL-2B-Instruct'));
      expect(metric.quantTier, equals('Q4_K_M'));
      expect(metric.backend, equals('AVX2/SIMD'));

      expect(telemetryService.recentEvents.length, equals(1));
      expect(telemetryService.recentEvents.first['type'], equals('inference_performance'));
      expect(telemetryService.recentEvents.first['tokens_per_second'], equals(200.0));
    });

    test('persists telemetry events to JSONL log file', () async {
      await telemetryService.recordInferencePerformance(
        inferenceDurationMs: 500,
        preprocessingMs: 30,
        tokenCount: 40,
        modelId: 'SmolVLM-500M',
        quantTier: 'Q8_0',
      );

      final diskCount = await telemetryService.getDiskEventCount();
      expect(diskCount, equals(1));

      final logFile = File('${tempDir.path}/logs/telemetry_events.jsonl');
      expect(await logFile.exists(), isTrue);

      final content = await logFile.readAsString();
      expect(content, contains('SmolVLM-500M'));
      expect(content, contains('Q8_0'));
    });
  });

  group('TelemetryService Privacy & PII Scrubbing', () {
    test('scrubs credit cards, emails, and Windows/Unix user paths from crash reports', () async {
      final errorWithPii = Exception(
        'Failed to connect user john.doe@example.com with card 4532 1234 5678 9012 on C:\\Users\\Administrator\\AppData\\Local',
      );

      final report = await telemetryService.recordCrash(
        error: errorWithPii,
        errorType: 'AuthenticationException',
        isFatal: false,
      );

      expect(report.sanitizedMessage, isNot(contains('john.doe@example.com')));
      expect(report.sanitizedMessage, contains('[REDACTED_EMAIL]'));
      expect(report.sanitizedMessage, isNot(contains('4532 1234 5678 9012')));
      expect(report.sanitizedMessage, contains('[REDACTED_CARD]'));
      expect(report.sanitizedMessage, isNot(contains('Administrator')));
      expect(report.sanitizedMessage, contains('C:\\Users\\[USER]'));
    });

    test('sanitizeTelemetryString strips POSIX /home/user and /Users/user paths', () {
      const posixPath = 'Error in /home/developer/projects/t_aidy/native/src/engine.cpp:42';
      const macPath = 'Error in /Users/johndoe/Library/Application Support/t_aidy/model.gguf';

      final cleanPosix = TelemetryService.sanitizeTelemetryString(posixPath);
      final cleanMac = TelemetryService.sanitizeTelemetryString(macPath);

      expect(cleanPosix, equals('Error in /Users/[USER]/projects/t_aidy/native/src/engine.cpp:42'));
      expect(cleanMac, equals('Error in /Users/[USER]/Library/Application Support/t_aidy/model.gguf'));
    });
  });

  group('TelemetryService Buffer & Maintenance', () {
    test('clearLogs clears both in-memory ring buffer and on-disk files', () async {
      await telemetryService.recordCrash(error: 'Test Error 1');
      await telemetryService.recordCrash(error: 'Test Error 2');

      expect(telemetryService.recentEvents.length, equals(2));
      expect(await telemetryService.getDiskEventCount(), equals(2));

      await telemetryService.clearLogs();

      expect(telemetryService.recentEvents.isEmpty, isTrue);
      expect(await telemetryService.getDiskEventCount(), equals(0));
    });
  });
}
