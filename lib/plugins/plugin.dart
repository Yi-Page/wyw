import 'dart:io';

import 'package:flutter/material.dart';
import 'package:wyw/js/base_js_engine.dart';
import 'package:wyw/js/entity/js_entity.dart';
import 'package:wyw/js/js_extends/js_descriptor.dart';
import 'package:wyw/js/js_extends/js_descriptor_renderer.dart';
import 'package:wyw/plugins/plugin_type.dart';
import 'package:wyw/services/logging/log_tags.dart';
import 'package:wyw/services/logging/logger.dart';

/// 统一插件类：元数据 + 运行时状态合一。
///
/// **单一数据源**：所有插件信息集中在此类，
/// 运行时状态（entity）和文件元数据（name/className/filePath/description）不再分离。
///
/// JS 类名 = 文件名（去 .js），由 JS 作者保证类名与文件名一致。
///
/// **生命周期**：
///   1. [register] — 注册到 JS 引擎
///   2. [invoke] — 调用插件方法
///   3. [reload] — 热重载
///   4. [unregister] — 从 JS 引擎卸载
///   5. [delete] — 删除插件文件
class Plugin {
  /// 插件名（文件名去 .js），如 `greeting`
  final String name;

  /// JS 文件绝对路径
  final String filePath;

  /// 描述（从文件头部 `// description:` 解析）
  String description;

  /// JS 头声明的分类（`// type:`），用户覆盖前的原始值
  PluginType headerType;

  /// 生效分类（用户覆盖 > headerType > 方法推断），UI 展示用
  PluginType type;

  /// 是否为应用内置插件（来自 `assets/plugin`）。
  ///
  /// 由 [PluginController] 在每次启动同步内置插件时按名称设置，
  /// 用于 UI 展示、删除追踪（防止下次启动重新复制）。
  bool isBuiltin;

  /// 内置版本与应用内版本内容不一致，存在可更新的新版本。
  ///
  /// 由 [PluginController] 在启动同步/编辑/更新时比对内容后设置；
  /// UI 据此展示「可更新」标识并提供更新入口。
  bool hasUpdate;

  /// JS 源码内容缓存（避免重复文件 I/O）
  String? _content;

  /// JS 运行时实体（注册后有值）
  JsEntity? _entity;

  /// 是否已注册到 JS 引擎
  bool get isRegistered => _entity?.isLoaded ?? false;

  /// 插件实体（未注册时为 null）
  JsEntity? get entity => _entity;

  Plugin({
    required this.name,
    required this.filePath,
    this.description = '',
    this.headerType = PluginType.unknown,
    this.type = PluginType.unknown,
    this.isBuiltin = false,
    this.hasUpdate = false,
    String? content,
  }) : _content = content;

  /// 读取 JS 源码（带内存缓存）
  Future<String> getContent() async {
    if (_content != null) return _content!;
    _content = await File(filePath).readAsString();
    return _content!;
  }

  /// 写入 JS 源码到文件并更新缓存
  Future<void> writeContent(String newContent) async {
    await File(filePath).writeAsString(newContent);
    _content = newContent;
  }

  /// 注册插件到 JS 引擎
  Future<void> register(BaseJsEngine engine) async {
    final content = await getContent();
    _entity = JsEntity(
      className: name,
      entityPath: '__plugins__',
      entityName: name,
      engine: engine,
      content: content,
    );
    await _entity!.register();
  }

  /// 热重载：清缓存、重新解析头部元数据并重新注册
  Future<void> reload(BaseJsEngine engine) async {
    _entity?.unload();
    _content = null;
    await getContent(); // 重新读盘，更新 _content 缓存
    refreshMetaFromContent();
    await register(engine);
  }

  /// 从当前内容重新解析头部元数据（description / headerType）。
  ///
  /// 热重载或编辑插件后调用；只更新元数据，**不会触发注册**。
  /// 生效分类 [type] 由 controller 依据用户覆盖/方法推断重新解析。
  void refreshMetaFromContent() {
    final header = _parseHeader(_content ?? '');
    description = header.description;
    headerType = header.type;
  }

  /// 卸载：从 JS 引擎移除实例
  void unregister() {
    _entity?.unload();
    _entity = null;
  }

  /// 删除插件文件
  Future<void> delete() async {
    unregister();
    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// 调用插件方法
  Future<dynamic> invoke(String method, [List<dynamic> args = const []]) {
    if (_entity == null) {
      throw StateError('Plugin $name not registered');
    }
    return _entity!.invoke(method, args);
  }

  /// 插件是否声明了可配置的设置项（`settings` 字段非空）。
  Future<bool> hasSettings() async {
    if (_entity == null) return false;
    try {
      final raw = await _entity!.invoke('getSettings', const []);
      return raw is Map && raw.isNotEmpty;
    } catch (e) {
      WywLogger().d('${LogTag.plugin} 读取插件设置项失败（按无设置处理） name=$name', error: e);
      return false;
    }
  }

  /// 调方法 + 渲染 UI 描述符 → 直接返回 [List<Widget>]。
  ///
  /// 任何返回 `List<Map>` 描述符的 plugin 方法都能用：
  ///   - `plugin.invokeWidgets('search', [keyword])`
  ///   - `plugin.invokeWidgets('getDetail', [id])`
  ///
  /// [onAction] 是按钮点击回调（`UI.Button.onTap` 触发的 [UiAction]）；
  /// 不传则按钮渲染为 disabled。
  ///
  /// [onNavigate] 是导航回调（`UI.Button.onTap` 为 `UI.Navigate` 描述符时触发），
  /// page 层接收到后调用 `Modular.to.pushNamed` 等。
  ///
  /// [sourcePluginName] 透传给 renderer，用于 navigate 跳详情页时定位目标 plugin。
  ///
  /// **典型用法**：业务页面（如搜索页）一次性拿 Widget 直接渲染，
  /// 不再需要自己维护 `UiDescriptorRenderer` 实例和 `List<Map>` 中间数据。
  Future<List<Widget>> invokeWidgets(
    String method, {
    List<dynamic> args = const [],
    Future<void> Function(UiAction action)? onAction,
    Future<void> Function(UiNavigate nav, String sourcePluginName)? onNavigate,
    String? sourcePluginName,
  }) async {
    if (_entity == null) {
      throw StateError('Plugin $name not registered');
    }
    final raw = await _entity!.invoke(method, args);
    final renderer = UiDescriptorRenderer(
      onAction: onAction ?? _noAction,
      onNavigate: onNavigate,
      sourcePluginName: sourcePluginName ?? name,
    );
    return renderer.buildList(_normalizeUiList(raw));
  }

  static Future<void> _noAction(UiAction _) async {}

  /// 把 `invoke` 返回值规范化为 `List<Map>`（与 `search_engine` 同样容错）
  static List<Map<String, dynamic>> _normalizeUiList(dynamic raw) {
    if (raw == null) return const [];
    if (raw is! List) return const [];
    return raw.whereType<Map<String, dynamic>>().toList();
  }

  /// 从 JS 文件路径构造 Plugin
  static Future<Plugin> fromFile(String filePath) async {
    // 用 File.uri.pathSegments 取 basename，跨平台一致（URI 永远按 / 分隔）。
    final basename = File(filePath).uri.pathSegments.last;
    final name = basename.endsWith('.js')
        ? basename.substring(0, basename.length - 3)
        : basename;

    String description = '';
    PluginType headerType = PluginType.unknown;
    String? content;
    try {
      content = await File(filePath).readAsString();
      final header = _parseHeader(content);
      description = header.description;
      headerType = header.type;
    } catch (e, s) {
      WywLogger().w('${LogTag.plugin} 读取或解析插件文件失败 filePath=$filePath',
          error: e, stackTrace: s);
    }

    return Plugin(
      name: name,
      filePath: filePath,
      description: description,
      headerType: headerType,
      type: headerType,
      content: content,
    );
  }

  /// 从 in-memory content 构造 Plugin（不读盘）。
  ///
  /// 用于「先验证 JS、后落盘」流程——`PluginController.create()` 走这条路径，
  /// 避免 `Plugin.fromFile()` 在文件还不存在时抛 `FileSystemException`。
  static Plugin fromContent({
    required String name,
    required String filePath,
    required String content,
  }) {
    final header = _parseHeader(content);
    return Plugin(
      name: name,
      filePath: filePath,
      description: header.description,
      headerType: header.type,
      type: header.type,
      content: content,
    );
  }

  /// 从源码前 5 行解析头部元数据（`// description:` + `// type:`）。
  static ({String description, PluginType type}) _parseHeader(String content) {
    String description = '';
    PluginType type = PluginType.unknown;
    final lines = content.split('\n').take(5);
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('// description:')) {
        description = trimmed.substring('// description:'.length).trim();
      } else if (trimmed.startsWith('// type:')) {
        type = PluginType.parse(trimmed.substring('// type:'.length));
      }
    }
    return (description: description, type: type);
  }

  @override
  String toString() => 'Plugin($name, $filePath)';
}
