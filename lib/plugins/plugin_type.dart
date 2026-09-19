import 'package:flutter/material.dart';

/// 插件分类。
///
/// 生效类型来源优先级：**用户覆盖（PluginController.setCategory）> JS 头 `// type:`
/// 声明（Plugin.headerType）> 依据实现方法推断（_inferType）> [unknown]**。
enum PluginType {
  video('视频', Icons.movie_outlined, Colors.redAccent),
  manga('漫画', Icons.menu_book_outlined, Colors.blueAccent),
  novel('小说', Icons.article_outlined, Colors.green),
  unknown('其他', Icons.extension, Colors.grey);

  const PluginType(this.label, this.icon, this.color);

  /// 显示名
  final String label;

  /// 分类图标
  final IconData icon;

  /// 分类标识色：categorical palette，M3 无对应 token，作为"数据"挂在枚举上
  /// （与主题种子色列表同性质，规范见 docs/ui-routing-design-spec.md 8A 节）。
  final Color color;

  static PluginType parse(String? raw) {
    switch (raw?.trim().toLowerCase()) {
      case 'video':
        return video;
      case 'manga':
        return manga;
      case 'novel':
        return novel;
      default:
        return unknown;
    }
  }
}
