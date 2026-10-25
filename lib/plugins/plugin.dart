import 'dart:io';

import 'package:flutter/material.dart';
import 'package:wyw/js/base_js_engine.dart';
import 'package:wyw/js/entity/js_entity.dart';
import 'package:wyw/js/js_extends/js_descriptor.dart';
import 'package:wyw/js/js_extends/js_descriptor_renderer.dart';
import 'package:wyw/plugins/plugin_bundle.dart';
import 'package:wyw/plugins/plugin_category.dart';
import 'package:wyw/plugins/plugin_source.dart';
import 'package:wyw/services/logging/log_tags.dart';
import 'package:wyw/services/logging/logger.dart';

/// 插件前置校验失败（命名链 / 类声明形态不合法，或目标文件已被占用）。
/// 文案可直接展示给用户。
class PluginSourceError implements Exception {
  const PluginSourceError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 插件在宿主里的存在状态。
enum PluginPresence {
  /// 已加载可用
  loaded,

  /// 已禁用：文件保留，可重新导入
  disabled,

  /// 加载失败：文件在，但注册到引擎时抛错
  failed,

  /// 文件缺失：记录还在（顺序与用户字段都保得住），磁盘上没有 `{name}.js`
  missing,

  /// 已删除：文件与记录都没了
  deleted,
}

/// 详情页「管理属性」里用户可直接改的字段。
///
/// **名字不在其中** —— 它是唯一标识（文件名 / 类名 / 引擎槽位），不可改。
enum PluginField { displayName, categoryId, homepage, description }

/// 插件：一条 `index.json` 记录 + 它的文件 + 它的 JS 实例。
///
/// **个体语义全部归本类** —— 凡是只靠插件自己的数据就能算出来的都写在这里：文件读写、
/// 源码校验、安装 / 更新 / 修复、注册与调用、能力探测、分类推断、状态判定、字段读写。
/// 宿主 `PluginController` 只管**集合**：谁该存在、按什么顺序、失败怎么记账。
///
/// 名字是唯一标识且不可变：文件名去 `.js` = 索引键 = JS 类名 = 引擎槽位
/// `__plugins__[name]`，四环逐字符相同（见 `docs/plugin-storage-spec.md`）。
class Plugin {
  /// 插件文件固定目录（`<appSupport>/plugins`），启动时设一次；测试里指临时目录。
  static String directory = '';

  Plugin({
    required this.name,
    this.enabled = true,
    this.displayName = '',
    this.categoryId = '',
    this.homepage = '',
    this.description = '',
    this.entity,
  });

  // ===== 持久化字段：index.json 里就写这六个 =====

  /// 唯一标识，不可变（改名 = 导出后以新名字导入）。
  final String name;

  /// 禁用 = 文件保留、不构造不注册。
  bool enabled;

  /// 展示名，空则回落到 [name]。
  String displayName;

  /// 分类 id，空则按 [inferredCategory] 显示。
  String categoryId;

  String homepage;

  String description;

  // ===== 运行时状态：不落盘 =====

  /// JS 代码与实例的持有者；null = 未加载。
  JsEntity? entity;

  /// 记录在、磁盘上没有 `{name}.js`。不注册，补回文件即恢复（见 [repairMissing]）。
  bool fileMissing = false;

  /// 注册失败原因；null = 没失败过。
  String? loadError;

  /// 自查出的分类（`categoryId` 为空时用它）。见 [refreshCategory]。
  PluginCategory? inferredCategory;

  /// 能力探测缓存：`null` = 尚未探测。探测要打引擎，所以缓存；内容变了要作废。
  bool? _hasSettings;
  String? _sourceUrl;

  bool get hasSettingsCached => _hasSettings ?? false;

  String? get cachedSourceUrl => _sourceUrl;

  /// 已探测过（无论结果）。
  bool get capabilitiesProbed => _hasSettings != null;

  // ===== 派生 =====

  /// 文件名（命名链第 1 环）。
  String get fileName => '$name.js';

  /// 文件绝对路径 = 固定目录 + 文件名。
  String get filePath => '$directory/$fileName';

  String get title => displayName.isEmpty ? name : displayName;

  bool get isLoaded => entity != null;

  /// 存在状态：全部来自本对象自己的字段。
  PluginPresence get presence {
    if (fileMissing) return PluginPresence.missing;
    if (!enabled) return PluginPresence.disabled;
    if (loadError != null) return PluginPresence.failed;
    return PluginPresence.loaded;
  }

  /// 读一个用户可编辑字段。
  String fieldValue(PluginField field) => switch (field) {
        PluginField.displayName => displayName,
        PluginField.categoryId => categoryId,
        PluginField.homepage => homepage,
        PluginField.description => description,
      };

  /// 写一个用户可编辑字段（只改内存；落盘由宿主统一负责）。
  void setField(PluginField field, String value) {
    final text = value.trim();
    switch (field) {
      case PluginField.displayName:
        displayName = text;
      case PluginField.categoryId:
        categoryId = text;
      case PluginField.homepage:
        homepage = text;
      case PluginField.description:
        description = text;
    }
  }

  // ===== 文件 =====

  Future<String> readSource() => File(filePath).readAsString();

  Future<bool> exists() => File(filePath).exists();

  /// **裸写**：不校验、不注册、不动 [entity]。只给出厂载荷这类内容已可信的场景用。
  Future<void> writeSource(String content) =>
      File(filePath).writeAsString(content);

  /// 把磁盘上拼写为 [actualFileName] 的文件改名为自己的 [fileName]（大小写对齐）。
  ///
  /// 文件系统大小写不敏感而 JS 类名敏感，所以索引里的拼写是权威。返回是否真的改过名。
  Future<bool> alignFileName(String actualFileName) async {
    if (actualFileName == fileName) return false;
    try {
      // 比对文件名而不是完整路径：目录枚举的分隔符与 [filePath] 未必一致
      await File('$directory${Platform.pathSeparator}$actualFileName')
          .rename(filePath);
      WywLogger()
          .w('${LogTag.plugin} 文件名大小写已对齐：$actualFileName → $fileName');
      return true;
    } catch (e, s) {
      WywLogger().w('${LogTag.plugin} 对齐文件名大小写失败 name=$name',
          error: e, stackTrace: s);
      return false;
    }
  }

  /// 删除文件（先卸载）。
  Future<void> delete() async {
    unregister();
    final file = File(filePath);
    if (await file.exists()) await file.delete();
  }

  Future<void> _deleteQuietly() async {
    try {
      final file = File(filePath);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // 回滚路径：删不掉不影响向上抛原始错误
    }
  }

  /// 导出成导入包条目；文件不在返回 null（禁用 / 加载失败的也能导出）。
  Future<PluginBundleEntry?> exportEntry() async {
    if (!await exists()) return null;
    return PluginBundleEntry(name: name, content: await readSource());
  }

  /// 从路径 / 文件名反推插件名（去掉 `.js`）。
  static String nameFromFilePath(String path) {
    final basename = File(path).uri.pathSegments.last;
    return basename.endsWith('.js')
        ? basename.substring(0, basename.length - 3)
        : basename;
  }

  // ===== 源码校验 =====

  /// 转发 [PluginSourceRule.check]：类名必须逐字符等于插件名。
  /// 宿主侧所有校验都走这里，不直接调规则类。
  PluginSourceCheck checkSource(String content) =>
      PluginSourceRule.check(source: content, pluginName: name);

  void _requireValidSource(String content) {
    final check = checkSource(content);
    if (!check.ok) throw PluginSourceError(check.message!);
  }

  // ===== 生命周期 =====

  /// 读盘 → 校验 → 建实例并挂到引擎。
  ///
  /// 失败时 [entity] 保持 null，不留「isLoaded 为真但引擎里没有实例」的假就绪。
  Future<void> register(BaseJsEngine engine) async {
    final content = await readSource();
    _requireValidSource(content);
    entity?.unload();
    final created = JsEntity(
      className: name,
      entityPath: '__plugins__',
      entityName: name,
      engine: engine,
      content: content,
    );
    try {
      await created.register();
    } catch (_) {
      entity = null;
      rethrow;
    }
    entity = created;
  }

  /// 热重载：卸载旧实例 → 重新读盘 → 重新注册。
  Future<void> reload(BaseJsEngine engine) async {
    entity?.unload();
    entity = null;
    await register(engine);
  }

  /// 卸载：从引擎移除实例（文件与记录都保留）。
  void unregister() {
    entity?.unload();
    entity = null;
  }

  // ===== 代码落盘：校验 + 写盘 + 注册是一个事务 =====
  //
  // 改插件代码只有这三个入口。调用方负责集合级判断（名字合法、折叠唯一）与失败记账。

  /// 首次安装。注册失败会把刚写出的文件删掉，不留半成品。
  ///
  /// [adoptExisting]：目标文件已在磁盘上（管理页「未导入」清单里的野文件）——
  /// 认领它而不是报冲突；认领来的文件注册失败**不删**（它本来就是用户的东西）。
  Future<void> install(
    String content,
    BaseJsEngine engine, {
    bool adoptExisting = false,
  }) async {
    _requireValidSource(content);
    if (!adoptExisting && await exists()) {
      throw PluginSourceError('同名插件文件已存在：$fileName');
    }
    await writeSource(content);
    try {
      await register(engine);
    } catch (_) {
      if (!adoptExisting) await _deleteQuietly();
      rethrow;
    }
  }

  /// 覆盖更新：写盘；已启用才热重载（禁用中只改文件，否则引擎里会凭空多一个实例）。
  ///
  /// ⚠️ 热重载失败**不回滚**磁盘内容（新代码已落盘，旧代码没有备份）。
  Future<void> updateSource(String content, BaseJsEngine engine) async {
    _requireValidSource(content);
    await writeSource(content);
    if (enabled) await reload(engine);
  }

  /// 补回缺失的文件（[fileMissing] 为真）。已启用才注册，成功后清掉标记。
  Future<void> repairMissing(String content, BaseJsEngine engine) async {
    _requireValidSource(content);
    await writeSource(content);
    if (enabled) await register(engine);
    fileMissing = false;
  }

  // ===== 调用 =====

  Future<dynamic> invoke(String method, [List<dynamic> args = const []]) {
    final target = entity;
    if (target == null) throw StateError('Plugin $name not registered');
    return target.invoke(method, args);
  }

  /// 调方法 + 把 UI 描述符渲染成 [Widget] 列表（任何返回 `List<Map>` 的方法都能用）。
  ///
  /// [onAction] 是按钮回调；[onNavigate] 是导航回调，由 page 层实现跳转。
  Future<List<Widget>> invokeWidgets(
    String method, {
    List<dynamic> args = const [],
    Future<void> Function(UiAction action)? onAction,
    Future<void> Function(UiNavigate nav, String sourcePluginName)? onNavigate,
    String? sourcePluginName,
  }) async {
    final target = entity;
    if (target == null) throw StateError('Plugin $name not registered');
    final raw = await target.invoke(method, args);
    final renderer = UiDescriptorRenderer(
      onAction: onAction ?? _noAction,
      onNavigate: onNavigate,
      sourcePluginName: sourcePluginName ?? name,
    );
    return renderer.buildList(_normalizeUiList(raw));
  }

  /// 插件**自己**实现了 [method] 吗？基类成员不算；赋成非函数 = 显式关掉该能力。
  /// 未加载 / 求值出错一律 false，所以调用方不需要 try/catch。
  Future<bool> implementsMethod(String method) async {
    final target = entity;
    if (target == null) return false;
    try {
      return await target.invoke('implementsMethod', [method]) == true;
    } catch (e) {
      WywLogger().d(
          '${LogTag.plugin} 能力探测失败（按不支持处理） name=$name method=$method',
          error: e);
      return false;
    }
  }

  // ===== 能力、设置项、分类 =====

  /// 设置项 schema：插件有 `getSettings()` 就用它，否则读它的 `settings` 字段。
  /// 两条路都返回空表 = 没有设置项。
  Future<Map<String, dynamic>> readSettingsSchema() async {
    final target = entity;
    if (target == null) return const {};
    try {
      final Object? raw;
      if (await implementsMethod('getSettings')) {
        raw = await target.invoke('getSettings', const []);
      } else {
        // flutter_qjs 对普通对象是深转换，直接 evaluate 就是 Map，无需 JSON 往返
        raw = target.engine.evaluate(
          '${target.entityFullPath}.settings || {}',
          name: '<plugin-settings:$name>',
        );
      }
      return raw is Map ? Map<String, dynamic>.from(raw) : const {};
    } catch (e) {
      WywLogger().d('${LogTag.plugin} 读取插件设置项失败（按无设置处理） name=$name',
          error: e);
      return const {};
    }
  }

  Future<bool> hasSettings() async => (await readSettingsSchema()).isNotEmpty;

  /// 插件声明的源站地址（固定方法 `getUrl()`）；没有就 null。
  Future<String?> fetchSourceUrl() async {
    if (!await implementsMethod('getUrl')) return null;
    try {
      final result = await invoke('getUrl', const []);
      if (result is String && result.isNotEmpty) return result;
    } catch (e) {
      WywLogger().d('${LogTag.plugin} 调用 getUrl 失败（已忽略） name=$name',
          error: e);
    }
    return null;
  }

  /// 探测设置项与源站地址并缓存。未加载时直接缓存「没有」。
  Future<void> probeCapabilities() async {
    if (entity == null) {
      _hasSettings = false;
      _sourceUrl = null;
      return;
    }
    _hasSettings = (await readSettingsSchema()).isNotEmpty;
    _sourceUrl = await fetchSourceUrl();
  }

  /// 内容或加载状态变了：缓存作废（宿主在注册 / 编辑 / 禁用 / 删除后调用）。
  void invalidateCapabilities() {
    _hasSettings = null;
    _sourceUrl = null;
  }

  /// 按实现的方法推断分类：`play` → 视频，`openReader` → 漫画，`openNovelReader` → 小说。
  Future<PluginCategory> inferCategory() async {
    if (await implementsMethod('play')) return PluginCategory.video;
    if (await implementsMethod('openReader')) return PluginCategory.manga;
    if (await implementsMethod('openNovelReader')) return PluginCategory.novel;
    return PluginCategory.unknown;
  }

  /// 重算 [inferredCategory]（`categoryId` 已填时清掉缓存）。
  Future<void> refreshCategory() async {
    if (categoryId.trim().isNotEmpty) {
      inferredCategory = null;
      return;
    }
    inferredCategory = await inferCategory();
  }

  static Future<void> _noAction(UiAction _) async {}

  /// 把 `invoke` 返回值规范化为 `List<Map>`（与 search_engine 同样容错）。
  static List<Map<String, dynamic>> _normalizeUiList(dynamic raw) {
    if (raw is! List) return const [];
    return raw.whereType<Map<String, dynamic>>().toList();
  }

  // ===== 序列化 =====

  /// 只写持久化的六个字段。
  Map<String, dynamic> toJson() => {
        'name': name,
        'enabled': enabled,
        'displayName': displayName,
        'categoryId': categoryId,
        'homepage': homepage,
        'description': description,
      };

  /// 绝不抛异常：畸形字段退化为默认值，`name` 缺失才返回 null。
  static Plugin? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final name = _text(raw['name']);
    if (name.isEmpty) return null;
    return Plugin(
      name: name,
      enabled: raw['enabled'] is bool ? raw['enabled'] as bool : true,
      displayName: _text(raw['displayName']),
      categoryId: _text(raw['categoryId']),
      homepage: _text(raw['homepage']),
      description: _text(raw['description']),
    );
  }

  static RegExp get namePattern => PluginNameRules.pattern;

  /// 校验插件名；合法返回 null，否则返回可直接展示给用户的错误信息。
  static String? validateName(String name) => PluginNameRules.validate(name);

  @override
  String toString() => 'Plugin($name, enabled=$enabled, title=$title)';
}

/// 一条**没有对应 [Plugin] 记录**的磁盘文件（文件名非法 / 未导入）。
///
/// 由控制器在扫描时收集，管理页据此展示原因并提供导入 / 删除入口 ——
/// 没有它的话，这类文件既不在列表里也没有任何提示，等于静默消失。
class PluginLoadFailure {
  const PluginLoadFailure({
    required this.name,
    required this.filePath,
    required this.message,
  });

  /// 文件名去 `.js`
  final String name;

  /// JS 文件绝对路径
  final String filePath;

  /// 失败原因（原样透传给用户排查）
  final String message;

  @override
  String toString() => 'PluginLoadFailure($name, $message)';
}

/// 去空白（空串与缺失等价，都归一为 `''`）
String _text(Object? value) => value?.toString().trim() ?? '';
