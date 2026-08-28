import 'package:flutter/foundation.dart';

/// Lifecycle stages of the cross-device sync engine.
enum SyncStage {
  idle,
  authenticating,
  fetchingManifest,
  downloadingDeltas,
  rehydratingStorage,
  verifyingParity,
  completed,
  interruptedRetrying,
  failed,
}

/// Immutable state capturing real-time progress, telemetry, and error states of the sync engine.
@immutable
class SyncProgressState {
  final SyncStage stage;
  final double progress; // 0.0 to 1.0
  final String message;
  final int itemsCompleted;
  final int totalItems;
  final int bytesTransferred;
  final int totalBytes;
  final double transferSpeedBytesPerSec;
  final bool isInitialSync;
  final String? errorMessage;
  final int retryAttempt;
  final int maxRetryAttempts;
  final bool canContinueOffline;

  const SyncProgressState({
    this.stage = SyncStage.idle,
    this.progress = 0.0,
    this.message = 'Initializing synchronization...',
    this.itemsCompleted = 0,
    this.totalItems = 0,
    this.bytesTransferred = 0,
    this.totalBytes = 0,
    this.transferSpeedBytesPerSec = 0.0,
    this.isInitialSync = true,
    this.errorMessage,
    this.retryAttempt = 0,
    this.maxRetryAttempts = 5,
    this.canContinueOffline = true,
  });

  SyncProgressState copyWith({
    SyncStage? stage,
    double? progress,
    String? message,
    int? itemsCompleted,
    int? totalItems,
    int? bytesTransferred,
    int? totalBytes,
    double? transferSpeedBytesPerSec,
    bool? isInitialSync,
    String? errorMessage,
    int? retryAttempt,
    int? maxRetryAttempts,
    bool? canContinueOffline,
  }) {
    return SyncProgressState(
      stage: stage ?? this.stage,
      progress: progress ?? this.progress,
      message: message ?? this.message,
      itemsCompleted: itemsCompleted ?? this.itemsCompleted,
      totalItems: totalItems ?? this.totalItems,
      bytesTransferred: bytesTransferred ?? this.bytesTransferred,
      totalBytes: totalBytes ?? this.totalBytes,
      transferSpeedBytesPerSec: transferSpeedBytesPerSec ?? this.transferSpeedBytesPerSec,
      isInitialSync: isInitialSync ?? this.isInitialSync,
      errorMessage: errorMessage,
      retryAttempt: retryAttempt ?? this.retryAttempt,
      maxRetryAttempts: maxRetryAttempts ?? this.maxRetryAttempts,
      canContinueOffline: canContinueOffline ?? this.canContinueOffline,
    );
  }

  bool get isCompleted => stage == SyncStage.completed;
  bool get isFailed => stage == SyncStage.failed;
  bool get isRetrying => stage == SyncStage.interruptedRetrying;
  bool get isRunning =>
      stage != SyncStage.idle &&
      stage != SyncStage.completed &&
      stage != SyncStage.failed;

  /// Formats transfer speed as human-readable string (e.g. "3.2 MB/s", "450 KB/s").
  String get formattedSpeed {
    if (transferSpeedBytesPerSec <= 0) return '0.0 KB/s';
    if (transferSpeedBytesPerSec >= 1024 * 1024) {
      return '${(transferSpeedBytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    }
    return '${(transferSpeedBytesPerSec / 1024).toStringAsFixed(1)} KB/s';
  }

  /// Formats total bytes transferred as human-readable string (e.g. "12.4 MB").
  String get formattedBytes {
    if (bytesTransferred >= 1024 * 1024) {
      return '${(bytesTransferred / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytesTransferred / 1024).toStringAsFixed(1)} KB';
  }

  /// Calculates estimated time remaining in seconds.
  double get estimatedSecondsRemaining {
    if (transferSpeedBytesPerSec <= 0 || totalBytes <= bytesTransferred) return 0.0;
    final remainingBytes = totalBytes - bytesTransferred;
    return remainingBytes / transferSpeedBytesPerSec;
  }

  /// Formats estimated time remaining (e.g. "4.2s", "1m 12s").
  String get formattedEta {
    final secs = estimatedSecondsRemaining;
    if (secs <= 0.1) return 'Finishing...';
    if (secs < 60) {
      return '${secs.toStringAsFixed(1)}s';
    }
    final mins = (secs / 60).floor();
    final remainingSecs = (secs % 60).floor();
    return '${mins}m ${remainingSecs}s';
  }
}
