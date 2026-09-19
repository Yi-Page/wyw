// ignore_for_file: library_private_types_in_public_api

import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:mobx/mobx.dart';
import 'package:wyw/js/entity/js_entity.dart';
import 'package:wyw/js/js_extends/js_descriptor.dart';
import 'package:wyw/pages/plugin/plugin_controller.dart';
import 'package:wyw/services/logging/log_tags.dart';
import 'package:wyw/services/logging/logger.dart';
import 'package:wyw/utils/plugin_action.dart';

part 'descriptor_controller.g.dart';

/// 通用详情页控制器。
///
/// 路由级 Store 单例（见 [descriptorModule] 的 `provide`），持有页面加载状态
/// 与 AppBar 动作回调。页面构造时通过 [configure] 注入本次路由参数。
class DescriptorController = _DescriptorController with _$DescriptorController;

abstract class _DescriptorController with Store {
  @observable
  List<Widget>? cards;

  @observable
  String? error;

  @observable
  bool loading = false;

  String pluginName = '';
  String method = '';
  List<dynamic> args = const [];
  String? title;
  List<Map<String, dynamic>> actions = const [];

  /// 页面注入：详情页内发生嵌套 `UI.Navigate` 时由页面负责 push 路由。
  Future<void> Function(UiNavigate nav, String sourcePluginName)? onNavigate;

  void configure({
    required String pluginName,
    required String method,
    required List<dynamic> args,
    String? title,
    List<Map<String, dynamic>> actions = const [],
  }) {
    this.pluginName = pluginName;
    this.method = method;
    this.args = args;
    this.title = title;
    this.actions = actions;
  }

  Future<void> load() async {
    loading = true;
    error = null;
    cards = null;
    try {
      final plugin = inject<PluginController>().getPlugin(pluginName);
      if (plugin == null) {
        error = '插件未找到: $pluginName';
        return;
      }
      final result = await plugin.invokeWidgets(
        method,
        args: args,
        onAction: handleAction,
        onNavigate: onNavigate,
        sourcePluginName: pluginName,
      );
      cards = result;
    } on EntityInvokeException catch (e, s) {
      error = e.message;
      WywLogger().e(
          '${LogTag.plugin} 详情页方法调用异常 plugin=$pluginName method=$method',
          error: e,
          stackTrace: s);
    } catch (e, s) {
      error = e.toString();
      WywLogger().e(
          '${LogTag.plugin} 详情页加载失败 plugin=$pluginName method=$method',
          error: e,
          stackTrace: s);
    } finally {
      loading = false;
    }
  }

  Future<void> handleAction(UiAction action) async {
    await invokePluginAction(defaultPluginName: pluginName, action: action);
  }
}
