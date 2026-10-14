// Hand-written Hive adapter(s). Not generated: the classes in box_model.dart carry no @HiveType
// annotation, so build_runner leaves this file alone. The readers tolerate records written by
// earlier versions (fields that did not exist yet, numbers stored as int or double); keep that
// when adding fields, and never reuse or change a typeId or field number.

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
    final currency = fields[4] as String;
    final budgetDouble = (fields[2] as num).toDouble();
    final spentDouble = (fields[3] as num).toDouble();
    final budgetMinor = fields[15] != null
        ? (fields[15] as num).toInt()
        : Money.fromDecimal(budgetDouble, currency: currency).cents;
    final spentMinor = fields[16] != null
        ? (fields[16] as num).toInt()
        : Money.fromDecimal(spentDouble, currency: currency).cents;

    return BoxModel(
      id: fields[0] as String,
      name: fields[1] as String,
      budget: budgetDouble,
      spent: spentDouble,
      currency: currency,
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
      budgetMinor: budgetMinor,
      spentMinor: spentMinor,
    );
  }

  @override
  void write(BinaryWriter writer, BoxModel obj) {
    writer
      ..writeByte(17)
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
      ..write(obj.version)
      ..writeByte(15)
      ..write(obj.budgetMinor)
      ..writeByte(16)
      ..write(obj.spentMinor);
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
