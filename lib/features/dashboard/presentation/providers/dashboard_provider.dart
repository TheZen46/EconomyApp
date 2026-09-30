import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import '../../data/models/dashboard_config.dart';
import 'package:t_aidy/features/receipt_scanning/presentation/providers/receipt_provider.dart';

final dashboardProvider = StateNotifierProvider<DashboardNotifier, List<DashboardItem>>((ref) {
  try {
    final box = ref.watch(settingsBoxProvider);
    return DashboardNotifier(box);
  } catch (_) {
    return DashboardNotifier(null);
  }
});

class DashboardNotifier extends StateNotifier<List<DashboardItem>> {
  final Box? _box;
  static const String _kDashboardKey = 'dashboard_layout';

  DashboardNotifier([this._box]) : super([]) {
    _loadLayout();
  }

  void _loadLayout() {
    final dynamic data = _box?.get(_kDashboardKey);
    
    if (data != null && data is List) {
      // Load saved layout
      try {
        state = data.cast<DashboardItem>();
        return;
      } catch (e) {
        debugPrint('Dashboard Load Error: $e. resetting defaults.');
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
    await _box?.put(_kDashboardKey, state);
  }
}

/// Provider for persisting user-configured dashboard widget column spans (1, 2, or 3 columns).
final dashboardWidgetSpansProvider = StateNotifierProvider<DashboardWidgetSpansNotifier, Map<DashboardWidgetType, int>>((ref) {
  try {
    final box = ref.watch(settingsBoxProvider);
    return DashboardWidgetSpansNotifier(box);
  } catch (_) {
    return DashboardWidgetSpansNotifier(null);
  }
});

class DashboardWidgetSpansNotifier extends StateNotifier<Map<DashboardWidgetType, int>> {
  final Box? _box;
  static const String _kSpansKey = 'dashboard_widget_spans';

  static const Map<DashboardWidgetType, int> defaultSpans = {
    DashboardWidgetType.summary: 2,
    DashboardWidgetType.chart: 3,
    DashboardWidgetType.monthlyBudget: 1,
    DashboardWidgetType.heatmap: 1,
    DashboardWidgetType.achievements: 1,
    DashboardWidgetType.necessityBreakdown: 1,
    DashboardWidgetType.recentTransactions: 3,
    DashboardWidgetType.taxNest: 1,
    DashboardWidgetType.projects: 3,
  };

  DashboardWidgetSpansNotifier([this._box]) : super(Map.from(defaultSpans)) {
    _load();
  }

  void _load() {
    final raw = _box?.get(_kSpansKey);
    if (raw is Map) {
      final loaded = Map<DashboardWidgetType, int>.from(state);
      raw.forEach((k, v) {
        final type = DashboardWidgetType.values.firstWhere(
          (t) => t.name == k,
          orElse: () => DashboardWidgetType.summary,
        );
        if (v is int && v >= 1 && v <= 3) {
          loaded[type] = v;
        }
      });
      state = loaded;
    }
  }

  Future<void> setSpan(DashboardWidgetType type, int span) async {
    state = {...state, type: span};
    final serialized = state.map((k, v) => MapEntry(k.name, v));
    await _box?.put(_kSpansKey, serialized);
  }

  Future<void> reset() async {
    state = Map.from(defaultSpans);
    await _box?.delete(_kSpansKey);
  }
}

