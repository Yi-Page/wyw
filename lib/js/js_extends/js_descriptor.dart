import 'package:flutter/foundation.dart';

/// UI 描述符（plugin 返回的 widget 树节点）。
///
/// 持有 JS 端 `UI.X({...})` 构造的原始 Map，renderer 按 `type` 派发、按
/// `raw` 字段取值。这样无需为每个原语各写一个 Dart 数据类。
///
/// **当前支持 22 个原语 + navigate**（详细见 [UiType]）。
@immutable
class UiDescriptor {
  /// 描述符类型（来自 JS 端 `__type` 字段，小写）
  final UiType type;

  /// 原始描述符 Map（含 `__type` + 其他字段）
  /// renderer 通过此 Map 访问 children / props，无需 Dart 侧字段镜像
  final Map<String, dynamic> raw;

  const UiDescriptor._(this.type, this.raw);

  /// 从 JS 返回的 Map 构造（容忍 `__type` 缺失 → UiType.unknown）
  factory UiDescriptor.fromJson(Map<String, dynamic> json) {
    final t = (json['__type'] as String?) ?? 'unknown';
    return UiDescriptor._(
        UiType.fromString(t), Map<String, dynamic>.from(json));
  }

  @override
  String toString() => 'UiDescriptor(${type.name})';
}

/// UI 原语类型枚举（与 JS 端 `UI.*` 一一对应）
enum UiType {
  // 顶层容器
  card,
  column,
  row,
  stack,
  // 叶子
  image,
  text,
  icon,
  button,
  iconButton,
  tag,
  spacer,
  divider,
  // 布局工具（新增）
  container,
  padding,
  sizedBox,
  center,
  align,
  expanded,
  wrap,
  aspectRatio,
  // 滚动（新增）
  listView,
  singleChildScrollView,
  // 折叠面板
  expansionTile,
  // 分页容器：children 为当前页结果 + 分页控制（上/下页、页码），
  // 点击切页后宿主用返回的新容器替换当页数据
  pagination,
  // 回调
  action,
  navigate,
  unknown;

  /// 解析 JS 字符串为枚举（未知值映射为 `unknown`）
  static UiType fromString(String s) {
    for (final t in UiType.values) {
      if (t.name == s) return t;
    }
    return UiType.unknown;
  }
}

/// 按钮点击动作描述符（不进渲染树，仅作为 `Button.onTap` 值）
///
/// 渲染时 `onTap: UiAction` → 通过 `Plugin.invoke(method, args)` 回调插件
/// `plugin == '__self__'` 表示调用当前 search 所属插件
///
/// **新增** [icon]：Material Icon 名字（用于 AppBar IconButton 渲染）
@immutable
class UiAction {
  /// 目标插件名，`'__self__'` 表示当前 tab 插件
  final String plugin;

  /// 插件方法名
  final String method;

  /// 透传参数列表
  final List<dynamic> args;

  /// 附加数据（不进 JSON 序列化场景使用）
  final dynamic payload;

  /// Material Icon 名字（用于 AppBar IconButton 等需要 icon 的场景）
  final String? icon;

  const UiAction({
    required this.plugin,
    required this.method,
    this.args = const [],
    this.payload,
    this.icon,
  });

  /// 从 Button.onTap 字段值构造（容忍 null / 缺字段）
  factory UiAction.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const UiAction(plugin: '__self__', method: '');
    }
    return UiAction(
      plugin: (json['plugin'] as String?) ?? '__self__',
      method: (json['method'] as String?) ?? '',
      args: (json['args'] as List?)?.cast<dynamic>() ?? const [],
      payload: json['payload'],
      icon: json['icon'] as String?,
    );
  }
}

/// 导航描述符（不进渲染树，作为 button.onTap 等值）
///
/// 触发 Dart 路由跳转 + 自动 `plugin.invokeWidgets(method, args)` 拿详情页内容
///
/// **典型用法**：
/// ```js
/// UI.Button({
///   onTap: UI.Navigate({
///     page: 'descriptor',
///     method: 'getDetail',
///     args: [id],
///     title: '详情',
///     actions: [{__type: 'action', icon: 'favorite', method: 'favorite', args: [id]}],
///   }),
/// });
/// ```
@immutable
class UiNavigate {
  /// 目标页标识（当前只支持 `'descriptor'`）
  final String page;

  /// 跳转后调用的 plugin 方法
  final String method;

  /// 方法参数
  final List<dynamic> args;

  /// AppBar 标题
  final String? title;

  /// AppBar 右侧 IconButton 列表（每项是 [UiAction] 描述符 raw Map）
  final List<Map<String, dynamic>> actions;

  const UiNavigate({
    required this.page,
    required this.method,
    this.args = const [],
    this.title,
    this.actions = const [],
  });

  /// 从 Button.onTap 字段值构造（缺字段使用默认）
  factory UiNavigate.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const UiNavigate(page: 'descriptor', method: '');
    }
    return UiNavigate(
      page: (json['page'] as String?) ?? 'descriptor',
      method: (json['method'] as String?) ?? '',
      args: (json['args'] as List?)?.cast<dynamic>() ?? const [],
      title: json['title'] as String?,
      actions:
          (json['actions'] as List?)?.cast<Map<String, dynamic>>() ?? const [],
    );
  }
}
