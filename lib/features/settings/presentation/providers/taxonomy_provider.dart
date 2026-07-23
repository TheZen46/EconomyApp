// ignore_for_file: deprecated_member_use, deprecated_member_use_from_same_package, unused_local_variable, unnecessary_underscores, invalid_annotation_target, unused_element, non_constant_identifier_names, use_build_context_synchronously
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../../../core/constants/taxonomy_constants.dart';
import '../../data/models/taxonomy_model.dart';

final taxonomyProvider = StateNotifierProvider<TaxonomyNotifier, Map<String, Map<String, List<TaxonomyItem>>>>((ref) {
  return TaxonomyNotifier();
});

class TaxonomyNotifier extends StateNotifier<Map<String, Map<String, List<TaxonomyItem>>>> {
  TaxonomyNotifier() : super({}) {
    _loadTaxonomy();
  }

  static const String _boxName = 'taxonomy_config';
  static const String _key = 'current_hierarchy';

  Future<void> _loadTaxonomy() async {
    final box = await Hive.openBox<TaxonomyConfigModel>(_boxName);
    final saved = box.get(_key);

    if (saved != null) {
      // Convert Model back to Entity
      final Map<String, Map<String, List<TaxonomyItem>>> loaded = {};
      
      saved.hierarchy.forEach((main, subs) {
        loaded[main] = {};
        subs.forEach((sub, items) {
          loaded[main]![sub] = items.map((m) => m.toEntity()).toList();
        });
      });
      state = loaded;
    } else {
      // First run: Use defaults
      state = TaxonomyConstants.hierarchy;
      _saveToHive();
    }
  }

  Future<void> _saveToHive() async {
    final box = await Hive.openBox<TaxonomyConfigModel>(_boxName);
    
    // Convert Entity to Model
    final Map<String, Map<String, List<TaxonomyItemModel>>> modelHierarchy = {};
    
    state.forEach((main, subs) {
      modelHierarchy[main] = {};
      subs.forEach((sub, items) {
        modelHierarchy[main]![sub] = items.map((i) => TaxonomyItemModel.fromEntity(i)).toList();
      });
    });

    await box.put(_key, TaxonomyConfigModel(hierarchy: modelHierarchy));
  }

  void updateItemNecessity(String main, String sub, String itemName, String newNecessity) {
    // Deep copy to trigger state change
    final newState = Map<String, Map<String, List<TaxonomyItem>>>.from(state);
    final newItemList = List<TaxonomyItem>.from(newState[main]![sub]!);
    
    final index = newItemList.indexWhere((i) => i.name == itemName);
    if (index != -1) {
      newItemList[index] = TaxonomyItem(itemName, newNecessity);
      newState[main] = Map.from(newState[main]!);
      newState[main]![sub] = newItemList;
      state = newState;
      _saveToHive();
    }
  }

  void addItem(String main, String sub, String name, String necessity) {
    final newState = Map<String, Map<String, List<TaxonomyItem>>>.from(state);
    final newItemList = List<TaxonomyItem>.from(newState[main]![sub]!);
    
    // Avoid duplicates
    if (!newItemList.any((i) => i.name.toLowerCase() == name.toLowerCase())) {
        newItemList.add(TaxonomyItem(name, necessity));
        newState[main] = Map.from(newState[main]!);
        newState[main]![sub] = newItemList;
        state = newState;
        _saveToHive();
    }
  }
  
  void resetDefaults() {
    state = TaxonomyConstants.hierarchy;
    _saveToHive();
  }
}
