// GENERATED CODE - MANUAL HIVE ADAPTER

part of 'box_model.dart';

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
      budget: (fields[2] as num).toDouble(),
      spent: (fields[3] as num).toDouble(),
      currency: fields[4] as String,
      color: fields[5] as int,
      icon: fields[6] as String?,
      autoCategorize: fields[7] as bool? ?? false,
      keywords: fields[8] as String? ?? '',
      isPrivate: fields[9] as bool? ?? false,
      userId: fields[10] as String?,
      createdAt: fields[11] as DateTime?,
      updatedAt: fields[12] as DateTime?,
      deletedAt: fields[13] as DateTime?,
      version: (fields[14] as num?)?.toInt() ?? 1,
    );
  }

  @override
  void write(BinaryWriter writer, BoxModel obj) {
    writer
      ..writeByte(15)
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
      ..write(obj.isPrivate)
      ..writeByte(10)
      ..write(obj.userId)
      ..writeByte(11)
      ..write(obj.createdAt)
      ..writeByte(12)
      ..write(obj.updatedAt)
      ..writeByte(13)
      ..write(obj.deletedAt)
      ..writeByte(14)
      ..write(obj.version);
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
