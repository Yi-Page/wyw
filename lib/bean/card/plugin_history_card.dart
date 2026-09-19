import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:wyw/bean/card/network_img_layer.dart';
import 'package:wyw/bean/card/swipe_to_delete_card.dart';
import 'package:wyw/bean/dialog/dialog_helper.dart';
import 'package:wyw/pages/plugin/plugin_controller.dart';
import 'package:wyw/services/storage/plugin_history_entry.dart';
import 'package:wyw/utils/date_time.dart';

class PluginHistoryCard extends StatelessWidget {
  const PluginHistoryCard({
    super.key,
    required this.historyItem,
    this.showDelete = false,
    this.onDeleted,
  });

  final PluginHistoryEntry historyItem;
  final bool showDelete;
  final VoidCallback? onDeleted;

  Future<void> _onTap() async {
    final ok = await inject<PluginController>().openBrowseEntry(
      pluginName: historyItem.pluginName,
      entryJson: historyItem.toJson(),
    );
    if (!ok) {
      WywDialog.showToast(message: '该插件未提供回放入口');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    const imageWidth = 80.0;
    const imageHeight = 108.0;

    return SwipeToDeleteCard(
      dismissKey: ValueKey(historyItem.key),
      onTap: _onTap,
      onDeleted: onDeleted,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (historyItem.cover.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: NetworkImgLayer(
                  src: historyItem.cover,
                  width: imageWidth,
                  height: imageHeight,
                ),
              ),
            if (historyItem.cover.isNotEmpty) const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: imageHeight,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      historyItem.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.extension_outlined,
                          size: 14,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            historyItem.pluginName,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        Icon(
                          Icons.access_time,
                          size: 12,
                          color: colorScheme.outline,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          formatTimestampToRelativeTime(
                            historyItem.visitTime.millisecondsSinceEpoch ~/
                                1000,
                          ),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (showDelete)
              IconButton(
                icon: Icon(
                  Icons.delete_outline,
                  color: colorScheme.error,
                ),
                tooltip: '删除记录',
                onPressed: onDeleted,
              ),
          ],
        ),
      ),
    );
  }
}
