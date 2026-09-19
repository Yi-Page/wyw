// ignore_for_file: library_private_types_in_public_api

import 'package:flutter_modular/flutter_modular.dart';
import 'package:mobx/mobx.dart';
import 'package:wyw/plugins/plugin.dart';
import 'package:wyw/pages/plugin/plugin_controller.dart';

part 'browse_controller.g.dart';

/// 分类浏览 Tab 控制器。
///
/// 应用级 Store 单例（见 [coreModule]），筛选出实现了「分类浏览」
/// （`getCategory` 返回非 null）的插件列表，供 [BrowsePage] 渲染 Tab。
class BrowseController = _BrowseController with _$BrowseController;

abstract class _BrowseController with Store {
  /// 支持分类浏览（getCategory 非 null）的插件。
  @observable
  List<Plugin> categoryPlugins = [];

  /// 已检查过的插件数量（plugins 增删时重新检查，由页面维护）。
  int checkedPluginsCount = -1;

  /// 重新筛选支持分类浏览的插件。
  Future<void> refreshCategoryPlugins() async {
    final plugins = inject<PluginController>().plugins;
    final result = <Plugin>[];
    for (final p in plugins) {
      if (!p.isRegistered) continue;
      try {
        final raw = await p.invoke('getCategory', const []);
        if (raw is Map) result.add(p);
      } catch (_) {
        // 静默可接受：插件无分类接口属预期分支，直接跳过该插件
      }
    }
    categoryPlugins = result;
  }
}
