/// 插件名称显示方式的取值（全局设置 `SettingsKeys.pluginNameDisplay`）。
///
/// 由 `PluginController.displayNameOf` 消费，设置页选择项也用同一组常量。
/// 独立成纯文件：不依赖 controller（那里拖了 flutter_qjs / path_provider 等
/// 平台依赖），测试与设置页都能安全引用。
abstract final class PluginNameDisplayMode {
  /// 展示名：用户覆盖 > 插件自称（`// name:` / 类字段）> 插件名
  static const String display = 'display';

  /// 插件名（= 文件名 = JS 类名，即插件的唯一标识）
  static const String identity = 'name';
}
