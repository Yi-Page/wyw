import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:wyw/services/logging/log_tags.dart';
import 'package:wyw/services/logging/logger.dart';
import 'package:wyw/services/storage/plugin_history_entry.dart';

import '../services/storage/storage.dart';

/// 插件浏览历史仓库（JSON 后端）
///
/// 与 [HistoryRepository]（应用自带进度，Hive 后端）独立：
///   - 写入方：JS 插件（通过 sendMessage → JS 桥）
///   - schema：完全自由（plugin 自定义 kv）
///   - 持久化：JSON 文件（每条完整读写，简单可靠；低频写）
///
/// 内部约定：
///   - 所有变更（upsert / remove / clearAll）走 `_mutate(apply)` 单一入口，
///     保证：私有模式检查 → 加载 → 应用变更 → 落盘 → 通知 changes 流。
///   - UI 层订阅 `changes` 自动重拉，无需在仓库里存"上一次成功数据"。
class PluginHistoryRepository {
  void init() {
    _file = File(GStorage.pluginHistoryFile);
    _privateModeReader = (() => false);
  }

  late File _file;
  late bool Function() _privateModeReader = () => false;

  /// 内存缓存（lazy load + 写后失效）
  List<PluginHistoryEntry>? _cache;

  /// 写后通知流（订阅后自动重新拉取）
  final StreamController<void> _changes = StreamController<void>.broadcast();
  Stream<void> get changes => _changes.stream;

  bool getPrivateMode() => _privateModeReader();

  // ===== 写操作 =====

  /// upsert（同 id 覆盖；visitTime 每次更新为 now）
  Future<void> upsert({
    required String pluginName,
    required String id,
    required String title,
    String? cover,
    Map<String, dynamic>? kv,
  }) async {
    if (id.isEmpty) {
      throw ArgumentError('id must not be empty');
    }
    if (pluginName.isEmpty) {
      throw ArgumentError('pluginName must not be empty');
    }
    await _mutate((entries) {
      final key = '$pluginName::$id';
      entries.removeWhere((e) => e.key == key);
      entries.add(PluginHistoryEntry(
        pluginName: pluginName,
        id: id,
        title: title.isEmpty ? id : title,
        cover: cover ?? '',
        visitTime: DateTime.now(),
        kv: kv ?? const {},
      ));
    });
  }

  /// 单条删除
  Future<void> remove({required String pluginName, required String id}) async {
    await _mutate((entries) {
      final key = '$pluginName::$id';
      entries.removeWhere((e) => e.key == key);
    });
  }

  /// 撤销删除：把条目原样放回（保留原 visitTime），并触发 changes 通知。
  Future<void> restore(PluginHistoryEntry entry) async {
    await _mutate((entries) {
      entries.removeWhere((e) => e.key == entry.key);
      entries.add(entry);
    });
  }

  /// 清空全部
  Future<void> clearAll() async {
    await _mutate((entries) => entries.clear());
  }

  // ===== 读操作 =====

  /// 同步查单条（仅在内存缓存已加载时有效；否则返回 null）
  PluginHistoryEntry? findSync(
      {required String pluginName, required String id}) {
    final entries = _cache;
    if (entries == null) return null;
    final key = '$pluginName::$id';
    for (final e in entries) {
      if (e.key == key) return e;
    }
    return null;
  }

  /// 异步查单条（确保缓存已加载）
  Future<PluginHistoryEntry?> find({
    required String pluginName,
    required String id,
  }) async {
    final entries = await _ensureLoaded();
    final key = '$pluginName::$id';
    for (final e in entries) {
      if (e.key == key) return e;
    }
    return null;
  }

  /// 查询某插件的全部记录（按 visitTime 倒序）
  Future<List<PluginHistoryEntry>> getAllByPlugin(String pluginName) async {
    final entries = await _ensureLoaded();
    final list = entries.where((e) => e.pluginName == pluginName).toList();
    list.sort((a, b) => b.visitTime.compareTo(a.visitTime));
    return list;
  }

  /// 全部记录（按 visitTime 倒序）
  Future<List<PluginHistoryEntry>> getAll() async {
    final entries = await _ensureLoaded();
    final list = List<PluginHistoryEntry>.from(entries);
    list.sort((a, b) => b.visitTime.compareTo(a.visitTime));
    return list;
  }

  // ===== 私有 =====

  /// 统一的变更入口：私有模式跳过 → 加载 → apply → 落盘 → 通知
  Future<void> _mutate(
      void Function(List<PluginHistoryEntry> entries) apply) async {
    if (getPrivateMode()) return;
    final entries = await _ensureLoaded();
    apply(entries);
    await _save(entries);
  }

  /// 确保缓存已加载，返回当前所有条目（按磁盘顺序）
  Future<List<PluginHistoryEntry>> _ensureLoaded() async {
    if (_cache != null) return _cache!;
    return _load();
  }

  Future<List<PluginHistoryEntry>> _load() async {
    if (!await _file.exists()) {
      _cache = [];
      return _cache!;
    }
    try {
      final raw = await _file.readAsString();
      if (raw.isEmpty) {
        _cache = [];
        return _cache!;
      }
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      _cache = list
          .map((m) => PluginHistoryEntry(
                pluginName: m['pluginName'] as String,
                id: m['id'] as String,
                title: m['title'] as String,
                cover: (m['cover'] as String?) ?? '',
                visitTime: DateTime.parse(m['visitTime'] as String),
                kv: (m['kv'] as Map?)?.cast<String, dynamic>() ?? const {},
              ))
          .toList();
      return _cache!;
    } catch (e, s) {
      WywLogger().e(
        '${LogTag.history} 插件浏览历史加载失败 file=${_file.path}',
        error: e,
        stackTrace: s,
      );
      _cache = [];
      return _cache!;
    }
  }

  Future<void> _save(List<PluginHistoryEntry> entries) async {
    _cache = entries;
    try {
      final encoded = jsonEncode(
        entries
            .map((e) => {
                  'pluginName': e.pluginName,
                  'id': e.id,
                  'title': e.title,
                  'cover': e.cover,
                  'visitTime': e.visitTime.toIso8601String(),
                  'kv': e.kv,
                })
            .toList(),
      );
      await _file.parent.create(recursive: true);
      await _file.writeAsString(encoded, flush: true);
    } catch (e, s) {
      WywLogger().e(
        '${LogTag.history} 插件浏览历史保存失败 file=${_file.path}',
        error: e,
        stackTrace: s,
      );
      return;
    }
    _changes.add(null);
  }

  /// 释放（应用退出时调用，避免 Stream 泄漏）
  void dispose() {
    _changes.close();
  }
}
