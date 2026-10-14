import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
import '../models/box_model.dart';
import '../../../../core/sync/outbox_service.dart';
import '../../../../core/sync/sync_providers.dart';
import '../../../receipt_scanning/data/models/receipt_model.dart';
import '../../../receipt_scanning/presentation/providers/receipt_provider.dart';
import '../../../../core/providers/storage_providers.dart';
export '../../../../core/providers/storage_providers.dart'
    show boxesHiveBoxProvider, boxesBoxProvider;

/// Currently active budget box identifier used for UI filtering (defaults to `'main'`).
///
/// **Lifetime:** App-scoped state provider.
final activeBoxIdProvider = StateProvider<String>((ref) => 'main');

/// State notifier managing user budget boxes, cascade receipt reassignments, and outbox sync.
class BoxesNotifier extends StateNotifier<List<BoxModel>> {
  final Box<BoxModel>? _box;
  final Ref? _ref;
  final OutboxService? _outboxService;
  final Box<ReceiptModel>? _receiptsBox;
  static const _uuid = Uuid();

  /// Creates a [BoxesNotifier] and auto-seeds the default `'main'` box if empty.
  BoxesNotifier([this._box, this._ref, this._outboxService, this._receiptsBox]) : super([]) {
    _load();
  }

  void _load() {
    final items = _box?.values.toList() ?? [];
    if (items.isEmpty) {
      // Seed default box
      final main = BoxModel(
        id: 'main',
        name: 'Out of the Box (Main Life)',
        budget: 0,
        spent: _computeSpentForBox('main'),
        currency: 'USD',
        color: Colors.black.value,
        icon: 'Home',
      );
      _box?.put(main.id, main);
      state = [main];
    } else {
      state = items.map((b) {
        final calculated = _computeSpentForBox(b.id);
        if ((b.spent - calculated).abs() > 0.001) {
          final updated = b.copyWith(spent: calculated);
          _box?.put(b.id, updated);
          return updated;
        }
        return b;
      }).toList();
    }
  }

  double _computeSpentForBox(String boxId) {
    final receipts = _receiptsBox?.values;
    if (receipts == null) return 0.0;
    double total = 0.0;
    for (final r in receipts) {
      if (r.items.isEmpty) {
        if ((r.boxId ?? 'main') == boxId) {
          total += r.totalAmount;
        }
      } else {
        for (final item in r.items) {
          final itemBox = item.boxId ?? r.boxId ?? 'main';
          if (itemBox == boxId) {
            total += item.totalPrice ?? (item.unitPrice * item.quantity);
          }
        }
      }
    }
    return total;
  }

  /// Reloads state from the persistent Hive box to reflect external updates.
  void reload() {
    _load();
  }

  BoxModel? findById(String id) {
    if (id == 'main' || id.isEmpty) {
      return state.firstWhere(
        (b) => b.id == 'main',
        orElse: () => state.isNotEmpty
            ? state.first
            : BoxModel(
                id: 'main',
                name: 'Out of the Box (Main Life)',
                budget: 0,
                spent: 0,
                currency: 'USD',
                color: Colors.black.value,
                icon: 'Home',
              ),
      );
    }
    try {
      return state.firstWhere((b) => b.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> addBox(BoxModel box) async {
    final previous = state;
    try {
      await _box?.put(box.id, box);
      if (!mounted) return;
      state = [...state, box];
      if (_outboxService != null) {
        await _outboxService.enqueue(
          entityType: 'box',
          entityId: box.id,
          mutationType: 'upsert',
          payload: box.toJson(),
        );
      }
    } catch (e) {
      debugPrint('BoxesNotifier: Error adding box: $e');
      if (mounted) state = previous;
      rethrow;
    }
  }

  Future<void> updateBox(String id, BoxModel updated) async {
    final previous = state;
    try {
      await _box?.put(id, updated);
      if (!mounted) return;
      state = state.map((b) => b.id == id ? updated : b).toList();
      if (_outboxService != null) {
        await _outboxService.enqueue(
          entityType: 'box',
          entityId: id,
          mutationType: 'upsert',
          payload: updated.toJson(),
        );
      }
    } catch (e) {
      debugPrint('BoxesNotifier: Error updating box: $e');
      if (mounted) state = previous;
      rethrow;
    }
  }

  /// Deletes the box. Its receipts, and line items assigned to it, are moved
  /// to the main box first, so that they stay visible and counted.
  Future<void> deleteBox(String id) async {
    if (id == 'main') return; // cannot delete main
    final previous = state;
    try {
      await _moveReceiptsToMain(id);
      await _box?.delete(id);
      if (!mounted) return;
      state = state.where((b) => b.id != id).toList();
      if (_ref != null && _ref.read(activeBoxIdProvider) == id) {
        _ref.read(activeBoxIdProvider.notifier).state = 'main';
      }
      if (_outboxService != null) {
        await _outboxService.enqueue(
          entityType: 'box',
          entityId: id,
          mutationType: 'delete',
          payload: {'id': id},
        );
      }
    } catch (e) {
      debugPrint('BoxesNotifier: Error deleting box: $e');
      if (mounted) state = previous;
      rethrow;
    }
  }

  Future<void> _moveReceiptsToMain(String boxId) async {
    final receipts = _receiptsBox;
    if (receipts == null) return;
    final now = DateTime.now().toUtc();
    var moved = 0;
    for (final receipt in receipts.values.toList()) {
      final inBox = receipt.boxId == boxId;
      final itemsInBox = receipt.items.any((i) => i.boxId == boxId);
      if (!inBox && !itemsInBox) continue;

      final updated = receipt.copyWith(
        boxId: inBox ? 'main' : receipt.boxId,
        items: [for (final item in receipt.items) item.boxId == boxId ? _itemInMain(item) : item],
        updatedAt: now,
        version: receipt.version + 1,
      );
      await receipts.put(updated.id, updated);
      moved++;
      if (_outboxService != null) {
        await _outboxService.enqueue(
          entityType: 'receipt',
          entityId: updated.id,
          mutationType: 'upsert',
          payload: updated.toRemoteJson(),
        );
      }
    }
    if (moved > 0) {
      try {
        _ref?.invalidate(receiptListProvider);
      } catch (_) {}
    }
  }

  static ReceiptItemModel _itemInMain(ReceiptItemModel item) => ReceiptItemModel(
        description: item.description,
        unitPrice: item.unitPrice,
        quantity: item.quantity,
        totalPrice: item.totalPrice,
        category: item.category,
        necessity: item.necessity,
        mainCategory: item.mainCategory,
        subCategory: item.subCategory,
        isAsset: item.isAsset,
        boxId: 'main',
        isUserCorrected: item.isUserCorrected,
        confidenceScore: item.confidenceScore,
        deletedAt: item.deletedAt,
        version: item.version,
      );

  Future<void> addSpent(String id, double amount) async {
    final box = findById(id);
    if (box == null) return;
    final updated = box.copyWith(
      spent: box.spent + amount,
      updatedAt: DateTime.now().toUtc(),
      version: box.version + 1,
    );
    await updateBox(id, updated);
  }

  /// Recomputes and updates the [spent] property for all active boxes
  /// based on currently persisted receipts.
  Future<void> recalculateAllBoxesSpent() async {
    final receipts = _receiptsBox?.values;
    if (receipts == null) return;
    for (final b in state) {
      final calculated = _computeSpentForBox(b.id);
      if ((b.spent - calculated).abs() > 0.001) {
        final updated = b.copyWith(
          spent: calculated,
          updatedAt: DateTime.now().toUtc(),
          version: b.version + 1,
        );
        await updateBox(b.id, updated);
      }
    }
  }

  Future<BoxModel> createNew({
    required String name,
    required double budget,
    required String currency,
    required Color color,
    String? icon,
    bool autoCategorize = false,
    String keywords = '',
    bool isPrivate = false,
  }) async {
    final nowUtc = DateTime.now().toUtc();
    final box = BoxModel(
      id: _uuid.v4(),
      name: name,
      budget: budget,
      spent: 0,
      currency: currency,
      color: color.value,
      icon: icon,
      autoCategorize: autoCategorize,
      keywords: keywords,
      isPrivate: isPrivate,
      createdAt: nowUtc,
      updatedAt: nowUtc,
    );
    await addBox(box);
    return box;
  }
}

/// Provides the reactive list of budget envelope boxes.
///
/// **Lifetime:** App-scoped state notifier provider.
/// **Dependencies:**
/// - `boxesHiveBoxProvider`: Persistent boxes Hive box.
/// - `outboxServiceProvider`: Offline CRDT outbox queue.
/// - `hiveBoxProvider`: Receipts Hive box for reassigning deleted boxes.
final boxesProvider = StateNotifierProvider<BoxesNotifier, List<BoxModel>>((ref) {
  final box = ref.watch(boxesBoxNullableProvider);
  final outbox = ref.watch(outboxServiceNullableProvider);
  final receipts = ref.watch(receiptsBoxNullableProvider);

  return BoxesNotifier(box, ref, outbox, receipts);
});
