// ignore_for_file: library_private_types_in_public_api

import 'package:flutter_modular/flutter_modular.dart';
import 'package:mobx/mobx.dart';
import 'package:wyw/plugins/plugin.dart';
import 'package:wyw/pages/plugin/plugin_controller.dart';

part 'browse_controller.g.dart';

/// 分类浏览 Tab 控制器。
///
/// 应用级 Store 单例（见 [coreModule]），筛选出实现了「分类浏览」
/// （声明了 `getCategory` 方法）的插件列表，供 [BrowsePage] 渲染 Tab。
class BrowseController = _BrowseController with _$BrowseController;

abstract class _BrowseController with Store {
  /// 支持分类浏览（声明了 getCategory 方法）的插件。
  @observable
  List<Plugin> categoryPlugins = [];

  /// 已检查过的插件数量（plugins 增删时重新检查，由页面维护）。
  int checkedPluginsCount = -1;

  /// 筛选批次号：只允许**最新**一次筛选写回结果（详见 [refreshCategoryPlugins]）。
  int _refreshSeq = 0;

  /// 重新筛选支持分类浏览的插件。
  ///
  /// **只做能力探测**（`PluginSource.implementsMethod('getCategory')`，无网络），
  /// 不再逐个 invoke `getCategory`——插件的分类数据由各 tab 内容在首次可见时懒加载，
  /// 避免进入浏览页被加载慢的插件卡住。
  ///
  /// 探测要走引擎调用，所以这里是异步的：先逐个 await 出结果，再**一次性**替换
  /// 列表（避免中途发射半成品列表引起 Tab 抖动）；并丢弃过期批次的结果。
  ///
  /// ⚠️ 这条探测之所以准，是因为**基类不给 `getCategory` 留空实现**：
  /// 一旦留了，`typeof getCategory === 'function'` 对每个插件都成立，这个筛选就废了。
  Future<void> refreshCategoryPlugins() async {
    final controller = inject<PluginController>();
    final seq = ++_refreshSeq;
    final next = <Plugin>[];
    for (final p in controller.plugins.toList()) {
      if (!p.isLoaded) continue;
      if (await controller.hasMethod(p.name, 'getCategory')) next.add(p);
    }
    if (seq != _refreshSeq) return; // 有更新的筛选在跑，丢弃本次结果
    runInAction(() => categoryPlugins = next);
  }
}
