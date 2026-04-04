// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'asset_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class AssetModelAdapter extends TypeAdapter<AssetModel> {
  @override
  final int typeId = 7;

  @override
  AssetModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return AssetModel(
      id: fields[0] as String,
      name: fields[1] as String,
      purchaseDate: fields[2] as DateTime,
      warrantyMonths: fields[3] as int,
      price: fields[4] as double,
      receiptImagePath: fields[5] as String,
      merchantName: fields[6] as String,
      receiptId: fields[7] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, AssetModel obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.purchaseDate)
      ..writeByte(3)
      ..write(obj.warrantyMonths)
      ..writeByte(4)
      ..write(obj.price)
      ..writeByte(5)
      ..write(obj.receiptImagePath)
      ..writeByte(6)
      ..write(obj.merchantName)
      ..writeByte(7)
      ..write(obj.receiptId);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AssetModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
