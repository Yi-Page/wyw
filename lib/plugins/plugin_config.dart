import 'dart:convert';
import 'dart:io';

/// 插件管理配置（排序 / 禁用 / 分类覆盖），持久化到 `{appSupportDir}/plugin_config.json`。
///
/// **字段语义**：
///   - [order]：扁平全量有序插件名列表（全局自定义排序的事实来源；**包含禁用插件的
///     槽位**，这样重新启用后能恢复到原位置）。
///   - [disabled]：已禁用（未导入）插件名集合 —— 文件保留在磁盘，但不加载不注册。
///   - [categories]：用户手动分类覆盖 `插件名 -> type 字符串`（覆盖 JS 头 `// type:`）。
class PluginConfig {
  static const int _currentVersion = 1;

  int version;
  List<String> order;
  Set<String> disabled;
  Map<String, String> categories;

  PluginConfig({
    this.version = _currentVersion,
    List<String>? order,
    Set<String>? disabled,
    Map<String, String>? categories,
  })  : order = order ?? [],
        disabled = disabled ?? {},
        categories = categories ?? {};

  Map<String, dynamic> toJson() => {
        'version': version,
        'order': order,
        'disabled': disabled.toList(),
        'categories': categories,
      };

  static PluginConfig fromJson(Map<String, dynamic> json) {
    return PluginConfig(
      version: (json['version'] as num?)?.toInt() ?? _currentVersion,
      order: (json['order'] as List?)?.whereType<String>().toList() ?? const [],
      disabled:
          (json['disabled'] as List?)?.whereType<String>().toSet() ?? const {},
      categories:
          (json['categories'] as Map?)?.map((k, v) => MapEntry('$k', '$v')) ??
              const {},
    );
  }

  /// 读取配置；文件不存在或损坏时返回默认值（不阻断启动）。
  static Future<PluginConfig> load(Directory appSupportDir) async {
    final file = File('${appSupportDir.path}/plugin_config.json');
    try {
      if (!await file.exists()) return PluginConfig();
      final text = await file.readAsString();
      final decoded = json.decode(text);
      if (decoded is! Map) return PluginConfig();
      return PluginConfig.fromJson(
        decoded.map((k, v) => MapEntry('$k', v)),
      );
    } catch (e) {
      return PluginConfig();
    }
  }

  /// 写回配置。
  Future<void> save(Directory appSupportDir) async {
    final file = File('${appSupportDir.path}/plugin_config.json');
    await file.writeAsString(json.encode(toJson()));
  }
}
