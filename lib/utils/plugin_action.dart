import 'package:flutter_modular/flutter_modular.dart';
import 'package:wyw/bean/dialog/dialog_helper.dart';
import 'package:wyw/js/entity/js_entity.dart';
import 'package:wyw/js/js_extends/js_descriptor.dart';
import 'package:wyw/pages/plugin/plugin_controller.dart';
import 'package:wyw/services/logging/log_tags.dart';
import 'package:wyw/services/logging/logger.dart';

/// 统一执行 UI 动作：解析插件 -> 校验 -> invoke -> 统一错误处理。
///
/// [defaultPluginName] 为动作未显式指定插件（`__self__`）时使用的插件名，
/// 通常传当前页面所属的插件名。聚合页（如搜索结果页）则传触发该动作的
/// 源插件名。
Future<void> invokePluginAction({
  required String defaultPluginName,
  required UiAction action,
}) async {
  try {
    final pluginName =
        action.plugin == '__self__' ? defaultPluginName : action.plugin;
    if (pluginName.isEmpty) {
      WywDialog.showToast(message: '未指定插件');
      return;
    }
    final plugin = inject<PluginController>().getPlugin(pluginName);
    if (plugin == null) {
      WywDialog.showToast(message: '插件不存在: $pluginName');
      return;
    }
    await plugin.invoke(action.method, action.args);
  } on EntityInvokeException catch (e, s) {
    WywLogger().e(
        '${LogTag.plugin} 插件方法执行异常 plugin=${action.plugin} defaultPlugin=$defaultPluginName method=${action.method}',
        error: e,
        stackTrace: s);
    WywDialog.showToast(message: '调用失败: ${e.message}');
  } catch (e, s) {
    WywLogger().e(
        '${LogTag.plugin} 插件方法调用失败 plugin=${action.plugin} defaultPlugin=$defaultPluginName method=${action.method}',
        error: e,
        stackTrace: s);
    WywDialog.showToast(message: '调用失败: $e');
  }
}
