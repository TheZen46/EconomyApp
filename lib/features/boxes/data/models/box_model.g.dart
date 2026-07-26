// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'box_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class BoxModelAdapter extends TypeAdapter<BoxModel> {
  @override
  final int typeId = 10;

  @override
  BoxModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return BoxModel(
      id: fields[0] as String,
      name: fields[1] as String,
      budget: fields[2] as double,
      spent: fields[3] as double,
      currency: fields[4] as String,
      color: fields[5] as int,
      icon: fields[6] as String?,
      autoCategorize: fields[7] as bool,
      keywords: fields[8] as String,
      isPrivate: fields[9] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, BoxModel obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.budget)
      ..writeByte(3)
      ..write(obj.spent)
      ..writeByte(4)
      ..write(obj.currency)
      ..writeByte(5)
      ..write(obj.color)
      ..writeByte(6)
      ..write(obj.icon)
      ..writeByte(7)
      ..write(obj.autoCategorize)
      ..writeByte(8)
      ..write(obj.keywords)
      ..writeByte(9)
      ..write(obj.isPrivate);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BoxModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
