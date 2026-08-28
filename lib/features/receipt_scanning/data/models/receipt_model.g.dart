// GENERATED CODE - MANUAL HIVE ADAPTER

part of 'receipt_model.dart';

class ReceiptModelAdapter extends TypeAdapter<ReceiptModel> {
  @override
  final int typeId = 0;

  @override
  ReceiptModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ReceiptModel(
      id: fields[0] as String,
      merchantName: fields[1] as String,
      date: fields[2] as DateTime,
      totalAmount: (fields[3] as num).toDouble(),
      currency: fields[4] as String,
      items: (fields[5] as List).cast<ReceiptItemModel>(),
      imagePath: fields[7] as String?,
      vatNumber: fields[8] as String? ?? '',
      merchantAddress: fields[9] as String? ?? '',
      time: fields[10] as String? ?? '',
      boxId: fields[11] as String? ?? 'main',
      userId: fields[12] as String?,
      createdAt: fields[13] as DateTime?,
      updatedAt: fields[14] as DateTime?,
      deletedAt: fields[15] as DateTime?,
      version: (fields[16] as num?)?.toInt() ?? 1,
    );
  }

  @override
  void write(BinaryWriter writer, ReceiptModel obj) {
    writer
      ..writeByte(16)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.merchantName)
      ..writeByte(2)
      ..write(obj.date)
      ..writeByte(3)
      ..write(obj.totalAmount)
      ..writeByte(4)
      ..write(obj.currency)
      ..writeByte(5)
      ..write(obj.items)
      ..writeByte(7)
      ..write(obj.imagePath)
      ..writeByte(8)
      ..write(obj.vatNumber)
      ..writeByte(9)
      ..write(obj.merchantAddress)
      ..writeByte(10)
      ..write(obj.time)
      ..writeByte(11)
      ..write(obj.boxId)
      ..writeByte(12)
      ..write(obj.userId)
      ..writeByte(13)
      ..write(obj.createdAt)
      ..writeByte(14)
      ..write(obj.updatedAt)
      ..writeByte(15)
      ..write(obj.deletedAt)
      ..writeByte(16)
      ..write(obj.version);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReceiptModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class ReceiptItemModelAdapter extends TypeAdapter<ReceiptItemModel> {
  @override
  final int typeId = 1;

  @override
  ReceiptItemModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ReceiptItemModel(
      description: fields[0] as String,
      unitPrice: (fields[1] as num).toDouble(),
      quantity: (fields[2] as num).toInt(),
      totalPrice: (fields[3] as num?)?.toDouble(),
      category: fields[4] as String?,
      necessity: fields[5] as String? ?? 'unknown',
      mainCategory: fields[6] as String?,
      subCategory: fields[7] as String?,
      isAsset: fields[8] as bool? ?? false,
      boxId: fields[9] as String? ?? 'main',
      isUserCorrected: fields[10] as bool? ?? false,
      confidenceScore: (fields[11] as num?)?.toDouble() ?? 1.0,
      deletedAt: fields[12] as DateTime?,
      version: (fields[13] as num?)?.toInt() ?? 1,
    );
  }

  @override
  void write(BinaryWriter writer, ReceiptItemModel obj) {
    writer
      ..writeByte(14)
      ..writeByte(0)
      ..write(obj.description)
      ..writeByte(1)
      ..write(obj.unitPrice)
      ..writeByte(2)
      ..write(obj.quantity)
      ..writeByte(3)
      ..write(obj.totalPrice)
      ..writeByte(4)
      ..write(obj.category)
      ..writeByte(5)
      ..write(obj.necessity)
      ..writeByte(6)
      ..write(obj.mainCategory)
      ..writeByte(7)
      ..write(obj.subCategory)
      ..writeByte(8)
      ..write(obj.isAsset)
      ..writeByte(9)
      ..write(obj.boxId)
      ..writeByte(10)
      ..write(obj.isUserCorrected)
      ..writeByte(11)
      ..write(obj.confidenceScore)
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
      other is ReceiptItemModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
