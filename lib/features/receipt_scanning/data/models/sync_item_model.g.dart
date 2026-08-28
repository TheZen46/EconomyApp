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

    final retryCount = (fields[3] as int?) ?? 0;
    final statusRaw = fields[6];
    SyncStatus status;
    if (statusRaw is SyncStatus) {
      status = statusRaw;
    } else if (statusRaw is int && statusRaw >= 0 && statusRaw < SyncStatus.values.length) {
      status = SyncStatus.values[statusRaw];
    } else {
      status = retryCount >= 5 ? SyncStatus.permanentlyFailed : SyncStatus.pending;
    }

    return SyncItemModel(
      receiptId: fields[0] as String,
      imagePath: fields[1] as String,
      addedAt: fields[2] as DateTime,
      retryCount: retryCount,
      lastAttemptAt: fields[4] as DateTime?,
      nextRetryTimestamp: fields[5] as DateTime?,
      status: status,
      errorMessage: fields[7] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, SyncItemModel obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.receiptId)
      ..writeByte(1)
      ..write(obj.imagePath)
      ..writeByte(2)
      ..write(obj.addedAt)
      ..writeByte(3)
      ..write(obj.retryCount)
      ..writeByte(4)
      ..write(obj.lastAttemptAt)
      ..writeByte(5)
      ..write(obj.nextRetryTimestamp)
      ..writeByte(6)
      ..write(obj.status.index)
      ..writeByte(7)
      ..write(obj.errorMessage);
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
