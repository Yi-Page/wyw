import 'package:flutter/material.dart';
import 'package:wyw/plugins/plugin_category.dart';

/// 分类图标选择器：铺开 [CategoryIcons.palette]，点选高亮。
///
/// **选中结果是字符串 key**（空串 = 用默认图标），不是 [IconData] —— 原因见
/// [CategoryIcons] 的说明（release 构建的 `--tree-shake-icons` 只认编译期常量图标）。
///
/// 首格是「默认」，对应空串：用户随时能退回不选图标的初始状态。
class CategoryIconPicker extends StatelessWidget {
  const CategoryIconPicker({
    super.key,
    required this.selected,
    required this.onSelected,
    this.tileSize = 40,
  });

  /// 当前选中的 key；空串表示默认图标。
  final String selected;

  /// 点选回调，参数是 key（空串 = 默认）
  final ValueChanged<String> onSelected;

  /// 单格边长
  final double tileSize;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        _tile(context, key: '', icon: CategoryIcons.fallback, isDefault: true),
        for (final entry in CategoryIcons.palette.entries)
          _tile(context, key: entry.key, icon: entry.value),
      ],
    );
  }

  Widget _tile(
    BuildContext context, {
    required String key,
    required IconData icon,
    bool isDefault = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final active = selected == key;
    return Tooltip(
      message: isDefault ? '默认图标' : key,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => onSelected(key),
        child: Container(
          width: tileSize,
          height: tileSize,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: active ? scheme.primaryContainer : null,
            border: Border.all(
              color: active ? scheme.primary : scheme.outlineVariant,
              width: active ? 2 : 1,
            ),
          ),
          child: Icon(
            icon,
            size: tileSize * 0.55,
            color: active ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
