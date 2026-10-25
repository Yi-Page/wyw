/// 插件导入 / 导出的 JSON 包格式。
///
/// 导出与导入对称，并且**故意容忍多种形态**，方便用户手工粘贴或从别处搬运：
///   - 完整包：`{"format":"wyw-plugin-bundle","version":1,"plugins":[{"name","content"}]}`
///   - 裸数组：`[{"name":"x","content":"…js…"}]`
///   - 单插件对象：`{"name":"x","content":"…js…"}`
///
/// 本文件只做**纯文本 ↔ 数据**的转换，不碰文件系统与 JS 引擎，
/// 因此导入导出格式可以直接单测（校验与落盘在 controller 里）。
library;

import 'dart:convert';

/// 包格式标识
const String pluginBundleFormat = 'wyw-plugin-bundle';

/// 当前包版本
const int pluginBundleVersion = 1;

/// 一个待导入 / 导出的插件条目
class PluginBundleEntry {
  const PluginBundleEntry({required this.name, required this.content});

  /// 插件名（= 文件名去 `.js` = JS 类名）
  final String name;

  /// JS 源码
  final String content;

  @override
  String toString() => 'PluginBundleEntry($name, ${content.length} chars)';
}

/// 解析结果：可导入的条目 + 逐条失败原因 + 整包级错误。
class PluginBundleParseResult {
  const PluginBundleParseResult({
    this.entries = const [],
    this.failed = const {},
    this.error,
  });

  /// 结构正确、可以进入校验流程的条目
  final List<PluginBundleEntry> entries;

  /// 逐条失败原因：条目标识（插件名 / `#序号`）-> 原因
  final Map<String, String> failed;

  /// 整包级错误（JSON 非法 / 结构无法识别）；非空时 [entries] 必为空
  final String? error;

  bool get isFatal => error != null;

  @override
  String toString() =>
      'PluginBundleParseResult(entries=${entries.length}, failed=${failed.length}, error=$error)';
}

/// 解析插件导入包。
///
/// 永远不会抛异常：非法 JSON 与无法识别的结构都走 [PluginBundleParseResult.error]，
/// 单条缺字段走 [PluginBundleParseResult.failed]，以便逐条告知用户。
PluginBundleParseResult parsePluginBundle(String jsonText) {
  final dynamic decoded;
  try {
    decoded = json.decode(jsonText);
  } catch (_) {
    return const PluginBundleParseResult(error: '不是合法的 JSON');
  }

  final List<dynamic> items;
  if (decoded is List) {
    items = decoded;
  } else if (decoded is Map && decoded['plugins'] is List) {
    items = decoded['plugins'] as List;
  } else if (decoded is Map && decoded.containsKey('name')) {
    items = [decoded]; // 单插件对象
  } else {
    return const PluginBundleParseResult(error: '无法识别的包格式');
  }

  final entries = <PluginBundleEntry>[];
  final failed = <String, String>{};
  for (var i = 0; i < items.length; i++) {
    final item = items[i];
    if (item is! Map) {
      failed['#${i + 1}'] = '条目不是对象';
      continue;
    }
    final name = item['name']?.toString().trim() ?? '';
    final content = item['content']?.toString() ?? '';
    if (name.isEmpty) {
      failed['#${i + 1}'] = '缺少 name';
      continue;
    }
    if (content.isEmpty) {
      failed[name] = '缺少 content';
      continue;
    }
    entries.add(PluginBundleEntry(name: name, content: content));
  }
  return PluginBundleParseResult(entries: entries, failed: failed);
}

/// 把插件条目编码成导入包 JSON（缩进 2 空格，便于用户查看与手工编辑）。
String encodePluginBundle(List<PluginBundleEntry> entries) {
  return const JsonEncoder.withIndent('  ').convert({
    'format': pluginBundleFormat,
    'version': pluginBundleVersion,
    'plugins': [
      for (final entry in entries)
        {'name': entry.name, 'content': entry.content},
    ],
  });
}
