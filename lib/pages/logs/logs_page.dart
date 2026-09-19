import 'dart:async';
import 'package:flutter/material.dart';
import 'package:wyw/bean/dialog/dialog_helper.dart';
import 'package:wyw/bean/appbar/app_bar_menu_button.dart';
import 'package:wyw/bean/settings/settings_detail_scaffold.dart';
import 'package:wyw/services/logging/log_tags.dart';
import 'package:wyw/utils/clipboard.dart';

import '../../services/logging/logger.dart';

class LogsPage extends StatefulWidget {
  const LogsPage({super.key});

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  final List<String> _logLines = [];
  final ScrollController _scrollController = ScrollController();

  bool _isLoading = true;
  bool _hasError = false;
  String _fullContent = '';

  static const int _initialLoadCount = 50;
  static const int _loadMoreCount = 100;
  int _displayedLines = 0;
  List<String> _allLines = [];

  @override
  void initState() {
    super.initState();
    _loadLogs();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!mounted || _displayedLines >= _allLines.length) {
      return;
    }

    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    final threshold = maxScroll * 0.8;

    if (currentScroll >= threshold) {
      _loadMoreLines();
    }
  }

  Future<void> _loadLogs() async {
    if (!mounted) return;

    try {
      final file = await getLogsPath();
      if (!mounted) return;

      if (await file.exists()) {
        final content = await file.readAsString();
        if (!mounted) return;

        _allLines = content.split('\n');
        _fullContent = content;

        final initialCount = _allLines.length < _initialLoadCount
            ? _allLines.length
            : _initialLoadCount;

        if (!mounted) return;
        setState(() {
          _logLines.clear();
          _logLines.addAll(_allLines.take(initialCount));
          _displayedLines = initialCount;
          _isLoading = false;
        });
      } else {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _isLoading = false;
      });
    }
  }

  void _loadMoreLines() {
    if (_displayedLines >= _allLines.length) {
      return;
    }

    // 使用 Future.microtask 避免在构建过程中调用 setState
    Future.microtask(() {
      if (!mounted) return;

      final remainingLines = _allLines.length - _displayedLines;
      final linesToLoad =
          remainingLines < _loadMoreCount ? remainingLines : _loadMoreCount;

      final newLines = _allLines.skip(_displayedLines).take(linesToLoad);

      if (!mounted) return;
      setState(() {
        _logLines.addAll(newLines);
        _displayedLines += linesToLoad;
      });
    });
  }

  Future<void> _clearLogs() async {
    try {
      // 复用 logger 的带锁清空逻辑，避免与后台写入并发时残留旧行。
      await clearLogs();
      if (!mounted) return;

      setState(() {
        _logLines.clear();
        _allLines.clear();
        _fullContent = '';
        _displayedLines = 0;
      });
    } catch (e) {
      if (!mounted) return;
      WywLogger().e('${LogTag.app} 清空日志失败', error: e);
      WywDialog.showToast(message: '清空失败: $e');
    }
  }

  Future<void> _copyLogs() async {
    try {
      await copyToClipboard(_fullContent);
      if (!mounted) return;
    } catch (e) {
      if (!mounted) return;
      WywLogger().e('${LogTag.app} 复制日志到剪贴板失败', error: e);
      WywDialog.showToast(message: '复制失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsDetailScaffold(
      title: const Text('日志'),
      body: buildBody,
      floatingActionButton: buildFloatingButtons,
      actions: const [WywAppBarMenuButton(pagePath: '/settings/logs/')],
    );
  }

  Widget get buildBody {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_hasError) {
      return const Center(
        child: Text('加载日志失败'),
      );
    }

    if (_logLines.isEmpty) {
      return const Center(
        child: Text('没有数据'),
      );
    }

    return SelectionArea(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: MediaQuery.of(context).size.width.clamp(600, double.infinity),
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(16.0),
            shrinkWrap: false,
            itemCount: _logLines.length,
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 4.0),
                child: Text(
                  _logLines[index],
                  softWrap: false,
                  overflow: TextOverflow.clip,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget get buildFloatingButtons {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        FloatingActionButton(
          heroTag: null,
          onPressed: _clearLogs,
          tooltip: '清空日志',
          child: const Icon(Icons.clear_all),
        ),
        const SizedBox(width: 15),
        FloatingActionButton(
          heroTag: null,
          onPressed: _copyLogs,
          tooltip: '复制日志',
          child: const Icon(Icons.copy),
        ),
      ],
    );
  }
}
