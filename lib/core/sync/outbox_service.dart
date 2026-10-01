import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
import 'models/sync_outbox_item.dart';

/// Service managing the local outbox queue for offline mutations.
class OutboxService {
  final Box<SyncOutboxItem> outboxBox;
  final _uuid = const Uuid();
  int _lastTimestampMicros = 0;

  OutboxService(this.outboxBox);

  DateTime _nextMonotonicTimestamp() {
    final nowMicros = DateTime.now().microsecondsSinceEpoch;
    if (nowMicros > _lastTimestampMicros) {
      _lastTimestampMicros = nowMicros;
    } else {
      _lastTimestampMicros++;
    }
    return DateTime.fromMicrosecondsSinceEpoch(_lastTimestampMicros, isUtc: true);
  }

  /// Enqueues a local mutation to be synchronized to Supabase.
  Future<SyncOutboxItem> enqueue({
    required String entityType,
    required String entityId,
    required String mutationType,
    required Map<String, dynamic> payload,
  }) async {
    final item = SyncOutboxItem(
      id: _uuid.v4(),
      entityType: entityType,
      entityId: entityId,
      mutationType: mutationType,
      payload: payload,
      timestamp: _nextMonotonicTimestamp(),
      status: 'pending',
      retryCount: 0,
    );

    await outboxBox.put(item.id, item);
    debugPrint('OutboxService: Enqueued mutation ${item.mutationType} for ${item.entityType} ($entityId)');
    return item;
  }

  /// Returns all pending mutations sorted by creation timestamp (FIFO).
  /// When [respectBackoff] is true, failed items whose exponential backoff window
  /// has not yet elapsed are omitted.
  List<SyncOutboxItem> getPendingMutations({bool respectBackoff = false}) {
    final now = DateTime.now();
    final list = outboxBox.values.where((item) {
      if (item.status == 'pending') return true;
      if (item.status == 'failed') {
        return !respectBackoff || !isBackingOff(item, now);
      }
      return false;
    }).toList();
    list.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return list;
  }

  /// Whether a failed [item] is still inside its exponential backoff window
  /// (2s, 4s, 8s, 16s, 32s, 64s after the last attempt) at [now].
  bool isBackingOff(SyncOutboxItem item, DateTime now) {
    if (item.status != 'failed' || item.lastAttemptAt == null) return false;
    final backoffSeconds = 1 << item.retryCount.clamp(0, 6);
    final nextRetry = item.lastAttemptAt!.add(Duration(seconds: backoffSeconds));
    return !now.isAfter(nextRetry);
  }

  /// Mutations that were dead-lettered and are no longer retried automatically.
  List<SyncOutboxItem> getPermanentlyFailed() {
    return outboxBox.values.where((item) => item.status == 'permanently_failed').toList();
  }

  /// Marks a mutation as successfully synchronized and removes it from the queue.
  Future<void> markCompleted(String id) async {
    await outboxBox.delete(id);
    debugPrint('OutboxService: Mutation $id synced and removed from outbox.');
  }

  /// Records a failed sync attempt and updates retry count/backoff.
  Future<void> markFailed(String id, String error, {bool permanent = false}) async {
    final item = outboxBox.get(id);
    if (item != null) {
      item.retryCount += 1;
      item.lastAttemptAt = DateTime.now();
      item.errorMessage = error;
      item.status = permanent || item.retryCount >= 5 ? 'permanently_failed' : 'failed';
      await item.save();
      debugPrint('OutboxService: Mutation $id failed (attempt ${item.retryCount}, status: ${item.status}): $error');
    }
  }

  /// Resets all permanently failed items back to pending for manual retry.
  Future<void> retryPermanentlyFailed() async {
    for (final item in outboxBox.values) {
      if (item.status == 'permanently_failed') {
        item.status = 'pending';
        item.retryCount = 0;
        item.errorMessage = null;
        await item.save();
      }
    }
  }

  /// Clears all items in the outbox.
  Future<void> clearAll() async {
    await outboxBox.clear();
  }
}
