import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'receipt_provider.dart';
import '../../../../core/constants/app_constants.dart';

// Key for storing categories in settings box
const String _kCustomCategoriesKey = 'custom_categories';

final categoryListProvider = StateNotifierProvider<CategoryNotifier, List<String>>((ref) {
  try {
    final box = ref.watch(settingsBoxProvider);
    return CategoryNotifier(box);
  } catch (_) {
    return CategoryNotifier(null);
  }
});

class CategoryNotifier extends StateNotifier<List<String>> {
  final Box? _box;

  CategoryNotifier([this._box]) : super([]) {
    _loadCategories();
  }

  void _loadCategories() {
    final List<dynamic>? saved = _box?.get(_kCustomCategoriesKey);
    if (saved != null && saved.isNotEmpty) {
      state = saved.cast<String>();
    } else {
      // Default to AppConstants if nothing saved
      state = List.from(AppConstants.categories);
      _saveToBox(state);
    }
  }

  Future<void> _saveToBox(List<String> list) async {
    await _box?.put(_kCustomCategoriesKey, list);
  }

  Future<void> addCategory(String category) async {
    if (category.trim().isEmpty) return;
    if (state.contains(category)) return;

    final newState = [...state, category.trim()];
    state = newState;
    await _saveToBox(newState);
  }

  Future<void> removeCategory(String category) async {
    // Prevent removing defaults? Maybe not. Let user customization be full.
    // If empty, maybe restore defaults? 
    // Let's just allow removal.
    
    final newState = state.where((c) => c != category).toList();
    if (newState.isEmpty) {
       // Optional: restore defaults if user deletes everything?
       // Or just leave empty.
    }
    state = newState;
    await _saveToBox(newState);
  }
  
  Future<void> resetToDefaults() async {
    state = List.from(AppConstants.categories);
    await _saveToBox(state);
  }
}
