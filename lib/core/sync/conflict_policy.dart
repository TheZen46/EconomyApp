/// Conflict rule applied whenever a remote row is merged into a local store.
///
/// Versions take precedence: a higher [remoteVersion] wins and a lower one
/// loses. With equal versions the later timestamp wins; a missing
/// [localUpdatedAt] counts as older, and a missing [remoteUpdatedAt] never wins.
///
/// Shared by `SyncManager` (delta pull) and `SyncEngine` (full replication) so
/// that both resolve the same row identically.
bool shouldRemoteOverwrite({
  required DateTime? localUpdatedAt,
  required int localVersion,
  required DateTime? remoteUpdatedAt,
  required int remoteVersion,
}) {
  if (remoteVersion > localVersion) return true;
  if (remoteVersion < localVersion) return false;
  if (localUpdatedAt == null) return true;
  if (remoteUpdatedAt == null) return false;
  return remoteUpdatedAt.isAfter(localUpdatedAt);
}
