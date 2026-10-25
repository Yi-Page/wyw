import 'package:flutter_test/flutter_test.dart';
import 'package:mobx/mobx.dart' as mobx;
import 'package:wyw/pages/plugin/plugin_controller.dart';
import 'package:wyw/plugins/plugin.dart';

/// [PluginController.presenceOf] 的口径回归 —— 收藏卡片图标与收藏页
/// 「已删除」筛选共用这个判定，必须能区分「已禁用/加载失败（文件还在）」
/// 与「已删除（文件已移除）」。
void main() {
  test('未知插件名 = 已删除（文件不在任何名单）', () {
    final controller = PluginController();
    expect(controller.presenceOf('not-exist'), PluginPresence.deleted);
  });

  test('已禁用（文件保留）≠ 已删除', () {
    final controller = PluginController();
    mobx.runInAction(
      () => controller.plugins.add(Plugin(name: 'ccc', enabled: false)),
    );
    expect(controller.presenceOf('ccc'), PluginPresence.disabled);
  });

  test('加载失败（文件在但报错）≠ 已删除', () {
    final controller = PluginController();
    mobx.runInAction(() {
      controller.plugins.add(Plugin(name: 'jm')..loadError = 'syntax error');
    });
    expect(controller.presenceOf('jm'), PluginPresence.failed);
  });

  test('文件缺失（记录还在）既不是 loaded 也不是 disabled', () {
    final controller = PluginController();
    final plugin = Plugin(name: 'ccc')..fileMissing = true;
    mobx.runInAction(() => controller.plugins.add(plugin));
    expect(controller.presenceOf('ccc'), PluginPresence.missing);
    // 缺文件优先于启用状态：一条"启用但没文件"的记录不能报成 loaded
    expect(plugin.enabled, isTrue);
    expect(controller.getPlugin('ccc'), isNull);
    expect(controller.missingFilePlugins.map((p) => p.name), ['ccc']);
  });

  test('已加载插件 = loaded（用 getPlugin 无法直接构造，校验枚举本身完整）', () {
    expect(PluginPresence.values, [
      PluginPresence.loaded,
      PluginPresence.disabled,
      PluginPresence.failed,
      PluginPresence.missing,
      PluginPresence.deleted,
    ]);
  });
}
