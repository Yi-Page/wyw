/// 分类索引文件：`{appSupportDir}/plugins/categories.json` —— 用户自定义分类的唯一数据源。
///
/// 与 `index.json` 对称：整个文件是一个数组，**数组顺序 = 分类展示顺序**，
/// 一项形如 `{ "id": "anime", "label": "番剧", "icon": "tv" }`（`icon` 是
/// [CategoryIcons] 的键，不存 IconData）。本类只做文件 I/O，增删改由 controller 决定。
///
/// 读不出来一律空表，写盘为原子写（`.tmp` → 改名，覆盖前留 `.bak`）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:wyw/plugins/plugin_category.dart';

/// 分类索引文件名
const String categoryIndexFileName = 'categories.json';

/// 分类索引文件的读写。
abstract final class CategoryIndex {
  static File fileIn(Directory dir) =>
      File('${dir.path}${Platform.pathSeparator}$categoryIndexFileName');

  static Future<bool> exists(Directory dir) => fileIn(dir).exists();

  /// 读取；文件不存在 / 损坏 / 不是数组时返回空表。
  static Future<List<CustomCategory>> load(Directory dir) async {
    try {
      final file = fileIn(dir);
      if (!await file.exists()) return [];
      return decode(json.decode(await file.readAsString()));
    } catch (_) {
      return [];
    }
  }

  /// 解析分类数组：非数组 → 空表；缺 `id` / `label` 的项丢弃；同 id 只留先出现的。
  static List<CustomCategory> decode(Object? raw) {
    if (raw is! List) return [];
    final result = <CustomCategory>[];
    final seen = <String>{};
    for (final item in raw) {
      final category = CustomCategory.fromJson(item);
      if (category == null) continue;
      if (!seen.add(category.id)) continue;
      result.add(category);
    }
    return result;
  }

  /// 序列化（带缩进，方便用户直接看 / 改这个文件）。
  static String encode(List<CustomCategory> categories) =>
      const JsonEncoder.withIndent('  ')
          .convert([for (final category in categories) category.toJson()]);

  /// 原子写：`categories.json.tmp` → 改名覆盖；覆盖前把旧文件留成 `.bak`。
  static Future<void> save(
    Directory dir,
    List<CustomCategory> categories,
  ) async {
    final target = fileIn(dir);
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsString(encode(categories), flush: true);
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
