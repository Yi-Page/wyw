// 手写 HistoryType adapter：绕开 hive_ce_generator 1.11.2 在 analyzer 12
// (analyzer 7) 下解析 enum 失败的问题。生成器原本的输出也是基于 obj.index
// 单字节读写，这里保持二进制兼容。
part of 'history_type.dart';

class HistoryTypeAdapter extends TypeAdapter<HistoryType> {
  @override
  final int typeId = 11;

  @override
  HistoryType read(BinaryReader reader) {
    final index = reader.readByte();
    if (index < 0 || index >= HistoryType.values.length) {
      return HistoryType.custom;
    }
    return HistoryType.values[index];
  }

  @override
  void write(BinaryWriter writer, HistoryType obj) {
    writer.writeByte(obj.index);
  }
}
