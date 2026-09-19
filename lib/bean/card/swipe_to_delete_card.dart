import 'package:flutter/material.dart';

/// 可左滑删除的卡片外壳：统一的删除背景 + Card + InkWell。
///
/// 被历史/浏览记录等列表卡片复用，避免各处重复实现
/// 「Dismissible 删除背景 + 圆角 Card + 点击水波」这一外壳。
class SwipeToDeleteCard extends StatelessWidget {
  const SwipeToDeleteCard({
    super.key,
    required this.dismissKey,
    required this.child,
    this.onTap,
    this.onDeleted,
  });

  /// Dismissible 的唯一 key（各卡片用条目的稳定 id 构造）。
  final Key dismissKey;

  /// 卡片主体内容（封面、标题等）。
  final Widget child;

  /// 点击卡片时回调。
  final VoidCallback? onTap;

  /// 左滑删除或点删除按钮时回调。
  final VoidCallback? onDeleted;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Dismissible(
      key: dismissKey,
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDeleted?.call(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        decoration: BoxDecoration(
          color: colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(
          Icons.delete_outline,
          color: colorScheme.onErrorContainer,
        ),
      ),
      child: Card(
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        color: colorScheme.surfaceContainerLow,
        child: InkWell(
          onTap: onTap,
          child: child,
        ),
      ),
    );
  }
}
