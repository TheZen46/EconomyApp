/// Entity-agnostic contract for data entities participating in offline-first
/// synchronization, conflict resolution, and outbox mutations.
abstract class SyncableEntity {
  /// Unique identifier of the entity.
  String get id;

  /// UTC timestamp of the last local or remote mutation.
  DateTime? get updatedAt;

  /// Monotonically increasing local/remote mutation sequence number.
  int get version;

  /// Tombstone deletion timestamp if soft-deleted, null if active.
  DateTime? get deletedAt;

  /// Tenant user ID owning this entity.
  String? get userId;
}
