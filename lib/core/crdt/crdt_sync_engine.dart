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

/// State-based CRDT Synchronization Engine for multi-tenant offline-first replication.
///
/// Ensures Strong Eventual Consistency (SEC):
/// - Replicas can mutate data independently offline.
/// - Concurrent edits on different fields of the same line item merge without data loss.
/// - Conflicts on the same field resolve deterministically via total-ordered HLC timestamps.
/// - Join operator is commutative, associative, and idempotent.
class CrdtSyncEngine {
  final String nodeId;
  Hlc _hlc;
  VectorClock _vectorClock;
  final Map<String, ReceiptCrdt> _store = {};

  CrdtSyncEngine({
    required this.nodeId,
    Hlc? initialHlc,
    VectorClock? initialVectorClock,
  })  : _hlc = initialHlc ?? Hlc.now(nodeId),
        _vectorClock = initialVectorClock ?? VectorClock({nodeId: 0});

  Hlc get currentHlc => _hlc;
  VectorClock get currentVectorClock => _vectorClock;
  int get count => _store.length;

  /// Advances the local HLC clock for a new local event.
  Hlc _tick() {
    _hlc = _hlc.send(DateTime.now().toUtc().millisecondsSinceEpoch);
    _vectorClock = _vectorClock.copyWithIncrement(nodeId);
    return _hlc;
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
    final existingItem = receipt.items[itemId];

    final updatedItem = LineItemCrdt(
      id: itemId,
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
    updatedItems[itemId] = mergedItem;

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
    return updatedReceipt;
  }

  /// Marks a receipt as tombstoned (soft-deleted).
  ReceiptCrdt deleteReceipt(String receiptId) {
    final receipt = _store[receiptId];
    if (receipt == null) {
      throw ArgumentError('Receipt with id $receiptId not found in CRDT store');
    }

    final tickHlc = _tick();
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
    // 1. Update local HLC with remote clock
    _hlc = _hlc.receive(
      Hlc(millis: payload.generatedAtMillis, counter: 0, nodeId: payload.senderNodeId),
      DateTime.now().toUtc().millisecondsSinceEpoch,
    );

    // 2. Merge Vector Clock
    _vectorClock = _vectorClock.merge(payload.vectorClock);

    // 3. Merge each Receipt CRDT entity
    for (final remoteReceipt in payload.modifiedReceipts) {
      if (_store.containsKey(remoteReceipt.id)) {
        _store[remoteReceipt.id] = _store[remoteReceipt.id]!.merge(remoteReceipt);
      } else {
        _store[remoteReceipt.id] = remoteReceipt;
      }
    }
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

  /// Prunes tombstoned items that were deleted before [cutoffMillis] to reclaim storage.
  void pruneTombstones(int cutoffMillis) {
    _store.removeWhere((id, receipt) {
      return receipt.isDeleted.value && receipt.isDeleted.hlc.millis < cutoffMillis;
    });
  }
}
