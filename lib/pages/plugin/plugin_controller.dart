// ignore_for_file: library_private_types_in_public_api

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:mobx/mobx.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wyw/js/production_script_engine.dart';
import 'package:wyw/plugins/plugin.dart';
import 'package:wyw/plugins/plugin_bundle.dart';
import 'package:wyw/plugins/plugin_category.dart';
import 'package:wyw/plugins/plugin_category_index.dart';
import 'package:wyw/plugins/plugin_display_mode.dart';
import 'package:wyw/plugins/plugin_index.dart';
import 'package:wyw/plugins/plugin_operation.dart';
import 'package:wyw/plugins/plugin_source.dart';
import 'package:wyw/services/logging/log_tags.dart';
import 'package:wyw/services/logging/logger.dart';
import 'package:wyw/services/storage/storage.dart';

part 'plugin_controller.g.dart';

/// 出厂安装包（asset）目录：`index.json` 是配置，`{name}.js` 是每条记录的载荷。
const String _pluginSeedDir = 'assets/plugin/';

/// 出厂配置。与运行时 `index.json` 同格式，只在设备上一个插件都没有时用一次。
const String _pluginSeedIndex = '${_pluginSeedDir}index.json';

class PluginController = _PluginController with _$PluginController;

/// [PluginReconciliation.of] 的返回值：记录与文件之间的三种关系。
/// 后两种**不删任何东西**，只是换个地方报出来。
class PluginReconciliation {
  const PluginReconciliation({
    required this.records,
    required this.missingFiles,
    required this.orphanFiles,
  });

  /// 对账：以 [records] 的顺序与字段为基准，把 [onDiskNames] 分成三类。
  ///
  /// 文件没了 → 记录**原样保留**（顺序与用户填的展示名 / 分类 / 主页 / 简介只存在于
  /// 记录里，丢掉就没了）；磁盘多出来的 → 记成孤儿。**两种都不删东西。** 纯函数，无 I/O。
  static PluginReconciliation of(
    List<Plugin> records,
    Set<String> onDiskNames,
  ) {
    final recordNames = {for (final record in records) record.name};
    return PluginReconciliation(
      records: List<Plugin>.of(records),
      missingFiles: recordNames.difference(onDiskNames),
      orphanFiles: onDiskNames.difference(recordNames).toList()..sort(),
    );
  }

  /// 全部记录，顺序原样 = 显示顺序。文件没了的**也在里面**。
  final List<Plugin> records;

  /// 记录在、磁盘上没有对应文件（调用方据此标 [Plugin.fileMissing]）。
  final Set<String> missingFiles;

  /// 磁盘上有、索引里没有（已排序）。不删文件，也不自动追加记录。
  final List<String> orphanFiles;

  bool get hasMissingFiles => missingFiles.isNotEmpty;

  bool get hasOrphanFiles => orphanFiles.isNotEmpty;

  @override
  String toString() => 'PluginReconciliation(${records.length} 条, '
      '缺文件 ${missingFiles.length}, 未导入 ${orphanFiles.length})';
}

/// 插件控制器：**只做集合语义** —— 谁该存在、按什么顺序、注册谁、失败怎么记。
///
/// 个体语义（文件、校验、安装 / 更新、注册、调用、能力探测、分类推断）全在 [Plugin] 上，
/// 这里只负责调用它并把结果写进 MobX 状态。
///
/// **单一数据源**：[plugins] —— 顺序 = 显示顺序 = `index.json` 数组顺序。
///
/// **索引与磁盘互为边界，谁都不许单方面抹掉对方**：磁盘多出来的文件进
/// [unimportedFiles]（不自动运行、也不删文件），记录缺的文件标 [Plugin.fileMissing]
/// （不丢顺序与用户字段、也不伪造空文件）。
///
/// **[rescan] 不写索引**：它只产出内存态，`index.json` 只在用户显式操作时落盘。
abstract class _PluginController with Store {
  final ProductionScriptEngine _engine = ProductionScriptEngine();
  Directory? _pluginDir;

  // ===== MobX observable =====

  /// **全应用唯一的插件存储**。顺序 = 显示顺序 = `index.json` 数组顺序。
  ///
  /// 插件的一切状态都活在这个列表里的实例上；其他地方（收藏条目、搜索 tab、播放历史、
  /// 各页面）只保存**插件名**，用时通过 [pluginByName] / [getPlugin] 解析回这里的实例。
  /// 新增 / 更新走 [updatePlugin]（替换那一条或追加），删除走 [deletePlugin]。
  @observable
  ObservableList<Plugin> plugins = ObservableList<Plugin>.of([]);

  @observable
  bool initialized = false;

  @observable
  bool loading = false;

  /// `index.json` 读不懂（内容坏了）。**不等于**「没有插件」，所以不走出厂安装、也不动磁盘。
  @observable
  bool indexCorrupt = false;

  /// 文件名不合法、连记录都建不了的文件（纯内存，只能提示 + 删除）。
  final ObservableList<PluginLoadFailure> invalidFiles =
      ObservableList<PluginLoadFailure>.of([]);

  /// 磁盘上有合法 `.js`、但索引里没有它的记录（纯内存，用户决定导入还是删除）。
  final ObservableList<PluginLoadFailure> unimportedFiles =
      ObservableList<PluginLoadFailure>.of([]);

  // ===== 路径与查询 =====

  /// 插件目录路径（用于 UI 显示）
  String? get pluginDirPath => _pluginDir?.path;

  /// 插件索引文件路径（用于 UI 显示）
  String? get indexPath =>
      _pluginDir == null ? null : '${_pluginDir!.path}/$pluginIndexFileName';

  /// 分类索引文件路径（用于 UI 显示）
  String? get categoriesPath => _pluginDir == null
      ? null
      : '${_pluginDir!.path}/$categoryIndexFileName';

  /// 按名字取插件，**任何状态都拿得到**（禁用 / 加载失败也在列表里）。
  Plugin? pluginByName(String name) {
    for (final plugin in plugins) {
      if (plugin.name == name) return plugin;
    }
    return null;
  }

  /// 大小写折叠查询（文件系统不敏感，写盘前必须用它查重）。
  Plugin? pluginByNameFold(String name) {
    final key = PluginNameFold.of(name);
    for (final plugin in plugins) {
      if (PluginNameFold.of(plugin.name) == key) return plugin;
    }
    return null;
  }

  /// 取**已就绪**的插件（实例在引擎里，可以调方法）；禁用 / 加载失败返回 null。
  ///
  /// UI 要展示「任何状态」的插件请用 [pluginByName]。
  Plugin? getPlugin(String name) {
    final plugin = pluginByName(name);
    return plugin != null && plugin.isLoaded ? plugin : null;
  }

  /// 已就绪的插件列表（顺序同 [plugins]）。
  ///
  /// 搜索 / 浏览这类**要真的调插件方法**的地方一律用它；直接遍历 [plugins] 会撞上
  /// 禁用与加载失败的条目（[Plugin.invoke] 会抛 `Plugin xxx not registered`）。
  List<Plugin> get readyPlugins => [
        for (final plugin in plugins)
          if (plugin.isLoaded) plugin,
      ];

  /// 是否加载失败（有记录、但注册到引擎时抛错）。
  bool isFailed(String name) => pluginByName(name)?.loadError != null;

  // ===== 分类 =====

  /// 分类注册表（内置分类 + 用户自定义分类）。**只读**；变更走 add/update/remove 那几个方法。
  @observable
  PluginCategoryRegistry categories = PluginCategoryRegistry();

  /// 用户**显式创建**的自定义分类，顺序 = `categories.json` 数组顺序。
  final List<CustomCategory> _customCategories = [];

  List<CustomCategory> get customCategories =>
      List<CustomCategory>.unmodifiable(_customCategories);

  /// 插件的生效分类：填了 `categoryId` 就查表，否则用它自查出的 [Plugin.inferredCategory]。
  PluginCategory categoryOf(Plugin plugin) {
    final id = plugin.categoryId.trim();
    if (id.isNotEmpty) return categories.resolve(id);
    return plugin.inferredCategory ?? PluginCategory.unknown;
  }

  // ===== 名称显示 =====

  /// 名称显示方式。**只读**；变更走 [setPluginNameDisplay]。
  @observable
  String pluginNameDisplay = PluginNameDisplayMode.display;

  /// 当前是否使用展示名（设置页读它来显示选中项）。
  bool get useDisplayName =>
      pluginNameDisplay != PluginNameDisplayMode.identity;

  /// 切换插件名称显示方式（设置页调用）。
  Future<void> setPluginNameDisplay(String mode) async {
    final normalized = mode == PluginNameDisplayMode.identity
        ? PluginNameDisplayMode.identity
        : PluginNameDisplayMode.display;
    if (pluginNameDisplay == normalized) return;
    pluginNameDisplay = normalized;
    await GStorage.putSetting(SettingsKeys.pluginNameDisplay, normalized);
  }

  /// 插件的**展示名** —— UI 一律用这个，不要直接渲染 [Plugin.name]。
  ///
  /// ⚠️ **插件名（[Plugin.name]）是唯一标识**，用于文件名 / 类名 / 引擎槽位 / 调用，
  /// 绝不能拿展示名替代它。
  String displayNameOf(String name) {
    if (!useDisplayName) return name;
    return pluginByName(name)?.title ?? name;
  }

  // ===== 生命周期 =====

  @action
  Future<void> init() async {
    loading = true;
    try {
      await _engine.init();
      final appSupportDir = await getApplicationSupportDirectory();
      pluginNameDisplay = GStorage.getSetting(SettingsKeys.pluginNameDisplay);
      final dir = Directory('${appSupportDir.path}/plugins');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      _pluginDir = dir;
      // 插件路径 = 固定目录 + {name}.js，目录只在这里设置一次
      Plugin.directory = dir.path;
      await _loadCategories();
      _rebuildCategoryRegistry();
      // 出厂安装：只在「一个插件都没有」时执行一次（见 _installFactoryPlugins）
      await _installFactoryPlugins();
      await rescan();
      initialized = true;
    } catch (e, s) {
      WywLogger().e('${LogTag.plugin} 插件控制器初始化失败', error: e, stackTrace: s);
    } finally {
      loading = false;
    }
  }

  /// 扫描插件目录，**以 `index.json` 为基准**与磁盘对账，注册所有**启用**的插件。
  ///
  /// 基准必须是索引：顺序与用户字段只存在那里。**本方法不写 `index.json`** ——
  /// 刷新永远不该改变磁盘上的持久化内容。三类异常分别记进 [invalidFiles]、
  /// [unimportedFiles] 与 [Plugin.loadError]，都不让插件静默消失。
  @action
  Future<void> rescan() async {
    _unregisterAll();
    invalidFiles.clear();
    unimportedFiles.clear();
    _rebuildCategoryRegistry();

    final dir = _pluginDir;
    if (dir == null) {
      plugins.clear();
      return;
    }

    // 基准：内存非空就用内存。启动那一刻内存是空的才读盘 —— 之后的 rescan 用内存
    // 才是权威（它和刚写下去的索引一致，还能兜住尚未落盘的改动）。
    // 索引读不懂时记录取空表，但那些 .js 会全部落进「未导入」，一个都不会丢。
    final List<Plugin> records;
    if (plugins.isNotEmpty) {
      records = plugins.toList();
    } else {
      final index = await PluginIndex.read(dir);
      indexCorrupt = index.isCorrupt;
      records = index.records;
    }

    // 1) 读目录。命名链第 1 环分两段判，顺序不能颠倒：
    //    ① 索引里已有记录（含历史遗留的大写名字）→ 索引的拼写是权威，必要时改名对齐。
    //       「强制小写」是准入规则，管不到存量，否则一次更新会打死用户所有大写插件。
    //    ② 索引里没有的新文件 → 过 `PluginNameRules.validate`。
    final onDisk = <String>{};
    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.endsWith('.js')) continue;
      final fileName = entity.uri.pathSegments.last;
      var name = _nameFromPath(fileName);

      final known = _recordByNameFold(records, name);
      if (known != null) {
        if (known.name != name) {
          if (!await known.alignFileName(fileName)) {
            _recordInvalidFile(
              known.name,
              entity.path,
              PluginSourceError('文件名 `$fileName` 与索引里的 `${known.name}` '
                  '大小写不一致，且自动重命名失败'),
            );
            continue;
          }
          name = known.name;
        }
        if (PluginNameRules.isLegacyName(name)) {
          WywLogger().w('${LogTag.plugin} 名字仍是大写形态（存量记录，不影响使用）'
              ' name=$name；建议导出后以小写名重新导入');
        }
        onDisk.add(name);
        continue;
      }

      final nameError = PluginNameRules.validate(name);
      if (nameError != null) {
        _recordInvalidFile(
          name,
          entity.path,
          PluginSourceError('文件名不合法：$nameError'),
        );
        continue;
      }
      onDisk.add(name);
    }

    // 2) 对账：索引给顺序与用户字段，磁盘给出「谁有文件」。
    final recon = PluginReconciliation.of(records, onDisk);
    runInAction(() {
      plugins = ObservableList<Plugin>.of(recon.records);
      for (final plugin in plugins) {
        plugin.fileMissing = recon.missingFiles.contains(plugin.name);
        plugin.loadError = null; // 重新注册会写回真实结果
      }
      for (final name in recon.orphanFiles) {
        unimportedFiles.add(PluginLoadFailure(
          name: name,
          filePath: Plugin(name: name).filePath,
          message: '磁盘上有这个插件文件，但 index.json 里没有它的记录',
        ));
      }
    });

    // 3) 注册启用的插件（缺文件的不注册、也不报错，补回文件即恢复）
    for (final plugin in plugins.toList()) {
      if (!plugin.enabled || plugin.fileMissing) continue;
      await _register(plugin);
    }

    // 4) 分类推断缓存（此时启用插件已注册）
    for (final plugin in plugins) {
      if (plugin.isLoaded) await plugin.refreshCategory();
    }
  }

  /// **出厂安装**：只在**这台设备上还没有任何插件**时执行一次。
  ///
  /// 它不删任何东西：不清目录（在"真的什么都没有"时那是空操作，别的场景就是删数据），
  /// 也不覆盖已存在的文件。判定「一个都没有」＝ 目录里没有任何 `.js` **且** 索引里没有
  /// 记录 **且** 索引不是坏的 —— 磁盘上有文件、或索引读不懂，都完全不碰出厂配置。
  ///
  /// 装完之后它们就是普通插件：可编辑、可禁用、可删除，删了不会再回来。
  Future<void> _installFactoryPlugins() async {
    final dir = _pluginDir;
    if (dir == null) return;

    final hasPluginFile =
        await dir.list().any((e) => e is File && e.path.endsWith('.js'));
    if (hasPluginFile) return;

    final index = await PluginIndex.read(dir);
    runInAction(() => indexCorrupt = index.isCorrupt);
    if (index.isCorrupt) {
      WywLogger().w('${LogTag.plugin} index.json 读不懂：保留原文件、跳过出厂安装');
      return;
    }
    if (index.records.isNotEmpty) return;

    final List<Plugin> seed;
    try {
      seed = PluginIndex.decodeText(
        await rootBundle.loadString(_pluginSeedIndex),
      );
    } catch (e, s) {
      WywLogger().w('${LogTag.plugin} 读取出厂插件配置失败（跳过）',
          error: e, stackTrace: s);
      return;
    }
    if (seed.isEmpty) return;

    // 缺载荷、目标文件已存在的条目都跳过（不覆盖用户的东西，也不写出指向不存在文件的记录）
    final installed = <Plugin>[];
    for (final plugin in seed) {
      if (await plugin.exists()) continue;
      final content = await _loadFactoryAsset('$_pluginSeedDir${plugin.fileName}');
      if (content == null) {
        WywLogger().w(
            '${LogTag.plugin} 出厂配置里的插件缺少载荷文件，已跳过 name=${plugin.name}');
        continue;
      }
      try {
        await plugin.writeSource(content);
        installed.add(plugin);
      } catch (e, s) {
        WywLogger().w('${LogTag.plugin} 写出厂插件失败 name=${plugin.name}',
            error: e, stackTrace: s);
      }
    }
    if (installed.isEmpty) return;

    // 全部载荷写成功之后才写索引 —— 中途失败不会留下指向不存在文件的记录
    await PluginIndex.save(dir, installed);
    WywLogger().i(
        '${LogTag.plugin} 出厂安装完成 ${installed.length} 个插件（全部禁用，等待导入）');
  }

  /// 读一个出厂载荷；不存在就返回 null（不抛）。
  Future<String?> _loadFactoryAsset(String assetPath) async {
    try {
      return await rootBundle.loadString(assetPath);
    } catch (_) {
      return null;
    }
  }

  // ===== 启用 / 禁用 / 删除 =====

  /// 注册单个插件：成功清掉失败记录与「文件缺失」标记，失败记进 [Plugin.loadError]。
  Future<bool> _register(Plugin plugin) async {
    try {
      await plugin.register(_engine);
      plugin.fileMissing = false; // 读到文件了，缺失标记自然消解
      plugin.loadError = null;
      plugin.invalidateCapabilities(); // 内容可能已变
      await plugin.refreshCategory();
      return true;
    } catch (e, s) {
      WywLogger().w('${LogTag.plugin} 注册插件失败 name=${plugin.name}',
          error: e, stackTrace: s);
      plugin.loadError = e.toString();
      plugin.inferredCategory = null;
      return false;
    }
  }

  /// 禁用插件：卸载引擎实例，记录与文件都保留（列表里位置不变）。
  Future<PluginOpResult> disable(String name) async {
    final plugin = pluginByName(name);
    if (plugin == null) return PluginOpResult.failure('插件不存在：$name');
    if (!plugin.enabled) return const PluginOpResult.failure('插件未启用');

    plugin.unregister();
    plugin.enabled = false;
    plugin.loadError = null;
    plugin.inferredCategory = null;
    plugin.invalidateCapabilities();
    updatePlugin(plugin);
    await _saveIndex();
    return const PluginOpResult.success();
  }

  /// 启用插件：读盘注册，成功后才写下启用标记（失败保持禁用并记错误）。
  ///
  /// 文件缺失的记录在这里被挡住 —— 走 [importFromFilePaths] 补回文件再启用。
  Future<PluginOpResult> enable(String name) async {
    final plugin = pluginByName(name);
    if (plugin == null) {
      return PluginOpResult.failure('插件不在列表中：$name（请先刷新）');
    }
    if (!await plugin.exists()) {
      return PluginOpResult.failure('插件文件缺失：$name.js，请重新导入该插件');
    }
    if (!await _register(plugin)) {
      final reason = plugin.loadError;
      updatePlugin(plugin);
      return PluginOpResult.failure(reason ?? '导入失败：$name');
    }
    plugin.enabled = true;
    updatePlugin(plugin);
    await _saveIndex();
    return const PluginOpResult.success();
  }

  /// 删除插件（文件 + 记录）。**所有插件一视同仁**：没有不可删的插件。
  Future<PluginOpResult> deletePlugin(String name) async {
    final plugin = pluginByName(name);
    if (plugin == null) return PluginOpResult.failure('插件不存在：$name');
    try {
      await plugin.delete();
      runInAction(() => plugins.removeWhere((p) => p.name == name));
      plugin.invalidateCapabilities();
      await _saveIndex();
      return const PluginOpResult.success();
    } catch (e, s) {
      WywLogger()
          .e('${LogTag.plugin} 删除插件失败 name=$name', error: e, stackTrace: s);
      return PluginOpResult.failure(e.toString());
    }
  }

  /// 删除一条**没有记录的野文件**（文件名非法 / 未导入）。
  ///
  /// 它们不属于任何 [Plugin]，所以既没有卸载动作，也不需要写 `index.json`。
  Future<PluginOpResult> deleteStrayFile(
    String name, {
    required bool unimported,
  }) async {
    final from = unimported ? unimportedFiles : invalidFiles;
    final index = from.indexWhere((f) => f.name == name);
    if (index < 0) return PluginOpResult.failure('文件不存在：$name');
    try {
      final file = File(from[index].filePath);
      if (await file.exists()) await file.delete();
      runInAction(() => from.removeAt(index));
      return const PluginOpResult.success();
    } catch (e, s) {
      WywLogger()
          .e('${LogTag.plugin} 删除文件失败 name=$name', error: e, stackTrace: s);
      return PluginOpResult.failure(e.toString());
    }
  }

  // ===== 用户字段 =====

  /// 写入一个用户可编辑字段（详情页「管理属性」表单）。null / 空串表示清空。
  Future<void> setPluginField(
    String name,
    PluginField field,
    String? value,
  ) async {
    final plugin = pluginByName(name);
    if (plugin == null) return;
    plugin.setField(field, value ?? '');
    // 分类改了，自查分类缓存要跟着作废
    if (field == PluginField.categoryId) await plugin.refreshCategory();
    updatePlugin(plugin);
    await _saveIndex();
  }

  /// 拖拽排序：把 [name] 挪到 [beforeName] 之前（null 表示挪到末尾）。
  ///
  /// 用名字定位而不是下标：管理页按状态分了多个分区，可见下标 ≠ 全量下标。
  /// 顺序本身就是持久化内容，没有 order 字段。
  @action
  Future<void> movePlugin({required String name, String? beforeName}) async {
    final at = plugins.indexWhere((p) => p.name == name);
    if (at < 0) return;
    final moved = plugins.removeAt(at);
    if (beforeName == null) {
      plugins.add(moved);
    } else {
      final target = plugins.indexWhere((p) => p.name == beforeName);
      plugins.insert(target < 0 ? plugins.length : target, moved);
    }
    await _saveIndex();
  }

  // ===== 自定义分类管理 =====

  /// 新建自定义分类。[iconKey] 未知时归一成空串（= 默认图标）。
  Future<PluginOpResult> addCustomCategory({
    required String id,
    required String label,
    String iconKey = '',
  }) async {
    final cleanId = id.trim().toLowerCase();
    final cleanLabel = label.trim();
    if (cleanId.isEmpty) return const PluginOpResult.failure('分类 id 不能为空');
    if (cleanLabel.isEmpty) return const PluginOpResult.failure('分类名不能为空');
    if (PluginCategory.builtinById(cleanId) != null) {
      return const PluginOpResult.failure('该 id 与内置分类冲突');
    }
    if (_findCustomCategory(cleanId) != null) {
      return PluginOpResult.failure('分类已存在：$cleanId');
    }
    _customCategories.add(CustomCategory(
      id: cleanId,
      label: cleanLabel,
      iconKey: _cleanIconKey(iconKey),
    ));
    await _commitCategories();
    return const PluginOpResult.success();
  }

  /// 修改自定义分类的展示名与图标。**id 不可改**：插件 `categoryId` 引用它。
  Future<PluginOpResult> updateCustomCategory({
    required String id,
    required String label,
    required String iconKey,
  }) async {
    final key = id.trim().toLowerCase();
    final cleanLabel = label.trim();
    if (cleanLabel.isEmpty) return const PluginOpResult.failure('分类名不能为空');
    final at =
        _customCategories.indexWhere((c) => c.id.trim().toLowerCase() == key);
    if (at < 0) return PluginOpResult.failure('分类不存在：$id');

    final next = _customCategories[at]
        .copyWith(label: cleanLabel, iconKey: _cleanIconKey(iconKey));
    final current = _customCategories[at];
    if (next.label == current.label && next.iconKey == current.iconKey) {
      return const PluginOpResult.success();
    }
    _customCategories[at] = next;
    await _commitCategories();
    return const PluginOpResult.success();
  }

  /// 删除自定义分类，并清掉指向它的插件的 `categoryId`（回落为自查分类）。
  Future<PluginOpResult> removeCustomCategory(String id) async {
    final key = id.trim().toLowerCase();
    final at =
        _customCategories.indexWhere((c) => c.id.trim().toLowerCase() == key);
    if (at < 0) return PluginOpResult.failure('分类不存在：$id');
    _customCategories.removeAt(at);

    var touched = false;
    for (final plugin in plugins) {
      if (plugin.categoryId.trim().toLowerCase() == key) {
        plugin.categoryId = '';
        await plugin.refreshCategory();
        touched = true;
      }
    }
    if (touched) await _saveIndex();
    await _commitCategories();
    return const PluginOpResult.success();
  }

  /// 分类登记表变更后：重建注册表（`categories` 是 observable，赋值即通知）+ 落盘。
  Future<void> _commitCategories() async {
    _rebuildCategoryRegistry();
    await _saveCategories();
  }

  CustomCategory? _findCustomCategory(String id) {
    final key = id.trim().toLowerCase();
    for (final category in _customCategories) {
      if (category.id.trim().toLowerCase() == key) return category;
    }
    return null;
  }

  /// 图标 key 归一：只接受调色板里存在的键，其余（含空串）一律为空串。
  String _cleanIconKey(String iconKey) {
    final clean = iconKey.trim();
    return CategoryIcons.contains(clean) ? clean : '';
  }

  /// 重建分类注册表（内置 + 用户自定义）。
  void _rebuildCategoryRegistry() {
    categories = PluginCategoryRegistry(custom: _customCategories);
  }

  // ===== 集合写入：只有这一扇门 =====

  /// **把一条插件记录放进列表** —— 已经在列表里就替换那一条，不在就追加到末尾。
  ///
  /// 这是「插件字段改完了」的**唯一通知方式**：`Plugin` 不是 observable，就地改它的字段
  /// MobX 看不见，所以调用方改完把**同一个实例**传回来，这里用 `replaceRange` 让列表
  /// 触发一次变更，读列表的 `Observer` 就会重新去读那些字段。
  ///
  /// 为什么必须是 `replaceRange` 而不是 `plugins[i] = plugin`：`operator []=` 有
  /// `if (oldValue != value)` 的守卫（`Plugin` 没重写 `==`，比的是同一性），同一个实例
  /// 传进去**不会通知**；`replaceRange` 没有这个守卫，一定会 `reportChanged()`。
  ///
  /// 按**名字逐字符**匹配（不做大小写折叠）：`name` 就是唯一标识，而且存量记录里可能有
  /// 历史遗留的大写名字，折叠匹配会替换到错误的那一条。
  @action
  void updatePlugin(Plugin plugin) {
    final at = plugins.indexWhere((p) => p.name == plugin.name);
    if (at < 0) {
      plugins.add(plugin);
      return;
    }
    plugins.replaceRange(at, at + 1, [plugin]);
  }

  // ===== 新增 / 更新 =====

  /// **新增插件**：以插件为单位 —— 只落一条台账记录，**不带源码**。
  ///
  /// 记录一落地，插件名就锁定了（它是文件名 / 类名 / 引擎槽位的共同来源）；源码由
  /// 详情页编辑后保存写入（走 [updateItem] → [Plugin.repairMissing]）。在那之前这条
  /// 记录处于「文件缺失」状态：不注册、不进主列表，管理页把它列在异常分区里。
  @action
  Future<PluginCreateResult> addPlugin(Plugin plugin) async {
    if (_pluginDir == null) {
      return const PluginCreateResult.failure('插件目录未初始化');
    }

    final nameError = PluginNameRules.validate(plugin.name);
    if (nameError != null) return PluginCreateResult.failure(nameError);

    final folded = pluginByNameFold(plugin.name);
    if (folded != null) {
      return PluginCreateResult.failure(
          '插件名与已有插件 `${folded.name}` 仅大小写不同（文件系统不敏感，会互相覆盖）');
    }
    // 磁盘上已有同名文件（未导入的野文件）：不悄悄认领，让用户走「未导入」入口
    if (await plugin.exists()) {
      return PluginCreateResult.failure(
          '磁盘上已有同名文件 ${plugin.fileName} —— 请到管理页「异常」分区认领它');
    }

    plugin.fileMissing = true; // 还没有源码 = 还没有文件
    updatePlugin(plugin);
    await _saveIndex();
    return PluginCreateResult.success(plugin);
  }

  /// **导入即安装**：有源码的路径（从文件 / 剪贴板 / 野文件认领）走这里。
  ///
  /// 两条修复路径，让「记录在、文件没了」能原地救回来而不是被拒绝：
  ///   - 同名记录被标 [Plugin.fileMissing] → 补回文件（[Plugin.repairMissing]）；
  ///   - [adoptExistingFile]：磁盘上已有同名野文件（管理页「未导入」清单的「导入」
  ///     按钮）→ 认领它，注册失败也**不删**。
  ///
  /// ⚠️ 新增插件请用 [addPlugin]（以插件为单位），不要用本方法 —— 它要求源码先就位。
  @action
  Future<PluginCreateResult> create(
    String name,
    String content, {
    bool adoptExistingFile = false,
  }) async {
    if (_pluginDir == null) {
      return const PluginCreateResult.failure('插件目录未初始化');
    }

    final nameError = PluginNameRules.validate(name);
    if (nameError != null) return PluginCreateResult.failure(nameError);

    // 折叠唯一：文件系统不敏感，`hanime` 与 `Hanime` 是同一个文件。
    // 例外是「同名记录缺文件」—— 那不是冲突，是等着被补上的洞。
    final folded = pluginByNameFold(name);
    if (folded != null) {
      if (folded.fileMissing && folded.name == name) {
        return _repairMissing(folded, content);
      }
      return PluginCreateResult.failure(
          '插件名与已有插件 `${folded.name}` 仅大小写不同（文件系统不敏感，会互相覆盖）');
    }

    final plugin = Plugin(name: name, enabled: true);
    try {
      await plugin.install(content, _engine, adoptExisting: adoptExistingFile);
      updatePlugin(plugin);
      runInAction(() => unimportedFiles.removeWhere((f) => f.name == name));
      // 等索引落盘再返回：文件已写出、索引没写就退出进程的话，这个文件会变成
      // 一条「未导入」（导入看着成功、重启后却不在列表里）
      await _saveIndex();
      return PluginCreateResult.success(plugin);
    } catch (e, s) {
      WywLogger()
          .e('${LogTag.plugin} 创建插件失败 name=$name', error: e, stackTrace: s);
      return PluginCreateResult.failure(e.toString());
    }
  }

  /// **修复导入**：记录还在、文件没了 —— 补回来，顺序与用户字段原地保留。
  Future<PluginCreateResult> _repairMissing(
    Plugin plugin,
    String content,
  ) async {
    // 扫描之后、这次修复之前文件自己回来了（外部贴回 / 别处导入）→ 按热重载处理
    if (await plugin.exists()) {
      final result = await updateItem(name: plugin.name, content: content);
      return result.isSuccess
          ? PluginCreateResult.success(plugin)
          : PluginCreateResult.failure(result.error!);
    }

    try {
      await plugin.repairMissing(content, _engine);
      plugin.loadError = null;
      plugin.invalidateCapabilities();
      await plugin.refreshCategory();
      runInAction(() => unimportedFiles.removeWhere((f) => f.name == plugin.name));
      updatePlugin(plugin);
      await _saveIndex();
      WywLogger().i('${LogTag.plugin} 已补回缺失的插件文件 name=${plugin.name}');
      return PluginCreateResult.success(plugin);
    } catch (e, s) {
      WywLogger().e('${LogTag.plugin} 补回插件文件失败 name=${plugin.name}',
          error: e, stackTrace: s);
      plugin.loadError = e.toString();
      return PluginCreateResult.failure(e.toString());
    }
  }

  /// **保存插件源码**：写盘 +（已启用则）注册 / 热重载。
  ///
  /// 缺文件的记录（[addPlugin] 刚建出来、或文件丢了）走 [Plugin.repairMissing]：
  /// 写文件并注册；其余走 [Plugin.updateSource]。两条路都先校验源码。
  @action
  Future<PluginOpResult> updateItem({
    required String name,
    required String content,
  }) async {
    final plugin = pluginByName(name);
    if (plugin == null) return PluginOpResult.failure('插件不存在：$name');

    try {
      if (plugin.fileMissing) {
        await plugin.repairMissing(content, _engine);
      } else {
        await plugin.updateSource(content, _engine);
      }
      plugin.loadError = null;
      plugin.invalidateCapabilities(); // 内容变了，设置项与源站地址都可能变
      await plugin.refreshCategory();
      updatePlugin(plugin);
      await _saveIndex();
      return const PluginOpResult.success();
    } catch (e, s) {
      WywLogger()
          .e('${LogTag.plugin} 保存插件源码失败 name=$name', error: e, stackTrace: s);
      plugin.loadError = e.toString();
      updatePlugin(plugin);
      return PluginOpResult.failure(e.toString());
    }
  }

  // ===== 导入 / 导出 =====

  /// 从本地 `.js` 文件导入插件（支持多选）。
  Future<PluginImportReport> importFromFilePaths(List<String> filePaths) async {
    if (_pluginDir == null) {
      return const PluginImportReport(failed: {'*': '插件目录未初始化'});
    }
    final imported = <String>[];
    final failed = <String, String>{};
    for (final path in filePaths) {
      final fileName = File(path).uri.pathSegments.last;
      final name = _nameFromPath(fileName);
      try {
        final content = await File(path).readAsString();
        final result = await create(name, content);
        if (result.isSuccess) {
          imported.add(name);
        } else {
          failed[fileName] = result.error ?? '导入失败';
        }
      } catch (e) {
        failed[fileName] = e.toString();
      }
    }
    return PluginImportReport(imported: imported, failed: failed);
  }

  /// 认领一条「未导入」文件：**原样读回**它建立记录，不复制、不改名、不覆盖。
  Future<PluginOpResult> adoptUnimportedFile(String name) async {
    final stray = _unimportedByName(name);
    if (stray == null) return PluginOpResult.failure('未导入文件不存在：$name');
    final file = File(stray.filePath);
    if (!await file.exists()) {
      return PluginOpResult.failure('文件不存在：${stray.filePath}');
    }
    try {
      final result =
          await create(name, await file.readAsString(), adoptExistingFile: true);
      return result.isSuccess
          ? const PluginOpResult.success()
          : PluginOpResult.failure(result.error!);
    } catch (e, s) {
      WywLogger().e('${LogTag.plugin} 认领未导入文件失败 name=$name',
          error: e, stackTrace: s);
      return PluginOpResult.failure(e.toString());
    }
  }

  PluginLoadFailure? _unimportedByName(String name) {
    for (final failure in unimportedFiles) {
      if (failure.name == name) return failure;
    }
    return null;
  }

  /// 从 JSON 文本导入插件。
  Future<PluginImportReport> importFromBundleJson(String jsonText) async {
    if (_pluginDir == null) {
      return const PluginImportReport(failed: {'*': '插件目录未初始化'});
    }
    final parsed = parsePluginBundle(jsonText);
    if (parsed.isFatal) {
      return PluginImportReport(failed: {'*': parsed.error!});
    }

    final imported = <String>[];
    final failed = Map<String, String>.from(parsed.failed);
    for (final entry in parsed.entries) {
      final result = await create(entry.name, entry.content);
      if (result.isSuccess) {
        imported.add(entry.name);
      } else {
        failed[entry.name] = result.error ?? '导入失败';
      }
    }
    return PluginImportReport(imported: imported, failed: failed);
  }

  /// 把指定插件导出成 JSON 包文本（供剪贴板 / 落盘）。
  ///
  /// 一律从磁盘读源码，因此已禁用 / 加载失败的插件也能导出；[names] 为空表示全部。
  Future<String> exportBundleJson(List<String> names) async {
    final targets =
        names.isEmpty ? [for (final plugin in plugins) plugin.name] : names;
    final entries = <PluginBundleEntry>[];
    for (final name in targets) {
      final entry = await pluginByName(name)?.exportEntry();
      if (entry != null) entries.add(entry);
    }
    return encodePluginBundle(entries);
  }

  // ===== 能力探测（设置项 / 源站地址）=====

  /// 探测单个插件的能力（幂等：已探测过直接返回）。
  Future<void> ensureCapabilities(String name) async {
    final plugin = getPlugin(name);
    if (plugin == null || plugin.capabilitiesProbed) return;
    await plugin.probeCapabilities();
    updatePlugin(plugin);
  }

  /// 为所有已加载插件补齐能力探测（幂等）。
  ///
  /// 顺序执行，避免几十个插件同时灌爆 JS 引擎。探测结果挂在 `Plugin` 上，
  /// 所以每条都要走一次 [updatePlugin] 才能让 UI 看见。
  Future<void> ensureAllCapabilities() async {
    final pending = [
      for (final plugin in plugins)
        if (plugin.isLoaded && !plugin.capabilitiesProbed) plugin,
    ];
    if (pending.isEmpty) return;
    for (final plugin in pending) {
      await plugin.probeCapabilities();
      updatePlugin(plugin);
    }
  }

  // ===== 运行时查询 =====

  /// 插件的存在状态（收藏卡片图标 / 收藏页插件筛选共用同一口径）。
  PluginPresence presenceOf(String pluginName) =>
      pluginByName(pluginName)?.presence ?? PluginPresence.deleted;

  /// **文件缺失**的记录（顺序同 [plugins]）。
  List<Plugin> get missingFilePlugins => [
        for (final plugin in plugins)
          if (plugin.fileMissing) plugin,
      ];

  /// 插件是否自己实现了 [methodName]（按名字取插件的便捷入口）。
  Future<bool> hasMethod(String pluginName, String methodName) async {
    final plugin = pluginByName(pluginName);
    if (plugin == null) return false;
    return plugin.implementsMethod(methodName);
  }

  /// 收藏条目点击入口：调用插件里固定名称 `onOpenBrowseEntry(entryJson)`。
  @action
  Future<bool> openBrowseEntry({
    required String pluginName,
    required Map<String, dynamic> entryJson,
  }) async {
    final plugin = getPlugin(pluginName);
    if (plugin == null) {
      WywLogger().w('${LogTag.plugin} 插件未注册，无法打开浏览历史 plugin=$pluginName');
      return false;
    }
    if (!await plugin.implementsMethod('onOpenBrowseEntry')) {
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

  /// 从文件路径提取插件名（去 `.js`）。
  String _nameFromPath(String path) => Plugin.nameFromFilePath(path);

  /// 在**索引记录**里做大小写折叠查询（[pluginByNameFold] 查的是内存列表）。
  Plugin? _recordByNameFold(List<Plugin> records, String name) {
    final key = PluginNameFold.of(name);
    for (final record in records) {
      if (PluginNameFold.of(record.name) == key) return record;
    }
    return null;
  }

  /// 记录一条「没有记录的野文件」，同名先移除避免重复条目。
  void _recordInvalidFile(String name, String filePath, Object error) {
    runInAction(() {
      invalidFiles.removeWhere((f) => f.name == name);
      invalidFiles.add(PluginLoadFailure(
        name: name,
        filePath: filePath,
        message: error.toString(),
      ));
    });
  }

  /// 写回 `index.json`（失败仅告警，不阻断业务）。写成功即清掉 [indexCorrupt] 提示。
  Future<void> _saveIndex() async {
    final dir = _pluginDir;
    if (dir == null) return;
    try {
      await PluginIndex.save(dir, plugins.toList());
      if (indexCorrupt) runInAction(() => indexCorrupt = false);
    } catch (e, s) {
      WywLogger().w('${LogTag.plugin} 保存插件索引失败', error: e, stackTrace: s);
    }
  }

  /// 读 `categories.json`；读不出就是空表。
  Future<void> _loadCategories() async {
    final dir = _pluginDir;
    if (dir == null) return;
    _customCategories
      ..clear()
      ..addAll(await CategoryIndex.load(dir));
  }

  /// 写 `categories.json`（失败仅告警，不阻断业务）。
  Future<void> _saveCategories() async {
    final dir = _pluginDir;
    if (dir == null) return;
    try {
      await CategoryIndex.save(dir, _customCategories);
    } catch (e, s) {
      WywLogger().w('${LogTag.plugin} 保存分类失败', error: e, stackTrace: s);
    }
  }

  void _unregisterAll() {
    for (final plugin in plugins) {
      plugin.unregister();
    }
  }
}
