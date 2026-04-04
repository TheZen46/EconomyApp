// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'receipt_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

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
      totalAmount: fields[3] as double,
      currency: fields[4] as String,
      items: (fields[5] as List).cast<ReceiptItemModel>(),
      imagePath: fields[7] as String?,
      vatNumber: fields[8] as String,
      merchantAddress: fields[9] as String,
      time: fields[10] as String,
    );
  }

  @override
  void write(BinaryWriter writer, ReceiptModel obj) {
    writer
      ..writeByte(10)
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
      ..write(obj.time);
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
      unitPrice: fields[1] as double,
      quantity: fields[2] as int,
      totalPrice: fields[3] as double?,
      category: fields[4] as String?,
      necessity: fields[5] as String?,
      mainCategory: fields[6] as String?,
      subCategory: fields[7] as String?,
      isAsset: fields[8] as bool?,
    );
  }

  @override
  void write(BinaryWriter writer, ReceiptItemModel obj) {
    writer
      ..writeByte(9)
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
      ..write(obj.isAsset);
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

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ReceiptModel _$ReceiptModelFromJson(Map<String, dynamic> json) => ReceiptModel(
      id: json['id'] as String,
      merchantName: json['merchant_name'] as String,
      date: DateTime.parse(json['date'] as String),
      totalAmount: (json['total_amount'] as num).toDouble(),
      currency: json['currency'] as String,
      items: (json['items'] as List<dynamic>)
          .map((e) => ReceiptItemModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      imagePath: json['imagePath'] as String?,
      vatNumber: json['vatNumber'] as String? ?? '',
      merchantAddress: json['merchantAddress'] as String? ?? '',
      time: json['time'] as String? ?? '',
    );

Map<String, dynamic> _$ReceiptModelToJson(ReceiptModel instance) =>
    <String, dynamic>{
      'id': instance.id,
      'merchant_name': instance.merchantName,
      'date': instance.date.toIso8601String(),
      'total_amount': instance.totalAmount,
      'currency': instance.currency,
      'items': instance.items.map((e) => e.toJson()).toList(),
      'imagePath': instance.imagePath,
      'vatNumber': instance.vatNumber,
      'merchantAddress': instance.merchantAddress,
      'time': instance.time,
    };

ReceiptItemModel _$ReceiptItemModelFromJson(Map<String, dynamic> json) =>
    ReceiptItemModel(
      description: json['description'] as String,
      unitPrice: (json['unit_price'] as num).toDouble(),
      quantity: json['quantity'] as int,
      totalPrice: (json['total_price'] as num?)?.toDouble(),
      category: json['category'] as String?,
      necessity: json['necessity'] as String? ?? 'unknown',
      mainCategory: json['main_category'] as String?,
      subCategory: json['sub_category'] as String?,
      isAsset: json['is_asset'] as bool? ?? false,
    );

Map<String, dynamic> _$ReceiptItemModelToJson(ReceiptItemModel instance) =>
    <String, dynamic>{
      'description': instance.description,
      'unit_price': instance.unitPrice,
      'quantity': instance.quantity,
      'total_price': instance.totalPrice,
      'category': instance.category,
      'necessity': instance.necessity,
      'main_category': instance.mainCategory,
      'sub_category': instance.subCategory,
      'is_asset': instance.isAsset,
    };
