import 'dart:async';
import 'dart:io';
import 'package:hive_ce/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wyw/hive_registrar.g.dart';
import 'package:wyw/modules/download/download_module.dart';
import 'package:wyw/services/storage/collect_entry.dart';
import 'package:wyw/services/storage/history_entry.dart';
import 'package:wyw/services/storage/history_type.dart';
import 'package:wyw/services/storage/settings_keys.dart';
import 'package:wyw/services/logging/log_tags.dart';
import 'package:wyw/services/logging/logger.dart';
export 'package:wyw/services/storage/settings_keys.dart';

class GStorage {
  /// 应用自带资源进度（视频/小说/漫画）
  static late Box<HistoryEntry> histories;

  /// 收藏条目（= 插件浏览足迹 + 收藏状态），与 [histories] 完全独立。
  static late Box<CollectEntry> collectibles;

  /// 旧版插件浏览历史 JSON 文件路径（仅用于一次性迁移，迁完保留作备份）
  static late String pluginHistoryFile;

  /// 下载任务记录
  static late Box<DownloadRecord> downloads;
  static late Box<String> shieldList;

  /// 弹幕库**详情缓存**：按库 id 键的 JSON（分集列表/多语言标题/标签等重数据）。
  ///
  /// 独立成箱的理由：进度记录里的弹幕选择只存**小快照 + 引用**，而分集列表可达
  /// 上千集；进度每 5–15 秒就会整体重写一次，把重数据塞进去等于每次写都重新序列化
  /// 一份大对象（见 `DanmakuLibraryCacheRepository` 的说明）。
  static late Box<String> danmakuLibraryCache;
  static late final Box<dynamic> _setting;

  /// Hive directory path, initialized during init()
  static String? _hivePath;

  static Future init() async {
    _hivePath = '${(await getApplicationSupportDirectory()).path}/hive';

    Hive.registerAdapters();
    Hive.registerAdapter(HistoryTypeAdapter());

    // 逐个打开 box；失败只重试并上报，不删除任何文件
    histories = await _openBoxSafe<HistoryEntry>('histories');
    collectibles = await _openBoxSafe<CollectEntry>('collectibles');
    final appSupport = await getApplicationSupportDirectory();
    pluginHistoryFile = '${appSupport.path}/plugin_history.json';
    shieldList = await _openBoxSafe<String>('shieldList');
    danmakuLibraryCache = await _openBoxSafe<String>('danmakuLibraryCache');
    _setting = await _openBoxSafe<dynamic>('setting');
    // v2：改用新 box 名，旧 'downloads' 数据直接丢弃（不迁移）
    downloads = await _openBoxSafe<DownloadRecord>('downloads_v2');
  }

  /// 打开 Hive box。
  ///
  /// **环境类失败绝不删除任何文件。** 文件被占用（例如另一个实例在运行）、
  /// 无权限、磁盘写满都不是数据损坏，删掉 `.hive` 会直接丢失用户历史；
  /// 而这些恰恰是这里最常遇到的失败。真·校验和损坏由 hive_ce 自身的
  /// crashRecovery（默认开启）在 openBox 内部截断修复，不会抛到这里。
  ///
  /// 失败先重试一次（占用通常是瞬时持有），仍失败则原样抛出，
  /// 由 main.dart 显示 StorageErrorPage 兜底。
  static Future<Box<T>> _openBoxSafe<T>(String boxName) async {
    try {
      return await Hive.openBox<T>(boxName);
    } catch (e) {
      WywLogger().w(
        '${LogTag.storage} 打开 box 失败，重试 box=$boxName'
        ' path=$_hivePath${_describeIoError(e)}',
        error: e,
      );
    }

    await Future<void>.delayed(const Duration(milliseconds: 300));

    try {
      return await Hive.openBox<T>(boxName);
    } catch (e) {
      WywLogger().e(
        '${LogTag.storage} Box 打开失败，未删除任何文件 box=$boxName'
        ' path=$_hivePath${_describeIoError(e)}',
        error: e,
      );
      rethrow;
    }
  }

  /// 给文件系统类错误补上 errno，便于排查「文件被占用 / 无权限」。
  static String _describeIoError(Object error) {
    if (error is! FileSystemException) return '';
    final code = error.osError?.errorCode;
    return code == null ? '（文件系统错误）' : '（文件系统错误 errno=$code）';
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

  static Future<void> resetDanmakuSettings() async {
    await resetSettings(SettingsKeys.byGroup(SettingGroup.danmaku));
  }

  GStorage._();
}
