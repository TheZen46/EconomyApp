import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'crdt_sync_engine.dart';
import '../providers/storage_providers.dart';

/// Provider for the CRDT storage engine.
final crdtStorageProvider = Provider<CrdtStorage?>((ref) {
  try {
    final settingsBox = ref.watch(settingsBoxProvider);
    return HiveCrdtStorage(settingsBox);
  } catch (_) {
    return null;
  }
});

/// Provider for the device/node identifier used by CRDT replication.
final crdtNodeIdProvider = Provider<String>((ref) {
  try {
    final settingsBox = ref.watch(settingsBoxProvider);
    final existing = settingsBox.get('crdt_node_id') as String?;
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final generated = 'node_${const Uuid().v4().substring(0, 8)}';
    settingsBox.put('crdt_node_id', generated);
    return generated;
  } catch (_) {
    return 'node_ephemeral_${const Uuid().v4().substring(0, 8)}';
  }
});

/// Authoritative provider for [CrdtSyncEngine].
final crdtSyncEngineProvider = Provider<CrdtSyncEngine>((ref) {
  final nodeId = ref.watch(crdtNodeIdProvider);
  final storage = ref.watch(crdtStorageProvider);
  return CrdtSyncEngine(nodeId: nodeId, storage: storage);
});
