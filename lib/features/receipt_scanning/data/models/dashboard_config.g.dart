// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'dashboard_config.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class DashboardItemAdapter extends TypeAdapter<DashboardItem> {
  @override
  final int typeId = 3;

  @override
  DashboardItem read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return DashboardItem(
      id: fields[0] as String,
      type: fields[1] as DashboardWidgetType,
      isVisible: fields[2] as bool,
      title: fields[3] as String,
    );
  }

  @override
  void write(BinaryWriter writer, DashboardItem obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.type)
      ..writeByte(2)
      ..write(obj.isVisible)
      ..writeByte(3)
      ..write(obj.title);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DashboardItemAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class DashboardWidgetTypeAdapter extends TypeAdapter<DashboardWidgetType> {
  @override
  final int typeId = 2;

  @override
  DashboardWidgetType read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return DashboardWidgetType.summary;
      case 1:
        return DashboardWidgetType.chart;
      case 2:
        return DashboardWidgetType.heatmap;
      case 3:
        return DashboardWidgetType.achievements;
      case 4:
        return DashboardWidgetType.recentTransactions;
      case 5:
        return DashboardWidgetType.monthlyBudget;
      case 6:
        return DashboardWidgetType.necessityBreakdown;
      default:
        return DashboardWidgetType.summary;
    }
  }

  @override
  void write(BinaryWriter writer, DashboardWidgetType obj) {
    switch (obj) {
      case DashboardWidgetType.summary:
        writer.writeByte(0);
        break;
      case DashboardWidgetType.chart:
        writer.writeByte(1);
        break;
      case DashboardWidgetType.heatmap:
        writer.writeByte(2);
        break;
      case DashboardWidgetType.achievements:
        writer.writeByte(3);
        break;
      case DashboardWidgetType.recentTransactions:
        writer.writeByte(4);
        break;
      case DashboardWidgetType.monthlyBudget:
        writer.writeByte(5);
        break;
      case DashboardWidgetType.necessityBreakdown:
        writer.writeByte(6);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DashboardWidgetTypeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
