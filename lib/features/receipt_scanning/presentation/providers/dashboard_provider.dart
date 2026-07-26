// ignore_for_file: deprecated_member_use, deprecated_member_use_from_same_package, unused_local_variable, unnecessary_underscores, invalid_annotation_target, unused_element, non_constant_identifier_names, use_build_context_synchronously
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import '../../data/models/dashboard_config.dart';
import '../providers/receipt_provider.dart'; // For settingsBoxProvider

final dashboardProvider = StateNotifierProvider<DashboardNotifier, List<DashboardItem>>((ref) {
  final box = ref.watch(settingsBoxProvider);
  return DashboardNotifier(box);
});

class DashboardNotifier extends StateNotifier<List<DashboardItem>> {
  final Box _box;
  static const String _kDashboardKey = 'dashboard_layout';

  DashboardNotifier(this._box) : super([]) {
    _loadLayout();
  }

  void _loadLayout() {
    final dynamic data = _box.get(_kDashboardKey);
    
    if (data != null && data is List) {
      // Load saved layout
      try {
        state = data.cast<DashboardItem>();
        return;
      } catch (e) {
        print('Dashboard Load Error: $e. resetting defaults.');
      }
    }

    // Default Layout
    _resetToDefault();
  }
  
  void _resetToDefault() {
     state = [
       DashboardItem(id: 'summary', type: DashboardWidgetType.summary, title: 'Monthly Summary'),
       DashboardItem(id: 'taxNest', type: DashboardWidgetType.taxNest, title: 'The Tax Nest'),
       DashboardItem(id: 'chart', type: DashboardWidgetType.chart, title: 'Activity Chart'),
       DashboardItem(id: 'boxes', type: DashboardWidgetType.monthlyBudget, title: 'Boxes'),
       DashboardItem(id: 'breakdown', type: DashboardWidgetType.necessityBreakdown, title: 'Financial Health'),
       DashboardItem(id: 'heatmap', type: DashboardWidgetType.heatmap, title: 'Spending Heatmap'),
       DashboardItem(id: 'achievements', type: DashboardWidgetType.achievements, title: 'Achievements'),
       DashboardItem(id: 'recent', type: DashboardWidgetType.recentTransactions, title: 'Recent Transactions'),
       DashboardItem(id: 'projects', type: DashboardWidgetType.projects, title: 'Active Invoices'),
     ];
     _save();
  }

  void reorder(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final item = state.removeAt(oldIndex);
    state.insert(newIndex, item);
    // Force new list reference for Riverpod
    state = [...state]; 
    _save();
  }

  void toggleVisibility(int index) {
    final item = state[index];
    final newItem = item.copyWith(isVisible: !item.isVisible);
    state[index] = newItem;
    state = [...state];
    _save();
  }

  void reset() {
    _resetToDefault();
  }

  Future<void> _save() async {
    await _box.put(_kDashboardKey, state);
  }
}
