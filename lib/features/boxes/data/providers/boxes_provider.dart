// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
import '../models/box_model.dart';

final boxesHiveBoxProvider = Provider<Box<BoxModel>>((ref) {
  throw UnimplementedError('boxesHiveBoxProvider must be overridden in main.dart');
});

final activeBoxIdProvider = StateProvider<String>((ref) => 'main');

class BoxesNotifier extends StateNotifier<List<BoxModel>> {
  final Box<BoxModel> _box;
  static const _uuid = Uuid();

  BoxesNotifier(this._box) : super([]) {
    _load();
  }

  void _load() {
    final items = _box.values.toList();
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
      _box.put(main.id, main);
      state = [main];
    } else {
      state = items;
    }
  }

  BoxModel? findById(String id) {
    try {
      return state.firstWhere((b) => b.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> addBox(BoxModel box) async {
    await _box.put(box.id, box);
    state = [...state, box];
  }

  Future<void> updateBox(String id, BoxModel updated) async {
    await _box.put(id, updated);
    state = state.map((b) => b.id == id ? updated : b).toList();
  }

  Future<void> deleteBox(String id) async {
    if (id == 'main') return; // cannot delete main
    await _box.delete(id);
    state = state.where((b) => b.id != id).toList();
  }

  Future<void> addSpent(String id, double amount) async {
    final box = findById(id);
    if (box == null) return;
    final updated = box.copyWith(spent: box.spent + amount);
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
    );
    await addBox(box);
    return box;
  }
}

final boxesProvider = StateNotifierProvider<BoxesNotifier, List<BoxModel>>((ref) {
  final box = ref.watch(boxesHiveBoxProvider);
  return BoxesNotifier(box);
});
