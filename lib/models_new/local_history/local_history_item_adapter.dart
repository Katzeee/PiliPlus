import 'package:PiliPlus/models_new/local_history/local_history_item.dart';
import 'package:hive_ce/hive.dart';

/// typeId lives outside the range upstream allocates.
class LocalHistoryItemAdapter extends TypeAdapter<LocalHistoryItem> {
  @override
  final int typeId = 100;

  @override
  LocalHistoryItem read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return LocalHistoryItem(
      accountMid: fields[0] as int,
      business: fields[1] as String,
      kid: fields[2] as int,
      syncedAt: fields[3] as int,
      title: fields[4] as String?,
      cover: fields[5] as String?,
      covers: (fields[6] as List?)?.cast<String>(),
      uri: fields[7] as String?,
      videos: fields[8] as int?,
      authorName: fields[9] as String?,
      authorMid: fields[10] as int?,
      viewAt: fields[11] as int?,
      progress: fields[12] as int?,
      badge: fields[13] as String?,
      showTitle: fields[14] as String?,
      duration: fields[15] as int?,
      isFav: fields[16] as int?,
      tagName: fields[17] as String?,
      liveStatus: fields[18] as int?,
      oid: fields[19] as int?,
      epid: fields[20] as int?,
      bvid: fields[21] as String?,
      page: fields[22] as int?,
      cid: fields[23] as int?,
    );
  }

  @override
  void write(BinaryWriter writer, LocalHistoryItem obj) {
    writer
      ..writeByte(24)
      ..writeByte(0)
      ..write(obj.accountMid)
      ..writeByte(1)
      ..write(obj.business)
      ..writeByte(2)
      ..write(obj.kid)
      ..writeByte(3)
      ..write(obj.syncedAt)
      ..writeByte(4)
      ..write(obj.title)
      ..writeByte(5)
      ..write(obj.cover)
      ..writeByte(6)
      ..write(obj.covers)
      ..writeByte(7)
      ..write(obj.uri)
      ..writeByte(8)
      ..write(obj.videos)
      ..writeByte(9)
      ..write(obj.authorName)
      ..writeByte(10)
      ..write(obj.authorMid)
      ..writeByte(11)
      ..write(obj.viewAt)
      ..writeByte(12)
      ..write(obj.progress)
      ..writeByte(13)
      ..write(obj.badge)
      ..writeByte(14)
      ..write(obj.showTitle)
      ..writeByte(15)
      ..write(obj.duration)
      ..writeByte(16)
      ..write(obj.isFav)
      ..writeByte(17)
      ..write(obj.tagName)
      ..writeByte(18)
      ..write(obj.liveStatus)
      ..writeByte(19)
      ..write(obj.oid)
      ..writeByte(20)
      ..write(obj.epid)
      ..writeByte(21)
      ..write(obj.bvid)
      ..writeByte(22)
      ..write(obj.page)
      ..writeByte(23)
      ..write(obj.cid);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LocalHistoryItemAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
