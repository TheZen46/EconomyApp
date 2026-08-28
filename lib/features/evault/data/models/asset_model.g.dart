// GENERATED CODE - MANUAL HIVE ADAPTER

part of 'asset_model.dart';

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
      warrantyMonths: (fields[3] as num).toInt(),
      price: (fields[4] as num).toDouble(),
      receiptImagePath: fields[5] as String? ?? '',
      merchantName: fields[6] as String? ?? '',
      receiptId: fields[7] as String?,
      userId: fields[8] as String?,
      documentPath: fields[9] as String? ?? '',
      createdAt: fields[10] as DateTime?,
      updatedAt: fields[11] as DateTime?,
      deletedAt: fields[12] as DateTime?,
      version: (fields[13] as num?)?.toInt() ?? 1,
    );
  }

  @override
  void write(BinaryWriter writer, AssetModel obj) {
    writer
      ..writeByte(14)
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
      ..write(obj.receiptId)
      ..writeByte(8)
      ..write(obj.userId)
      ..writeByte(9)
      ..write(obj.documentPath)
      ..writeByte(10)
      ..write(obj.createdAt)
      ..writeByte(11)
      ..write(obj.updatedAt)
      ..writeByte(12)
      ..write(obj.deletedAt)
      ..writeByte(13)
      ..write(obj.version);
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
