import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:wyw/plugins/plugin.dart';
import 'package:wyw/pages/plugin/plugin_controller.dart';
import 'package:wyw/bean/appbar/sys_app_bar.dart';
import 'package:wyw/bean/dialog/dialog_helper.dart';

/// 插件设置页。
///
/// 读取插件 JS 中声明的 `settings` 字段（`{key: {title, type, options, default}}`），
/// 动态渲染表单；读写通过插件基类 `loadSetting` / `saveSetting`（经 JS 桥持久化）。
class PluginSettingsPage extends StatefulWidget {
  const PluginSettingsPage({super.key, required this.pluginName});

  final String pluginName;

  @override
  State<PluginSettingsPage> createState() => _PluginSettingsPageState();
}

class _PluginSettingsPageState extends State<PluginSettingsPage> {
  final PluginController _c = inject<PluginController>();

  bool _loading = true;
  String? _error;
  Map<String, dynamic> _schema = {};
  final Map<String, dynamic> _values = {};

  Plugin? get _plugin => _c.getPlugin(widget.pluginName);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final plugin = _plugin;
    if (plugin == null || !plugin.isRegistered) {
      setState(() {
        _error = '插件未注册：${widget.pluginName}';
        _loading = false;
      });
      return;
    }
    try {
      // 读取插件声明的 settings schema（基类 getSettings() 返回 this.settings）
      final rawSettings = await plugin.invoke('getSettings', []);
      Map<String, dynamic> schema = {};
      if (rawSettings is Map) {
        schema = rawSettings.cast<String, dynamic>();
      }
      // 读取当前值
      final values = <String, dynamic>{};
      for (final key in schema.keys) {
        values[key] = await plugin.invoke('loadSetting', [key]);
      }
      if (!mounted) return;
      setState(() {
        _schema = schema;
        _values.addAll(values);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '读取设置失败：$e';
        _loading = false;
      });
    }
  }

  Future<void> _save(String key, dynamic value) async {
    final plugin = _plugin;
    if (plugin == null) return;
    try {
      await plugin.invoke('saveSetting', [key, value]);
      if (mounted) {
        setState(() {
          _values[key] = value;
        });
      }
    } catch (e) {
      if (mounted) {
        WywDialog.showToast(message: '保存「$key」失败：$e', context: context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SysAppBar(title: Text('${widget.pluginName} · 设置')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(_error!));
    }
    if (_schema.isEmpty) {
      return const Center(child: Text('该插件没有可配置的设置项'));
    }
    return ListView(
      children: [
        for (final entry in _schema.entries) _buildTile(entry.key, entry.value),
      ],
    );
  }

  Widget _buildTile(String key, dynamic def) {
    final Map<String, dynamic> meta =
        def is Map<String, dynamic> ? def : const {};
    final title = meta['title']?.toString() ?? key;
    final type = meta['type']?.toString() ?? 'input';
    final defaultValue = meta['default'];
    final current = _values[key] ?? defaultValue;

    switch (type) {
      case 'select':
        final options = (meta['options'] as List?) ?? const [];
        return ListTile(
          title: Text(title),
          trailing: DropdownButton<dynamic>(
            value: _dropdownValue(options, current),
            underline: const SizedBox.shrink(),
            items: [
              for (final opt in options)
                if (opt is Map)
                  DropdownMenuItem<dynamic>(
                    value: opt['value'],
                    child: Text(opt['text']?.toString() ?? ''),
                  ),
            ],
            onChanged: (v) {
              if (v != null) _save(key, v);
            },
          ),
        );
      case 'switch':
        return SwitchListTile(
          title: Text(title),
          value: current == true,
          onChanged: (v) => _save(key, v),
        );
      case 'input':
        return ListTile(
          title: Text(title),
          subtitle: TextField(
            controller: TextEditingController(text: current?.toString() ?? ''),
            decoration: const InputDecoration(isDense: true),
            onSubmitted: (v) => _save(key, v),
          ),
        );
      default:
        return ListTile(
          title: Text(title),
          subtitle: const Text('暂不支持的设置类型'),
        );
    }
  }

  dynamic _dropdownValue(List<dynamic> options, dynamic current) {
    for (final opt in options) {
      if (opt is Map && opt['value'] == current) return opt['value'];
    }
    if (options.isNotEmpty && options.first is Map) {
      return options.first['value'];
    }
    return current;
  }
}

/// `/settings/plugin/settings/` 路由参数（见 pluginModule，挂载于 settingsModule 之下）。
class PluginSettingsPageRouteArgs {
  const PluginSettingsPageRouteArgs({required this.pluginName});

  final String pluginName;
}
