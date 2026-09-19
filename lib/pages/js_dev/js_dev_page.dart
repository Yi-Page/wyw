import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:wyw/bean/appbar/app_bar_menu_button.dart';
import 'package:wyw/bean/appbar/sys_app_bar.dart';
import 'package:wyw/bean/dialog/dialog_helper.dart';
import 'package:wyw/bean/styles/js_console_colors.dart';
import 'package:wyw/pages/js_dev/js_dev_controller.dart';

const String _kDefaultScript = '''
class Test {
  run() {
    log('hello from JS engine', 'info');
    log('something might be wrong', 'warn');
    log('oh no', 'error');
    return { ok: true, count: 42 };
  }
}
''';

class JsDevPage extends StatefulWidget {
  const JsDevPage({super.key, required this.controller});

  /// 路由级 Store 单例（由 [jsDevModule] 在 child 构建上下文解析后传入）。
  final JsDevController controller;

  @override
  State<JsDevPage> createState() => _JsDevPageState();
}

class _JsDevPageState extends State<JsDevPage> {
  JsDevController get _controller => widget.controller;
  final TextEditingController _editor =
      TextEditingController(text: _kDefaultScript);
  final ScrollController _logScroll = ScrollController();

  @override
  void dispose() {
    _editor.dispose();
    _logScroll.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    FocusScope.of(context).unfocus();
    await _controller.run(_editor.text);
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_logScroll.hasClients) return;
      _logScroll.animateTo(
        _logScroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _clearLogs() async {
    final ok = await WywDialog.showConfirm(
      title: '清空日志',
      message: '确认清空所有日志？',
      confirmText: '清空',
    );
    if (ok) {
      _controller.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SysAppBar(
        title: const Text('JS 开发'),
        needTopOffset: false,
        actions: [
          IconButton(
            tooltip: '清空日志',
            icon: const Icon(Icons.delete_sweep),
            onPressed: _clearLogs,
          ),
          Observer(
            builder: (_) => IconButton(
              tooltip: '运行',
              icon: _controller.running
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow),
              onPressed: _controller.running ? null : _run,
            ),
          ),
          const WywAppBarMenuButton(pagePath: '/js-dev/'),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 1,
            child: Container(
              color: JsConsoleColors.editorBg,
              padding: const EdgeInsets.all(8),
              child: TextField(
                controller: _editor,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  height: 1.4,
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: 'function test() { ... }',
                  isCollapsed: true,
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            flex: 1,
            child: Container(
              color: JsConsoleColors.consoleBg,
              child: Observer(
                builder: (_) {
                  final lines = _controller.lines;
                  if (lines.isEmpty) {
                    return Center(
                      child: Text(
                        '点 ▶ 运行脚本',
                        style: TextStyle(color: JsConsoleColors.consoleText),
                      ),
                    );
                  }
                  return ListView.builder(
                    controller: _logScroll,
                    padding: const EdgeInsets.all(8),
                    itemCount: lines.length,
                    itemBuilder: (_, i) => _LogLineView(line: lines[i]),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LogLineView extends StatelessWidget {
  const _LogLineView({required this.line});

  final JsLogLine line;

  IconData get _icon => switch (line.kind) {
        JsLogKind.info => Icons.info_outline,
        JsLogKind.warn => Icons.warning_amber_outlined,
        JsLogKind.error => Icons.error_outline,
        JsLogKind.header => Icons.play_arrow,
        JsLogKind.returnValue => Icons.check_circle_outline,
        JsLogKind.stack => Icons.article_outlined,
      };

  Color get _color => switch (line.kind) {
        JsLogKind.info => JsConsoleColors.info,
        JsLogKind.warn => JsConsoleColors.warn,
        JsLogKind.error => JsConsoleColors.error,
        JsLogKind.returnValue => JsConsoleColors.returnValue,
        JsLogKind.header => JsConsoleColors.header,
        JsLogKind.stack => JsConsoleColors.stack,
      };

  String get _timestamp {
    if (line.timestamp == null) return '';
    final t = line.timestamp!;
    return '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}:'
        '${t.second.toString().padLeft(2, '0')}.'
        '${t.millisecond.toString().padLeft(3, '0')}';
  }

  String get _levelTag {
    return switch (line.kind) {
      JsLogKind.info => 'INFO',
      JsLogKind.warn => 'WARN',
      JsLogKind.error => 'ERROR',
      JsLogKind.header => '───',
      JsLogKind.returnValue => 'RET ',
      JsLogKind.stack => 'STCK',
    };
  }

  @override
  Widget build(BuildContext context) {
    final isHeader = line.kind == JsLogKind.header;
    final isReturn = line.kind == JsLogKind.returnValue;
    final isStack = line.kind == JsLogKind.stack;

    if (isHeader) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(_icon, size: 14, color: _color),
            const SizedBox(width: 6),
            Text(
              line.text.toString(),
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: _color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }

    if (isReturn) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_icon, size: 14, color: _color),
                const SizedBox(width: 6),
                Text(
                  '$_levelTag  $_timestamp',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: _color.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
            Container(
              margin: const EdgeInsets.only(left: 20, top: 4),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: _color.withValues(alpha: 0.3)),
              ),
              width: double.infinity,
              child: SelectableText(
                _formatReturnValue(line.text),
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: _color,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (isStack) {
      return Padding(
        padding: const EdgeInsets.only(left: 20, top: 2, bottom: 2),
        child: SelectableText(
          line.text.toString(),
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 11,
            color: _color.withValues(alpha: 0.8),
            height: 1.3,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // title 行：图标 + 级别 + 时间戳
          Row(
            children: [
              Icon(_icon, size: 14, color: _color),
              const SizedBox(width: 6),
              Text(
                _levelTag,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: _color.withValues(alpha: 0.8),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _timestamp,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: JsConsoleColors.faintText.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
          // subtitle 行：消息内容（缩进 20px）
          if (line.text.toString().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 20, top: 2),
              child: SelectableText(
                line.text.toString(),
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: _color,
                  height: 1.4,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _formatReturnValue(dynamic v) {
    if (v == null) return 'null';
    if (v is num || v is bool) return v.toString();
    if (v is String) {
      try {
        final decoded = json.decode(v);
        return const JsonEncoder.withIndent('  ').convert(decoded);
      } catch (_) {
        return v;
      }
    }
    try {
      return const JsonEncoder.withIndent('  ').convert(v);
    } catch (_) {
      return v.toString();
    }
  }
}
