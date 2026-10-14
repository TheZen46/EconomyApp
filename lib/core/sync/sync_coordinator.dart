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

  /// Executes [action] exclusively under the shared synchronization mutex.
  Future<T> synchronized<T>(Future<T> Function() action) {
    return _lock.synchronized(action);
  }

  /// Whether a synchronization operation is currently active.
  bool get isLocked => _lock.locked;
}

/// Provider for the shared [SyncCoordinator] instance.
final syncCoordinatorProvider = Provider<SyncCoordinator>((ref) {
  return SyncCoordinator.instance;
});
