import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:wyw/bean/dialog/dialog_helper.dart';
import 'package:wyw/bean/widget/empty_state_widget.dart';
import 'package:wyw/plugins/plugin.dart';
import 'package:wyw/plugins/plugin_type.dart';
import 'package:wyw/pages/plugin/plugin_controller.dart';
import 'package:wyw/pages/plugin/plugin_edit_page.dart';
import 'package:wyw/pages/plugin/plugin_settings_page.dart';
import 'package:wyw/pages/webview/webview_page.dart';
import 'package:wyw/bean/settings/settings_detail_scaffold.dart';

/// 规则（plugin）管理页面（卡片列表 + 多选模式）。
///
/// **操作流程**（参考 ScrapPluginViewPage 模式）：
///   1. 点击右上角「+」→ 弹窗输入规则名 + JS 代码 → 新增
///   2. 点击卡片 → 弹窗编辑 JS 代码 → 保存
///   3. 点击卡片右上角 ⋮ → 编辑 / 删除
///   4. 长按卡片 → 进入多选模式 → 点击多选 → 批量禁用
///   5. 拖拽卡片 → 调整顺序（内存顺序，文件按 name 索引）
///
/// **内置插件**（`assets/plugin`）只能禁用不能删除（删了下次启动也会自动
/// 重新禁用）；非内置插件可禁用也可删除。已禁用插件在底部可收起的分区中。
class PluginManagerPage extends StatefulWidget {
  const PluginManagerPage({super.key});

  @override
  State<PluginManagerPage> createState() => _PluginManagerPageState();
}

class _PluginManagerPageState extends State<PluginManagerPage> {
  final PluginController _c = inject<PluginController>();

  /// 是否处于多选模式
  bool _isMultiSelectMode = false;

  /// 已选中的规则名称集合
  final Set<String> _selectedNames = {};

  /// 「已禁用（未导入）」分区是否展开（默认收起）
  bool _disabledSectionExpanded = false;

  /// 已检查过是否有设置的插件
  final Set<String> _settingsChecked = {};

  /// 声明了设置项的插件
  final Set<String> _pluginsWithSettings = {};

  /// 已检查过是否声明源网站（getUrl）的插件
  final Set<String> _urlChecked = {};

  /// getUrl 返回了有效网址的插件
  final Set<String> _pluginsWithUrl = {};

  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // ===== 添加 / 编辑 / 删除 =====

  /// 打开「新增 / 编辑」页面。
  /// [plugin] 为 null 表示新建模式；非 null 表示编辑该插件。
  Future<void> _openEditPage(Plugin? plugin) async {
    String? initialContent;
    if (plugin != null) {
      initialContent = await plugin.getContent();
    }
    if (!mounted) return;
    final result = await context.pushNamed<PluginEditResult>(
      // pluginModule 挂在 settingsModule 之下，完整路径为 /settings/plugin/…
      '/settings/plugin/edit/',
      arguments: PluginEditPageRouteArgs(
        initialName: plugin?.name,
        initialContent: initialContent,
        isEdit: plugin != null,
      ),
    );
    if (result == null) return;
    if (plugin == null) {
      // 新建模式：写文件 + 注册 + 加入列表由 controller.create() 完成
      await _c.create(result.name, result.content);
    } else {
      await _c.updateItem(name: plugin.name, content: result.content);
    }
    if (_c.lastError != null && mounted) {
      _showError(_c.lastError!);
    }
  }

  Future<void> _confirmDelete(Plugin plugin) async {
    final ok = await WywDialog.showConfirm(
      title: '删除规则',
      message: '确认删除规则「${plugin.name}」？\n文件：${plugin.filePath}',
      confirmText: '删除',
      confirmTextStyle: TextStyle(color: Theme.of(context).colorScheme.error),
      cancelTextStyle: TextStyle(color: Theme.of(context).colorScheme.outline),
    );
    if (!ok) return;
    await _c.removeItem(plugin.name);
  }

  Future<void> _confirmBatchDisable() async {
    final ok = await WywDialog.showConfirm(
      title: '禁用规则',
      message: '确定要禁用选中的 ${_selectedNames.length} 条规则吗？禁用后可从底部「已禁用」分区重新导入。',
      confirmText: '禁用',
    );
    if (!ok) return;
    for (final name in _selectedNames.toList()) {
      await _c.disable(name);
    }
    if (mounted) {
      setState(() {
        _isMultiSelectMode = false;
        _selectedNames.clear();
      });
    }
  }

  /// 异步检查插件是否声明了设置项（结果缓存，用于决定是否显示「设置」菜单）。
  Future<void> _checkSettings(Plugin plugin) async {
    if (_settingsChecked.contains(plugin.name)) return;
    final has = await plugin.hasSettings();
    if (!mounted) return;
    setState(() {
      _settingsChecked.add(plugin.name);
      if (has) {
        _pluginsWithSettings.add(plugin.name);
      }
    });
  }

  /// 异步检查插件是否声明了源网站（getUrl 返回网址），决定是否显示「网站」菜单。
  Future<void> _checkUrl(Plugin plugin) async {
    if (_urlChecked.contains(plugin.name)) return;
    final url = await _c.getPluginUrl(plugin.name);
    if (!mounted) return;
    setState(() {
      _urlChecked.add(plugin.name);
      if (url != null) {
        _pluginsWithUrl.add(plugin.name);
      }
    });
  }

  /// 用 WebView 打开插件源网站。
  Future<void> _openPluginWebsite(Plugin plugin) async {
    final url = await _c.getPluginUrl(plugin.name);
    if (url == null || url.isEmpty) {
      if (mounted) _showError('该插件未声明网站地址');
      return;
    }
    if (!mounted) return;
    context.pushNamed('/webview/', arguments: WebviewPageRouteArgs(url: url));
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

  void _exitMultiSelectMode() {
    if (!_isMultiSelectMode) return;
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

  void _toggleSelection(String name) {
    setState(() {
      if (_selectedNames.contains(name)) {
        _selectedNames.remove(name);
        if (_selectedNames.isEmpty) _isMultiSelectMode = false;
      } else {
        _selectedNames.add(name);
      }
    });
  }

  /// 禁用插件：卸载但保留文件（移动到「已禁用」分区）
  Future<void> _disablePlugin(Plugin plugin) async {
    final ok = await _c.disable(plugin.name);
    if (!ok && mounted && _c.lastError != null) _showError(_c.lastError!);
  }

  /// 重新导入已禁用插件
  Future<void> _enable(String name) async {
    final ok = await _c.enable(name);
    if (!ok && mounted && _c.lastError != null) _showError(_c.lastError!);
  }

  /// 用内置版本更新插件（覆盖文件 + 热重载）。
  Future<void> _updatePlugin(Plugin plugin) async {
    final ok = await _c.updatePluginFromBuiltin(plugin.name);
    if (mounted) setState(() {});
    if (!ok && _c.lastError != null) _showError(_c.lastError!);
  }

  /// 更新已禁用内置插件的文件到内置版本。
  Future<void> _updateDisabledPlugin(String name) async {
    final ok = await _c.updatePluginFromBuiltin(name);
    if (mounted) setState(() {});
    if (!ok && _c.lastError != null) _showError(_c.lastError!);
  }

  /// 设置插件分类（null 表示清除覆盖，回退到声明/推断）
  Future<void> _setCategory(Plugin plugin, String? type) async {
    await _c.setCategory(plugin.name, type);
    if (mounted) setState(() {});
  }

  /// 删除已禁用插件的文件（真正卸载，不可恢复）
  Future<void> _confirmDeleteDisabled(String name) async {
    final ok = await WywDialog.showConfirm(
      title: '删除插件文件',
      message: '确认删除「$name」的插件文件？此操作不可恢复。',
      confirmText: '删除',
      confirmTextStyle: TextStyle(color: Theme.of(context).colorScheme.error),
    );
    if (!ok) return;
    final success = await _c.deleteDisabledPlugin(name);
    if (!success && mounted && _c.lastError != null) _showError(_c.lastError!);
  }

  /// 「已禁用（未导入）」分区：文件还在磁盘，但未加载到 App。
  /// 点「导入」可快速重新启用（重新注册并恢复排序位置）。
  /// 默认收起，点击标题栏可展开 / 收起。
  /// 内置插件只能导入；非内置插件额外提供「删除文件」。
  Widget _buildDisabledSection() {
    final disabled = _c.disabledPluginNames;
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
          InkWell(
            onTap: () {
              setState(() {
                _disabledSectionExpanded = !_disabledSectionExpanded;
              });
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 2),
              child: Row(
                children: [
                  Icon(Icons.extension_off, size: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(
                    '已禁用 ${disabled.length}',
                    style: TextStyle(fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  const Spacer(),
                  AnimatedRotation(
                    turns: _disabledSectionExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      size: 18,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_disabledSectionExpanded)
            // 高度上限：禁用项过多时在分区内滚动，避免撑爆页面布局（主列表被挤压 / 溢出）
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.4,
              ),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: disabled.length,
                itemBuilder: (context, index) {
                  final name = disabled[index];
                  return ListTile(
                    key: ValueKey('disabled-\$name'),
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    leading:
                        const Icon(Icons.insert_drive_file_outlined, size: 20),
                    title: Text(name, style: const TextStyle(fontSize: 14)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_c.updatablePluginNames.contains(name))
                          IconButton(
                            tooltip: '更新到内置版本',
                            icon: Icon(Icons.system_update_alt,
                                size: 20,
                                color: Theme.of(context).colorScheme.tertiary),
                            onPressed: () => _updateDisabledPlugin(name),
                          ),
                        if (!_c.isBuiltin(name))
                          IconButton(
                            tooltip: '删除文件',
                            icon: const Icon(Icons.delete_outline, size: 20),
                            onPressed: () => _confirmDeleteDisabled(name),
                          ),
                        TextButton.icon(
                          icon: const Icon(Icons.download, size: 16),
                          label: const Text('导入'),
                          onPressed: () => _enable(name),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
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
            ? Text('已选择 ${_selectedNames.length} 项')
            : const Text('规则管理'),
        leading: _isMultiSelectMode
            ? IconButton(
                icon: const Icon(Icons.close),
                tooltip: '取消多选',
                onPressed: _exitMultiSelectMode,
              )
            : null,
        actions: _isMultiSelectMode
            ? [
                IconButton(
                  tooltip: '禁用选中',
                  icon: const Icon(Icons.toggle_off_rounded),
                  onPressed:
                      _selectedNames.isEmpty ? null : _confirmBatchDisable,
                ),
              ]
            : [
                IconButton(
                  tooltip: '添加规则',
                  icon: const Icon(Icons.add),
                  onPressed: () => _openEditPage(null),
                ),
              ],
        body: Observer(
          builder: (context) {
            return Column(
              children: [
                Expanded(
                  child: _c.plugins.isEmpty
                      ? _buildEmptyState()
                      : ReorderableListView.builder(
                          buildDefaultDragHandles: false,
                          proxyDecorator: (child, index, animation) {
                            return Material(
                              elevation: 0,
                              color: Colors.transparent,
                              child: child,
                            );
                          },
                          itemCount: _c.plugins.length,
                          onReorderItem: (int oldIndex, int newIndex) {
                            _c.reorder(oldIndex, newIndex);
                          },
                          itemBuilder: (BuildContext context, int index) {
                            final plugin = _c.plugins[index];
                            return _buildCard(plugin, index);
                          },
                        ),
                ),
                if (_c.disabledPluginNames.isNotEmpty) _buildDisabledSection(),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: GeneralEmptyState(
        icon: Icons.extension,
        title: '还没有规则，点击右上角 + 添加',
      ),
    );
  }

  /// 构建规则卡片
  Widget _buildCard(Plugin plugin, int index) {
    _checkSettings(plugin);
    _checkUrl(plugin);
    return Card(
      key: ValueKey(plugin.name),
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        selected: _selectedNames.contains(plugin.name),
        selectedTileColor: Theme.of(context).colorScheme.primaryContainer,
        onLongPress: () {
          if (!_isMultiSelectMode) {
            _enterMultiSelectMode(plugin.name);
          }
        },
        onTap: () {
          if (_isMultiSelectMode) {
            _toggleSelection(plugin.name);
          } else {
            _openEditPage(plugin);
          }
        },
        leading: Icon(plugin.type.icon, color: plugin.type.color),
        title: Row(
          children: [
            Flexible(
              child: Text(
                plugin.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            if (plugin.hasUpdate) ...[
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 0.5),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '可更新',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color:
                            Theme.of(context).colorScheme.onSecondaryContainer,
                      ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Text(
          plugin.description.isNotEmpty ? plugin.description : plugin.filePath,
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
                onChanged: (bool? value) {
                  setState(() {
                    if (value == true) {
                      _selectedNames.add(plugin.name);
                    } else {
                      _selectedNames.remove(plugin.name);
                      if (_selectedNames.isEmpty) {
                        _isMultiSelectMode = false;
                      }
                    }
                  });
                },
              )
            else
              _popupMenu(plugin),
            ReorderableDragStartListener(
              index: index,
              child: const Icon(Icons.drag_handle),
            ),
          ],
        ),
      ),
    );
  }

  /// 每卡片的 MenuAnchor（编辑 / 删除）
  Widget _popupMenu(Plugin plugin) {
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
        if (plugin.hasUpdate)
          MenuItemButton(
            onPressed: () => _updatePlugin(plugin),
            child: Container(
              height: 48,
              constraints: BoxConstraints(minWidth: 112),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  children: [
                    Icon(Icons.system_update_alt,
                        color: Theme.of(context).colorScheme.tertiary),
                    const SizedBox(width: 8),
                    Text('更新',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.tertiary)),
                  ],
                ),
              ),
            ),
          ),
        MenuItemButton(
          onPressed: () => _openEditPage(plugin),
          child: Container(
            height: 48,
            constraints: BoxConstraints(minWidth: 112),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  const Icon(Icons.edit),
                  const SizedBox(width: 8),
                  const Text('编辑'),
                ],
              ),
            ),
          ),
        ),
        if (_settingsChecked.contains(plugin.name) &&
            _pluginsWithSettings.contains(plugin.name))
          MenuItemButton(
            onPressed: () {
              context.pushNamed(
                '/settings/plugin/settings/',
                arguments: PluginSettingsPageRouteArgs(pluginName: plugin.name),
              );
            },
            child: Container(
              height: 48,
              constraints: BoxConstraints(minWidth: 112),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  children: [
                    const Icon(Icons.settings),
                    const SizedBox(width: 8),
                    const Text('设置'),
                  ],
                ),
              ),
            ),
          ),
        if (_urlChecked.contains(plugin.name) &&
            _pluginsWithUrl.contains(plugin.name))
          MenuItemButton(
            onPressed: () => _openPluginWebsite(plugin),
            child: Container(
              height: 48,
              constraints: BoxConstraints(minWidth: 112),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  children: [
                    const Icon(Icons.language),
                    const SizedBox(width: 8),
                    const Text('网站'),
                  ],
                ),
              ),
            ),
          ),
        SubmenuButton(
          // 悬停稍作延迟再展开，避免扫过即弹；移开到其它项时焦点被抢走即自动收起
          hoverOpenDelay: const Duration(milliseconds: 250),
          menuChildren: [
            MenuItemButton(
              requestFocusOnHover: false,
              onPressed: () => _setCategory(plugin, null),
              child: Container(
                height: 48,
                constraints: BoxConstraints(minWidth: 112),
                child: const Align(
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      Icon(Icons.autorenew),
                      SizedBox(width: 8),
                      Text('跟随声明'),
                    ],
                  ),
                ),
              ),
            ),
            for (final t in PluginType.values)
              MenuItemButton(
                requestFocusOnHover: false,
                onPressed: () => _setCategory(plugin, t.name),
                child: Container(
                  height: 48,
                  constraints: BoxConstraints(minWidth: 112),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Row(
                      children: [
                        Icon(t.icon, size: 20),
                        const SizedBox(width: 8),
                        Text(t.label),
                      ],
                    ),
                  ),
                ),
              ),
          ],
          child: Container(
            height: 48,
            constraints: BoxConstraints(minWidth: 112),
            child: const Align(
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  Icon(Icons.label_outline),
                  SizedBox(width: 8),
                  Text('分类'),
                ],
              ),
            ),
          ),
        ),
        // 禁用开关：关掉即卸载（文件保留），重新启用走「已禁用」分区的导入
        MenuItemButton(
          onPressed: () => _disablePlugin(plugin),
          child: Container(
            height: 48,
            constraints: BoxConstraints(minWidth: 112),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  const Icon(Icons.toggle_off_rounded),
                  const SizedBox(width: 8),
                  const Text('禁用'),
                ],
              ),
            ),
          ),
        ),
        // 内置插件只能禁用不能删除（删了下次启动也会自动重新禁用）
        if (!plugin.isBuiltin)
          MenuItemButton(
            onPressed: () => _confirmDelete(plugin),
            child: Container(
              height: 48,
              constraints: BoxConstraints(minWidth: 112),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  children: [
                    const Icon(Icons.delete),
                    const SizedBox(width: 8),
                    const Text('删除'),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
