import 'package:flutter/material.dart';
import 'package:wyw/bean/appbar/sys_app_bar.dart';
import 'package:wyw/bean/dialog/dialog_helper.dart';

/// 插件「新增 / 编辑」共用页面。
///
/// [isEdit] 为 true 时名称只读；保存时 `Navigator.pop(PluginEditResult)`，
/// 由调用方（插件管理页）决定创建或更新。
class PluginEditPage extends StatefulWidget {
  const PluginEditPage({
    super.key,
    this.initialName,
    this.initialContent,
    this.isEdit = false,
  });

  final String? initialName;
  final String? initialContent;
  final bool isEdit;

  @override
  State<PluginEditPage> createState() => _PluginEditPageState();
}

class _PluginEditPageState extends State<PluginEditPage> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _contentCtrl;

  static const _kTemplate = '''class MyRule {
  run(input) {
    return 'Hello, ' + input;
  }
}
''';

  /// 占位类名：用于「名称改了但 JS 代码没改」时自动同步。
  static const _kPlaceholderClass = 'MyRule';

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName ?? '');
    _contentCtrl = TextEditingController(
      text: widget.initialContent ?? _kTemplate,
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final name = _nameCtrl.text.trim();
    final content = _contentCtrl.text;
    if (name.isEmpty) {
      WywDialog.showToast(message: '规则名不能为空', context: context);
      return;
    }
    Navigator.of(context).pop(PluginEditResult(name: name, content: content));
  }

  /// 名称变化时同步 JS 代码里的类名占位符。
  ///
  /// 仅当内容里仍含 `_kPlaceholderClass` 才同步，避免覆盖用户已编辑的代码。
  void _syncClassName(String newName) {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;
    final content = _contentCtrl.text;
    if (content.contains(_kPlaceholderClass)) {
      _contentCtrl.text = content.replaceFirst(_kPlaceholderClass, trimmed);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SysAppBar(
        title: Text(widget.isEdit ? '编辑规则' : '添加规则'),
        actions: [
          FilledButton(
            onPressed: _save,
            child: Text(widget.isEdit ? '保存' : '添加'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '规则名（字母开头，仅含字母/数字/_/-）',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 4),
            TextField(
              controller: _nameCtrl,
              readOnly: widget.isEdit,
              onChanged: _syncClassName,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                hintText: 'my_rule',
              ),
              style: const TextStyle(fontFamily: 'monospace'),
            ),
            const SizedBox(height: 12),
            const Text(
              'JS 代码（类名必须与上方规则名一致）',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: TextField(
                controller: _contentCtrl,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `/settings/plugin/edit/` 路由参数（见 pluginModule，挂载于 settingsModule 之下）。
class PluginEditPageRouteArgs {
  const PluginEditPageRouteArgs({
    this.initialName,
    this.initialContent,
    this.isEdit = false,
  });

  final String? initialName;
  final String? initialContent;
  final bool isEdit;
}

/// 新增/编辑页的保存结果。
class PluginEditResult {
  final String name;
  final String content;
  PluginEditResult({required this.name, required this.content});
}
