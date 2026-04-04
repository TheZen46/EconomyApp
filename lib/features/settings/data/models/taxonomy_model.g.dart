// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'taxonomy_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class TaxonomyItemModelAdapter extends TypeAdapter<TaxonomyItemModel> {
  @override
  final int typeId = 4;

  @override
  TaxonomyItemModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return TaxonomyItemModel(
      name: fields[0] as String,
      defaultNecessity: fields[1] as String,
    );
  }

  @override
  void write(BinaryWriter writer, TaxonomyItemModel obj) {
    writer
      ..writeByte(2)
      ..writeByte(0)
      ..write(obj.name)
      ..writeByte(1)
      ..write(obj.defaultNecessity);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TaxonomyItemModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class TaxonomyConfigModelAdapter extends TypeAdapter<TaxonomyConfigModel> {
  @override
  final int typeId = 5;

  @override
  TaxonomyConfigModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return TaxonomyConfigModel(
      hierarchy: (fields[0] as Map).map((dynamic k, dynamic v) => MapEntry(
          k as String,
          (v as Map).map((dynamic k, dynamic v) =>
              MapEntry(k as String, (v as List).cast<TaxonomyItemModel>())))),
    );
  }

  @override
  void write(BinaryWriter writer, TaxonomyConfigModel obj) {
    writer
      ..writeByte(1)
      ..writeByte(0)
      ..write(obj.hierarchy);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TaxonomyConfigModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
