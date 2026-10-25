import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:mobx/mobx.dart';
import 'package:wyw/bean/dialog/dialog_helper.dart';
import 'package:wyw/bean/widget/empty_state_widget.dart';
import 'package:wyw/bean/widget/select_field.dart';
import 'package:wyw/plugins/plugin.dart';
import 'package:wyw/plugins/plugin_category.dart';
import 'package:wyw/plugins/plugin_operation.dart';
import 'package:wyw/pages/plugin/plugin_controller.dart';
import 'package:wyw/pages/plugin/plugin_detail_page.dart';
import 'package:wyw/pages/plugin/widgets/category_manager_dialog.dart';
import 'package:wyw/pages/webview/webview_page.dart';
import 'package:wyw/bean/settings/settings_detail_scaffold.dart';
import 'package:wyw/utils/clipboard.dart';

/// 插件（规则）管理页面。
///
/// [PluginController.plugins] 装着全部插件，顺序就是显示顺序。本页把它分成两块：
/// **主列表**（已启用 + 已禁用一视同仁，禁用只在卡片上多一个标签）与**异常**
/// （注册失败 / 缺文件 / 野文件）。工具栏提供关键词 + 类型 + 状态三个筛选。
///
/// **「异常」分区自带批量动作**（标题行右侧：全部导入 / 全部删除），语义与逐行
/// 按钮完全一致，只是循环一遍并把失败原因汇总成一个弹窗。
///
/// 顺序只来自全量列表，所以拖拽用名字定位（[PluginController.movePlugin]）；
/// 任一筛选生效时禁用拖拽（可见顺序 ≠ 全量顺序）。
///
/// 所有插件一视同仁：没有「内置 / 第三方」之分，都能编辑、禁用、删除，删了不会再回来。
/// 本页只保留**纯视图状态**（多选、分区展开、搜索词、筛选）——它们跨页面存活没有意义。
class PluginManagerPage extends StatefulWidget {
  const PluginManagerPage({super.key});

  @override
  State<PluginManagerPage> createState() => _PluginManagerPageState();
}

class _PluginManagerPageState extends State<PluginManagerPage> {
  final PluginController _c = inject<PluginController>();

  /// 是否处于多选模式。
  ///
  /// **与选中数量无关**：把选择清空（「取消全选」/「反选」/ 取消勾选最后一条）不会
  /// 自动退出，退出只由左上角关闭按钮或系统返回触发 —— 否则清空之后就没法接着反选了。
  bool _isMultiSelectMode = false;

  /// 已选中的插件名集合（存名字而不是实例：列表刷新 / 状态变化后仍然有效）。
  final Set<String> _selectedNames = {};

  /// 批量动作是否正在跑。
  ///
  /// 确认框关掉之后、循环结束之前，标题栏按钮是可以再点的；没有这个开关，连点两次
  /// 就会让两条循环并发写 `index.json`（见 [_applyBatchEnabled] 的说明）。
  bool _batchBusy = false;

  /// 「异常」分区是否展开
  bool _issueSectionExpanded = false;

  /// 搜索关键词（匹配插件名 / 展示名 / 描述 / 分类名）
  String _keyword = '';

  /// 类型筛选：null = 全部。
  PluginCategory? _categoryFilter;

  /// 状态筛选。
  _PluginStatusFilter _statusFilter = _PluginStatusFilter.all;

  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  /// 插件列表变化时补探测能力（设置项 / 源站地址）。
  ///
  /// 用 reaction 而不是在 build 里发探测请求：build 里做副作用会在每帧重建时
  /// 重复触发，而且 setState 与 build 交错容易出问题。
  late final ReactionDisposer _capabilityReaction;

  @override
  void initState() {
    super.initState();
    _capabilityReaction = reaction<int>(
      (_) => _c.plugins.length,
      (_) => unawaited(_c.ensureAllCapabilities()),
    );
    unawaited(_c.ensureAllCapabilities());
  }

  @override
  void dispose() {
    _capabilityReaction();
    _searchCtrl.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ===== 过滤 =====

  /// 关键词匹配：插件名 / 展示名 / 描述 / 生效分类名。
  bool _matchesKeyword(Plugin plugin) {
    if (_keyword.isEmpty) return true;
    final needle = _keyword.toLowerCase();
    return plugin.name.toLowerCase().contains(needle) ||
        plugin.displayName.toLowerCase().contains(needle) ||
        plugin.description.toLowerCase().contains(needle) ||
        _c.categoryOf(plugin).label.toLowerCase().contains(needle);
  }

  bool _matchesStatus(Plugin plugin) => switch (_statusFilter) {
        _PluginStatusFilter.all => true,
        _PluginStatusFilter.enabled => plugin.enabled,
        _PluginStatusFilter.disabled => !plugin.enabled,
      };

  bool _matchesCategory(Plugin plugin) =>
      _categoryFilter == null || _c.categoryOf(plugin) == _categoryFilter;

  /// 主列表 = **已启用与已禁用一视同仁**（禁用只是在卡片上多一个标签）；
  /// 注册失败 / 缺文件的记录归「异常」分区，不在这里重复出现。
  List<Plugin> get _visiblePlugins => _c.plugins
      .where((p) => !p.fileMissing && !_c.isFailed(p.name))
      .where(_matchesStatus)
      .where(_matchesCategory)
      .where(_matchesKeyword)
      .toList();

  /// 异常分区：注册失败的插件 + 文件缺失 + 野文件（未导入 / 文件名非法）
  List<Plugin> get _failedPlugins => _c.plugins
      .where((p) => p.loadError != null)
      .where((p) => _matchesName(p.name))
      .toList();

  /// 文件缺失：记录在、磁盘上没有 `{name}.js`（顺序与用户字段都还在）。
  List<Plugin> get _missingFiles => _c.missingFilePlugins
      .where((p) => _matchesName(p.name))
      .toList();

  List<PluginLoadFailure> get _invalidFiles => _c.invalidFiles
      .where((f) => _matchesName(f.name))
      .toList();

  /// 未导入：磁盘上有合法 `.js`，但索引里没有它的记录。
  List<PluginLoadFailure> get _unimportedFiles => _c.unimportedFiles
      .where((f) => _matchesName(f.name))
      .toList();

  int get _issueCount =>
      _failedPlugins.length +
      _missingFiles.length +
      _invalidFiles.length +
      _unimportedFiles.length;

  /// 禁用 / 异常分区按名字匹配关键词（这两块不参与状态筛选）
  bool _matchesName(String name) {
    if (_keyword.isEmpty) return true;
    final needle = _keyword.toLowerCase();
    if (name.toLowerCase().contains(needle)) return true;
    final plugin = _c.pluginByName(name);
    return plugin != null &&
        plugin.displayName.toLowerCase().contains(needle);
  }

  // ===== 添加 / 编辑 / 删除 =====

  /// 打开插件详情页（属性集中在那里：展示名 / 分类 / 启用 / 代码 / 设置）。
  /// [plugin] 为 null 表示新建模式。
  Future<void> _openDetailPage(Plugin? plugin) async {
    await context.pushNamed(
      // pluginModule 挂在 settingsModule 之下，完整路径为 /settings/plugin/…
      '/settings/plugin/detail/',
      arguments: PluginDetailRouteArgs(pluginName: plugin?.name),
    );
  }

  /// 批量禁用：卸载但保留文件（留在同一个列表里，只多一个「已禁用」标签）。
  Future<void> _confirmBatchDisable() async {
    if (_selectedNames.isEmpty || _batchBusy) return;
    final ok = await WywDialog.showConfirm(
      title: '禁用规则',
      message: '确定要禁用选中的 ${_selectedNames.length} 条规则吗？'
          '禁用后它们仍在这个列表里（带「已禁用」标签），随时可从卡片菜单重新启用。'
          '已经禁用的会跳过。',
      confirmText: '禁用',
    );
    if (!ok) return;
    await _applyBatchEnabled(enabled: false);
  }

  /// 批量启用：与「批量禁用」对称。
  ///
  /// 已经启用的条目会跳过；真正失败的（文件读不到 / 注册失败）**保持「已禁用」**，
  /// 完成后连同原因汇总报出（与导入结果同一套口径）。
  Future<void> _confirmBatchEnable() async {
    if (_selectedNames.isEmpty || _batchBusy) return;
    final ok = await WywDialog.showConfirm(
      title: '启用规则',
      message: '确定要启用选中的 ${_selectedNames.length} 条规则吗？'
          '已经启用的会跳过；失败的保持「已禁用」，完成后汇总结果。',
      confirmText: '启用',
    );
    if (!ok) return;
    await _applyBatchEnabled(enabled: true);
  }

  /// 批量启用 / 禁用的公共实现。
  ///
  /// 逐条 `await`：每条都要读盘注册（或卸载）并写一次 `index.json`，并发写索引不安全，
  /// 所以执行期间用 [_batchBusy] 挡住第二次触发。已经是目标状态的直接跳过（省掉无谓的
  /// 注册与失败噪音）；失败的条目**不回滚**已成功的，只把原因汇总报出。
  Future<void> _applyBatchEnabled({required bool enabled}) async {
    final names = _selectedNames.toList();
    if (names.isEmpty || _batchBusy) return;
    setState(() => _batchBusy = true);
    try {
      final verb = enabled ? '启用' : '禁用';
      var done = 0;
      final failed = <String, String>{};
      for (final name in names) {
        final plugin = _c.pluginByName(name);
        if (plugin == null) {
          failed[name] = '不在列表中（请先刷新）';
          continue;
        }
        if (plugin.enabled == enabled) continue; // 已经是目标状态
        final result = enabled ? await _c.enable(name) : await _c.disable(name);
        if (result.isFailure) {
          failed[name] = result.error ?? '$verb失败';
        } else {
          done++;
        }
      }
      if (!mounted) return;
      _exitMultiSelectMode();
      _reportBatchEnabled(enabled: enabled, done: done, failed: failed);
    } finally {
      if (mounted) setState(() => _batchBusy = false);
    }
  }

  /// 批量启用 / 禁用的结果：全成功给一条 toast，有失败给可滚动的明细弹窗
  /// （与 [_showImportReport] 同一套口径）。
  void _reportBatchEnabled({
    required bool enabled,
    required int done,
    required Map<String, String> failed,
  }) {
    final verb = enabled ? '启用' : '禁用';
    if (failed.isEmpty) {
      WywDialog.showToast(
        message: done == 0
            ? '选中的规则都已经是「${enabled ? '已启用' : '已禁用'}」状态'
            : '已$verb $done 条规则',
        context: context,
      );
      return;
    }
    // 明细里的条目用展示名（与卡片、删除确认框一致），不让用户看到内部插件名
    _showBulkResultDialog(
      title: '$verb结果',
      summary: '成功 $done 条，失败 ${failed.length} 条。',
      failures: {
        for (final entry in failed.entries)
          _c.displayNameOf(entry.key): entry.value,
      },
    );
  }

  /// 批量删除（所有插件一视同仁，删了不会回来）。
  Future<void> _confirmBatchDelete() async {
    if (_selectedNames.isEmpty || _batchBusy) return;
    final ok = await WywDialog.showConfirm(
      title: '删除规则',
      message: '确认删除选中的 ${_selectedNames.length} 条规则？此操作不可恢复。',
      confirmText: '删除',
      confirmTextStyle: TextStyle(color: Theme.of(context).colorScheme.error),
    );
    if (!ok) return;
    setState(() => _batchBusy = true);
    try {
      for (final name in _selectedNames.toList()) {
        await _c.deletePlugin(name);
      }
      _exitMultiSelectMode();
    } finally {
      if (mounted) setState(() => _batchBusy = false);
    }
  }

  // ===== 分类 =====

  /// 分类管理：新建 / 删除自定义分类（与详情页共用同一个弹窗）。
  Future<void> _openCategoryManager() => CategoryManagerDialog.show(_c);

  // ===== 导入 / 导出 =====

  /// 从本地 `.js` 文件导入（支持多选）。
  Future<void> _importFromFiles() async {
    final picked = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const ['js'],
    );
    if (picked == null) return;
    final paths = picked.files
        .map((f) => f.path)
        .whereType<String>()
        .toList();
    if (paths.isEmpty) return;
    final report = await _c.importFromFilePaths(paths);
    if (mounted) _showImportReport(report);
  }

  /// 从剪贴板导入 JSON 包。
  Future<void> _importFromClipboard() async {
    final text = await Clipboard.getData(Clipboard.kTextPlain);
    final content = text?.text?.trim() ?? '';
    if (content.isEmpty) {
      _showError('剪贴板为空');
      return;
    }
    final report = await _c.importFromBundleJson(content);
    if (mounted) _showImportReport(report);
  }

  /// 导出到剪贴板。[names] 为空表示导出全部。
  Future<void> _exportToClipboard(List<String> names) async {
    final json = await _c.exportBundleJson(names);
    // 自带 toast，静默复制避免两条提示
    await copyToClipboard(json, toastMessage: null);
    if (!mounted) return;
    WywDialog.showToast(
      message: names.isEmpty ? '已复制全部插件到剪贴板' : '已复制 ${names.length} 个插件到剪贴板',
      context: context,
    );
  }

  /// 导出到文件（用户选目录 + 写单文件）。
  Future<void> _exportToFile(List<String> names) async {
    final dir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择导出目录',
    );
    if (dir == null) return;
    final json = await _c.exportBundleJson(names);
    final fileName =
        'wyw-plugins-${DateTime.now().millisecondsSinceEpoch}.json';
    try {
      await File('$dir/$fileName').writeAsString(json);
      if (!mounted) return;
      WywDialog.showToast(message: '已导出到 $fileName', context: context);
    } catch (e) {
      if (mounted) _showError('导出失败：$e');
    }
  }

  /// 批量动作的**失败明细**弹窗：摘要一行 + 前 8 条原因 + 「还有 N 条」。
  ///
  /// 导入 / 启用 / 禁用 / 删除共用同一套口径 —— 批量动作都是「尽力而为」，
  /// 单个失败不影响其余，所以失败原因必须逐条带回。
  /// [failures] 用「给用户看的名字 -> 原因」（插件用展示名，野文件用文件名）。
  void _showBulkResultDialog({
    required String title,
    required String summary,
    required Map<String, String> failures,
  }) {
    final detail = failures.entries
        .take(8)
        .map((e) => '· ${e.key}：${e.value}')
        .join('\n');
    final more = failures.length > 8 ? '\n…还有 ${failures.length - 8} 条' : '';
    WywDialog.show<void>(
      builder: (_) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Text('$summary\n\n$detail$more'),
        ),
        actions: [
          TextButton(
            onPressed: () => WywDialog.dismiss(),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _showImportReport(PluginImportReport report) {
    if (!report.hasFailure) {
      WywDialog.showToast(message: report.summary, context: context);
      return;
    }
    _showBulkResultDialog(
      title: '导入结果',
      summary: report.summary,
      failures: report.failed,
    );
  }

  // ===== 单项操作 =====

  void _showError(String msg) {
    WywDialog.show<void>(
      builder: (_) => AlertDialog(
        title: const Text('错误'),
        content: Text(msg),
        actions: [
          TextButton(
            onPressed: () => WywDialog.dismiss(),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  /// 用 WebView 打开插件源网站。
  Future<void> _openPluginWebsite(Plugin plugin) async {
    final url = plugin.cachedSourceUrl;
    if (url == null || url.isEmpty) {
      if (mounted) _showError('该插件未声明网站地址');
      return;
    }
    if (!mounted) return;
    context.pushNamed('/webview/', arguments: WebviewPageRouteArgs(url: url));
  }

  void _exitMultiSelectMode() {
    if (!mounted) return;
    setState(() {
      _isMultiSelectMode = false;
      _selectedNames.clear();
    });
  }

  void _enterMultiSelectMode(String firstSelected) {
    setState(() {
      _isMultiSelectMode = true;
      _selectedNames.add(firstSelected);
    });
  }

  /// 勾选 / 取消勾选一条。**不再因为清空而自动退出多选模式**（见 [_isMultiSelectMode]）。
  void _toggleSelection(String name) {
    setState(() {
      if (!_selectedNames.remove(name)) _selectedNames.add(name);
    });
  }

  /// **全选**：把**当前可见**（关键词 / 类型 / 状态筛选之后）的主列表全部选上。
  ///
  /// 作用于可见列表而不是全量列表：这样「筛出已禁用 → 全选 → 启用选中」才是一条
  /// 顺畅的路径。可见范围之外已经选中的条目**保持选中** —— 它们不该因为改一下
  /// 搜索词或筛选条件就被悄悄丢掉。
  void _selectAllVisible() {
    setState(() => _selectedNames.addAll(_visiblePlugins.map((p) => p.name)));
  }

  /// **取消全选**：清空已选，但留在多选模式里（好接着反选或重新挑）。
  void _clearSelection() {
    setState(_selectedNames.clear);
  }

  /// **反选**：在当前可见范围内取反 —— 可见的未选 → 选上，可见的已选 → 取消；
  /// 可见范围之外的选中项不受影响（口径同 [_selectAllVisible]）。
  void _invertSelection() {
    final visible = _visiblePlugins.map((p) => p.name).toList();
    setState(() {
      for (final name in visible) {
        if (!_selectedNames.remove(name)) _selectedNames.add(name);
      }
    });
  }

  /// 禁用插件：卸载但保留文件（移到「已禁用」分区，在全量列表里的位置不变）
  Future<void> _disablePlugin(Plugin plugin) async {
    final result = await _c.disable(plugin.name);
    if (result.isFailure && mounted) _showError(result.error!);
  }

  /// 重新导入已禁用插件
  Future<void> _enable(String name) async {
    final result = await _c.enable(name);
    if (result.isFailure && mounted) _showError(result.error!);
  }

  /// 删除插件文件（真正卸载，不可恢复；所有插件都可删）
  Future<void> _confirmDeletePlugin(String name) async {
    final ok = await WywDialog.showConfirm(
      title: '删除插件文件',
      message: '确认删除「${_c.displayNameOf(name)}」的插件文件？此操作不可恢复。',
      confirmText: '删除',
      confirmTextStyle: TextStyle(color: Theme.of(context).colorScheme.error),
    );
    if (!ok) return;
    final result = await _c.deletePlugin(name);
    if (result.isFailure && mounted) _showError(result.error!);
  }

  /// 删除文件名非法、无法成为插件的文件。
  Future<void> _confirmDeleteInvalidFile(String name) async {
    final ok = await WywDialog.showConfirm(
      title: '删除文件',
      message: '「$name」文件名不合法，无法作为插件加载。确认删除该文件？',
      confirmText: '删除',
      confirmTextStyle: TextStyle(color: Theme.of(context).colorScheme.error),
    );
    if (!ok) return;
    final result = await _c.deleteStrayFile(name, unimported: false);
    if (result.isFailure && mounted) _showError(result.error!);
  }

  /// **补回缺失的插件文件**：选一个 `.js`，其文件名（去掉 `.js`）与记录同名即可。
  ///
  /// 复用常规导入通道：名字撞上那条缺文件的记录时，`PluginController.create` 会走
  /// 「修复导入」分支 —— 补文件、保留顺序与用户字段，而不是新建一个插件。
  Future<void> _repairMissingPlugin(Plugin plugin) async {
    final picked = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: const ['js'],
    );
    final path = picked?.files.single.path;
    if (path == null || !mounted) return;
    final report = await _c.importFromFilePaths([path]);
    if (mounted) _showImportReport(report);
  }

  /// **认领**一条「未导入」文件：原样读回磁盘上那份 `.js`，为它建立索引记录。
  Future<void> _adoptUnimportedFile(String name) async {
    final result = await _c.adoptUnimportedFile(name);
    if (result.isFailure && mounted) _showError(result.error!);
  }

  /// 删除一条「未导入」文件（它不属于任何记录，删的纯粹是文件）。
  Future<void> _confirmDeleteUnimportedFile(String name) async {
    final ok = await WywDialog.showConfirm(
      title: '删除文件',
      message: '「$name」在磁盘上，但索引里没有它的记录。确认删除该文件？',
      confirmText: '删除',
      confirmTextStyle: TextStyle(color: Theme.of(context).colorScheme.error),
    );
    if (!ok) return;
    final result = await _c.deleteStrayFile(name, unimported: true);
    if (result.isFailure && mounted) _showError(result.error!);
  }

  // ===== 异常分区的批量动作 =====

  /// **全部导入**：把「未导入」里的 `.js` 一次全部认领成插件记录。
  ///
  /// 只覆盖这一类 —— 另外三类要么磁盘上本来就没有文件（文件缺失），要么文件名连
  /// 记录都建不了（文件名非法），都不是「导入」能解决的。逐条 `await`：每条都要读盘
  /// 注册 + 写一次 `index.json`，并发写索引不安全。单条失败不影响其余，最后按
  /// [_showImportReport] 的同一套口径汇总（成功 toast / 失败明细弹窗）。
  Future<void> _importAllIssues() async {
    if (_batchBusy) return;
    // 快照：循环里 `adoptUnimportedFile` 会把它从 unimportedFiles 里移走
    final names = [for (final file in _unimportedFiles) file.name];
    if (names.isEmpty) return;
    setState(() => _batchBusy = true);
    final imported = <String>[];
    final failed = <String, String>{};
    try {
      for (final name in names) {
        final result = await _c.adoptUnimportedFile(name);
        if (result.isSuccess) {
          imported.add(name);
        } else {
          failed[name] = result.error ?? '导入失败';
        }
      }
    } finally {
      if (mounted) setState(() => _batchBusy = false);
    }
    if (!mounted) return;
    _showImportReport(PluginImportReport(imported: imported, failed: failed));
  }

  /// **全部删除**：异常分区的四类问题一次性清掉。
  ///
  /// 与逐行删除**同一套语义**，只是循环一遍：
  ///   - 有记录的（注册失败 / 文件缺失）→ `PluginController.deletePlugin`（删记录；
  ///     缺文件那条本来就没有文件可删）；
  ///   - 没记录的野文件（未导入 / 文件名非法）→ `PluginController.deleteStrayFile`
  ///     （只删磁盘上的文件，不动索引）。
  ///
  /// 作用范围 = **当前可见**（关键词筛选之后）的异常项，与分区里显示的行一一对应；
  /// 有筛选时确认框里会点明。逐条 `await` 的原因同上，失败项不回滚已成功的。
  Future<void> _confirmDeleteAllIssues() async {
    if (_batchBusy) return;
    // 快照：确认框是 await，期间可能刷新目录
    final missing = [for (final plugin in _missingFiles) plugin.name];
    final failed = [for (final plugin in _failedPlugins) plugin.name];
    final unimported = [for (final file in _unimportedFiles) file.name];
    final invalid = [for (final file in _invalidFiles) file.name];
    final total =
        missing.length + failed.length + unimported.length + invalid.length;
    if (total == 0) return;

    final ok = await WywDialog.showConfirm(
      title: '删除全部异常项',
      message: _issueDeleteMessage(
        missing: missing.length,
        failed: failed.length,
        unimported: unimported.length,
        invalid: invalid.length,
      ),
      confirmText: '全部删除',
      confirmTextStyle: TextStyle(color: Theme.of(context).colorScheme.error),
    );
    if (!ok || !mounted) return;

    setState(() => _batchBusy = true);
    var done = 0;
    final failures = <String, String>{};
    try {
      for (final name in [...missing, ...failed]) {
        final result = await _c.deletePlugin(name);
        if (result.isSuccess) {
          done++;
        } else {
          // 删失败时记录还在，展示名查得到（与卡片、删除确认框同一口径）
          failures[_c.displayNameOf(name)] = result.error ?? '删除失败';
        }
      }
      for (final name in unimported) {
        final result = await _c.deleteStrayFile(name, unimported: true);
        if (result.isSuccess) {
          done++;
        } else {
          failures[name] = result.error ?? '删除失败';
        }
      }
      for (final name in invalid) {
        final result = await _c.deleteStrayFile(name, unimported: false);
        if (result.isSuccess) {
          done++;
        } else {
          failures[name] = result.error ?? '删除失败';
        }
      }
    } finally {
      if (mounted) setState(() => _batchBusy = false);
    }
    if (!mounted) return;
    if (failures.isEmpty) {
      WywDialog.showToast(
        message: '已删除异常分区全部 $done 项',
        context: context,
      );
      return;
    }
    _showBulkResultDialog(
      title: '删除结果',
      summary: '成功 $done 项，失败 ${failures.length} 项。',
      failures: failures,
    );
  }

  /// 「全部删除」确认框正文：逐类说清**删掉的是什么**（记录还是文件），
  /// 整类为空的行不出现；关键词筛选生效时点明作用范围。
  String _issueDeleteMessage({
    required int missing,
    required int failed,
    required int unimported,
    required int invalid,
  }) {
    final lines = <String>[
      if (failed > 0) '· 注册失败 $failed 条：删除记录与插件文件',
      if (missing > 0) '· 文件缺失 $missing 条：只删索引记录（磁盘上本来就没有文件）',
      if (unimported > 0) '· 未导入 $unimported 个：删除磁盘上的 .js 文件',
      if (invalid > 0) '· 文件名非法 $invalid 个：删除磁盘上的文件',
    ];
    final filterNote = _keyword.isEmpty
        ? ''
        : '\n\n当前有关键词「$_keyword」筛选，只处理匹配的项。';
    final total = missing + failed + unimported + invalid;
    return '确认删除异常分区里的全部 $total 项？此操作不可恢复。\n\n'
        '${lines.join('\n')}$filterNote';
  }

  // ===== UI 构建 =====

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isMultiSelectMode,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (_isMultiSelectMode) {
          _exitMultiSelectMode();
        }
      },
      child: SettingsDetailScaffold(
        title: _isMultiSelectMode
            // 多选模式右侧有 4 个动作，窄面板（~280）下会把标题挤没；
            // 单行 + 省略号保证这里不换行、不会把标题栏撑破（选中数量在选择条里还有一份）。
            ? Text(
                '已选择 ${_selectedNames.length} 项',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )
            : const Text('规则管理'),
        leading: _isMultiSelectMode
            ? IconButton(
                icon: const Icon(Icons.close),
                tooltip: '取消多选',
                onPressed: _exitMultiSelectMode,
              )
            : null,
        actions: _isMultiSelectMode ? _buildMultiSelectActions() : _buildActions(),
        body: Observer(
          builder: (context) {
            return Column(
              children: [
                if (_isMultiSelectMode) _buildSelectionBar(),
                _buildToolbar(),
                Expanded(child: _buildMainList()),
                if (_issueCount > 0 || _c.indexCorrupt) _buildIssueSection(),
              ],
            );
          },
        ),
      ),
    );
  }

  /// 多选模式的 AppBar 动作：导出 / 删除 / 禁用 / 启用。
  ///
  /// 「全选 / 取消全选 / 反选」**不在这里** —— 再加按钮，窄面板（~280）就放不下了；
  /// 它们放在列表上方的选择条里（见 [_buildSelectionBar]），那里可以换行。
  ///
  /// 批量动作在 [_batchBusy] 期间一并置灰：循环还没跑完时再点一次会让两条循环
  /// 并发写索引。
  List<Widget> _buildMultiSelectActions() {
    final enabled = _selectedNames.isNotEmpty && !_batchBusy;
    return [
      IconButton(
        tooltip: '导出选中到剪贴板',
        icon: const Icon(Icons.copy_all_outlined),
        onPressed: enabled
            ? () => _exportToClipboard(_selectedNames.toList())
            : null,
      ),
      IconButton(
        tooltip: '删除选中',
        icon: const Icon(Icons.delete_outline),
        onPressed: enabled ? _confirmBatchDelete : null,
      ),
      IconButton(
        tooltip: '禁用选中',
        icon: const Icon(Icons.toggle_off_rounded),
        onPressed: enabled ? _confirmBatchDisable : null,
      ),
      IconButton(
        tooltip: '启用选中',
        icon: const Icon(Icons.toggle_on_rounded),
        onPressed: enabled ? _confirmBatchEnable : null,
      ),
    ];
  }

  /// 多选模式下的**选择条**：全选 / 取消全选 / 反选 + 已选计数。
  ///
  /// 三个动作都只作用于**当前可见**的主列表（搜索 + 类型 + 状态筛选之后），所以
  /// 「筛出已禁用 → 全选 → 启用选中」是一条顺畅的路径。计数写成
  /// `已选 N 条 · 可见 M 条`：N ≠ M 时一眼能看出还有筛选之外的选中项。
  ///
  /// 用 [Wrap] 排布：窄面板下自动换行，任何宽度都不会溢出。
  Widget _buildSelectionBar() {
    final visibleCount = _visiblePlugins.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _selectionButton(
            label: '全选',
            icon: Icons.select_all_rounded,
            tooltip: '全选当前可见的规则',
            onPressed: visibleCount == 0 ? null : _selectAllVisible,
          ),
          _selectionButton(
            label: '取消全选',
            icon: Icons.deselect_rounded,
            tooltip: '取消全选（留在多选模式）',
            onPressed: _selectedNames.isEmpty ? null : _clearSelection,
          ),
          _selectionButton(
            label: '反选',
            icon: Icons.swap_horiz_rounded,
            tooltip: '反选当前可见的规则',
            onPressed: visibleCount == 0 ? null : _invertSelection,
          ),
          Text(
            '已选 ${_selectedNames.length} 条 · 可见 $visibleCount 条',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
        ],
      ),
    );
  }

  /// 选择条里的一个动作按钮（紧凑的「图标 + 文案」，带 tooltip 说明作用范围）。
  Widget _selectionButton({
    required String label,
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: TextButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 10),
        ),
      ),
    );
  }

  List<Widget> _buildActions() {
    return [
      IconButton(
        tooltip: '刷新（重扫插件目录）',
        icon: const Icon(Icons.refresh),
        onPressed: _c.loading ? null : () => unawaited(_c.rescan()),
      ),
      MenuAnchor(
        consumeOutsideTap: true,
        builder: (context, controller, child) => IconButton(
          tooltip: '更多',
          icon: const Icon(Icons.more_vert),
          onPressed: () =>
              controller.isOpen ? controller.close() : controller.open(),
        ),
        menuChildren: [
          _menuItem(
            icon: Icons.file_open_outlined,
            label: '从文件导入',
            onPressed: _importFromFiles,
          ),
          _menuItem(
            icon: Icons.content_paste_go,
            label: '从剪贴板导入',
            onPressed: _importFromClipboard,
          ),
          _menuItem(
            icon: Icons.copy_all_outlined,
            label: '导出全部到剪贴板',
            onPressed: () => _exportToClipboard(const []),
          ),
          _menuItem(
            icon: Icons.save_alt,
            label: '导出全部到文件',
            onPressed: () => _exportToFile(const []),
          ),
          _menuItem(
            icon: Icons.label_outline,
            label: '分类管理',
            onPressed: _openCategoryManager,
          ),
        ],
      ),
      IconButton(
        tooltip: '添加规则',
        icon: const Icon(Icons.add),
        onPressed: () => _openDetailPage(null),
      ),
    ];
  }

  Widget _menuItem({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    Color? color,
  }) {
    return MenuItemButton(
      onPressed: onPressed,
      child: Container(
        height: 48,
        constraints: const BoxConstraints(minWidth: 160),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 8),
              Text(label, style: color == null ? null : TextStyle(color: color)),
            ],
          ),
        ),
      ),
    );
  }

  /// 搜索框 + 右侧两个筛选（类型 / 状态）。
  ///
  /// 窄面板（设置页主从布局下可能只有 300 上下）放不下「搜索 + 两个筛选」一行，
  /// 所以按可用宽度分两种排法：够宽一行、不够则搜索独占一行、两个筛选平分下一行。
  Widget _buildToolbar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 宽排需要 132 + 120 + 16(间距) ≈ 268，再给搜索框留 ~140
          if (constraints.maxWidth >= 420) {
            return Row(
              children: [
                Expanded(child: _buildSearchField()),
                const SizedBox(width: 8),
                SizedBox(width: 132, child: _buildCategoryFilter()),
                const SizedBox(width: 8),
                SizedBox(width: 120, child: _buildStatusFilter()),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSearchField(),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _buildCategoryFilter()),
                  const SizedBox(width: 8),
                  Expanded(child: _buildStatusFilter()),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchCtrl,
      onChanged: (v) => setState(() => _keyword = v.trim()),
      decoration: InputDecoration(
        isDense: true,
        prefixIcon: const Icon(Icons.search, size: 18),
        suffixIcon: _keyword.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.clear, size: 18),
                tooltip: '清空',
                onPressed: () {
                  _searchCtrl.clear();
                  setState(() => _keyword = '');
                },
              ),
        hintText: '搜索插件名 / 描述 / 分类',
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _buildCategoryFilter() {
    return SelectField<PluginCategory?>(
      value: _categoryFilter,
      label: '类型',
      placeholder: '全部',
      options: [
        // 标签刻意短：窄面板下两个筛选各只分到 ~124px
        const SelectOption<PluginCategory?>(value: null, label: '全部'),
        for (final c in _c.categories.all)
          SelectOption<PluginCategory?>(value: c, label: c.label, icon: c.icon),
      ],
      onChanged: (v) => setState(() => _categoryFilter = v),
    );
  }

  Widget _buildStatusFilter() {
    return SelectField<_PluginStatusFilter>(
      value: _statusFilter,
      label: '状态',
      options: [
        for (final s in _PluginStatusFilter.values)
          SelectOption(value: s, label: s.label),
      ],
      onChanged: (v) => setState(() => _statusFilter = v),
    );
  }

  Widget _buildMainList() {
    final visible = _visiblePlugins;
    if (_c.plugins.isEmpty) return _buildEmptyState();
    if (visible.isEmpty) {
      return const Center(
        child: GeneralEmptyState(
          icon: Icons.search_off,
          title: '没有匹配的插件',
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _c.rescan(),
      child: ReorderableListView.builder(
        scrollController: _scrollController,
        // 列表不足一屏时也要能下拉刷新
        physics: const AlwaysScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        proxyDecorator: (child, index, animation) {
          return Material(
            elevation: 0,
            color: Colors.transparent,
            child: child,
          );
        },
        itemCount: visible.length,
        // 搜索/筛选生效时禁用拖拽：可见顺序不等于全量顺序，拖拽结果会反直觉
        onReorderItem: (int oldIndex, int newIndex) {
          if (_isFiltering) return;
          // 可见顺序就是全量列表里的相对顺序，但可见下标 ≠ 全量下标（主列表之外
          // 还有禁用 / 异常两块）。所以拿**落点那一行的名字**做锚点交给控制器，
          // 它在全量列表里定位插入，跨分区也不会错位。
          final rest = [...visible]..removeAt(oldIndex);
          final anchor = newIndex < rest.length ? rest[newIndex].name : null;
          // 落盘在 movePlugin 内部 await；列表改动在 await 之前同步生效
          unawaited(
            _c.movePlugin(name: visible[oldIndex].name, beforeName: anchor),
          );
        },
        itemBuilder: (BuildContext context, int index) {
          final plugin = visible[index];
          return _buildCard(plugin, index);
        },
      ),
    );
  }

  /// 任一筛选生效时禁用拖拽：可见顺序不等于全量顺序，拖拽结果会反直觉。
  bool get _isFiltering =>
      _keyword.isNotEmpty ||
      _categoryFilter != null ||
      _statusFilter != _PluginStatusFilter.all;

  Widget _buildEmptyState() {
    return const Center(
      child: GeneralEmptyState(
        icon: Icons.extension,
        title: '还没有规则，点击右上角 + 添加',
      ),
    );
  }

  /// 构建规则卡片。[reorderIndex] 是插件在**可见列表**里的下标（拖拽用）。
  Widget _buildCard(Plugin plugin, int reorderIndex) {
    final scheme = Theme.of(context).colorScheme;
    final category = _c.categoryOf(plugin);
    return Card(
      key: ValueKey(plugin.name),
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        selected: _selectedNames.contains(plugin.name),
        selectedTileColor: scheme.primaryContainer,
        onLongPress: () {
          if (!_isMultiSelectMode) {
            _enterMultiSelectMode(plugin.name);
          }
        },
        onTap: () {
          if (_isMultiSelectMode) {
            _toggleSelection(plugin.name);
          } else {
            _openDetailPage(plugin);
          }
        },
        leading: Icon(category.icon, color: category.color),
        title: Row(
          children: [
            Flexible(
              child: Text(
                _c.displayNameOf(plugin.name),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            if (!plugin.enabled) ...[
              const SizedBox(width: 6),
              _tag('已禁用'),
            ],
          ],
        ),
        subtitle: Text(
          _subtitleFor(plugin),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isMultiSelectMode)
              Checkbox(
                value: _selectedNames.contains(plugin.name),
                // 与点标题同一套语义（含「清空不退出多选模式」）
                onChanged: (_) => _toggleSelection(plugin.name),
              )
            else
              _popupMenu(plugin),
            if (!_isFiltering)
              ReorderableDragStartListener(
                index: reorderIndex,
                child: const Icon(Icons.drag_handle),
              ),
          ],
        ),
      ),
    );
  }

  /// 卡片副标题：分类 · 描述（描述缺失时回落到文件路径）
  String _subtitleFor(Plugin plugin) {
    final body = plugin.description.isNotEmpty
        ? plugin.description
        : plugin.filePath;
    return '${_c.categoryOf(plugin).label} — $body';
  }

  /// 卡片标题旁的小标签（当前只有「已禁用」）。
  Widget _tag(String text) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
      ),
    );
  }

  /// 每卡片的 MenuAnchor。
  ///
  /// **只放动作，不放属性**：展示名 / 分类 / 启用 / 代码 / 设置都在详情页
  /// （点卡片进入），这里保留高频动作作为快捷入口，避免每次都要进详情页。
  Widget _popupMenu(Plugin plugin) {
    final scheme = Theme.of(context).colorScheme;
    final hasUrl = plugin.cachedSourceUrl?.isNotEmpty ?? false;
    return MenuAnchor(
      consumeOutsideTap: true,
      builder:
          (BuildContext context, MenuController controller, Widget? child) {
        return IconButton(
          tooltip: '更多',
          icon: const Icon(Icons.more_vert),
          onPressed: () {
            if (controller.isOpen) {
              controller.close();
            } else {
              controller.open();
            }
          },
        );
      },
      menuChildren: [
        _menuItem(
          icon: Icons.tune,
          label: '详情与属性',
          onPressed: () => _openDetailPage(plugin),
        ),
        if (hasUrl)
          _menuItem(
            icon: Icons.language,
            label: '网站',
            onPressed: () => _openPluginWebsite(plugin),
          ),
        _menuItem(
          icon: Icons.copy_all_outlined,
          label: '导出到剪贴板',
          onPressed: () => _exportToClipboard([plugin.name]),
        ),
        // 启用开关：禁用 = 卸载但保留文件；两种状态在同一个列表里，就地切换
        _menuItem(
          icon: plugin.enabled
              ? Icons.toggle_off_rounded
              : Icons.toggle_on_rounded,
          label: plugin.enabled ? '禁用' : '启用',
          onPressed: () => plugin.enabled
              ? _disablePlugin(plugin)
              : _enable(plugin.name),
        ),
        // 删除：所有插件一视同仁（删了不会回来）
        _menuItem(
          icon: Icons.delete,
          label: '删除',
          color: scheme.error,
          onPressed: () => _confirmDeletePlugin(plugin.name),
        ),
      ],
    );
  }

  /// 异常行统一外观（图标 + 标题 + 原因 + 动作）。
  Widget _issueTile({
    required String keyName,
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    return ListTile(
      key: ValueKey(keyName),
      dense: true,
      visualDensity: VisualDensity.compact,
      leading: Icon(icon, size: 20, color: color),
      title: Text(title, style: const TextStyle(fontSize: 14)),
      subtitle: Text(
        subtitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11),
      ),
      onTap: onTap,
      trailing: trailing,
    );
  }

  /// 收起 / 展开「异常」分区（标题区与最右的箭头都走这里）。
  void _toggleIssueSection() {
    setState(() => _issueSectionExpanded = !_issueSectionExpanded);
  }

  /// 「异常」分区的**标题行**：左边标题（可点收起 / 展开），右边批量动作 + 展开箭头。
  ///
  /// 两个批量按钮都放在**同一行、靠右**（不再单独占一行）：
  ///   - **全部导入**：只对「未导入」生效（其余三类没有可导入的文件），为 0 时置灰；
  ///   - **全部删除**：四类一起清，计数 = 当前可见异常项总数。
  ///
  /// 窄面板（主从布局右窗格可能只有 280 上下）放不下「图标 + 文案」时，退回纯文案
  /// 按钮：宁可少个图标，也不换行、不溢出、不把标题挤没。
  /// 批量进行中（[_batchBusy]）两个按钮一并置灰，避免两条循环并发写 `index.json`。
  Widget _buildIssueHeader(ColorScheme scheme) {
    final importable = _unimportedFiles.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 「图标 + 文案」两个按钮 + 箭头约占 235，再给标题留出 ~90 才够摆字
          final compact = constraints.maxWidth < 326;
          return Row(
            children: [
              Expanded(child: _buildIssueTitleToggle(scheme)),
              if (_issueCount > 0) ...[
                _issueBulkButton(
                  compact: compact,
                  label: importable == 0 ? '全部导入' : '全部导入 $importable',
                  icon: Icons.download_for_offline_outlined,
                  tooltip: importable == 0
                      ? '没有「未导入」的插件文件'
                      : '为全部 $importable 个「未导入」文件建立索引并注册',
                  onPressed:
                      importable == 0 || _batchBusy ? null : _importAllIssues,
                ),
                const SizedBox(width: 2),
                _issueBulkButton(
                  compact: compact,
                  label: '全部删除',
                  icon: Icons.delete_sweep_outlined,
                  tooltip: '删除异常分区里的全部 $_issueCount 项',
                  color: scheme.error,
                  onPressed: _issueCount == 0 || _batchBusy
                      ? null
                      : _confirmDeleteAllIssues,
                ),
                const SizedBox(width: 2),
              ],
              _issueChevron(scheme),
            ],
          );
        },
      ),
    );
  }

  /// 标题区（警告图标 + 「异常 N」）：整块可点，切换展开 / 收起。
  ///
  /// [Expanded] 外面套的，宽度由标题行剩余空间决定；文字单行 + 省略号，
  /// 任何面板宽度都不会把这一行撑破。
  Widget _buildIssueTitleToggle(ColorScheme scheme) {
    return InkWell(
      onTap: _toggleIssueSection,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          children: [
            Icon(Icons.error_outline, size: 14, color: scheme.error),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                '异常 $_issueCount',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: scheme.error),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 标题行最右的展开箭头（点它也能收起 / 展开）。
  Widget _issueChevron(ColorScheme scheme) {
    return InkWell(
      onTap: _toggleIssueSection,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: AnimatedRotation(
          turns: _issueSectionExpanded ? 0.5 : 0,
          duration: const Duration(milliseconds: 200),
          child: Icon(
            Icons.keyboard_arrow_down,
            size: 18,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  /// 批量动作按钮。[compact] 为真时省掉图标（只留文案），窄面板下两个也摆得下。
  Widget _issueBulkButton({
    required bool compact,
    required String label,
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    Color? color,
  }) {
    return Tooltip(
      message: tooltip,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 32),
          padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 8),
          foregroundColor: color,
        ),
        child: compact
            ? Text(label)
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18),
                  const SizedBox(width: 8),
                  Text(label),
                ],
              ),
      ),
    );
  }

  /// 「异常」分区：**四类问题合在一起** ——
  ///   - **注册失败**：文件在、名字合法，但注册到 JS 引擎时抛错（记录还在列表里）；
  ///   - **文件缺失**：索引里有记录，磁盘上却没有 `{name}.js`
  ///     （记录、顺序与用户字段都还在，重新导入同名文件即恢复）；
  ///   - **未导入**：磁盘上有合法 `.js`，但索引里没有它的记录；
  ///   - **文件名非法**：连记录都建不了，只剩一条错误信息。
  ///
  /// 四类都不展示就等于凭空消失，所以默认展开。**没有一类是「扫描时自动删掉」**：
  /// 删除只能由用户在这里显式点 —— 扫描永远不替用户销毁文件。
  Widget _buildIssueSection() {
    final scheme = Theme.of(context).colorScheme;
    final tiles = <Widget>[
      for (final plugin in _missingFiles)
        _issueTile(
          keyName: 'missing-${plugin.name}',
          icon: Icons.link_off,
          color: scheme.error,
          title: _c.displayNameOf(plugin.name),
          subtitle: '插件文件缺失（${plugin.fileName}）。记录、顺序与属性都还在 —— '
              '点这一行进去写源码，或重新导入同名文件。',
          onTap: () => _openDetailPage(plugin),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: '删除记录',
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: () => _confirmDeletePlugin(plugin.name),
              ),
              TextButton.icon(
                icon: const Icon(Icons.file_open_outlined, size: 16),
                label: const Text('重新导入'),
                onPressed: () => _repairMissingPlugin(plugin),
              ),
            ],
          ),
        ),
      for (final plugin in _failedPlugins)
        _issueTile(
          keyName: 'failed-${plugin.name}',
          icon: Icons.report_gmailerrorred_outlined,
          color: scheme.error,
          title: plugin.title,
          subtitle: plugin.loadError ?? '',
          onTap: () => _openDetailPage(plugin),
          trailing: IconButton(
            tooltip: '删除文件',
            icon: const Icon(Icons.delete_outline, size: 20),
            onPressed: () => _confirmDeletePlugin(plugin.name),
          ),
        ),
      for (final file in _unimportedFiles)
        _issueTile(
          keyName: 'unimported-${file.name}',
          icon: Icons.insert_drive_file_outlined,
          color: scheme.onSurfaceVariant,
          title: file.name,
          subtitle: file.message,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: '删除文件',
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: () => _confirmDeleteUnimportedFile(file.name),
              ),
              TextButton.icon(
                icon: const Icon(Icons.download, size: 16),
                label: const Text('导入'),
                onPressed: () => _adoptUnimportedFile(file.name),
              ),
            ],
          ),
        ),
      for (final file in _invalidFiles)
        _issueTile(
          keyName: 'invalid-${file.name}',
          icon: Icons.report_gmailerrorred_outlined,
          color: scheme.error,
          title: file.name,
          subtitle: file.message,
          trailing: IconButton(
            tooltip: '删除文件',
            icon: const Icon(Icons.delete_outline, size: 20),
            onPressed: () => _confirmDeleteInvalidFile(file.name),
          ),
        ),
    ];

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildIssueHeader(scheme),
          if (_issueSectionExpanded) ...[
            if (_c.indexCorrupt)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                child: Text(
                  'index.json 读不懂：已保留原文件，未执行出厂安装。'
                  '列表可能不完整 —— 备份后手动删掉该文件可重建，'
                  '磁盘上的插件会出现在下面「未导入」里，一个都不会丢。',
                  style: TextStyle(fontSize: 11, color: scheme.error),
                ),
              ),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.4,
              ),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: tiles.length,
                itemBuilder: (context, index) => tiles[index],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 主列表的「状态」筛选取值。
enum _PluginStatusFilter {
  all('全部'),
  enabled('已启用'),
  disabled('已禁用');

  const _PluginStatusFilter(this.label);

  final String label;
}
