import 'package:flutter/material.dart';

/// 分段控件里的一个选项。
class SegmentedChoiceItem<T> {
  const SegmentedChoiceItem({
    required this.value,
    required this.label,
    this.icon,
    this.enabled = true,
  });

  final T value;
  final String label;
  final IconData? icon;
  final bool enabled;
}

/// 值型分段控件（Material 3 connected button group 的简化实现）。
///
/// 与 [ConnectedTabs] 的分工：
///   - `ConnectedTabs` 绑定 `TabController`，用于页面级 tab，标签放不下时横向滚动；
///   - [SegmentedChoice] 绑定**值**，用于表单内切换视图；放不下时**换行**，
///     不会把标签压成省略号（分段少而字长时更可读）。
class SegmentedChoice<T> extends StatelessWidget {
  const SegmentedChoice({
    super.key,
    required this.value,
    required this.segments,
    required this.onChanged,
  });

  final T value;
  final List<SegmentedChoiceItem<T>> segments;
  final ValueChanged<T> onChanged;

  /// 单个分段的最小宽度（大字号时按比例放大）
  static const double _minSegmentWidth = 76;

  /// 相邻分段的间隙
  static const double _gap = 4;

  @override
  Widget build(BuildContext context) {
    if (segments.isEmpty) return const SizedBox.shrink();
    final scaledMin = MediaQuery.textScalerOf(context).scale(_minSegmentWidth);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wrap = constraints.maxWidth < segments.length * scaledMin;
        if (wrap) {
          return Wrap(
            spacing: _gap,
            runSpacing: _gap,
            children: [
              for (var i = 0; i < segments.length; i++)
                _segment(context, i, wrapped: true),
            ],
          );
        }
        return Row(
          children: [
            for (var i = 0; i < segments.length; i++) ...[
              if (i > 0) const SizedBox(width: _gap),
              Expanded(child: _segment(context, i, wrapped: false)),
            ],
          ],
        );
      },
    );
  }

  Widget _segment(BuildContext context, int index, {required bool wrapped}) {
    final colors = Theme.of(context).colorScheme;
    final segment = segments[index];
    final selected = segment.value == value;
    const outer = Radius.circular(24);
    final inner = Radius.circular(selected ? 24 : 8);
    final first = index == 0;
    final last = index == segments.length - 1;
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: FilledButton(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          backgroundColor: selected
              ? colors.secondaryContainer
              : colors.surfaceContainerHighest,
          foregroundColor: selected
              ? colors.onSecondaryContainer
              : colors.onSurfaceVariant,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadiusDirectional.only(
              topStart: first || wrapped ? outer : inner,
              bottomStart: first || wrapped ? outer : inner,
              topEnd: last || wrapped ? outer : inner,
              bottomEnd: last || wrapped ? outer : inner,
            ),
          ),
        ),
        onPressed: segment.enabled ? () => onChanged(segment.value) : null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (segment.icon != null) ...[
              Icon(segment.icon, size: 18),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                segment.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
