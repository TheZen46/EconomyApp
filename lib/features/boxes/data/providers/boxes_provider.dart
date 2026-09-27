import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
import '../models/box_model.dart';
import '../../../../core/sync/outbox_service.dart';
import '../../../../core/sync/sync_providers.dart';

final boxesHiveBoxProvider = Provider<Box<BoxModel>>((ref) {
  throw UnimplementedError('boxesHiveBoxProvider must be overridden in main.dart');
});

final activeBoxIdProvider = StateProvider<String>((ref) => 'main');

class BoxesNotifier extends StateNotifier<List<BoxModel>> {
  final Box<BoxModel>? _box;
  final Ref? _ref;
  final OutboxService? _outboxService;
  static const _uuid = Uuid();

  BoxesNotifier([this._box, this._ref, this._outboxService]) : super([]) {
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
        spent: 0,
        currency: 'USD',
        color: Colors.black.value,
        icon: 'Home',
      );
      _box?.put(main.id, main);
      state = [main];
    } else {
      state = items;
    }
  }

  /// Reloads state from the persistent Hive box to reflect external updates.
  void reload() {
    _load();
  }

  BoxModel? findById(String id) {
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
      state = previous;
      rethrow;
    }
  }

  Future<void> updateBox(String id, BoxModel updated) async {
    final previous = state;
    try {
      await _box?.put(id, updated);
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
      state = previous;
      rethrow;
    }
  }

  Future<void> deleteBox(String id) async {
    if (id == 'main') return; // cannot delete main
    final previous = state;
    try {
      await _box?.delete(id);
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
      state = previous;
      rethrow;
    }
  }

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

final boxesProvider = StateNotifierProvider<BoxesNotifier, List<BoxModel>>((ref) {
  Box<BoxModel>? box;
  try {
    box = ref.watch(boxesHiveBoxProvider);
  } catch (_) {}

  OutboxService? outbox;
  try {
    outbox = ref.watch(outboxServiceProvider);
  } catch (_) {}

  return BoxesNotifier(box, ref, outbox);
});
