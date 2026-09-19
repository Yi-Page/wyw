// ignore_for_file: library_private_types_in_public_api

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:mobx/mobx.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wyw/js/production_script_engine.dart';
import 'package:wyw/plugins/plugin_config.dart';
import 'package:wyw/plugins/plugin_type.dart';
import 'package:wyw/services/logging/log_tags.dart';
import 'package:wyw/services/logging/logger.dart';

import '../../plugins/plugin.dart';

part 'plugin_controller.g.dart';

class PluginController = _PluginController with _$PluginController;

/// 统一插件控制器：文件 I/O + 运行时管理 + MobX 状态。
///
/// **单一数据源**：[plugins] 列表是唯一数据源，不再有 PluginRule + JsPlugin 冗余。
///
/// **职责**：
///   - 文件 I/O：扫描目录、创建/删除插件文件
///   - 运行时管理：注册/卸载/热重载插件
///   - UI 状态：MobX observable 供 UI 绑定
abstract class _PluginController with Store {
  final ProductionScriptEngine _engine = ProductionScriptEngine();
  final Map<String, Plugin> _plugins = {};
  Directory? _pluginDir;
  Directory? _appSupportDir;

  /// 插件管理配置（排序 / 禁用 / 分类覆盖 / 已删除内置插件）
  PluginConfig _config = PluginConfig();

  /// 内置插件名集合（`assets/plugin` 中内置的插件，不含 `.js`）。
  ///
  /// 每次启动由 [_syncBuiltinPlugins] 从 AssetManifest 重建。
  final Set<String> _builtinPluginNames = {};

  /// 可更新的内置插件名集合（内置内容与应用内文件内容不一致）。
  final Set<String> _updatablePluginNames = {};

  /// 可更新的内置插件名集合（UI 展示「可更新」标识）。
  Set<String> get updatablePluginNames => _updatablePluginNames;

  /// 是否为应用内置插件。
  bool isBuiltin(String name) => _builtinPluginNames.contains(name);

  /// 已禁用（未导入）插件名列表，供管理页「已禁用」分区展示。
  ///
  /// **非 observable**：它的每次变更都伴随 `plugins`（ObservableList）的增删，
  /// Observer 会随 `plugins` 重建后读到最新值；唯一例外是 [deleteDisabledPlugin]
  /// 会主动调用 [_notifyPluginsChanged] 触发刷新。
  final List<String> _disabledPluginNames = [];

  /// 已禁用（未导入）插件名列表
  List<String> get disabledPluginNames => _disabledPluginNames;

  // ===== MobX observable =====

  @observable
  ObservableList<Plugin> plugins = ObservableList<Plugin>.of([]);

  @observable
  bool initialized = false;

  @observable
  bool loading = false;

  @observable
  String? lastError;

  @observable
  String? selectedPluginName;

  /// 插件目录路径（用于 UI 显示）
  String? get pluginDirPath => _pluginDir?.path;

  // ===== 生命周期 =====

  @action
  Future<void> init() async {
    loading = true;
    try {
      await _engine.init();
      final appSupportDir = await getApplicationSupportDirectory();
      _appSupportDir = appSupportDir;
      _config = await PluginConfig.load(appSupportDir);
      _pluginDir = Directory('${appSupportDir.path}/plugins');
      if (!await _pluginDir!.exists()) {
        await _pluginDir!.create(recursive: true);
      }
      // 每次启动同步内置插件：未安装的复制并设为禁用；同名已装的比对内容、标记可更新
      await _syncBuiltinPlugins();
      await rescan();
      initialized = true;
    } catch (e, s) {
      lastError = e.toString();
      WywLogger().e('${LogTag.plugin} 插件控制器初始化失败', error: e, stackTrace: s);
    } finally {
      loading = false;
    }
  }

  /// 扫描目录并注册所有**启用**的 `.js` 文件。
  ///
  /// 被禁用的插件（在 `_config.disabled` 中）**不构造不注册**，只记录名字到
  /// [disabledPluginNames]；文件保留在磁盘，管理页可通过名称重新导入。
  @action
  Future<void> rescan() async {
    plugins.clear();
    _unregisterAll();
    _disabledPluginNames.clear();
    if (_pluginDir == null) return;

    final onDisk = <String>{};
    await for (final entity in _pluginDir!.list()) {
      if (entity is File && entity.path.endsWith('.js')) {
        final name = _nameFromPath(entity.path);
        onDisk.add(name);
        if (_config.disabled.contains(name)) {
          _disabledPluginNames.add(name);
          continue; // 禁用：不构造不注册
        }
        await _loadFromFile(entity.path);
      }
    }

    // 分类：用户覆盖 > JS 头声明 > 方法推断（此时启用插件已注册，hasMethod 可用）
    // 同时标注内置身份与「可更新」标识（由启动同步 [_syncBuiltinPlugins] 计算）
    for (final p in plugins.toList()) {
      p.type = _resolveType(p, _config.categories[p.name]);
      p.isBuiltin = _builtinPluginNames.contains(p.name);
      p.hasUpdate = _updatablePluginNames.contains(p.name);
    }

    // 按持久化顺序排序（新插件保持文件扫描顺序）
    _sortByOrder();

    // 修剪配置：以「磁盘文件集合」为准，保留禁用插件的 order 槽位
    _config.order = [
      ..._config.order.where(onDisk.contains),
      ...onDisk.where((n) => !_config.order.contains(n)),
    ];
    _config.disabled = _config.disabled.intersection(onDisk);
    _config.categories.removeWhere((k, _) => !onDisk.contains(k));
    _disabledPluginNames.sort(_compareByOrder);
    await _saveConfig();
  }

  /// 每次启动同步内置插件（`assets/plugin/`）到用户插件目录。
  ///
  /// 这是「首次启动检测安装」的扩展：现在**每次打开应用**都会执行——
  ///   - **系统内未安装**的内置插件：一律复制到用户目录并设为禁用（出现在管理页
  ///     「已禁用（未导入）」分区，用户可一键导入启用）。即使之前删除过，
  ///     下次启动仍会重新识别为禁用插件。
  ///   - **同名已装**插件：比对内容，不同则记入 [_updatablePluginNames]，
  ///     UI 据此展示「可更新」标识，并可通过 [updatePluginFromBuiltin] 更新。
  Future<void> _syncBuiltinPlugins() async {
    final dir = _pluginDir;
    if (dir == null) return;
    _builtinPluginNames.clear();
    _updatablePluginNames.clear();
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final builtinAssets = manifest
          .listAssets()
          .where((a) => a.startsWith('assets/plugin/') && a.endsWith('.js'))
          .toList();

      for (final assetPath in builtinAssets) {
        final fileName = assetPath.split('/').last;
        final name = _nameFromPath(fileName);
        _builtinPluginNames.add(name);

        final bundledContent = await rootBundle.loadString(assetPath);
        final target = File('${dir.path}/$fileName');

        if (!await target.exists()) {
          // 系统内未安装：复制 + 设为禁用
          await target.writeAsString(bundledContent);
          _config.disabled.add(name);
          if (!_config.order.contains(name)) {
            _config.order.add(name); // 保留排序槽位
          }
          WywLogger().i('${LogTag.plugin} 内置插件未安装，已复制并设为禁用 file=$fileName');
        } else if (await _contentDiffers(bundledContent, target)) {
          // 同名已装且内容不同：标记可更新
          _updatablePluginNames.add(name);
        }
      }
      await _saveConfig();
    } catch (e, s) {
      WywLogger().w('${LogTag.plugin} 内置插件同步失败', error: e, stackTrace: s);
    }
  }

  /// 比对内置内容与用户目录文件内容是否不一致（读文件失败视为不一致）。
  Future<bool> _contentDiffers(String bundledContent, File target) async {
    try {
      final installed = await target.readAsString();
      return installed != bundledContent;
    } catch (e) {
      WywLogger().d(
          '${LogTag.plugin} 读取已安装插件内容失败（已忽略，按内容不一致处理） file=${target.path}',
          error: e);
      return true;
    }
  }

  /// 判断某内置插件当前文件内容与内置资源是否不一致。
  ///
  /// 非内置插件始终返回 false。用于编辑/导入后刷新「可更新」标识。
  Future<bool> _builtinDiffers(String name) async {
    if (!_builtinPluginNames.contains(name)) return false;
    final file = File('${_pluginDir!.path}/$name.js');
    try {
      final bundled = await rootBundle.loadString('assets/plugin/$name.js');
      final installed = await file.readAsString();
      return installed != bundled;
    } catch (e) {
      WywLogger().d('${LogTag.plugin} 比对内置插件内容失败（已忽略） name=$name', error: e);
      return false;
    }
  }

  // ===== 私有辅助 =====

  /// 从文件路径提取插件名（去 .js）
  String _nameFromPath(String path) {
    final basename = File(path).uri.pathSegments.last;
    return basename.endsWith('.js')
        ? basename.substring(0, basename.length - 3)
        : basename;
  }

  /// 按 `_config.order` 重排 plugins（新插件保持文件扫描顺序追加末尾）。
  void _sortByOrder() {
    final byName = {for (final p in plugins) p.name: p};
    final ordered = <Plugin>[];
    for (final name in _config.order) {
      final p = byName.remove(name);
      if (p != null) ordered.add(p);
    }
    ordered.addAll(byName.values);
    plugins
      ..clear()
      ..addAll(ordered);
  }

  int _orderIndexOf(String name) {
    final i = _config.order.indexOf(name);
    return i < 0 ? _config.order.length : i;
  }

  int _compareByOrder(String a, String b) =>
      _orderIndexOf(a).compareTo(_orderIndexOf(b));

  /// 解析插件的生效分类：用户覆盖 > JS 头声明 > 方法推断。
  PluginType _resolveType(Plugin p, String? override) {
    if (override != null) {
      final t = PluginType.parse(override);
      if (t != PluginType.unknown) return t;
    }
    if (p.headerType != PluginType.unknown) return p.headerType;
    return _inferType(p);
  }

  /// 依据插件实现的方法推断分类（需插件已注册）。
  PluginType _inferType(Plugin p) {
    if (hasMethod(p.name, 'play')) return PluginType.video;
    if (hasMethod(p.name, 'openReader')) return PluginType.manga;
    if (hasMethod(p.name, 'openNovelReader')) return PluginType.novel;
    return PluginType.unknown;
  }

  /// 触发 ObservableList 通知（plugins 本身未变但需要 UI 刷新时用）。
  ///
  /// 直接整体重赋值：生成式 setter 的 `reportWrite` 会无条件通知，即使内容
  /// 相同、甚至列表为空也能触发 Observer 重建。
  void _notifyPluginsChanged() {
    plugins = ObservableList<Plugin>.of(plugins);
  }

  /// 写回配置（失败仅告警，不阻断业务）。
  Future<void> _saveConfig() async {
    final dir = _appSupportDir;
    if (dir == null) return;
    try {
      await _config.save(dir);
    } catch (e, s) {
      WywLogger().w('${LogTag.plugin} 保存插件配置失败', error: e, stackTrace: s);
    }
  }

  // ===== 文件 I/O =====

  /// 从文件加载插件
  Future<bool> _loadFromFile(String filePath) async {
    try {
      final plugin = await Plugin.fromFile(filePath);
      await plugin.register(_engine);
      _plugins[plugin.name] = plugin;
      plugins.add(plugin);
      return true;
    } catch (e, s) {
      WywLogger().w('${LogTag.plugin} 从文件加载插件失败 file=$filePath',
          error: e, stackTrace: s);
      return false;
    }
  }

  /// 添加新插件（通过文件路径）
  @action
  Future<bool> addItemFromPath({required String filePath}) async {
    return _loadFromFile(filePath);
  }

  /// 禁用插件：卸载引擎实例并从 plugins/_plugins 移除，**文件保留在磁盘**。
  ///
  /// 禁用后插件不再出现在 App（搜索页 tab / 管理页主列表），只在管理页
  /// 「已禁用」分区按名称可见。重新启用见 [enable]（快速重新导入）。
  Future<bool> disable(String name) async {
    final plugin = _plugins.remove(name);
    if (plugin == null) return false;
    plugin.unregister();
    runInAction(() {
      plugins.removeWhere((p) => p.name == name);
      _disabledPluginNames.add(name);
      _disabledPluginNames.sort(_compareByOrder);
    });
    _config.disabled.add(name);
    await _saveConfig();
    return true;
  }

  /// 重新启用（导入）被禁用的插件：按名称找到文件，构造 + 注册 + 恢复到原排序位置。
  Future<bool> enable(String name) async {
    if (_pluginDir == null) return false;
    final file = File('${_pluginDir!.path}/$name.js');
    if (!await file.exists()) {
      lastError = '文件不存在：$name';
      return false;
    }
    try {
      final ok = await _loadFromFile(file.path);
      if (!ok) {
        lastError = '导入失败：$name';
        return false;
      }
      _config.disabled.remove(name);
      runInAction(() {
        _disabledPluginNames.remove(name);
      });
      _sortByOrder(); // 恢复到 order 中保留的槽位
      final p = _plugins[name];
      if (p != null) {
        p.type = _resolveType(p, _config.categories[name]);
        p.isBuiltin = _builtinPluginNames.contains(name);
        p.hasUpdate = _updatablePluginNames.contains(name);
      }
      await _saveConfig();
      return true;
    } catch (e, s) {
      lastError = '导入失败：$e';
      WywLogger()
          .e('${LogTag.plugin} 启用插件失败 name=$name', error: e, stackTrace: s);
      return false;
    }
  }

  /// 手动设置插件分类（覆盖 JS 头声明）。
  ///
  /// [type] 传 null / 空字符串表示清除覆盖，回退到 `// type:` 声明或方法推断。
  Future<void> setCategory(String name, String? type) async {
    if (type == null || type.isEmpty) {
      _config.categories.remove(name);
    } else {
      _config.categories[name] = type;
    }
    final p = _plugins[name];
    if (p != null) {
      p.type = _resolveType(p, _config.categories[name]);
    }
    _notifyPluginsChanged(); // type 非 observable，主动触发刷新
    await _saveConfig();
  }

  /// 删除已禁用插件的文件（真正卸载，不可恢复）。
  ///
  /// 内置插件（`assets/plugin`）不可删除：删除后下次启动 [init] 仍会重新
  /// 复制并设为禁用，删除无意义，因此直接拒绝。
  Future<bool> deleteDisabledPlugin(String name) async {
    if (_builtinPluginNames.contains(name)) {
      lastError = '内置插件无法删除，只能禁用或导入';
      return false;
    }
    if (_pluginDir == null) return false;
    final file = File('${_pluginDir!.path}/$name.js');
    try {
      if (await file.exists()) await file.delete();
      _config.disabled.remove(name);
      _config.order.remove(name);
      _config.categories.remove(name);
      _updatablePluginNames.remove(name);
      runInAction(() {
        _disabledPluginNames.remove(name);
      });
      _notifyPluginsChanged(); // plugins 未变，主动触发刷新禁用分区
      await _saveConfig();
      return true;
    } catch (e, s) {
      lastError = e.toString();
      WywLogger()
          .e('${LogTag.plugin} 删除已禁用插件失败 name=$name', error: e, stackTrace: s);
      return false;
    }
  }

  /// 创建新插件
  ///
  /// 流程：凭空构造 → JS 注册验证 → 通过后才落盘。
  /// 验证失败时**不写文件**，错误信息（JS SyntaxError / class not found 等）原样
  /// 写入 [lastError] 供 UI 展示。
  @action
  Future<Plugin?> create(String name, String content) async {
    lastError = null;
    if (_pluginDir == null) {
      lastError = '插件目录未初始化';
      return null;
    }
    try {
      final filePath = '${_pluginDir!.path}/$name.js';

      // 1) 凭空构造 + 注册验证（不读盘——文件还没写）
      final plugin = Plugin.fromContent(
        name: name,
        filePath: filePath,
        content: content,
      );
      await plugin.register(_engine);

      // 2) 验证通过后再落盘
      await File(filePath).writeAsString(content);

      // 3) 加入状态
      _plugins[plugin.name] = plugin;
      plugins.add(plugin);
      plugin.type = _resolveType(plugin, _config.categories[plugin.name]);
      _config.order.add(plugin.name); // 追加到顺序末尾
      unawaited(_saveConfig());

      return plugin;
    } catch (e, s) {
      lastError = e.toString();
      WywLogger()
          .e('${LogTag.plugin} 创建插件失败 name=$name', error: e, stackTrace: s);
      return null;
    }
  }

  /// 更新插件内容并热重载
  @action
  Future<bool> updateItem({
    required String name,
    required String content,
  }) async {
    lastError = null;
    final plugin = _plugins[name];
    if (plugin == null) {
      lastError = '插件不存在：$name';
      return false;
    }
    try {
      await plugin.writeContent(content);
      await plugin.reload(_engine);
      // reload 后重新解析生效分类（reload 内部已刷新 headerType）
      plugin.type = _resolveType(plugin, _config.categories[plugin.name]);
      // 编辑后重新比对内置内容，刷新「可更新」标识
      plugin.isBuiltin = _builtinPluginNames.contains(name);
      plugin.hasUpdate = await _builtinDiffers(name);
      if (plugin.hasUpdate) {
        _updatablePluginNames.add(name);
      } else {
        _updatablePluginNames.remove(name);
      }
      return true;
    } catch (e, s) {
      lastError = e.toString();
      WywLogger()
          .e('${LogTag.plugin} 更新插件内容失败 name=$name', error: e, stackTrace: s);
      return false;
    }
  }

  /// 用内置版本更新插件内容（覆盖用户目录文件）。
  ///
  /// - 已启用插件：覆盖文件 + 热重载 + 刷新元数据/分类；
  /// - 已禁用插件：仅覆盖文件（下次导入时读取新内容）；
  /// 成功后该插件从「可更新」集合移除，下次启动不会再被标记。
  Future<bool> updatePluginFromBuiltin(String name) async {
    if (_pluginDir == null) return false;
    final assetPath = 'assets/plugin/$name.js';
    String bundledContent;
    try {
      bundledContent = await rootBundle.loadString(assetPath);
    } catch (e) {
      lastError = '内置资源不存在：$name';
      return false;
    }
    try {
      final file = File('${_pluginDir!.path}/$name.js');
      await file.writeAsString(bundledContent);

      _updatablePluginNames.remove(name);

      final plugin = _plugins[name];
      if (plugin != null) {
        plugin.isBuiltin = true;
        plugin.hasUpdate = false;
        await plugin.reload(_engine);
        plugin.type = _resolveType(plugin, _config.categories[plugin.name]);
      }
      _notifyPluginsChanged();
      await _saveConfig();
      return true;
    } catch (e, s) {
      lastError = e.toString();
      WywLogger().e('${LogTag.plugin} 用内置版本更新插件失败 name=$name',
          error: e, stackTrace: s);
      return false;
    }
  }

  /// 删除插件（仅限非内置插件）。
  ///
  /// 内置插件（`assets/plugin`）不可删除：删除后下次启动 [init] 仍会重新
  /// 复制并设为禁用，删除无意义，因此直接拒绝。
  @action
  Future<bool> removeItem(String name) async {
    lastError = null;
    if (_builtinPluginNames.contains(name)) {
      lastError = '内置插件无法删除，只能禁用';
      return false;
    }
    final plugin = _plugins[name];
    if (plugin == null) return false;
    try {
      await plugin.delete();
      _plugins.remove(name);
      plugins.removeWhere((p) => p.name == name);
      _config.order.remove(name);
      _config.disabled.remove(name);
      _config.categories.remove(name);
      _updatablePluginNames.remove(name);
      runInAction(() {
        _disabledPluginNames.remove(name);
      });
      if (selectedPluginName == name) {
        selectedPluginName = null;
      }
      unawaited(_saveConfig());
      return true;
    } catch (e, s) {
      lastError = e.toString();
      WywLogger()
          .e('${LogTag.plugin} 删除插件失败 name=$name', error: e, stackTrace: s);
      return false;
    }
  }

  /// 拖拽排序（修改内存顺序并持久化）
  @action
  void reorder(int oldIndex, int newIndex) {
    // onReorderItem 的 newIndex 已按移除 oldIndex 调整，直接插入。
    final item = plugins.removeAt(oldIndex);
    plugins.insert(newIndex, item);
    _config.order = plugins.map((p) => p.name).toList();
    unawaited(_saveConfig()); // 拖拽结束落盘
  }

  /// 选中插件
  @action
  void select(String? name) {
    selectedPluginName = name;
  }

  // ===== 运行时查询 =====

  /// 按名称获取插件
  Plugin? getPlugin(String name) => _plugins[name];

  /// 读取插件源网站地址：调插件固定方法 `getUrl()`，返回非空网址才有效。
  /// 插件未实现 getUrl 或返回空时返回 null。
  Future<String?> getPluginUrl(String pluginName) async {
    if (!hasMethod(pluginName, 'getUrl')) return null;
    final plugin = _plugins[pluginName];
    if (plugin == null || !plugin.isRegistered) return null;
    try {
      final result = await plugin.invoke('getUrl', const []);
      if (result is String && result.isNotEmpty) return result;
    } catch (e) {
      WywLogger()
          .d('${LogTag.plugin} 调用 getUrl 失败（已忽略） plugin=$pluginName', error: e);
    }
    return null;
  }

  /// 检查插件是否有某方法
  bool hasMethod(String pluginName, String methodName) {
    final plugin = _plugins[pluginName];
    if (plugin == null || !plugin.isRegistered) return false;
    try {
      final result = _engine.evaluate(
        'typeof __plugins__.$pluginName.$methodName === "function"',
        name: '<plugin-hasMethod:$pluginName.$methodName>',
      );
      return result == true;
    } catch (e) {
      WywLogger().d(
          '${LogTag.plugin} 检查插件方法存在性失败（已忽略） plugin=$pluginName method=$methodName',
          error: e);
      return false;
    }
  }

  /// 浏览历史点击入口：调用插件里固定名称 `onOpenBrowseEntry(entryJson)`。
  ///
  /// 由 `PluginHistoryCard` 点击触发；参数是历史 entry 的 JSON 描述，
  /// 插件可以读取 `id/kv` 自行决定回放路径。
  @action
  Future<bool> openBrowseEntry({
    required String pluginName,
    required Map<String, dynamic> entryJson,
  }) async {
    final plugin = _plugins[pluginName];
    if (plugin == null || !plugin.isRegistered) {
      WywLogger().w('${LogTag.plugin} 插件未注册，无法打开浏览历史 plugin=$pluginName');
      return false;
    }
    if (!hasMethod(pluginName, 'onOpenBrowseEntry')) {
      WywLogger()
          .w('${LogTag.plugin} 插件未实现 onOpenBrowseEntry plugin=$pluginName');
      return false;
    }
    try {
      await plugin.invoke('onOpenBrowseEntry', [entryJson]);
      return true;
    } catch (e, s) {
      WywLogger().e('${LogTag.plugin} 打开浏览历史失败 plugin=$pluginName',
          error: e, stackTrace: s);
      return false;
    }
  }

  // ===== 私有辅助 =====

  void _unregisterAll() {
    for (final plugin in _plugins.values.toList()) {
      plugin.unregister();
    }
    _plugins.clear();
  }
}
