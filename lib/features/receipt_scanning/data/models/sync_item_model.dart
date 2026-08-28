import 'dart:math' as math;
import 'package:hive/hive.dart';

part 'sync_item_model.g.dart';

@HiveType(typeId: 12)
enum SyncStatus {
  @HiveField(0)
  pending,

  @HiveField(1)
  inProgress,

  @HiveField(2)
  success,

  @HiveField(3)
  permanentlyFailed,
}

@HiveType(typeId: 6)
class SyncItemModel {
  @HiveField(0)
  final String receiptId;

  @HiveField(1)
  final String imagePath;

  @HiveField(2)
  final DateTime addedAt;

  /// Number of failed upload attempts. Starts at 0.
  /// When this reaches [maxRetries] (5), the item is marked permanentlyFailed.
  @HiveField(3)
  final int retryCount;

  /// Timestamp of the last failed attempt.
  @HiveField(4)
  final DateTime? lastAttemptAt;

  /// Earliest timestamp at which the next retry attempt is permitted.
  @HiveField(5)
  final DateTime? nextRetryTimestamp;

  /// Current sync lifecycle state.
  @HiveField(6)
  final SyncStatus status;

  /// Optional error message from the last failure.
  @HiveField(7)
  final String? errorMessage;

  SyncItemModel({
    required this.receiptId,
    required this.imagePath,
    required this.addedAt,
    this.retryCount = 0,
    this.lastAttemptAt,
    this.nextRetryTimestamp,
    this.status = SyncStatus.pending,
    this.errorMessage,
  });

  /// Maximum number of retries before the item transitions to permanentlyFailed.
  static const int maxRetries = 5;

  /// Base delay for exponential backoff in seconds (2s).
  static const int baseDelaySeconds = 2;

  /// Maximum delay ceiling in seconds (32s).
  static const int maxDelaySeconds = 32;

  /// Returns true if this item has reached the maximum retry threshold.
  bool get isDeadLettered => retryCount >= maxRetries || status == SyncStatus.permanentlyFailed;

  /// Returns true if enough time has passed to permit the next retry attempt.
  bool get isReadyForRetry {
    if (status == SyncStatus.permanentlyFailed) return false;
    if (nextRetryTimestamp == null) return true;
    final now = DateTime.now();
    return now.isAfter(nextRetryTimestamp!) || now.isAtSameMomentAs(nextRetryTimestamp!);
  }

  /// Calculates exponential backoff duration: min(maxDelay, baseDelay * 2^(retryCount)) + jitter
  static Duration computeBackoff(int currentRetryCount, {int jitterMs = 0}) {
    final exponent = currentRetryCount.clamp(0, 30);
    final backoffSeconds = baseDelaySeconds * (1 << exponent);
    final clamped = math.min(backoffSeconds, maxDelaySeconds);
    return Duration(seconds: clamped) + Duration(milliseconds: jitterMs);
  }

  /// Returns an updated copy after a failed sync attempt.
  SyncItemModel withFailedAttempt({String? error, int jitterMs = 0}) {
    final newRetryCount = retryCount + 1;
    final now = DateTime.now();

    if (newRetryCount >= maxRetries) {
      return SyncItemModel(
        receiptId: receiptId,
        imagePath: imagePath,
        addedAt: addedAt,
        retryCount: newRetryCount,
        lastAttemptAt: now,
        nextRetryTimestamp: null,
        status: SyncStatus.permanentlyFailed,
        errorMessage: error ?? errorMessage,
      );
    }

    final backoff = computeBackoff(retryCount, jitterMs: jitterMs);
    return SyncItemModel(
      receiptId: receiptId,
      imagePath: imagePath,
      addedAt: addedAt,
      retryCount: newRetryCount,
      lastAttemptAt: now,
      nextRetryTimestamp: now.add(backoff),
      status: SyncStatus.pending,
      errorMessage: error ?? errorMessage,
    );
  }

  /// Returns a reset copy for manual retry by the user.
  SyncItemModel forManualRetry() {
    return SyncItemModel(
      receiptId: receiptId,
      imagePath: imagePath,
      addedAt: addedAt,
      retryCount: 0,
      lastAttemptAt: null,
      nextRetryTimestamp: null,
      status: SyncStatus.pending,
      errorMessage: null,
    );
  }

  SyncItemModel copyWith({
    String? receiptId,
    String? imagePath,
    DateTime? addedAt,
    int? retryCount,
    DateTime? lastAttemptAt,
    DateTime? nextRetryTimestamp,
    SyncStatus? status,
    String? errorMessage,
  }) {
    return SyncItemModel(
      receiptId: receiptId ?? this.receiptId,
      imagePath: imagePath ?? this.imagePath,
      addedAt: addedAt ?? this.addedAt,
      retryCount: retryCount ?? this.retryCount,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      nextRetryTimestamp: nextRetryTimestamp ?? this.nextRetryTimestamp,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
