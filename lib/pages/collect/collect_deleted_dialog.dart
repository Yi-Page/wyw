import 'package:flutter/material.dart';
import 'package:wyw/bean/dialog/deleted_entries_dialog.dart';
import 'package:wyw/bean/widget/collect_button.dart';
import 'package:wyw/services/storage/collect_entry.dart';
import 'package:wyw/services/storage/collect_type.dart';
import 'package:wyw/utils/date_time.dart';
import 'package:wyw/utils/deleted_ledger.dart';

/// 来源插件展示名解析（由调用方注入 → 弹窗不依赖 Modular DI，便于单测）。
typedef PluginDisplayNameResolver = String Function(String pluginName);

/// 打开收藏页的「本次已删除」弹窗（外壳共用 [showDeletedEntriesDialog]）。
Future<void> showCollectDeletedDialog(
  BuildContext context, {
  required List<DeletedRecord<CollectEntry>> entries,
  required PluginDisplayNameResolver displayNameOf,
  required Future<void> Function(CollectEntry entry) onRestore,
  required Future<void> Function(List<CollectEntry> entries) onRestoreAll,
  required VoidCallback onClear,
}) =>
    showDeletedEntriesDialog<CollectEntry>(
      context,
      entries: entries,
      subtitleOf: (count) => count == 0
          ? '离开收藏页后不再保留'
          : '$count 条 · 恢复后回到原来的位置与收藏状态',
      semanticsOf: (record) {
        final entry = record.item;
        return '${entry.title}，${displayNameOf(entry.pluginName)}，'
            '${entry.type.label}，删除于 ${_relative(record.deletedAt)}';
      },
      tileBuilder: (record, wide, onRestore) => _CollectDeletedTile(
        record: record,
        wide: wide,
        displayName: displayNameOf(record.item.pluginName),
        onRestore: onRestore,
      ),
      onRestore: onRestore,
      onRestoreAll: onRestoreAll,
      onClear: onClear,
    );

String _relative(DateTime time) =>
    formatTimestampToRelativeTime(time.millisecondsSinceEpoch ~/ 1000);

/// 单条已删除收藏条目：封面 + 标题 + 来源插件 + 条目 id + 收藏状态 + 访问/删除时间 + 恢复。
class _CollectDeletedTile extends StatelessWidget {
  const _CollectDeletedTile({
    required this.record,
    required this.wide,
    required this.displayName,
    required this.onRestore,
  });

  final DeletedRecord<CollectEntry> record;
  final bool wide;
  final String displayName;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final entry = record.item;

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
          '$displayName · 访问 ${_relative(entry.visitTime)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: colors.onSurfaceVariant),
        ),
        Text(
          entry.id,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(color: colors.outline),
        ),
      ],
    );
    final status = _StatusChip(type: entry.type);
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
                  status,
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
                      status,
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

/// 只读收藏状态角标（用与卡片菜单一致的图标语义）。
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.type});

  final CollectType type;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final collected = type.isCollected;
    return Material(
      color:
          collected ? colors.secondaryContainer : colors.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              CollectButton.iconFor(type),
              size: 16,
              color: collected
                  ? colors.onSecondaryContainer
                  : colors.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              type.label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: collected
                        ? colors.onSecondaryContainer
                        : colors.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
