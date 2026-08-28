import 'package:hive/hive.dart';

part 'dashboard_config.g.dart';

@HiveType(typeId: 2) // Ensure ID is unique (Receipt is Likely 0 or 1)
enum DashboardWidgetType {
  @HiveField(0)
  summary,
  @HiveField(1)
  chart,
  @HiveField(2)
  heatmap,
  @HiveField(3)
  achievements,
  @HiveField(4)
  recentTransactions,
  @HiveField(5)
  monthlyBudget,
  @HiveField(6)
  necessityBreakdown,
  @HiveField(7)
  taxNest,
  @HiveField(8)
  projects
}

@HiveType(typeId: 3)
class DashboardItem {
  @HiveField(0)
  final String id;
  
  @HiveField(1)
  final DashboardWidgetType type;
  
  @HiveField(2)
  final bool isVisible;

  @HiveField(3)
  final String title; // User-facing name

  DashboardItem({
    required this.id,
    required this.type,
    this.isVisible = true,
    required this.title,
  });

  DashboardItem copyWith({
    bool? isVisible,
  }) {
    return DashboardItem(
      id: id,
      type: type,
      isVisible: isVisible ?? this.isVisible,
      title: title,
    );
  }
}
