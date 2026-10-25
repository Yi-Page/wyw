/// 插件索引 `index.json` 的读写。
///
/// 索引是插件持久化的唯一数据源：一个数组，一条记录一个插件，**数组顺序 = 管理页
/// 显示顺序**（六个字段见 [Plugin.toJson]）。本文件不持有任何状态，全是静态方法：
///
/// | 接口 | 用途 |
/// |---|---|
/// | [PluginIndex.read] | 读索引，**带读取状态**（「没这个文件」与「读坏了」要分开） |
/// | [PluginIndex.load] | 读索引，只要记录 |
/// | [PluginIndex.save] | 原子写回：`.tmp` → 改名，覆盖前留 `.bak` |
/// | [PluginIndex.decode] / [PluginIndex.encode] | 数据 ↔ 文本 |
/// | [PluginIndex.decodeText] | 文本 → 数据（出厂配置是 asset 字符串，走这条） |
/// | [PluginIndex.fileIn] / [exists] | 路径 / 存在性 |
///
/// 排序、增删、启用状态由 `PluginController` 持有；对账也在那边。这里**不抛异常**。
library;

import 'dart:convert';
import 'dart:io';

import 'package:wyw/plugins/plugin.dart';

/// 索引文件名。
const String pluginIndexFileName = 'index.json';

/// 索引的读取状态。「没这个文件」和「读坏了」处置完全相反，必须分开。
enum PluginIndexState {
  /// 文件不存在：新设备，可以走出厂安装。
  absent,

  /// 读出来了（含空数组）。
  ok,

  /// 文件在但内容不是合法索引：不能当空表装机，也不能动磁盘。
  corrupt,
}

/// [PluginIndex.read] 的返回值。
class PluginIndexRead {
  const PluginIndexRead(this.state, this.records);

  const PluginIndexRead.absent()
      : state = PluginIndexState.absent,
        records = const [];

  const PluginIndexRead.corrupt()
      : state = PluginIndexState.corrupt,
        records = const [];

  final PluginIndexState state;

  /// 解析出的记录；`corrupt` 时为空表，但不代表设备上没有插件。
  final List<Plugin> records;

  bool get isCorrupt => state == PluginIndexState.corrupt;

  bool get isEmpty => records.isEmpty;

  @override
  String toString() => 'PluginIndexRead($state, ${records.length} 条)';
}

/// `index.json` 的读写。全部静态方法，无状态。
abstract final class PluginIndex {
  static File fileIn(Directory dir) =>
      File('${dir.path}${Platform.pathSeparator}$pluginIndexFileName');

  static Future<bool> exists(Directory dir) => fileIn(dir).exists();

  /// 读索引，带上读取状态。
  ///
  /// **判断「要不要走出厂安装」只能用它**：`load` 把「没文件」和「读坏了」都压成空表，
  /// 据此装机就会盖掉用户的东西。
  static Future<PluginIndexRead> read(Directory dir) async {
    final file = fileIn(dir);
    if (!await file.exists()) return const PluginIndexRead.absent();
    try {
      final raw = json.decode(await file.readAsString());
      if (raw is List) {
        return PluginIndexRead(PluginIndexState.ok, decode(raw));
      }
      // 旧版本是 {"format":…,"plugins":…} 对象形态：能读出数组就用，读不出就是空表，
      // 交目录扫描补齐 —— 但那不是「新设备」，所以状态记 ok 而不是 absent。
      if (raw is Map) {
        return PluginIndexRead(PluginIndexState.ok, decode(raw['plugins']));
      }
      return const PluginIndexRead.corrupt();
    } catch (_) {
      return const PluginIndexRead.corrupt();
    }
  }

  /// 读索引，只要记录。文件不存在 / 损坏 / 不是数组时返回空表（不阻断启动）。
  static Future<List<Plugin>> load(Directory dir) async =>
      (await read(dir)).records;

  /// 解析插件数组：非数组 → 空表；缺 `name` 的项丢弃；同名（逐字符）只留先出现的。
  /// 大小写冲突不在这里判 —— 那是扫描层（命名链）的职责。
  static List<Plugin> decode(Object? raw) {
    if (raw is! List) return [];
    final result = <Plugin>[];
    final seen = <String>{};
    for (final item in raw) {
      final plugin = Plugin.fromJson(item);
      if (plugin == null) continue;
      if (!seen.add(plugin.name)) continue;
      result.add(plugin);
    }
    return result;
  }

  /// 序列化（带缩进，方便用户直接看 / 改这个文件）。
  static String encode(List<Plugin> plugins) =>
      const JsonEncoder.withIndent('  ')
          .convert([for (final plugin in plugins) plugin.toJson()]);

  /// 从 JSON 文本解析（出厂配置走这条：内容是 asset 字符串）。
  static List<Plugin> decodeText(String text) {
    try {
      return decode(json.decode(text));
    } catch (_) {
      return [];
    }
  }

  /// 原子写：先写 `.tmp` 再改名覆盖，覆盖前把旧文件留成 `.bak`。
  static Future<void> save(Directory dir, List<Plugin> plugins) async {
    final target = fileIn(dir);
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsString(encode(plugins), flush: true);
    if (await target.exists()) {
      try {
        await target.copy('${target.path}.bak');
      } catch (_) {
        // 备份失败不影响主流程
      }
    }
    await tmp.rename(target.path);
  }
}
