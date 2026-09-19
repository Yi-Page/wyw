import 'dart:async';
import 'dart:io';
import 'package:hive_ce/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wyw/hive_registrar.g.dart';
import 'package:wyw/modules/download/download_module.dart';
import 'package:wyw/services/storage/history_entry.dart';
import 'package:wyw/services/storage/history_type.dart';
import 'package:wyw/services/storage/settings_keys.dart';
import 'package:wyw/services/logging/log_tags.dart';
import 'package:wyw/services/logging/logger.dart';
export 'package:wyw/services/storage/settings_keys.dart';

class GStorage {
  /// 应用自带资源进度（视频/小说/漫画）
  static late Box<HistoryEntry> histories;

  /// 插件浏览历史 JSON 文件路径（与 historiesV2 完全独立）
  static late String pluginHistoryFile;

  /// 下载任务记录
  static late Box<DownloadRecord> downloads;
  static late Box<String> shieldList;
  static late final Box<dynamic> _setting;

  /// Hive directory path, initialized during init()
  static String? _hivePath;

  static Future init() async {
    _hivePath = '${(await getApplicationSupportDirectory()).path}/hive';

    Hive.registerAdapters();
    Hive.registerAdapter(HistoryTypeAdapter());

    // Open each box with automatic recovery on corruptions
    histories = await _openBoxSafe<HistoryEntry>('histories');
    final appSupport = await getApplicationSupportDirectory();
    pluginHistoryFile = '${appSupport.path}/plugin_history.json';
    shieldList = await _openBoxSafe<String>('shieldList');
    _setting = await _openBoxSafe<dynamic>('setting');
    // v2：改用新 box 名，旧 'downloads' 数据直接丢弃（不迁移）
    downloads = await _openBoxSafe<DownloadRecord>('downloads_v2');
  }

  /// Open a Hive box with automatic recovery on corruption.
  /// If the box is corrupted, delete it and create a new empty one.
  static Future<Box<T>> _openBoxSafe<T>(String boxName) async {
    // 先清掉残留的 .lock（上次进程异常退出可能没释放）
    await _releaseStaleLock(boxName);
    try {
      return await Hive.openBox<T>(boxName);
    } catch (e) {
      WywLogger().e(
        '${LogTag.storage} Box $boxName 损坏，尝试恢复',
        error: e,
      );

      // 让 Hive 关闭句柄并删文件（避免直接 File.delete 撞 Windows mmap）
      try {
        await Hive.deleteBoxFromDisk(boxName);
        WywLogger()
            .i('${LogTag.storage} Hive.deleteBoxFromDisk 成功 box=$boxName');
      } catch (e2) {
        WywLogger().w(
          '${LogTag.storage} Hive.deleteBoxFromDisk 失败 box=$boxName',
          error: e2,
        );
        await _deleteBoxFiles(boxName);
      }

      // Try to open again (will create a new empty box)
      try {
        final box = await Hive.openBox<T>(boxName);
        WywLogger().i(
          '${LogTag.storage} Box $boxName 恢复成功（数据已丢失）',
        );
        return box;
      } catch (e2) {
        WywLogger().e('${LogTag.storage} Box 恢复失败 box=$boxName', error: e2);
        rethrow;
      }
    }
  }

  /// 强制删除残留的 .lock 文件（Hive 异常退出后未释放）。
  static Future<void> _releaseStaleLock(String boxName) async {
    if (_hivePath == null) return;
    final lockFile = File('$_hivePath/$boxName.lock');
    if (!await lockFile.exists()) return;
    try {
      await lockFile.delete();
      WywLogger().i('${LogTag.storage} 释放残留 lock 成功 box=$boxName');
    } catch (e) {
      WywLogger().w(
        '${LogTag.storage} 释放残留 lock 失败 box=$boxName',
        error: e,
      );
    }
  }

  /// Delete Hive box files for a given box name
  static Future<void> _deleteBoxFiles(String boxName) async {
    if (_hivePath == null) return;

    final boxFile = File('$_hivePath/$boxName.hive');
    final lockFile = File('$_hivePath/$boxName.lock');

    try {
      if (await boxFile.exists()) {
        await boxFile.delete();
        WywLogger().i('${LogTag.storage} 已删除损坏的 box 文件 file=$boxName.hive');
      }
      if (await lockFile.exists()) {
        await lockFile.delete();
        WywLogger().i('${LogTag.storage} 已删除 lock 文件 file=$boxName.lock');
      }
    } catch (e) {
      WywLogger().e(
        '${LogTag.storage} 删除 box 文件失败 box=$boxName',
        error: e,
      );
    }
  }

  static Future<void> backupBox(String boxName, String backupFilePath) async {
    final appDocumentDir = await getApplicationSupportDirectory();
    final hiveBoxFile = File('${appDocumentDir.path}/hive/$boxName.hive');
    if (await hiveBoxFile.exists()) {
      await hiveBoxFile.copy(backupFilePath);
      WywLogger().i('${LogTag.storage} 备份成功 path=$backupFilePath');
    } else {
      WywLogger().w('${LogTag.storage} Hive box 不存在 box=$boxName');
    }
  }

  static T getSetting<T>(
    SettingKey<T> key, {
    SettingContext context = const SettingContext(),
  }) {
    final defaultValue = key.resolveDefault(context);
    final storedValue = _setting.get(key.name);
    if (storedValue is T) {
      return storedValue;
    }
    return defaultValue;
  }

  static Future<void> putSetting<T>(SettingKey<T> key, T value) async {
    await _setting.put(key.name, value);
  }

  static List<String> getStringListSettingByName(
    String key, {
    List<String> defaultValue = const [],
  }) {
    final storedValue = _setting.get(key);
    if (storedValue is List) {
      return storedValue.whereType<String>().toList();
    }
    return defaultValue;
  }

  static Future<void> putStringListSettingByName(
    String key,
    List<String> value,
  ) async {
    await _setting.put(key, value);
  }

  /// 按字符串键读取设置（用于尚未纳入 [SettingKey] 注册表的动态键）。
  static dynamic getSettingByName(String key) => _setting.get(key);

  /// 按字符串键写入设置。
  static Future<void> putSettingByName(String key, dynamic value) async {
    await _setting.put(key, value);
  }

  /// 按字符串键删除设置（Hive 不接受 put null，删除需显式 delete）。
  static Future<void> deleteSettingByName(String key) async {
    await _setting.delete(key);
  }

  static Future<void> resetSettings(Iterable<SettingKey<Object?>> keys) async {
    await _setting.deleteAll(keys.map((key) => key.name));
    await _setting.flush();
  }

  static Future<void> resetPlayerSettings() async {
    await resetSettings(SettingsKeys.byGroup(SettingGroup.player));
  }

  GStorage._();
}
