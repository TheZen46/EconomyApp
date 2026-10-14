import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:synchronized/synchronized.dart';

/// Central synchronization coordinator providing a single shared mutex lock
/// across all replication, delta pulling, outbox flushing, and attachment uploads.
///
/// Ensures concurrent sync processes (SyncManager, SyncService, SyncEngine) never
/// interleave database writes or race on local Hive stores.
class SyncCoordinator {
  /// Global singleton coordinator instance.
  static final SyncCoordinator instance = SyncCoordinator._();
  SyncCoordinator._();

  final Lock _lock = Lock();
  final List<void Function()> _listeners = [];

  /// Executes [action] exclusively under the shared synchronization mutex.
  Future<T> synchronized<T>(Future<T> Function() action) {
    return _lock.synchronized(action);
  }

  /// Whether a synchronization operation is currently active.
  bool get isLocked => _lock.locked;

  /// Registers a callback to be notified when a synchronization pass completes.
  void addSyncCompletedListener(void Function() listener) {
    _listeners.add(listener);
  }

  /// Removes a previously registered synchronization pass listener.
  void removeSyncCompletedListener(void Function() listener) {
    _listeners.remove(listener);
  }

  Future<void> Function()? _attachmentFlusher;

  /// Registers a delegate to flush pending attachments during synchronization cycles.
  void registerAttachmentFlusher(Future<void> Function() flusher) {
    _attachmentFlusher = flusher;
  }

  /// Unregisters the current attachment flusher delegate.
  void unregisterAttachmentFlusher() {
    _attachmentFlusher = null;
  }

  /// Flushes pending attachments if a flusher delegate is registered.
  Future<void> flushAttachments() async {
    final flusher = _attachmentFlusher;
    if (flusher != null) {
      await flusher();
    }
  }

  /// Notifies all registered listeners that a synchronization cycle completed.
  void notifySyncCompleted() {
    for (final listener in List.of(_listeners)) {
      try {
        listener();
      } catch (_) {}
    }
  }
}

/// Provider for the shared [SyncCoordinator] instance.
final syncCoordinatorProvider = Provider<SyncCoordinator>((ref) {
  return SyncCoordinator.instance;
});
