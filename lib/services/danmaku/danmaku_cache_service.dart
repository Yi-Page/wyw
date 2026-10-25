import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:wyw/modules/danmaku/danmaku_module.dart';
import 'package:wyw/services/logging/log_tags.dart';
import 'package:wyw/services/logging/logger.dart';

/// 剧集目录里缓存的弹幕文件内容。
class CachedDanmaku {
  const CachedDanmaku({
    required this.episodeId,
    required this.libraryTitle,
    required this.danmakus,
  });

  /// 弹弹play 弹幕库编号，便于排查"这条缓存对应哪个库"。
  final int episodeId;
  final String libraryTitle;
  final List<DanmakuEntry> danmakus;
}

/// 离线弹幕缓存：把某集的弹幕写进**剧集下载目录**。
///
/// 为什么落成文件而不是写 Hive：弹幕数据量随剧集线性增长（一集几十 KB 到几 MB），
/// 塞进 Hive 会让下载记录箱膨胀、每次读记录都要反序列化整包；文件放在剧集目录里
/// 天然跟随后续的"删除下载"一起被清掉，不产生孤儿数据。
class DanmakuCacheService {
  DanmakuCacheService();

  static final DanmakuCacheService instance = DanmakuCacheService();

  static const String fileName = 'danmaku.json';

  String _pathFor(String directory) => path.join(directory, fileName);

  /// 该剧集目录是否已经有弹幕缓存（用于避免完成通知重复触发时重复抓取）。
  Future<bool> hasCache(String directory) async {
    if (directory.isEmpty) return false;
    return File(_pathFor(directory)).exists();
  }

  /// 读取缓存；不存在或格式损坏返回 null（损坏时顺手删掉，避免每次播放都踩）。
  Future<CachedDanmaku?> read(String directory) async {
    if (directory.isEmpty) return null;
    final file = File(_pathFor(directory));
    try {
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      if (raw.isEmpty) return null;
      final json = jsonDecode(raw);
      if (json is! Map) return null;

      final danmakus = DanmakuEntry.listFromJson(json['comments']);
      if (danmakus.isEmpty) return null;
      return CachedDanmaku(
        episodeId: _asInt(json['episodeId']),
        libraryTitle: _asString(json['libraryTitle']),
        danmakus: danmakus,
      );
    } catch (error) {
      WywLogger().w('${LogTag.danmaku} 离线弹幕缓存读取失败，已删除 dir=$directory',
          error: error);
      await delete(directory);
      return null;
    }
  }

  Future<void> write({
    required String directory,
    required int episodeId,
    required String libraryTitle,
    required List<DanmakuEntry> danmakus,
  }) async {
    if (directory.isEmpty || danmakus.isEmpty) return;
    try {
      final dir = Directory(directory);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      await File(_pathFor(directory)).writeAsString(jsonEncode({
        'episodeId': episodeId,
        'libraryTitle': libraryTitle,
        'cachedAtMs': DateTime.now().millisecondsSinceEpoch,
        'comments': [for (final danmaku in danmakus) danmaku.toJson()],
      }));
    } catch (error) {
      WywLogger().w('${LogTag.danmaku} 离线弹幕缓存写入失败 dir=$directory',
          error: error);
    }
  }

  Future<void> delete(String directory) async {
    if (directory.isEmpty) return;
    try {
      final file = File(_pathFor(directory));
      if (await file.exists()) {
        await file.delete();
      }
    } catch (error) {
      WywLogger().w('${LogTag.danmaku} 离线弹幕缓存删除失败 dir=$directory',
          error: error);
    }
  }
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

String _asString(Object? value) => value is String ? value : '';
