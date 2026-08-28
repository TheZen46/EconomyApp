import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
import 'models/sync_outbox_item.dart';

/// Service managing the local outbox queue for offline mutations.
class OutboxService {
  final Box<SyncOutboxItem> outboxBox;
  final _uuid = const Uuid();

  OutboxService(this.outboxBox);

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
      timestamp: DateTime.now(),
      status: 'pending',
      retryCount: 0,
    );

    await outboxBox.put(item.id, item);
    debugPrint('OutboxService: Enqueued mutation ${item.mutationType} for ${item.entityType} ($entityId)');
    return item;
  }

  /// Returns all pending mutations sorted by creation timestamp (FIFO).
  List<SyncOutboxItem> getPendingMutations() {
    final list = outboxBox.values
        .where((item) => item.status == 'pending' || item.status == 'failed')
        .toList();
    list.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return list;
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

  /// Clears all items in the outbox.
  Future<void> clearAll() async {
    await outboxBox.clear();
  }
}
