import 'dart:convert';
import 'package:hive/hive.dart';
import 'hlc.dart';
import 'lww_register.dart';
import 'receipt_crdt.dart';
import 'vector_clock.dart';
import '../../features/receipt_scanning/data/models/receipt_model.dart';

/// Network sync delta payload transmitted between offline/online peers.
class SyncDeltaPayload {
  final String senderNodeId;
  final int generatedAtMillis;
  final VectorClock vectorClock;
  final List<ReceiptCrdt> modifiedReceipts;

  const SyncDeltaPayload({
    required this.senderNodeId,
    required this.generatedAtMillis,
    required this.vectorClock,
    required this.modifiedReceipts,
  });

  /// Computes the maximum HLC timestamp across the payload envelope and all entity registers.
  /// Advancing the local HLC with this value prevents HLC clock regression.
  Hlc get maxObservedHlc {
    Hlc max = Hlc(millis: generatedAtMillis, counter: 0, nodeId: senderNodeId);
    for (final receipt in modifiedReceipts) {
      for (final hlc in receipt.allHlcs) {
        if (hlc.isAfter(max)) {
          max = hlc;
        }
      }
    }
    return max;
  }

  Map<String, dynamic> toJson() => {
        'senderNodeId': senderNodeId,
        'generatedAtMillis': generatedAtMillis,
        'vectorClock': vectorClock.toJson(),
        'modifiedReceipts': modifiedReceipts.map((r) => r.toJson()).toList(),
      };

  factory SyncDeltaPayload.fromJson(Map<String, dynamic> json) => SyncDeltaPayload(
        senderNodeId: json['senderNodeId'] as String,
        generatedAtMillis: json['generatedAtMillis'] as int,
        vectorClock: VectorClock.fromJson(json['vectorClock'] as Map<String, dynamic>),
        modifiedReceipts: (json['modifiedReceipts'] as List)
            .map((r) => ReceiptCrdt.fromJson(r as Map<String, dynamic>))
            .toList(),
      );
}

/// Snapshot of persisted CRDT engine state.
class CrdtPersistedState {
  final Hlc hlc;
  final VectorClock vectorClock;
  final Map<String, ReceiptCrdt> store;
  final Map<String, VectorClock> deletionClocks;
  final Map<String, VectorClock> peerClocks;
  final Set<String> knownPeers;

  const CrdtPersistedState({
    required this.hlc,
    required this.vectorClock,
    required this.store,
    required this.deletionClocks,
    required this.peerClocks,
    required this.knownPeers,
  });
}

/// Persistent storage contract for CRDT state across application restarts.
abstract class CrdtStorage {
  Future<void> persist({
    required String nodeId,
    required Hlc hlc,
    required VectorClock vectorClock,
    required Map<String, ReceiptCrdt> store,
    required Map<String, VectorClock> deletionClocks,
    required Map<String, VectorClock> peerClocks,
    required Set<String> knownPeers,
  });

  Future<CrdtPersistedState?> load(String nodeId);
}

/// In-memory implementation of [CrdtStorage] primarily for unit testing.
class InMemoryCrdtStorage implements CrdtStorage {
  final Map<String, CrdtPersistedState> _states = {};

  @override
  Future<void> persist({
    required String nodeId,
    required Hlc hlc,
    required VectorClock vectorClock,
    required Map<String, ReceiptCrdt> store,
    required Map<String, VectorClock> deletionClocks,
    required Map<String, VectorClock> peerClocks,
    required Set<String> knownPeers,
  }) async {
    _states[nodeId] = CrdtPersistedState(
      hlc: hlc,
      vectorClock: vectorClock,
      store: Map.from(store),
      deletionClocks: Map.from(deletionClocks),
      peerClocks: Map.from(peerClocks),
      knownPeers: Set.from(knownPeers),
    );
  }

  @override
  Future<CrdtPersistedState?> load(String nodeId) async {
    return _states[nodeId];
  }
}

/// Hive-backed persistent storage for [CrdtSyncEngine].
class HiveCrdtStorage implements CrdtStorage {
  final Box<dynamic> box;
  static const String keyPrefix = 'crdt_node_';

  const HiveCrdtStorage(this.box);

  @override
  Future<void> persist({
    required String nodeId,
    required Hlc hlc,
    required VectorClock vectorClock,
    required Map<String, ReceiptCrdt> store,
    required Map<String, VectorClock> deletionClocks,
    required Map<String, VectorClock> peerClocks,
    required Set<String> knownPeers,
  }) async {
    final payload = {
      'nodeId': nodeId,
      'hlc': hlc.toJson(),
      'vectorClock': vectorClock.toJson(),
      'store': store.map((k, v) => MapEntry(k, v.toJson())),
      'deletionClocks': deletionClocks.map((k, v) => MapEntry(k, v.toJson())),
      'peerClocks': peerClocks.map((k, v) => MapEntry(k, v.toJson())),
      'knownPeers': knownPeers.toList(),
    };
    await box.put('$keyPrefix$nodeId', jsonEncode(payload));
  }

  @override
  Future<CrdtPersistedState?> load(String nodeId) async {
    final raw = box.get('$keyPrefix$nodeId');
    if (raw == null) return null;
    final Map<String, dynamic> data =
        raw is String ? jsonDecode(raw) : Map<String, dynamic>.from(raw as Map);
    return CrdtPersistedState(
      hlc: Hlc.fromJson(data['hlc'] as Map<String, dynamic>),
      vectorClock: VectorClock.fromJson(data['vectorClock'] as Map<String, dynamic>),
      store: (data['store'] as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, ReceiptCrdt.fromJson(v as Map<String, dynamic>)),
      ),
      deletionClocks: (data['deletionClocks'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, VectorClock.fromJson(v as Map<String, dynamic>)),
          ) ??
          {},
      peerClocks: (data['peerClocks'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, VectorClock.fromJson(v as Map<String, dynamic>)),
          ) ??
          {},
      knownPeers: (data['knownPeers'] as List<dynamic>?)?.cast<String>().toSet() ?? {},
    );
  }
}

/// State-based CRDT Synchronization Engine for multi-tenant offline-first replication.
///
/// Ensures Strong Eventual Consistency (SEC):
/// - Replicas can mutate data independently offline.
/// - Concurrent edits on different fields of the same line item merge without data loss.
/// - Conflicts on the same field resolve deterministically via total-ordered HLC timestamps.
/// - Join operator is commutative, associative, and idempotent.
class CrdtSyncEngine {
  final String nodeId;
  final CrdtStorage? storage;
  Hlc _hlc;
  VectorClock _vectorClock;
  final Map<String, ReceiptCrdt> _store = {};
  final Map<String, VectorClock> _deletionClocks = {};
  final Map<String, VectorClock> _peerClocks = {};
  final Set<String> _knownPeers = {};

  CrdtSyncEngine({
    required this.nodeId,
    Hlc? initialHlc,
    VectorClock? initialVectorClock,
    this.storage,
    Map<String, ReceiptCrdt>? initialStore,
    Map<String, VectorClock>? initialDeletionClocks,
    Map<String, VectorClock>? initialPeerClocks,
    Set<String>? initialKnownPeers,
  })  : _hlc = initialHlc ?? Hlc.now(nodeId),
        _vectorClock = initialVectorClock ?? VectorClock({nodeId: 0}) {
    if (initialStore != null) _store.addAll(initialStore);
    if (initialDeletionClocks != null) _deletionClocks.addAll(initialDeletionClocks);
    if (initialPeerClocks != null) _peerClocks.addAll(initialPeerClocks);
    if (initialKnownPeers != null) _knownPeers.addAll(initialKnownPeers);
  }

  /// Restores engine state from [storage] or initializes a fresh engine.
  static Future<CrdtSyncEngine> createWithStorage({
    required String nodeId,
    required CrdtStorage storage,
  }) async {
    final loaded = await storage.load(nodeId);
    if (loaded != null) {
      return CrdtSyncEngine(
        nodeId: nodeId,
        initialHlc: loaded.hlc,
        initialVectorClock: loaded.vectorClock,
        storage: storage,
        initialStore: loaded.store,
        initialDeletionClocks: loaded.deletionClocks,
        initialPeerClocks: loaded.peerClocks,
        initialKnownPeers: loaded.knownPeers,
      );
    }
    return CrdtSyncEngine(nodeId: nodeId, storage: storage);
  }

  Hlc get currentHlc => _hlc;
  VectorClock get currentVectorClock => _vectorClock;
  int get count => _store.length;
  Set<String> get knownPeers => Set.unmodifiable(_knownPeers);
  Map<String, VectorClock> get peerClocks => Map.unmodifiable(_peerClocks);

  /// Registers a known replica node in the distributed cluster.
  void registerPeer(String peerNodeId) {
    if (peerNodeId != nodeId) {
      _knownPeers.add(peerNodeId);
    }
  }

  /// Removes a known replica node (e.g. decommissioned device).
  void unregisterPeer(String peerNodeId) {
    _knownPeers.remove(peerNodeId);
    _peerClocks.remove(peerNodeId);
  }

  /// Advances the local HLC clock for a new local event.
  Hlc _tick() {
    _hlc = _hlc.send(DateTime.now().toUtc().millisecondsSinceEpoch);
    _vectorClock = _vectorClock.copyWithIncrement(nodeId);
    return _hlc;
  }

  /// Persists current engine state to storage if configured.
  Future<void> persist() async {
    if (storage != null) {
      await storage!.persist(
        nodeId: nodeId,
        hlc: _hlc,
        vectorClock: _vectorClock,
        store: _store,
        deletionClocks: _deletionClocks,
        peerClocks: _peerClocks,
        knownPeers: _knownPeers,
      );
    }
  }

  void _persistIfConfigured() {
    if (storage != null) {
      persist();
    }
  }

  /// Inserts or updates a complete receipt from local user actions.
  ReceiptCrdt recordReceipt(ReceiptModel model) {
    final tickHlc = _tick();
    final newCrdt = ReceiptCrdt.fromModel(model, tickHlc);

    if (_store.containsKey(model.id)) {
      _store[model.id] = _store[model.id]!.merge(newCrdt);
    } else {
      _store[model.id] = newCrdt;
    }

    _persistIfConfigured();
    return _store[model.id]!;
  }

  /// Updates specific fields of a line item concurrently.
  ReceiptCrdt updateLineItem({
    required String receiptId,
    required String itemId,
    String? description,
    int? unitPriceCents,
    int? quantity,
    String? category,
    String? necessity,
    int? taxRateBps,
    bool? isDeleted,
  }) {
    final receipt = _store[receiptId];
    if (receipt == null) {
      throw ArgumentError('Receipt with id $receiptId not found in CRDT store');
    }

    final tickHlc = _tick();
    String effectiveItemId = itemId;
    LineItemCrdt? existingItem = receipt.items[effectiveItemId];

    // Backward-compatibility fallback: if caller passed a positional ID like 'rec_item_0'
    // and no exact item has that ID, map to the line item at that index.
    if (existingItem == null && effectiveItemId.contains('_item_')) {
      final idx = int.tryParse(effectiveItemId.split('_item_').last);
      if (idx != null && idx >= 0 && idx < receipt.items.length) {
        effectiveItemId = receipt.items.keys.elementAt(idx);
        existingItem = receipt.items[effectiveItemId];
      }
    }

    final updatedItem = LineItemCrdt(
      id: effectiveItemId,
      description: description != null
          ? LwwRegister(description, tickHlc)
          : (existingItem?.description ?? LwwRegister('', tickHlc)),
      unitPriceCents: unitPriceCents != null
          ? LwwRegister(unitPriceCents, tickHlc)
          : (existingItem?.unitPriceCents ?? LwwRegister(0, tickHlc)),
      quantity: quantity != null
          ? LwwRegister(quantity, tickHlc)
          : (existingItem?.quantity ?? LwwRegister(1, tickHlc)),
      category: category != null
          ? LwwRegister(category, tickHlc)
          : (existingItem?.category ?? LwwRegister('General', tickHlc)),
      necessity: necessity != null
          ? LwwRegister(necessity, tickHlc)
          : (existingItem?.necessity ?? LwwRegister('essential', tickHlc)),
      taxRateBps: taxRateBps != null
          ? LwwRegister(taxRateBps, tickHlc)
          : (existingItem?.taxRateBps ?? LwwRegister(2200, tickHlc)),
      isDeleted: isDeleted != null
          ? LwwRegister(isDeleted, tickHlc)
          : (existingItem?.isDeleted ?? LwwRegister(false, tickHlc)),
    );

    final mergedItem = existingItem != null ? existingItem.merge(updatedItem) : updatedItem;
    final updatedItems = Map<String, LineItemCrdt>.from(receipt.items);
    updatedItems[effectiveItemId] = mergedItem;

    // Recalculate total amount from active items
    int newTotalCents = 0;
    for (final item in updatedItems.values) {
      if (!item.isDeleted.value) {
        newTotalCents += item.unitPriceCents.value * item.quantity.value;
      }
    }

    final updatedReceipt = ReceiptCrdt(
      id: receipt.id,
      merchantName: receipt.merchantName,
      totalAmountCents: LwwRegister(newTotalCents, tickHlc),
      currency: receipt.currency,
      receiptDateMillis: receipt.receiptDateMillis,
      vatNumber: receipt.vatNumber,
      merchantAddress: receipt.merchantAddress,
      boxId: receipt.boxId,
      isDeleted: receipt.isDeleted,
      items: updatedItems,
    );

    _store[receiptId] = updatedReceipt;
    _persistIfConfigured();
    return updatedReceipt;
  }

  /// Marks a receipt as tombstoned (soft-deleted).
  ReceiptCrdt deleteReceipt(String receiptId) {
    final receipt = _store[receiptId];
    if (receipt == null) {
      throw ArgumentError('Receipt with id $receiptId not found in CRDT store');
    }

    final tickHlc = _tick();
    _deletionClocks[receiptId] = _vectorClock;

    final updatedReceipt = ReceiptCrdt(
      id: receipt.id,
      merchantName: receipt.merchantName,
      totalAmountCents: receipt.totalAmountCents,
      currency: receipt.currency,
      receiptDateMillis: receipt.receiptDateMillis,
      vatNumber: receipt.vatNumber,
      merchantAddress: receipt.merchantAddress,
      boxId: receipt.boxId,
      isDeleted: LwwRegister(true, tickHlc),
      items: receipt.items,
    );

    _store[receiptId] = updatedReceipt;
    _persistIfConfigured();
    return updatedReceipt;
  }

  /// Updates top-level metadata of an existing receipt without clobbering line items or their causality clocks.
  ReceiptCrdt updateReceiptMetadata({
    required String receiptId,
    String? merchantName,
    String? boxId,
    String? currency,
    String? vatNumber,
    String? merchantAddress,
    DateTime? receiptDate,
  }) {
    final receipt = _store[receiptId];
    if (receipt == null) {
      throw ArgumentError('Receipt with id $receiptId not found in CRDT store');
    }

    final tickHlc = _tick();
    final updatedReceipt = ReceiptCrdt(
      id: receipt.id,
      merchantName: merchantName != null
          ? LwwRegister(merchantName, tickHlc)
          : receipt.merchantName,
      totalAmountCents: receipt.totalAmountCents,
      currency: currency != null
          ? LwwRegister(currency, tickHlc)
          : receipt.currency,
      receiptDateMillis: receiptDate != null
          ? LwwRegister(receiptDate.millisecondsSinceEpoch, tickHlc)
          : receipt.receiptDateMillis,
      vatNumber: vatNumber != null
          ? LwwRegister(vatNumber, tickHlc)
          : receipt.vatNumber,
      merchantAddress: merchantAddress != null
          ? LwwRegister(merchantAddress, tickHlc)
          : receipt.merchantAddress,
      boxId: boxId != null
          ? LwwRegister(boxId, tickHlc)
          : receipt.boxId,
      isDeleted: receipt.isDeleted,
      items: receipt.items,
    );

    _store[receiptId] = updatedReceipt;
    _persistIfConfigured();
    return updatedReceipt;
  }

  /// Generates a sync delta payload containing all modified state for transmission.
  SyncDeltaPayload generateDeltaPayload() {
    return SyncDeltaPayload(
      senderNodeId: nodeId,
      generatedAtMillis: DateTime.now().toUtc().millisecondsSinceEpoch,
      vectorClock: _vectorClock,
      modifiedReceipts: _store.values.toList(),
    );
  }

  /// Merges a remote sync delta payload using state-based join-semilattice operator ($\sqcup$).
  void mergeDeltaPayload(SyncDeltaPayload payload) {
    // 1. Advance local HLC using the maximum observed register HLC in the payload (prevents HLC clock regression)
    final maxRemoteHlc = payload.maxObservedHlc;
    _hlc = _hlc.receive(
      maxRemoteHlc,
      DateTime.now().toUtc().millisecondsSinceEpoch,
    );

    // 2. Track sender peer clock and merge into local Vector Clock
    _peerClocks[payload.senderNodeId] = payload.vectorClock;
    _vectorClock = _vectorClock.merge(payload.vectorClock);

    // 3. Merge each Receipt CRDT entity
    for (final remoteReceipt in payload.modifiedReceipts) {
      if (_store.containsKey(remoteReceipt.id)) {
        _store[remoteReceipt.id] = _store[remoteReceipt.id]!.merge(remoteReceipt);
      } else {
        _store[remoteReceipt.id] = remoteReceipt;
      }
    }

    _persistIfConfigured();
  }

  /// Retrieves a materialized `ReceiptModel` by ID, or `null` if not found or deleted.
  ReceiptModel? getReceipt(String receiptId, {bool includeDeleted = false}) {
    final crdt = _store[receiptId];
    if (crdt == null) return null;
    if (!includeDeleted && crdt.isDeleted.value) return null;
    return crdt.toModel();
  }

  /// Returns all active, non-tombstoned receipts materialized for UI display.
  List<ReceiptModel> getActiveReceipts() {
    return _store.values
        .where((r) => !r.isDeleted.value)
        .map((r) => r.toModel())
        .toList();
  }

  /// Checks if a tombstone is causally stable across all known peers.
  ///
  /// A tombstone is causally stable if every active replica has acknowledged
  /// a vector clock at or after the deletion event.
  bool isCausallyStable(String receiptId) {
    final receipt = _store[receiptId];
    if (receipt == null || !receipt.isDeleted.value) return false;

    final peersToCheck = _knownPeers.isNotEmpty ? _knownPeers : _peerClocks.keys.toSet();
    if (peersToCheck.isEmpty) {
      // In a single-node cluster with no known peers, local deletion is immediately stable.
      return true;
    }

    final deletionClock = _deletionClocks[receiptId];
    for (final peerId in peersToCheck) {
      final peerClock = _peerClocks[peerId];
      if (peerClock == null) {
        // Peer has never synced, so it might not have observed the tombstone
        return false;
      }
      if (deletionClock != null) {
        if (!deletionClock.isAncestorOrEqual(peerClock)) {
          return false;
        }
      } else {
        // Fallback when deletion clock was not recorded locally:
        // Check if peer has observed at least the deletion node's timestamp
        final tombstoneNode = receipt.isDeleted.hlc.nodeId;
        final peerCounter = peerClock.entries[tombstoneNode] ?? 0;
        if (peerCounter == 0) return false;
      }
    }
    return true;
  }

  /// Prunes tombstoned receipts that were deleted before [cutoffMillis] AND are causally stable.
  ///
  /// Setting [requireCausalStability] to true (default) ensures replicas that have
  /// not yet observed the deletion will not resurrect the pruned receipt.
  int pruneTombstones(int cutoffMillis, {bool requireCausalStability = true}) {
    int prunedCount = 0;
    _store.removeWhere((id, receipt) {
      if (!receipt.isDeleted.value) return false;
      if (receipt.isDeleted.hlc.millis >= cutoffMillis) return false;

      if (requireCausalStability && !isCausallyStable(id)) {
        return false; // Retain until all replicas acknowledge
      }

      _deletionClocks.remove(id);
      prunedCount++;
      return true;
    });

    if (prunedCount > 0) {
      _persistIfConfigured();
    }
    return prunedCount;
  }
}
