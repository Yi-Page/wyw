import 'package:flutter/material.dart';
import 'package:wyw/bean/dialog/dialog_helper.dart';
import 'package:wyw/pages/plugin/plugin_controller.dart';
import 'package:wyw/pages/plugin/widgets/category_icon_picker.dart';
import 'package:wyw/plugins/plugin_category.dart';

/// 分类管理弹窗：列出用户自定义分类（可编辑图标 / 展示名，可删除）+ 新建入口。
///
/// 只管理**用户显式创建**的分类；插件声明带出的「隐式自定义分类」不在这里
/// （它们没有用户填的名字，删掉也会被插件重新带出来）。
///
/// 由插件详情页的「分类」段与管理页的「更多」菜单共用，因此独立成文件。
class CategoryManagerDialog extends StatefulWidget {
  const CategoryManagerDialog({super.key, required this.controller});

  final PluginController controller;

  /// 打开弹窗的便捷入口。
  static Future<void> show(PluginController controller) {
    return WywDialog.show<void>(
      clickMaskDismiss: true,
      builder: (_) => CategoryManagerDialog(controller: controller),
    );
  }

  @override
  State<CategoryManagerDialog> createState() => _CategoryManagerDialogState();
}

class _CategoryManagerDialogState extends State<CategoryManagerDialog> {
  final TextEditingController _idCtrl = TextEditingController();
  final TextEditingController _labelCtrl = TextEditingController();
  String _error = '';

  /// 新建分类时选中的图标 key（空串 = 默认图标）
  String _iconKey = '';

  @override
  void dispose() {
    _idCtrl.dispose();
    _labelCtrl.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final result = await widget.controller.addCustomCategory(
      id: _idCtrl.text,
      label: _labelCtrl.text,
      iconKey: _iconKey,
    );
    if (!mounted) return;
    setState(() {
      _error = result.error ?? '';
      if (result.isSuccess) _iconKey = '';
    });
    if (result.isSuccess) {
      _idCtrl.clear();
      _labelCtrl.clear();
    }
  }

  /// 编辑分类：改展示名与图标，id 只读（id 是插件 `categoryId` 引用的键）。
  ///
  /// 这里刻意用 `TextFormField(initialValue:)` + 局部变量而不是外部
  /// `TextEditingController`：`showDialog` 的 future 在**路由 pop 时**就完成了，但
  /// 退场动画期间 `TextField` 仍然挂在树上；此时 dispose 外部 controller 会让动画中的
  /// `TextField` 摸到已销毁的 `ChangeNotifier`
  /// （`TextEditingController was used after being disposed`），断言打断当前帧后还会
  /// 连锁出一堆 layout / build scope 崩坏。`TextFormField` 自带内部 controller，随
  /// widget 一起销毁，没有这个时序问题。图标选择用 [StatefulBuilder] 就地刷新。
  Future<void> _edit(CustomCategory category) async {
    var editedLabel = category.label;
    var editedIcon = category.iconKey;
    final saved = await WywDialog.show<(String, String)>(
      clickMaskDismiss: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('编辑分类'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  initialValue: category.label,
                  autofocus: true,
                  onChanged: (v) => editedLabel = v,
                  onFieldSubmitted: (_) =>
                      Navigator.of(ctx).pop((editedLabel, editedIcon)),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    labelText: '显示名',
                  ),
                ),
                const SizedBox(height: 12),
                const Text('图标', style: TextStyle(fontSize: 12)),
                const SizedBox(height: 6),
                SizedBox(
                  width: 280,
                  child: CategoryIconPicker(
                    selected: editedIcon,
                    onSelected: (key) =>
                        setDialogState(() => editedIcon = key),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '分类 id：${category.id}\n'
                  'id 不可更改 —— 它是插件 categoryId 引用的键。'
                  '需要换 id 请删除后重建。',
                  style: const TextStyle(fontSize: 11),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(ctx).pop((editedLabel, editedIcon)),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (saved == null || !mounted) return;

    final result = await widget.controller.updateCustomCategory(
      id: category.id,
      label: saved.$1,
      iconKey: saved.$2,
    );
    if (!mounted) return;
    setState(() => _error = result.error ?? '');
  }

  Future<void> _remove(CustomCategory category) async {
    final ok = await WywDialog.showConfirm(
      title: '删除分类',
      message: '删除分类「${category.label}」？'
          '使用该分类的插件会变为未分类。',
      confirmText: '删除',
      confirmTextStyle: TextStyle(color: Theme.of(context).colorScheme.error),
    );
    if (!ok) return;
    final result = await widget.controller.removeCustomCategory(category.id);
    if (!mounted) return;
    setState(() => _error = result.error ?? '');
  }

  @override
  Widget build(BuildContext context) {
    final custom = widget.controller.customCategories;
    final registry = widget.controller.categories;
    return AlertDialog(
      title: const Text('分类管理'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('内置分类', style: TextStyle(fontSize: 12)),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                children: [
                  for (final c in PluginCategory.builtins)
                    Chip(
                      avatar: Icon(c.icon, size: 16, color: c.color),
                      label: Text(c.label),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              const Text('自定义分类', style: TextStyle(fontSize: 12)),
              const SizedBox(height: 4),
              if (custom.isEmpty)
                const Text('还没有自定义分类', style: TextStyle(fontSize: 12))
              else
                for (final c in custom)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      registry.byId(c.id)?.icon ?? CategoryIcons.fallback,
                      size: 20,
                      color: PluginCategory.customColor,
                    ),
                    title: Text(c.label),
                    subtitle: Text(c.id, style: const TextStyle(fontSize: 11)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: '编辑展示名与图标',
                          icon: const Icon(Icons.edit_outlined, size: 20),
                          onPressed: () => _edit(c),
                        ),
                        IconButton(
                          tooltip: '删除',
                          icon: const Icon(Icons.delete_outline, size: 20),
                          onPressed: () => _remove(c),
                        ),
                      ],
                    ),
                  ),
              const Divider(),
              const Text('新建分类', style: TextStyle(fontSize: 12)),
              const SizedBox(height: 4),
              TextField(
                controller: _idCtrl,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  labelText: '分类 id（英文，如 anime）',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _labelCtrl,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  labelText: '显示名（如 番剧）',
                ),
                onSubmitted: (_) => _add(),
              ),
              const SizedBox(height: 10),
              const Text('图标', style: TextStyle(fontSize: 12)),
              const SizedBox(height: 6),
              CategoryIconPicker(
                selected: _iconKey,
                onSelected: (key) => setState(() => _iconKey = key),
              ),
              if (_error.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  _error,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => WywDialog.dismiss(),
          child: const Text('关闭'),
        ),
        FilledButton.tonal(onPressed: _add, child: const Text('新建')),
      ],
    );
  }
}
