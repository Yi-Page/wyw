import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:wyw/bean/card/network_img_layer.dart';
import 'package:wyw/bean/card/swipe_to_delete_card.dart';
import 'package:wyw/bean/dialog/dialog_helper.dart';
import 'package:wyw/bean/widget/collect_button.dart';
import 'package:wyw/pages/plugin/plugin_controller.dart';
import 'package:wyw/plugins/plugin.dart';
import 'package:wyw/services/storage/collect_entry.dart';
import 'package:wyw/services/storage/collect_type.dart';
import 'package:wyw/utils/date_time.dart';
import 'package:wyw/plugins/plugin_category.dart';

/// 收藏条目卡片：单列分组列表的一行。
///
/// 内容：封面 + 标题 + 来源插件 + 相对时间 + 收藏状态菜单（照 Kazumi 的
/// 单列 list tile：状态菜单既是角标也是入口）。
class CollectEntryCard extends StatelessWidget {
  const CollectEntryCard({
    super.key,
    required this.entry,
    this.onChangedType,
    this.onDeleted,
    this.borderRadius,
    this.margin,
    this.selecting = false,
    this.selected = false,
    this.onToggleSelect,
  });

  final CollectEntry entry;

  /// 切换收藏状态；为 null 时状态菜单禁用。
  final ValueChanged<CollectType>? onChangedType;

  final VoidCallback? onDeleted;
  final BorderRadius? borderRadius;
  final EdgeInsets? margin;

  /// 多选模式：整行点击 = 勾选/取消勾选（滑动删除同时停用）。
  final bool selecting;
  final bool selected;
  final VoidCallback? onToggleSelect;

  /// 状态按钮带文字的**行宽**阈值：卡片可用宽度 ≥ 该值才显示「图标 + 文字」，
  /// 否则只留图标（窄卡片上"图标 + 文字"会挤掉标题宽度）。
  static const double extendedStatusMinWidth = 500;

  /// 来源插件的展示名（用户覆盖 > 插件自称 > 插件名）。
  ///
  /// 条目只存插件名（标识），直接渲染会显示成文件名。
  String get _displayName =>
      inject<PluginController>().displayNameOf(entry.pluginName);

  /// 插件存在状态（口径在 [PluginController.presenceOf]，卡片图标与收藏页
  /// 筛选共用；已删除 = 文件已经没了，不能与禁用/失败混为一谈）。
  PluginPresence get _presence =>
      inject<PluginController>().presenceOf(entry.pluginName);

  /// 条目的插件分类（与收藏页分类筛选同一口径；未加载归「其他」）。
  PluginCategory get _category {
    final controller = inject<PluginController>();
    final plugin = controller.getPlugin(entry.pluginName);
    return plugin == null
        ? PluginCategory.unknown
        : controller.categoryOf(plugin);
  }

  /// 插件行的类型图标：
  ///   - 插件已加载 → **分类图标 + 分类色**（与插件管理页逐字一致：
  ///     `Icon(controller.categoryOf(plugin).icon, color: …category.color)`）；
  ///   - 插件已删除 → 特定「插件缺失」图标 + **错误色** + tooltip 提示；
  ///   - 插件文件缺失（记录还在）→ 同样的破损图标 + 错误色，tooltip 说明可恢复；
  ///   - 已禁用 / 加载失败（文件还在）→ 保留原扩展图标（不误报已删除）。
  Widget _buildPluginIcon(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final presence = _presence;
    // 「已删除」与「文件缺失」都是"打不开"，共用破损图标；后者可恢复。
    final broken = presence == PluginPresence.deleted ||
        presence == PluginPresence.missing;
    final icon = switch (presence) {
      PluginPresence.loaded => _category.icon,
      PluginPresence.deleted || PluginPresence.missing => Icons.extension_off,
      _ => Icons.extension_outlined,
    };
    final color = switch (presence) {
      PluginPresence.loaded => _category.color,
      PluginPresence.deleted || PluginPresence.missing => colorScheme.error,
      _ => colorScheme.onSurfaceVariant,
    };
    Widget result = Icon(icon, size: 14, color: color);
    if (broken) {
      // Tooltip 的 message 不能为 null（断言），所以只对这两种状态包一层。
      result = Tooltip(
        message: presence == PluginPresence.deleted
            ? '插件已删除'
            : '插件文件缺失（重新导入同名插件可恢复）',
        child: result,
      );
    }
    return result;
  }

  Future<void> _onTap() async {
    final ok = await inject<PluginController>().openBrowseEntry(
      pluginName: entry.pluginName,
      entryJson: entry.toJson(),
    );
    if (!ok) {
      WywDialog.showToast(message: '该插件未提供回放入口');
    }
  }

  @override
  Widget build(BuildContext context) {
    // 状态按钮形态按**行宽**决定（不按平台）：宽到放得下就带文字，
    // 窄卡片只留图标（图标本身已表达状态，文字仍在菜单与 tooltip 里）。
    return LayoutBuilder(
      builder: (context, constraints) => _buildCard(
        context,
        extendedStatus: constraints.maxWidth >= extendedStatusMinWidth,
      ),
    );
  }

  Widget _buildCard(BuildContext context, {required bool extendedStatus}) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    const imageWidth = 80.0;
    const imageHeight = 108.0;

    final content = Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (selecting)
            Padding(
              padding: const EdgeInsets.only(right: 4, top: 4),
              child: IgnorePointer(
                child: Checkbox(
                  value: selected,
                  onChanged: (_) {},
                  semanticLabel: '选择「${entry.title}」',
                ),
              ),
            ),
          if (entry.cover.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: NetworkImgLayer(
                src: entry.cover,
                width: imageWidth,
                height: imageHeight,
              ),
            ),
          if (entry.cover.isNotEmpty) const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: imageHeight,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
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
                      _buildPluginIcon(context),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          _displayName,
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
                          entry.visitTime.millisecondsSinceEpoch ~/ 1000,
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
          const SizedBox(width: 8),
          Align(
            alignment: Alignment.centerRight,
            child: extendedStatus
                ? CollectButton.extend(
                    type: entry.type,
                    onChanged: selecting ? null : onChangedType,
                  )
                : CollectButton(
                    type: entry.type,
                    onChanged: selecting ? null : onChangedType,
                  ),
          ),
        ],
      ),
    );

    // 多选模式下不挂 Dismissible：否则滑动会把行从视觉上移除而数据未变。
    if (selecting) {
      final shape = borderRadius ?? BorderRadius.circular(16);
      return Card(
        elevation: 0,
        margin: margin ?? const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        shape: RoundedRectangleBorder(borderRadius: shape),
        clipBehavior: Clip.antiAlias,
        color: colorScheme.surfaceContainerLow,
        child: InkWell(onTap: onToggleSelect, child: content),
      );
    }

    return SwipeToDeleteCard(
      dismissKey: ValueKey(entry.key),
      onTap: _onTap,
      onDeleted: onDeleted,
      borderRadius: borderRadius,
      margin: margin,
      child: content,
    );
  }
}
