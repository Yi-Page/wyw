// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'collect_entry.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class CollectEntryAdapter extends TypeAdapter<CollectEntry> {
  @override
  final typeId = 12;

  @override
  CollectEntry read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return CollectEntry(
      pluginName: fields[0] as String,
      id: fields[1] as String,
      title: fields[2] as String,
      cover: fields[3] == null ? '' : fields[3] as String,
      visitTime: fields[4] as DateTime,
      kv: fields[5] == null ? {} : (fields[5] as Map).cast<String, dynamic>(),
      collectType: fields[6] == null ? 0 : (fields[6] as num).toInt(),
      collectedAt: fields[7] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, CollectEntry obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.pluginName)
      ..writeByte(1)
      ..write(obj.id)
      ..writeByte(2)
      ..write(obj.title)
      ..writeByte(3)
      ..write(obj.cover)
      ..writeByte(4)
      ..write(obj.visitTime)
      ..writeByte(5)
      ..write(obj.kv)
      ..writeByte(6)
      ..write(obj.collectType)
      ..writeByte(7)
      ..write(obj.collectedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CollectEntryAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
