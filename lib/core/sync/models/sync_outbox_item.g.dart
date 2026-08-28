// GENERATED CODE - MANUAL HIVE ADAPTER

part of 'sync_outbox_item.dart';

class SyncOutboxItemAdapter extends TypeAdapter<SyncOutboxItem> {
  @override
  final int typeId = 12;

  @override
  SyncOutboxItem read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SyncOutboxItem(
      id: fields[0] as String,
      entityType: fields[1] as String,
      entityId: fields[2] as String,
      mutationType: fields[3] as String,
      payload: (fields[4] as Map).cast<String, dynamic>(),
      timestamp: fields[5] as DateTime,
      retryCount: (fields[6] as num?)?.toInt() ?? 0,
      status: fields[7] as String? ?? 'pending',
      errorMessage: fields[8] as String?,
      lastAttemptAt: fields[9] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, SyncOutboxItem obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.entityType)
      ..writeByte(2)
      ..write(obj.entityId)
      ..writeByte(3)
      ..write(obj.mutationType)
      ..writeByte(4)
      ..write(obj.payload)
      ..writeByte(5)
      ..write(obj.timestamp)
      ..writeByte(6)
      ..write(obj.retryCount)
      ..writeByte(7)
      ..write(obj.status)
      ..writeByte(8)
      ..write(obj.errorMessage)
      ..writeByte(9)
      ..write(obj.lastAttemptAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SyncOutboxItemAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
