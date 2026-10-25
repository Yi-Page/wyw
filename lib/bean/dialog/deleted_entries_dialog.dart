import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wyw/bean/card/network_img_layer.dart';
import 'package:wyw/bean/widget/empty_state_widget.dart';
import 'package:wyw/utils/deleted_ledger.dart';

/// 「本次已删除」弹窗（收藏页 / 历史页共用外壳）。
///
/// 尺寸与样式**对齐播放器的截图管理弹窗**
/// （`lib/pages/player/player_screenshot_sheet.dart` 的 `showPlayerScreenshotSheet`）：
/// `Dialog` + `insetPadding` 16/24 + 圆角 28 + `surfaceContainerHigh`
/// + 内容 `width: 1120` / `maxHeight: min(840, 屏高 - inset*2)`，
/// 以及同一套 compact/wide 阈值（高度 < 500 记 compact，宽度 ≥ 700 记 wide）。
///
/// 各页只提供「一行怎么画」（[tileBuilder]）与文案；外壳、交互、快捷键共用。
Future<void> showDeletedEntriesDialog<T>(
  BuildContext context, {
  required List<DeletedRecord<T>> entries,
  required Widget Function(
    DeletedRecord<T> record,
    bool wide,
    VoidCallback onRestore,
  ) tileBuilder,
  required String Function(DeletedRecord<T> record) semanticsOf,
  required Future<void> Function(T item) onRestore,
  required Future<void> Function(List<T> items) onRestoreAll,
  required VoidCallback onClear,
  String title = '本次已删除',
  String Function(int count)? subtitleOf,
  String emptyTitle = '本次没有待恢复的删除记录',
  String emptySubtitle = '删除的条目会保留在这里，直到离开本页。',
  IconData emptyIcon = Icons.delete_sweep_outlined,
  String clearLabel = '清空记录',
}) =>
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => LayoutBuilder(
        builder: (context, constraints) {
          final inset =
              constraints.maxWidth < 700 || constraints.maxHeight < 500
                  ? 16.0
                  : 24.0;
          return Dialog(
            clipBehavior: Clip.antiAlias,
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
            insetPadding: EdgeInsets.all(inset),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            child: SizedBox(
              width: 1120,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: math.min(840, constraints.maxHeight - inset * 2),
                ),
                child: _DeletedEntriesDialog<T>(
                  entries: entries,
                  tileBuilder: tileBuilder,
                  semanticsOf: semanticsOf,
                  onRestore: onRestore,
                  onRestoreAll: onRestoreAll,
                  onClear: onClear,
                  title: title,
                  subtitleOf: subtitleOf,
                  emptyTitle: emptyTitle,
                  emptySubtitle: emptySubtitle,
                  emptyIcon: emptyIcon,
                  clearLabel: clearLabel,
                ),
              ),
            ),
          );
        },
      ),
    );

/// 已删除条目的封面缩略图（两页共用）：无封面 / 加载失败时占位。
class DeletedRecordCover extends StatelessWidget {
  const DeletedRecordCover({super.key, required this.src});

  final String src;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (src.isEmpty) return _placeholder(colors);
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: NetworkImgLayer(src: src, width: 56, height: 76),
    );
  }

  Widget _placeholder(ColorScheme colors) => Container(
        width: 56,
        height: 76,
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          Icons.image_not_supported_outlined,
          size: 20,
          color: colors.outline,
        ),
      );
}

class _DeletedEntriesDialog<T> extends StatefulWidget {
  const _DeletedEntriesDialog({
    required this.entries,
    required this.tileBuilder,
    required this.semanticsOf,
    required this.onRestore,
    required this.onRestoreAll,
    required this.onClear,
    required this.title,
    required this.subtitleOf,
    required this.emptyTitle,
    required this.emptySubtitle,
    required this.emptyIcon,
    required this.clearLabel,
  });

  final List<DeletedRecord<T>> entries;
  final Widget Function(
    DeletedRecord<T> record,
    bool wide,
    VoidCallback onRestore,
  ) tileBuilder;
  final String Function(DeletedRecord<T> record) semanticsOf;
  final Future<void> Function(T item) onRestore;
  final Future<void> Function(List<T> items) onRestoreAll;
  final VoidCallback onClear;
  final String title;
  final String Function(int count)? subtitleOf;
  final String emptyTitle;
  final String emptySubtitle;
  final IconData emptyIcon;
  final String clearLabel;

  @override
  State<_DeletedEntriesDialog<T>> createState() =>
      _DeletedEntriesDialogState<T>();
}

class _DeletedEntriesDialogState<T> extends State<_DeletedEntriesDialog<T>> {
  final FocusNode _focus = FocusNode(debugLabel: 'Deleted entries');
  late List<DeletedRecord<T>> _entries = List.of(widget.entries);
  bool _busy = false;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _close() => Navigator.maybePop(context);

  Future<void> _restore(int index) async {
    if (_busy || index < 0 || index >= _entries.length) return;
    final record = _entries[index];
    setState(() => _busy = true);
    await widget.onRestore(record.item);
    if (!mounted) return;
    setState(() {
      _entries.removeAt(index);
      _busy = false;
    });
  }

  Future<void> _restoreAll() async {
    if (_busy || _entries.isEmpty) return;
    setState(() => _busy = true);
    await widget.onRestoreAll([for (final record in _entries) record.item]);
    if (!mounted) return;
    setState(() {
      _entries = const [];
      _busy = false;
    });
  }

  void _clear() {
    widget.onClear();
    _close();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _close,
      },
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        child: Material(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxHeight < 500;
              final wide = constraints.maxWidth >= 700;
              final padding = compact || !wide ? 16.0 : 24.0;
              return Column(
                mainAxisSize: wide ? MainAxisSize.max : MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(context, compact: compact, padding: padding),
                  if (_entries.isEmpty)
                    Flexible(child: _empty(compact: compact))
                  else
                    Flexible(
                      child: ListView.separated(
                        padding: EdgeInsets.fromLTRB(
                          padding,
                          0,
                          padding,
                          compact ? 8 : 16,
                        ),
                        itemCount: _entries.length,
                        separatorBuilder: (_, __) =>
                            SizedBox(height: compact ? 8 : 10),
                        itemBuilder: (context, index) => Semantics(
                          label: widget.semanticsOf(_entries[index]),
                          button: true,
                          child: widget.tileBuilder(
                            _entries[index],
                            wide,
                            () => _restore(index),
                          ),
                        ),
                      ),
                    ),
                  _footer(context, compact: compact, padding: padding),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _header(
    BuildContext context, {
    required bool compact,
    required double padding,
  }) =>
      Padding(
        padding: EdgeInsets.fromLTRB(
          padding,
          compact ? 4 : 16,
          math.max(0, padding - 8),
          compact ? 4 : 16,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: compact
                        ? Theme.of(context).textTheme.titleLarge
                        : Theme.of(context).textTheme.headlineSmall,
                  ),
                  if (!compact)
                    Text(
                      widget.subtitleOf?.call(_entries.length) ??
                          '${_entries.length} 条',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                ],
              ),
            ),
            IconButton(
              tooltip: '关闭',
              onPressed: _busy ? null : _close,
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
      );

  Widget _empty({required bool compact}) => Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(compact ? 16 : 24),
          child: GeneralEmptyState(
            icon: widget.emptyIcon,
            title: widget.emptyTitle,
            subtitle: widget.emptySubtitle,
            compact: true,
          ),
        ),
      );

  Widget _footer(
    BuildContext context, {
    required bool compact,
    required double padding,
  }) {
    final hasEntries = _entries.isNotEmpty;
    final clear = TextButton(
      onPressed: _busy || !hasEntries ? null : _clear,
      child: Text(widget.clearLabel),
    );
    final close = TextButton(
      onPressed: _busy ? null : _close,
      child: const Text('关闭'),
    );
    final restoreAll = FilledButton.icon(
      onPressed: _busy || !hasEntries ? null : _restoreAll,
      icon: const Icon(Icons.restore_rounded, size: 20),
      label: Text(
        hasEntries ? '全部恢复（${_entries.length}）' : '全部恢复',
        maxLines: 1,
      ),
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        padding,
        compact ? 8 : 16,
        padding,
        compact ? 8 : 24,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 420) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                restoreAll,
                const SizedBox(height: 4),
                Row(children: [clear, const Spacer(), close]),
              ],
            );
          }
          return Row(
            children: [
              clear,
              const Spacer(),
              close,
              const SizedBox(width: 8),
              restoreAll,
            ],
          );
        },
      ),
    );
  }
}
