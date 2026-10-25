import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:wyw/bean/dialog/dialog_helper.dart';
import 'package:wyw/bean/widget/select_field.dart';
import 'package:wyw/pages/plugin/plugin_controller.dart';
import 'package:wyw/plugins/plugin.dart';
import 'package:wyw/services/logging/log_tags.dart';
import 'package:wyw/services/logging/logger.dart';
import 'package:wyw/utils/constants.dart';

/// 插件设置表单：读取插件 JS 中声明的 `settings` 字段
/// （`{key: {title, type, options, default}}`）动态渲染表单，
/// 读写通过插件基类 `loadSetting` / `saveSetting`（经 JS 桥持久化）。
///
/// 从原独立「插件设置页」迁入插件详情页的「设置」段 —— 插件的各类属性集中到
/// 一处，不再需要为设置单独开一个页面。
class PluginSettingsForm extends StatefulWidget {
  const PluginSettingsForm({super.key, required this.pluginName});

  final String pluginName;

  @override
  State<PluginSettingsForm> createState() => _PluginSettingsFormState();
}

class _PluginSettingsFormState extends State<PluginSettingsForm> {
  final PluginController _c = inject<PluginController>();

  /// 文本类设置项的落盘防抖：停止输入后才过一次 JS 桥，避免逐字符调用。
  static const Duration _saveDebounce = Duration(milliseconds: 400);

  bool _loading = true;
  String? _error;
  Map<String, dynamic> _schema = {};
  final Map<String, dynamic> _values = {};

  /// 文本类设置项的 controller（按 key 复用，dispose 时统一释放）。
  final Map<String, TextEditingController> _textControllers = {};
  final Map<String, Timer> _saveTimers = {};

  /// 已输入但尚未落盘的值（退出时补写，兜住防抖窗口内返回的情况）。
  final Map<String, dynamic> _pendingValues = {};

  Plugin? get _plugin => _c.getPlugin(widget.pluginName);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final timer in _saveTimers.values) {
      timer.cancel();
    }
    _saveTimers.clear();
    _flushPendingValues();
    for (final controller in _textControllers.values) {
      controller.dispose();
    }
    _textControllers.clear();
    super.dispose();
  }

  /// 取（或惰性创建）某设置项的输入 controller。
  TextEditingController _controllerFor(String key, dynamic current) {
    return _textControllers.putIfAbsent(
      key,
      () => TextEditingController(text: current?.toString() ?? ''),
    );
  }

  /// 输入变化：防抖落盘。
  void _onTextChanged(String key, String value) {
    _pendingValues[key] = value;
    _saveTimers[key]?.cancel();
    _saveTimers[key] = Timer(_saveDebounce, () {
      _saveTimers.remove(key);
      final pending = _pendingValues.remove(key);
      if (pending != null) _save(key, pending);
    });
  }

  /// 回车提交：取消防抖立即落盘。
  void _onSubmitted(String key, String value) {
    _saveTimers.remove(key)?.cancel();
    _pendingValues.remove(key);
    _save(key, value);
  }

  /// 销毁前补写未落盘的输入（此时已不能 setState，只写存储）。
  void _flushPendingValues() {
    if (_pendingValues.isEmpty) return;
    final plugin = _plugin;
    final pending = Map<String, dynamic>.from(_pendingValues);
    _pendingValues.clear();
    if (plugin == null) return;
    for (final entry in pending.entries) {
      unawaited(
        plugin.invoke('saveSetting', [entry.key, entry.value]).then<void>(
          (_) {},
          onError: (Object e, StackTrace s) {
            WywLogger().w(
              '${LogTag.plugin} 退出设置时保存「${entry.key}」失败',
              error: e,
              stackTrace: s,
            );
          },
        ),
      );
    }
  }

  Future<void> _load() async {
    final plugin = _plugin;
    if (plugin == null || !plugin.isLoaded) {
      if (!mounted) return;
      setState(() {
        _error = '插件未注册：${widget.pluginName}';
        _loading = false;
      });
      return;
    }
    try {
      // 读取插件声明的 settings schema：插件自己实现了 getSettings() 就用它，
      // 否则读它的 settings 字段（基类不提供 getSettings 空实现）
      final schema = await plugin.readSettingsSchema();
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

  /// 校验 `input` 型设置项的值（venera 的 `validator` 是正则源码字符串）。
  ///
  /// 返回非空字符串表示错误提示（显示在输入框下方）。正则为空或无法编译时放行。
  String? _validateInput(Map<String, dynamic> meta, String value) {
    final pattern = meta['validator']?.toString() ?? '';
    if (pattern.isEmpty || value.isEmpty) return null;
    try {
      if (!RegExp(pattern).hasMatch(value)) {
        return meta['validatorMessage']?.toString() ?? '格式不正确';
      }
    } catch (_) {
      // 正则非法：放行（不因插件写错正则而阻断用户）
    }
    return null;
  }

  /// 执行回调型设置项：调用插件上的同名方法。
  Future<void> _invokeCallback(String method) async {
    final plugin = _plugin;
    if (plugin == null) return;
    try {
      await plugin.invoke(method, const []);
      if (mounted) {
        WywDialog.showToast(message: '已执行：$method', context: context);
      }
    } catch (e) {
      if (mounted) {
        WywDialog.showToast(message: '执行「$method」失败：$e', context: context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
      // 设置项即时落盘，详情页在这一段没有悬浮按钮，所以底部不需要让位留白
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 16),
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
        // 与 input/password 同款的 SelectField，整页表单口径一致。
        return ListTile(
          title: Text(title),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: SelectField<dynamic>(
              value: _dropdownValue(options, current),
              options: [
                for (final opt in options)
                  if (opt is Map)
                    SelectOption<dynamic>(
                      value: opt['value'],
                      label: opt['text']?.toString() ?? opt['value'].toString(),
                    ),
              ],
              onChanged: (v) => _save(key, v),
            ),
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
            controller: _controllerFor(key, current),
            decoration: InputDecoration(
              isDense: true,
              errorText: _validateInput(
                meta,
                _textControllers[key]?.text ?? current?.toString() ?? '',
              ),
              contentPadding: StyleString.fieldContentPadding,
              border: const OutlineInputBorder(
                borderRadius: StyleString.controlBorderRadius,
              ),
            ),
            onChanged: (v) => _onTextChanged(key, v),
            onSubmitted: (v) => _onSubmitted(key, v),
          ),
        );
      case 'password':
        // 密码型设置项：遮蔽显示（venera 的 `type:'password'`，如 picacg 的账号密码）
        return ListTile(
          title: Text(title),
          subtitle: TextField(
            controller: _controllerFor(key, current),
            obscureText: true,
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: StyleString.fieldContentPadding,
              border: OutlineInputBorder(
                borderRadius: StyleString.controlBorderRadius,
              ),
            ),
            onChanged: (v) => _onTextChanged(key, v),
            onSubmitted: (v) => _onSubmitted(key, v),
          ),
        );
      case 'callback':
        // 回调型设置项（venera 的 `type:'callback'`，如「刷新域名列表」按钮）。
        //
        // wyw 约定：`callback` 写**插件方法名字符串**，而不是 venera 的 JS 函数 ——
        // 函数无法跨 JSON 边界（`getSettings()` 的返回值经 JSON.stringify，函数会被丢弃）。
        final callbackName = meta['callback']?.toString() ?? '';
        return ListTile(
          title: Text(title),
          subtitle: callbackName.isEmpty
              ? const Text('未指定 callback 方法名')
              : Text(callbackName,
                  style: Theme.of(context).textTheme.bodySmall),
          trailing: FilledButton.tonal(
            onPressed: callbackName.isEmpty
                ? null
                : () => _invokeCallback(callbackName),
            child: Text(meta['buttonText']?.toString() ?? '执行'),
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
