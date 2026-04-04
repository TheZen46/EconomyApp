// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sync_item_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class SyncItemModelAdapter extends TypeAdapter<SyncItemModel> {
  @override
  final int typeId = 6;

  @override
  SyncItemModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SyncItemModel(
      receiptId: fields[0] as String,
      imagePath: fields[1] as String,
      addedAt: fields[2] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, SyncItemModel obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.receiptId)
      ..writeByte(1)
      ..write(obj.imagePath)
      ..writeByte(2)
      ..write(obj.addedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SyncItemModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
