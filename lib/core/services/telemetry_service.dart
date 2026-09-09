import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../privacy/pii_scrubber_service.dart';

/// Represents performance metrics for an on-device VLM inference operation.
@immutable
class InferenceTelemetryMetric {
  final int inferenceDurationMs;
  final int preprocessingMs;
  final int tokenCount;
  final double tokensPerSecond;
  final String modelId;
  final String quantTier;
  final String backend;
  final int memoryRssDeltaBytes;
  final DateTime timestamp;
  final Map<String, dynamic> metadata;

  const InferenceTelemetryMetric({
    required this.inferenceDurationMs,
    required this.preprocessingMs,
    required this.tokenCount,
    required this.tokensPerSecond,
    required this.modelId,
    required this.quantTier,
    required this.backend,
    required this.memoryRssDeltaBytes,
    required this.timestamp,
    this.metadata = const {},
  });

  Map<String, dynamic> toJson() {
    return {
      'type': 'inference_performance',
      'inference_duration_ms': inferenceDurationMs,
      'preprocessing_ms': preprocessingMs,
      'token_count': tokenCount,
      'tokens_per_second': double.parse(tokensPerSecond.toStringAsFixed(2)),
      'model_id': modelId,
      'quant_tier': quantTier,
      'backend': backend,
      'memory_rss_delta_bytes': memoryRssDeltaBytes,
      'timestamp': timestamp.toUtc().toIso8601String(),
      'metadata': metadata,
    };
  }

  factory InferenceTelemetryMetric.fromJson(Map<String, dynamic> json) {
    return InferenceTelemetryMetric(
      inferenceDurationMs: (json['inference_duration_ms'] as num?)?.toInt() ?? 0,
      preprocessingMs: (json['preprocessing_ms'] as num?)?.toInt() ?? 0,
      tokenCount: (json['token_count'] as num?)?.toInt() ?? 0,
      tokensPerSecond: (json['tokens_per_second'] as num?)?.toDouble() ?? 0.0,
      modelId: json['model_id']?.toString() ?? 'unknown',
      quantTier: json['quant_tier']?.toString() ?? 'unknown',
      backend: json['backend']?.toString() ?? 'cpu',
      memoryRssDeltaBytes: (json['memory_rss_delta_bytes'] as num?)?.toInt() ?? 0,
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'].toString()) ?? DateTime.now()
          : DateTime.now(),
      metadata: (json['metadata'] as Map<String, dynamic>?) ?? {},
    );
  }
}

/// Represents a sanitized crash or unhandled error telemetry record.
@immutable
class CrashTelemetryReport {
  final String errorType;
  final String sanitizedMessage;
  final String sanitizedStackTrace;
  final bool isFatal;
  final String platform;
  final DateTime timestamp;

  const CrashTelemetryReport({
    required this.errorType,
    required this.sanitizedMessage,
    required this.sanitizedStackTrace,
    required this.isFatal,
    required this.platform,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() {
    return {
      'type': 'crash_report',
      'error_type': errorType,
      'message': sanitizedMessage,
      'stack_trace': sanitizedStackTrace,
      'is_fatal': isFatal,
      'platform': platform,
      'timestamp': timestamp.toUtc().toIso8601String(),
    };
  }
}

/// Service managing privacy-preserving performance profiling and crash telemetry.
class TelemetryService {
  static final TelemetryService instance = TelemetryService._internal();

  TelemetryService._internal();
  factory TelemetryService({Directory? baseDirectory}) {
    if (baseDirectory != null) {
      return TelemetryService._withDirectory(baseDirectory);
    }
    return instance;
  }

  TelemetryService._withDirectory(Directory baseDirectory) : _customDirectory = baseDirectory;

  Directory? _customDirectory;
  final List<Map<String, dynamic>> _inMemoryRingBuffer = [];
  static const int _maxRingBufferSize = 100;
  static const String _logFileName = 'telemetry_events.jsonl';
  String? _sentryDsn;
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;
  List<Map<String, dynamic>> get recentEvents => List.unmodifiable(_inMemoryRingBuffer);

  /// Initializes the telemetry service with optional Sentry DSN and sets up directories.
  Future<void> initialize({String? sentryDsn, Directory? baseDirectory}) async {
    _sentryDsn = sentryDsn;
    if (baseDirectory != null) {
      _customDirectory = baseDirectory;
    }
    _isInitialized = true;
    debugPrint('TelemetryService: Initialized (Sentry: ${_sentryDsn != null ? "CONFIGURED" : "OFFLINE_LOCAL"})');
  }

  /// Configures global Flutter framework and Dart isolate error boundaries.
  void setupGlobalErrorHandlers() {
    FlutterError.onError = (FlutterErrorDetails details) {
      recordCrash(
        error: details.exception,
        stackTrace: details.stack,
        isFatal: false,
        errorType: 'FlutterError.${details.library ?? "framework"}',
      );
      // Also log to console in debug mode
      if (kDebugMode) {
        FlutterError.dumpErrorToConsole(details);
      }
    };

    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      recordCrash(
        error: error,
        stackTrace: stack,
        isFatal: true,
        errorType: 'PlatformDispatcher.UncaughtAsync',
      );
      return true; // Handled — prevent process termination
    };
  }

  /// Records an on-device VLM inference performance metric.
  Future<InferenceTelemetryMetric> recordInferencePerformance({
    required int inferenceDurationMs,
    required int preprocessingMs,
    required int tokenCount,
    required String modelId,
    required String quantTier,
    String backend = 'cpu',
    int memoryRssDeltaBytes = 0,
    Map<String, dynamic>? customMetadata,
  }) async {
    final tps = inferenceDurationMs > 0
        ? (tokenCount * 1000.0) / inferenceDurationMs
        : 0.0;

    // Sanitize any metadata to ensure zero sensitive data leaks
    final sanitizedMeta = <String, dynamic>{};
    if (customMetadata != null) {
      customMetadata.forEach((key, value) {
        if (value is String) {
          sanitizedMeta[key] = sanitizeTelemetryString(value);
        } else if (value is num || value is bool) {
          sanitizedMeta[key] = value;
        }
      });
    }

    final metric = InferenceTelemetryMetric(
      inferenceDurationMs: inferenceDurationMs,
      preprocessingMs: preprocessingMs,
      tokenCount: tokenCount,
      tokensPerSecond: tps,
      modelId: sanitizeTelemetryString(modelId),
      quantTier: quantTier,
      backend: backend,
      memoryRssDeltaBytes: memoryRssDeltaBytes,
      timestamp: DateTime.now().toUtc(),
      metadata: sanitizedMeta,
    );

    _appendEvent(metric.toJson());
    await _persistEventToFile(metric.toJson());

    debugPrint(
      'TelemetryService [VLM_PERF]: ${metric.tokensPerSecond.toStringAsFixed(1)} tokens/sec | '
      'Duration: ${metric.inferenceDurationMs}ms (Pre: ${metric.preprocessingMs}ms) | '
      'Model: ${metric.modelId} ($quantTier, $backend)',
    );

    return metric;
  }

  /// Records an unhandled error or crash with strict PII scrubbing.
  Future<CrashTelemetryReport> recordCrash({
    required Object error,
    StackTrace? stackTrace,
    bool isFatal = false,
    String? errorType,
  }) async {
    final resolvedErrorType = errorType ?? error.runtimeType.toString();
    final sanitizedMessage = sanitizeTelemetryString(error.toString());
    final sanitizedStack = sanitizeStackTrace(stackTrace);

    final report = CrashTelemetryReport(
      errorType: resolvedErrorType,
      sanitizedMessage: sanitizedMessage,
      sanitizedStackTrace: sanitizedStack,
      isFatal: isFatal,
      platform: _getPlatformName(),
      timestamp: DateTime.now().toUtc(),
    );

    _appendEvent(report.toJson());
    await _persistEventToFile(report.toJson());

    debugPrint(
      'TelemetryService [CRASH_LOG]: [$resolvedErrorType] $sanitizedMessage (Fatal: $isFatal)',
    );

    return report;
  }

  /// Appends an event to the circular in-memory buffer.
  void _appendEvent(Map<String, dynamic> event) {
    if (_inMemoryRingBuffer.length >= _maxRingBufferSize) {
      _inMemoryRingBuffer.removeAt(0);
    }
    _inMemoryRingBuffer.add(event);
  }

  /// Persists event to the local JSONL log file.
  Future<void> _persistEventToFile(Map<String, dynamic> eventJson) async {
    if (kIsWeb) return;
    try {
      final file = await _getLogFile();
      if (file == null) return;

      final sink = file.openWrite(mode: FileMode.append);
      sink.writeln(jsonEncode(eventJson));
      await sink.flush();
      await sink.close();
    } catch (e) {
      debugPrint('TelemetryService: Failed to write event to disk: $e');
    }
  }

  Future<File?> _getLogFile() async {
    try {
      final dir = _customDirectory ?? await getApplicationDocumentsDirectory();
      final logsDir = Directory('${dir.path}/logs');
      if (!await logsDir.exists()) {
        await logsDir.create(recursive: true);
      }
      return File('${logsDir.path}/$_logFileName');
    } catch (_) {
      return null;
    }
  }

  /// Returns total count of logged telemetry records on disk.
  Future<int> getDiskEventCount() async {
    final file = await _getLogFile();
    if (file == null || !await file.exists()) return _inMemoryRingBuffer.length;
    try {
      final lines = await file.readAsLines();
      return lines.where((l) => l.trim().isNotEmpty).length;
    } catch (_) {
      return _inMemoryRingBuffer.length;
    }
  }

  /// Clears in-memory and disk telemetry logs.
  Future<void> clearLogs() async {
    _inMemoryRingBuffer.clear();
    final file = await _getLogFile();
    if (file != null && await file.exists()) {
      try {
        await file.delete();
      } catch (_) {}
    }
  }

  /// Sanitizes any string payload to guarantee zero PII and zero local user paths.
  static String sanitizeTelemetryString(String input) {
    if (input.trim().isEmpty) return '';

    // 1. Scrub emails, phone numbers, credit cards, IBANs, and street addresses
    String cleaned = PiiScrubberService.sanitizeText(input);

    // 2. Scrub user profile paths on Windows (C:\Users\<username>\...)
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'[a-zA-Z]:\\Users\\[^\\]+', caseSensitive: false),
      (_) => 'C:\\Users\\[USER]',
    );

    // 3. Scrub user profile paths on POSIX/macOS/Linux (/Users/<username> or /home/<username>)
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'\/(?:Users|home)\/[^\/]+', caseSensitive: false),
      (_) => '/Users/[USER]',
    );

    return cleaned;
  }

  /// Sanitizes a stack trace removing user-specific path prefixes.
  static String sanitizeStackTrace(StackTrace? stackTrace) {
    if (stackTrace == null) return '';
    return sanitizeTelemetryString(stackTrace.toString());
  }

  static String _getPlatformName() {
    if (kIsWeb) return 'web';
    if (Platform.isWindows) return 'windows';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }
}

/// Global Riverpod provider for [TelemetryService].
final telemetryServiceProvider = Provider<TelemetryService>((ref) {
  return TelemetryService.instance;
});
