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

  TelemetryService._internal() : maxLogBytes = defaultMaxLogBytes;
  factory TelemetryService({Directory? baseDirectory, int maxLogBytes = defaultMaxLogBytes}) {
    if (baseDirectory != null) {
      return TelemetryService._withDirectory(baseDirectory, maxLogBytes);
    }
    return instance;
  }

  TelemetryService._withDirectory(Directory baseDirectory, this.maxLogBytes) : _customDirectory = baseDirectory;

  /// Size at which the log file is rotated. At most two generations are kept,
  /// so the log never occupies more than twice this size on disk.
  static const int defaultMaxLogBytes = 512 * 1024;

  /// Age after which the rotated generation is deleted.
  static const Duration maxLogAge = Duration(days: 30);

  final int maxLogBytes;
  Directory? _customDirectory;
  final List<Map<String, dynamic>> _inMemoryRingBuffer = [];
  static const int _maxRingBufferSize = 100;
  static const String _logFileName = 'telemetry_events.jsonl';
  bool _isInitialized = false;

  /// Serializes appends and rotation.
  Future<void> _pendingWrite = Future.value();

  bool get isInitialized => _isInitialized;
  List<Map<String, dynamic>> get recentEvents => List.unmodifiable(_inMemoryRingBuffer);

  /// Initializes the telemetry service. Events are kept on this device only;
  /// nothing is transmitted.
  Future<void> initialize({Directory? baseDirectory}) async {
    if (baseDirectory != null) {
      _customDirectory = baseDirectory;
    }
    _isInitialized = true;
    debugPrint('TelemetryService: Initialized (local log only)');
  }

  /// Configures global Flutter framework and Dart isolate error boundaries.
  ///
  /// Errors are recorded and then passed on to the default handling: they are
  /// not marked as handled, because the application did not handle them.
  void setupGlobalErrorHandlers() {
    FlutterError.onError = (FlutterErrorDetails details) {
      unawaited(recordCrash(
        error: details.exception,
        stackTrace: details.stack,
        isFatal: false,
        errorType: 'FlutterError.${details.library ?? "framework"}',
      ));
      FlutterError.presentError(details);
    };

    PlatformDispatcher.instance.onError = handleUncaughtError;
  }

  /// [PlatformDispatcher.onError] callback. Records the error and returns
  /// false, so that the engine reports it as unhandled instead of the
  /// application continuing as if it had been dealt with.
  bool handleUncaughtError(Object error, StackTrace stack) {
    unawaited(recordCrash(
      error: error,
      stackTrace: stack,
      // The process keeps running after an uncaught asynchronous error.
      isFatal: false,
      errorType: 'PlatformDispatcher.UncaughtAsync',
    ));
    return false;
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
  Future<void> _persistEventToFile(Map<String, dynamic> eventJson) {
    if (kIsWeb) return Future.value();
    return _pendingWrite = _pendingWrite.then((_) async {
      try {
        final file = await _getLogFile();
        if (file == null) return;

        await _rotateIfNeeded(file);
        final sink = file.openWrite(mode: FileMode.append);
        sink.writeln(jsonEncode(eventJson));
        await sink.flush();
        await sink.close();
      } catch (e) {
        debugPrint('TelemetryService: Failed to write event to disk: $e');
      }
    });
  }

  File _rotatedFile(File file) => File('${file.path}.1');

  /// Moves the log to its single rotated generation once it reaches
  /// [maxLogBytes], and deletes that generation once it is older than
  /// [maxLogAge].
  Future<void> _rotateIfNeeded(File file) async {
    final rotated = _rotatedFile(file);
    if (await rotated.exists() &&
        DateTime.now().difference(await rotated.lastModified()) > maxLogAge) {
      await rotated.delete();
    }
    if (await file.exists() && await file.length() >= maxLogBytes) {
      if (await rotated.exists()) await rotated.delete();
      await file.rename(rotated.path);
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

  /// Returns total count of logged telemetry records on disk, across the
  /// current and the rotated log file.
  Future<int> getDiskEventCount() async {
    await _pendingWrite;
    final file = await _getLogFile();
    if (file == null) return _inMemoryRingBuffer.length;
    try {
      var count = 0;
      for (final f in [file, _rotatedFile(file)]) {
        if (!await f.exists()) continue;
        final lines = await f.readAsLines();
        count += lines.where((l) => l.trim().isNotEmpty).length;
      }
      return count;
    } catch (_) {
      return _inMemoryRingBuffer.length;
    }
  }

  /// Clears in-memory and disk telemetry logs.
  Future<void> clearLogs() async {
    _inMemoryRingBuffer.clear();
    await _pendingWrite;
    final file = await _getLogFile();
    if (file == null) return;
    for (final f in [file, _rotatedFile(file)]) {
      if (await f.exists()) {
        try {
          await f.delete();
        } catch (_) {}
      }
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
