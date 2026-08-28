// GENERATED CODE - MANUAL HIVE ADAPTER

part of 'user_profile_model.dart';

class UserProfileModelAdapter extends TypeAdapter<UserProfileModel> {
  @override
  final int typeId = 13;

  @override
  UserProfileModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return UserProfileModel(
      id: fields[0] as String,
      monthlyBudget: (fields[1] as num?)?.toDouble() ?? 2000.0,
      defaultCurrency: fields[2] as String? ?? 'USD',
      themeMode: fields[3] as String? ?? 'system',
      biometricEnabled: fields[4] as bool? ?? false,
      googleDriveSyncEnabled: fields[5] as bool? ?? false,
      gamificationXp: (fields[6] as num?)?.toInt() ?? 0,
      gamificationStreak: (fields[7] as num?)?.toInt() ?? 0,
      updatedAt: fields[8] as DateTime?,
      version: (fields[9] as num?)?.toInt() ?? 1,
    );
  }

  @override
  void write(BinaryWriter writer, UserProfileModel obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.monthlyBudget)
      ..writeByte(2)
      ..write(obj.defaultCurrency)
      ..writeByte(3)
      ..write(obj.themeMode)
      ..writeByte(4)
      ..write(obj.biometricEnabled)
      ..writeByte(5)
      ..write(obj.googleDriveSyncEnabled)
      ..writeByte(6)
      ..write(obj.gamificationXp)
      ..writeByte(7)
      ..write(obj.gamificationStreak)
      ..writeByte(8)
      ..write(obj.updatedAt)
      ..writeByte(9)
      ..write(obj.version);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserProfileModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
