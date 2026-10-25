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
    this.borderRadius,
    this.margin,
  });

  /// Dismissible 的唯一 key（各卡片用条目的稳定 id 构造）。
  final Key dismissKey;

  /// 卡片主体内容（封面、标题等）。
  final Widget child;

  /// 点击卡片时回调。
  final VoidCallback? onTap;

  /// 左滑删除或点删除按钮时回调。
  final VoidCallback? onDeleted;

  /// 卡片圆角（删除背景与 Card 共用）。默认 16。
  ///
  /// 分组列表里由列表按行位置传入：首行上圆角、末行下圆角，中间行小圆角，
  /// 使同一日期分组视觉上并成一块。
  final BorderRadius? borderRadius;

  /// 卡片外边距（删除背景与 Card 共用）。默认 vertical 4 / horizontal 8。
  ///
  /// 分组列表把它压到 vertical 1（行间 2px 缝），让分组更紧凑。
  final EdgeInsets? margin;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final shape = borderRadius ?? BorderRadius.circular(16);
    final inset =
        margin ?? const EdgeInsets.symmetric(vertical: 4, horizontal: 8);
    return Dismissible(
      key: dismissKey,
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDeleted?.call(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        margin: inset,
        decoration: BoxDecoration(
          color: colorScheme.errorContainer,
          borderRadius: shape,
        ),
        child: Icon(
          Icons.delete_outline,
          color: colorScheme.onErrorContainer,
        ),
      ),
      child: Card(
        elevation: 0,
        margin: inset,
        shape: RoundedRectangleBorder(borderRadius: shape),
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
