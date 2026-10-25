import 'package:flutter/material.dart';
import 'package:wyw/bean/widget/kazumi_menu.dart';
import 'package:wyw/services/storage/collect_type.dart';

/// 收藏状态按钮（照 Kazumi `CollectButton`）。
///
/// 点击展开 6 个状态的菜单；「未收藏」也是合法状态之一（浏览历史条目的默认
/// 状态），所以菜单列出全部 6 项，与 Kazumi 的 `CollectType.values` 一致。
///
/// 两种形态：
///   - 默认：图标按钮（紧凑，用于窄槽位）
///   - [CollectButton.extend]：带状态文字的 tonal 按钮（充当"状态角标 + 菜单"）
class CollectButton extends StatelessWidget {
  const CollectButton({
    super.key,
    required this.type,
    required this.onChanged,
    this.color,
  }) : _extended = false;

  const CollectButton.extend({
    super.key,
    required this.type,
    required this.onChanged,
  })  : _extended = true,
        color = null;

  final CollectType type;

  /// 选择新状态；为 null 时按钮禁用（只读展示）。
  final ValueChanged<CollectType>? onChanged;

  /// 图标按钮的前景色（媒体铬层等自定义底上用）。
  final Color? color;

  final bool _extended;

  /// 状态图标（照 Kazumi 逐字对齐）。
  static IconData iconFor(CollectType type) => switch (type) {
        CollectType.none => Icons.favorite_border,
        CollectType.watching => Icons.favorite,
        CollectType.planToWatch => Icons.star_rounded,
        CollectType.onHold => Icons.pending_actions,
        CollectType.watched => Icons.done,
        CollectType.abandoned => Icons.heart_broken,
      };

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    return KazumiMenuButton(
      enabled: enabled,
      menuChildren: [
        for (final option in CollectType.values)
          KazumiMenuItem(
            label: option.label,
            selected: option == type,
            leadingIcon: Icon(iconFor(option)),
            onPressed: enabled && option != type
                ? () => onChanged!(option)
                : null,
          ),
      ],
      builder: (context, toggle) => _extended
          ? FilledButton.tonalIcon(
              onPressed: toggle,
              icon: Icon(iconFor(type), size: 18),
              label: Text(type.label),
            )
          : IconButton(
              onPressed: toggle,
              tooltip: '收藏状态：${type.label}',
              icon: Icon(iconFor(type), color: color),
            ),
    );
  }
}
