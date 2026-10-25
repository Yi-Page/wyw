import 'package:flutter/material.dart';
import 'package:wyw/bean/dialog/deleted_entries_dialog.dart';
import 'package:wyw/pages/history/history_progress_summary.dart';
import 'package:wyw/services/storage/history_entry.dart';
import 'package:wyw/utils/date_time.dart';
import 'package:wyw/utils/deleted_ledger.dart';

/// 打开进度历史页的「本次已删除」弹窗（外壳共用 [showDeletedEntriesDialog]）。
Future<void> showHistoryDeletedDialog(
  BuildContext context, {
  required List<DeletedRecord<HistoryEntry>> entries,
  required Future<void> Function(HistoryEntry entry) onRestore,
  required Future<void> Function(List<HistoryEntry> entries) onRestoreAll,
  required VoidCallback onClear,
}) =>
    showDeletedEntriesDialog<HistoryEntry>(
      context,
      entries: entries,
      subtitleOf: (count) => count == 0
          ? '离开历史页后不再保留'
          : '$count 条 · 恢复后回到原来的位置与进度',
      semanticsOf: (record) {
        final entry = record.item;
        final summary = historyProgressSummary(entry);
        return '${entry.title}，${historyTypeLabel(entry.type)}'
            '${summary == null ? '' : '，$summary'}'
            '，删除于 ${_relative(record.deletedAt)}';
      },
      tileBuilder: (record, wide, onRestore) => _HistoryDeletedTile(
        record: record,
        wide: wide,
        onRestore: onRestore,
      ),
      onRestore: onRestore,
      onRestoreAll: onRestoreAll,
      onClear: onClear,
    );

String _relative(DateTime time) =>
    formatTimestampToRelativeTime(time.millisecondsSinceEpoch ~/ 1000);

/// 单条已删除历史条目：封面 + 标题 + 类型 + 进度 + 上次观看/删除时间 + 恢复。
class _HistoryDeletedTile extends StatelessWidget {
  const _HistoryDeletedTile({
    required this.record,
    required this.wide,
    required this.onRestore,
  });

  final DeletedRecord<HistoryEntry> record;
  final bool wide;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final entry = record.item;
    final summary = historyProgressSummary(entry);

    final title = Text(
      entry.title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
    );
    final meta = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          summary == null
              ? '上次观看 ${_relative(entry.lastWatchTime)}'
              : '$summary · 上次观看 ${_relative(entry.lastWatchTime)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: colors.onSurfaceVariant),
        ),
        Text(
          entry.sourceId,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(color: colors.outline),
        ),
      ],
    );
    final typeChip = _TypeChip(entry: entry);
    final deletedAt = Text(
      '删除 ${_relative(record.deletedAt)}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.labelMedium?.copyWith(color: colors.outline),
    );
    final restore = TextButton.icon(
      onPressed: onRestore,
      icon: const Icon(Icons.restore_rounded, size: 18),
      label: const Text('恢复'),
    );

    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: wide
            ? Row(
                children: [
                  DeletedRecordCover(src: entry.cover),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [title, const SizedBox(height: 4), meta],
                    ),
                  ),
                  const SizedBox(width: 12),
                  typeChip,
                  const SizedBox(width: 16),
                  deletedAt,
                  const SizedBox(width: 12),
                  restore,
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DeletedRecordCover(src: entry.cover),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [title, const SizedBox(height: 4), meta],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      typeChip,
                      const SizedBox(width: 12),
                      Expanded(child: deletedAt),
                      restore,
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}

/// 只读类型角标（视频 / 漫画 / 小说）。
class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.entry});

  final HistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              historyTypeIcon(entry.type),
              size: 16,
              color: colors.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              historyTypeLabel(entry.type),
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
