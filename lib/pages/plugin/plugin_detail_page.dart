import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:wyw/bean/appbar/sys_app_bar.dart';
import 'package:wyw/bean/dialog/dialog_helper.dart';
import 'package:wyw/bean/widget/content_section.dart';
import 'package:wyw/bean/widget/kazumi_menu.dart';
import 'package:wyw/bean/widget/segmented_choice.dart';
import 'package:wyw/bean/widget/select_field.dart';
import 'package:wyw/pages/plugin/plugin_controller.dart';
import 'package:wyw/pages/plugin/widgets/category_manager_dialog.dart';
import 'package:wyw/pages/plugin/widgets/plugin_settings_form.dart';
import 'package:wyw/pages/webview/webview_page.dart';
import 'package:wyw/plugins/plugin.dart';
import 'package:wyw/utils/clipboard.dart';

/// 插件详情页：**以插件名为唯一入口**的单页状态机，新建与编辑共用。
///
/// 进来只看 `pluginName` 能不能在插件列表里匹配到：
///   - **匹配到** → 编辑模式：属性直接改（400ms 防抖落盘）；源码改的是一份**副本**，
///     可随时「校验」，确认后再「保存」（写盘 + 热重载）。插件名只读。
///   - **没匹配到** → 新建模式：插件名与属性都能填，点「保存」把这条**插件记录**建出来
///     （[PluginController.addPlugin]，此时还没有源码）；创建成功后插件名锁定、
///     「代码」段开放 —— 也就是「先立身份，再写代码」。
///
/// 分段：基本（标识 / 展示名 / 分类 / 简介 / 主页 / 只读信息）、代码、设置（插件声明了
/// settings schema 且已注册时才出现）。
class PluginDetailPage extends StatefulWidget {
  const PluginDetailPage({super.key, this.pluginName});

  /// 插件名；null 或列表里查不到 = 新建。
  final String? pluginName;

  @override
  State<PluginDetailPage> createState() => _PluginDetailPageState();
}

/// `/settings/plugin/detail/` 路由参数。
class PluginDetailRouteArgs {
  const PluginDetailRouteArgs({this.pluginName});

  final String? pluginName;
}

/// 详情页分段
enum _DetailSection { basic, code, settings }

class _PluginDetailPageState extends State<PluginDetailPage> {
  final PluginController _c = inject<PluginController>();

  /// 台账字段落盘防抖：不逐字符写 `index.json`
  static const Duration _fieldDebounce = Duration(milliseconds: 400);

  late final TextEditingController _nameCtrl;
  late final TextEditingController _codeCtrl;

  final Map<PluginField, TextEditingController> _attrCtrls = {
    for (final field in PluginField.values) field: TextEditingController(),
  };
  final Map<PluginField, Timer> _attrTimers = {};

  /// 本页的插件标识。创建成功后就地更新，页面随即切进编辑模式。
  String? _name;

  /// 新建模式下还没落盘、只存在的这个下拉框里的分类。
  String _draftCategoryId = '';

  /// 代码段：编辑器里的**副本**内容，以及它对应的「已保存」版本（用于标出未保存）。
  String _savedCode = '';
  bool _validated = false;
  String? _validationError;
  List<String> _validationWarnings = const [];

  _DetailSection _section = _DetailSection.basic;
  bool _loading = true;
  bool _saving = false;

  /// 列表里匹配得到的插件；null = 新建模式。
  Plugin? get _plugin => _name == null ? null : _c.pluginByName(_name!);

  /// 没匹配到插件（名字为空、或列表里没这个名字）= 新建。
  bool get _isNew => _plugin == null;

  @override
  void initState() {
    super.initState();
    _name = widget.pluginName;
    _nameCtrl = TextEditingController(text: widget.pluginName ?? '');
    _codeCtrl = TextEditingController();
    // 一改动就把上一次的校验结果作废（不 setState：下面的 ValueListenableBuilder 会重建）
    _codeCtrl.addListener(() {
      _validated = false;
      _validationError = null;
      _validationWarnings = const [];
    });
    unawaited(_load());
  }

  @override
  void dispose() {
    for (final timer in _attrTimers.values) {
      timer.cancel();
    }
    // 离开页面时把未落盘的属性编辑补写一次（防抖窗口内退出也不丢）
    for (final field in PluginField.values) {
      unawaited(_commitField(field));
    }
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    for (final controller in _attrCtrls.values) {
      controller.dispose();
    }
    super.dispose();
  }

  // ===== 加载 =====

  Future<void> _load() async {
    final plugin = _plugin;
    if (plugin == null) {
      setState(() => _loading = false);
      return;
    }
    await _probeCapabilities();
    _fillFields(plugin);
    await _loadCode(plugin);
    if (mounted) setState(() => _loading = false);
  }

  /// 读源码到编辑器**副本**里。没有源码（新建 / 文件丢了）就给一份类名正确的骨架，
  /// 免得用户写出类名与插件标识不一致的代码 —— 那是校验必错的第一大来源。
  Future<void> _loadCode(Plugin plugin) async {
    var content = '';
    if (!plugin.fileMissing) {
      try {
        content = await plugin.readSource();
      } catch (e) {
        _showError('读取插件源码失败：$e');
      }
    }
    if (content.isEmpty) content = _skeleton(plugin.name);
    _codeCtrl.text = content;
    _savedCode = content;
  }

  void _fillFields(Plugin plugin) {
    for (final field in PluginField.values) {
      _attrCtrls[field]!.text = plugin.fieldValue(field);
    }
  }

  static String _skeleton(String name) =>
      'class $name extends PluginSource {\n'
      '  // 在这里实现 search / getDetail / play / openReader 等方法\n'
      '}\n';

  Future<void> _probeCapabilities() async {
    final name = _name;
    if (name == null) return;
    await _c.ensureCapabilities(name);
    if (mounted) setState(() {});
  }

  // ===== 分段 =====

  List<SegmentedChoiceItem<_DetailSection>> get _segments => [
        const SegmentedChoiceItem(
          value: _DetailSection.basic,
          label: '基本',
          icon: Icons.tune,
        ),
        // 「先立身份，再写代码」：记录还没落地时不给代码段
        if (!_isNew)
          const SegmentedChoiceItem(
            value: _DetailSection.code,
            label: '代码',
            icon: Icons.code,
          ),
        if (_hasSettingsSection)
          const SegmentedChoiceItem(
            value: _DetailSection.settings,
            label: '设置',
            icon: Icons.settings,
          ),
      ];

  bool get _hasSettingsSection =>
      !_isNew && (_plugin?.hasSettingsCached ?? false);

  /// 当前生效的分段（分段可能因状态变化消失，需回落到「基本」）
  _DetailSection get _effectiveSection {
    final available = _segments.map((s) => s.value);
    return available.contains(_section) ? _section : _DetailSection.basic;
  }

  // ===== 基本段：台账字段 =====

  void _onFieldChanged(PluginField field, String _) {
    _attrTimers[field]?.cancel();
    _attrTimers[field] = Timer(_fieldDebounce, () => _commitField(field));
  }

  /// 把某个属性写回记录。新建模式没有记录可写，值留在输入框里等「保存」。
  Future<void> _commitField(PluginField field) async {
    // remove 顺带取消：map 的值类型是非空 Timer，不能赋 null
    _attrTimers.remove(field)?.cancel();
    final plugin = _plugin;
    final controller = _attrCtrls[field];
    if (plugin == null || controller == null) return;
    // 与已落盘的值相同就不写（避免每次进入页面都写一遍索引）
    if (plugin.fieldValue(field) == controller.text.trim()) return;
    await _c.setPluginField(plugin.name, field, controller.text);
    if (mounted) setState(() {});
  }

  Future<void> _setCategory(String? categoryId) async {
    final id = categoryId ?? '';
    final plugin = _plugin;
    if (plugin == null) {
      setState(() => _draftCategoryId = id);
      return;
    }
    await _c.setPluginField(plugin.name, PluginField.categoryId, id);
    if (mounted) setState(() {});
  }

  // ===== 代码段：副本 + 校验 + 保存 =====

  void _validateDraft() {
    final name = _name?.trim() ?? '';
    if (name.isEmpty) {
      setState(() {
        _validated = true;
        _validationError = '先填插件标识（它必须与 JS 类名逐字符相同）';
        _validationWarnings = const [];
      });
      return;
    }
    final check = (_plugin ?? Plugin(name: name)).checkSource(_codeCtrl.text);
    setState(() {
      _validated = true;
      _validationError = check.ok ? null : check.message;
      _validationWarnings = check.warnings;
    });
  }

  Future<void> _saveCode() async {
    final plugin = _plugin;
    if (plugin == null) return;
    setState(() => _saving = true);
    final result =
        await _c.updateItem(name: plugin.name, content: _codeCtrl.text);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (result.isSuccess) _savedCode = _codeCtrl.text;
    });
    if (result.isFailure) {
      _showError(result.error!);
      return;
    }
    WywDialog.showToast(message: '源码已保存', context: context);
    await _probeCapabilities(); // 设置项声明可能变了
  }

  // ===== 新建：以插件为单位落一条记录 =====

  Future<void> _saveNew() async {
    final draft = Plugin(
      name: _nameCtrl.text.trim(),
      displayName: _attrCtrls[PluginField.displayName]!.text.trim(),
      categoryId: _draftCategoryId,
      homepage: _attrCtrls[PluginField.homepage]!.text.trim(),
      description: _attrCtrls[PluginField.description]!.text.trim(),
    );
    setState(() => _saving = true);
    final result = await _c.addPlugin(draft);
    if (!mounted) return;
    setState(() => _saving = false);
    if (result.isFailure) {
      _showError(result.error!);
      return;
    }
    final created = result.plugin!;
    await _loadCode(created);
    if (!mounted) return;
    setState(() {
      _name = created.name;
      _nameCtrl.text = created.name; // 名字已锁定，输入框转为只读
      _section = _DetailSection.code; // 直接送到代码段
    });
    WywDialog.showToast(
      message: '已创建「${created.name}」，现在写源码',
      context: context,
    );
  }

  // ===== 更多操作 =====

  Future<void> _openWebsite() async {
    final plugin = _plugin;
    if (plugin == null) return;
    final url = plugin.cachedSourceUrl;
    if (url == null || url.isEmpty) {
      _showError('该插件未声明网站地址');
      return;
    }
    if (!mounted) return;
    context.pushNamed('/webview/', arguments: WebviewPageRouteArgs(url: url));
  }

  Future<void> _exportToClipboard() async {
    final plugin = _plugin;
    if (plugin == null) return;
    final json = await _c.exportBundleJson([plugin.name]);
    await copyToClipboard(json, toastMessage: null);
    if (!mounted) return;
    WywDialog.showToast(message: '已复制到剪贴板', context: context);
  }

  Future<void> _confirmDelete() async {
    final plugin = _plugin;
    if (plugin == null) return;
    final ok = await WywDialog.showConfirm(
      title: '删除插件',
      message: '确认删除「${plugin.title}」？\n文件：${plugin.filePath}',
      confirmText: '删除',
      confirmTextStyle: TextStyle(color: Theme.of(context).colorScheme.error),
      cancelTextStyle: TextStyle(color: Theme.of(context).colorScheme.outline),
    );
    if (!ok) return;
    final result = await _c.deletePlugin(plugin.name);
    if (!mounted) return;
    if (result.isFailure) {
      _showError(result.error!);
      return;
    }
    Navigator.of(context).pop();
  }

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

  // ===== UI =====

  @override
  Widget build(BuildContext context) {
    final title = _isNew ? '添加插件' : _c.displayNameOf(_name!);
    if (_loading) {
      return Scaffold(
        appBar: SysAppBar(title: Text(title)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: SysAppBar(
        title: Text(title),
        actions: [
          if (!_isNew)
            KazumiMenuButton(
              menuChildren: _buildMoreActions(),
              builder: (context, toggle) => IconButton(
                tooltip: '更多操作',
                onPressed: toggle,
                icon: const Icon(Icons.more_horiz_rounded),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SegmentedChoice<_DetailSection>(
              value: _effectiveSection,
              segments: _segments,
              onChanged: (v) => setState(() => _section = v),
            ),
          ),
          Expanded(child: _buildSection()),
        ],
      ),
      floatingActionButton: _buildSaveFab(),
    );
  }

  /// 主操作：**只有新建模式需要**（把记录建出来）。
  ///
  /// 其余段不再用悬浮按钮：属性是即时生效的，源码段的「保存源码」就放在段内的操作行里
  /// —— 用悬浮按钮就得在段底部留出一条空白避免遮挡，那是白扔的高度。
  Widget? _buildSaveFab() {
    if (!_isNew) return null;
    return FloatingActionButton.extended(
      onPressed: _saving ? null : _saveNew,
      icon: _fabIcon(Icons.add),
      label: Text(_saving ? '处理中' : '保存'),
    );
  }

  Widget _fabIcon(IconData icon) => _saving
      ? const SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        )
      : Icon(icon);

  Widget _buildSection() {
    switch (_effectiveSection) {
      case _DetailSection.basic:
        return _buildBasicSection();
      case _DetailSection.code:
        return _buildCodeSection();
      case _DetailSection.settings:
        return PluginSettingsForm(pluginName: _name!);
    }
  }

  // ----- 基本段 -----

  Widget _buildBasicSection() {
    final plugin = _plugin;
    // 先解析一次生效分类：未注册的 categoryId 会就地登记成隐式自定义分类，
    // 这样下拉框的选项里一定含有当前值（否则 SelectField 选不中）
    if (plugin != null) _c.categoryOf(plugin);
    return ListView(
      // 新建模式底部有悬浮「保存」，留出让位；编辑模式没有悬浮按钮，不留空
      padding: EdgeInsets.fromLTRB(16, 8, 16, _isNew ? 104 : 8),
      children: [
        ContentSection(
          title: '插件标识',
          description: _isNew
              ? '同时是文件名、JS 类名与引擎槽位名 —— 保存后不可更改'
              : '同时是文件名、JS 类名与引擎槽位名，不可更改',
          child: TextField(
            controller: _nameCtrl,
            readOnly: !_isNew,
            style: const TextStyle(fontFamily: 'monospace'),
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              hintText: 'my_rule',
            ),
          ),
        ),
        const SizedBox(height: 20),
        ContentSection(
          title: '展示名',
          description: _c.useDisplayName
              ? '只影响界面显示；留空则显示插件名'
              : '⚠️ 当前「设置 → 界面设置 → 插件名称显示」选的是「插件名」，'
                  '此处的展示名不会显示（改完可在设置里切回）',
          child: _attrField(PluginField.displayName, hint: '留空显示插件名'),
        ),
        const SizedBox(height: 20),
        _buildCategorySection(plugin),
        const SizedBox(height: 20),
        ContentSection(
          title: '简介',
          description: '管理页卡片的副标题；留空则显示文件路径',
          child: _attrField(PluginField.description),
        ),
        const SizedBox(height: 20),
        ContentSection(
          title: '主页',
          description: '如 https://…',
          child: _attrField(PluginField.homepage),
        ),
        if (plugin != null) ...[
          const SizedBox(height: 20),
          ContentSection.group(
            title: '只读信息',
            children: _buildInfoRows(plugin),
          ),
        ],
      ],
    );
  }

  Widget _buildCategorySection(Plugin? plugin) {
    return ContentSection(
      title: '分类',
      description: '留空则按插件实现的方法自动判断（play→视频 / '
          'openReader→漫画 / openNovelReader→小说）',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SelectField<String>(
            value: plugin?.categoryId ?? _draftCategoryId,
            options: [
              const SelectOption(value: '', label: '自动判断'),
              for (final c in _c.categories.all)
                SelectOption(value: c.id, label: c.label, icon: c.icon),
            ],
            onChanged: _setCategory,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              // 弹窗关闭后必须重建本页：分类选项是在 build 时从注册表取的，
              // 而本页没有包 Observer（弹窗里的增删改不会通知到这里）。
              onPressed: () async {
                await CategoryManagerDialog.show(_c);
                if (mounted) setState(() {});
              },
              icon: const Icon(Icons.label_outline, size: 18),
              label: const Text('管理分类'),
            ),
          ),
        ],
      ),
    );
  }

  /// 一个用户可编辑字段的输入框（展示名 / 简介 / 主页共用同一外观）。
  Widget _attrField(PluginField field, {String? hint}) {
    return TextField(
      controller: _attrCtrls[field],
      onChanged: (value) => _onFieldChanged(field, value),
      onSubmitted: (_) => unawaited(_commitField(field)),
      decoration: InputDecoration(
        isDense: true,
        border: const OutlineInputBorder(),
        hintText: hint,
      ),
    );
  }

  List<Widget> _buildInfoRows(Plugin plugin) {
    return [
      _infoRow('状态', _statusLabel(plugin)),
      if (plugin.fileMissing)
        _infoRow('提示', '还没有源码。到「代码」段写入并保存，插件即可启用。'),
      if (plugin.loadError != null)
        _infoRow('失败原因', plugin.loadError ?? ''),
      _infoRow('生效分类', _c.categoryOf(plugin).label),
      _infoRow('文件', plugin.filePath),
    ];
  }

  String _statusLabel(Plugin plugin) => switch (plugin.presence) {
        PluginPresence.missing => '待写入源码',
        PluginPresence.disabled => '已禁用',
        PluginPresence.failed => '加载失败',
        _ => '已启用',
      };

  Widget _infoRow(String label, String value) {
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      title: Text(label, style: const TextStyle(fontSize: 13)),
      subtitle: Text(value, style: const TextStyle(fontSize: 12)),
    );
  }

  // ----- 代码段 -----

  Widget _buildCodeSection() {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      // 底部不留白：「保存源码」在下面的操作行里，不需要为悬浮按钮让位
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 说明 + 状态 + 两个动作挤在一行会在窄面板溢出，用 Wrap 自动折行
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '类名必须是 `${_name ?? ''}`（编辑的是副本，保存后才写盘）',
                style: const TextStyle(fontSize: 12),
              ),
              // 只在内容与已保存版本不同时出现
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _codeCtrl,
                builder: (_, value, __) => value.text == _savedCode
                    ? const SizedBox.shrink()
                    : Text('未保存',
                        style: TextStyle(fontSize: 11, color: scheme.error)),
              ),
              TextButton.icon(
                onPressed: _validateDraft,
                icon: const Icon(Icons.rule, size: 18),
                label: const Text('校验'),
              ),
              FilledButton.tonalIcon(
                onPressed: _saving ? null : _saveCode,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check, size: 18),
                label: const Text('保存源码'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _codeCtrl,
            builder: (_, value, __) => _buildValidationResult(),
          ),
          Expanded(
            child: TextField(
              controller: _codeCtrl,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 校验结果：错误（红）/ 通过（绿）/ 提示（黄，**不阻断保存**）。
  Widget _buildValidationResult() {
    if (!_validated) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;

    if (_validationError != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _resultRow(Icons.error_outline, scheme.error, _validationError!),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _resultRow(
            Icons.check_circle_outline,
            scheme.primary,
            _validationWarnings.isEmpty
                ? '校验通过：括号配平、恰好一个顶层类、类名与插件标识一致'
                : '校验通过（有提示，不影响保存）',
          ),
          for (final warning in _validationWarnings)
            _resultRow(Icons.warning_amber_outlined, scheme.tertiary, warning),
        ],
      ),
    );
  }

  Widget _resultRow(IconData icon, Color color, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 12, color: color)),
          ),
        ],
      ),
    );
  }

  // ----- 更多操作（导航栏菜单）-----

  List<Widget> _buildMoreActions() {
    final plugin = _plugin;
    if (plugin == null) return const [];
    final colors = Theme.of(context).colorScheme;
    Widget item(IconData icon, String label, VoidCallback onPressed,
        {Color? color}) {
      return MenuItemButton(
        onPressed: onPressed,
        leadingIcon: Icon(icon, color: color),
        child:
            Text(label, style: color == null ? null : TextStyle(color: color)),
      );
    }

    return [
      if (plugin.cachedSourceUrl?.isNotEmpty ?? false)
        item(Icons.language, '打开源网站', _openWebsite),
      item(Icons.copy_all_outlined, '导出到剪贴板', _exportToClipboard),
      const Divider(),
      item(Icons.delete_outline, '删除插件', _confirmDelete, color: colors.error),
    ];
  }
}
