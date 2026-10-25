/// 收藏类型枚举
///
/// 用于标识浏览历史条目（= 收藏条目）的收藏状态。
///
/// **未收藏（[none]）也是收藏状态之一**，并且是插件通过 `PluginBrowse.open`
/// 收录一条浏览足迹时的默认状态；它与其余 5 态地位相同，可以互相切换。
///
/// 数值与标签照 Kazumi 的 `CollectType` 逐字对齐（含 `onHold=3` / `watched=4`
/// 的顺序），因为该数值会随条目持久化，必须与参考实现一致。
enum CollectType {
  /// 未收藏（插件收录历史时的默认状态）
  none(0, '未收藏'),

  /// 在看
  watching(1, '在看'),

  /// 想看
  planToWatch(2, '想看'),

  /// 搁置
  onHold(3, '搁置'),

  /// 看过
  watched(4, '看过'),

  /// 抛弃
  abandoned(5, '抛弃');

  const CollectType(this.value, this.label);

  /// 数值表示（持久化字段）
  final int value;

  /// 显示标签
  final String label;

  /// 根据数值获取枚举；未知数值回退为 [none]（向后兼容）。
  static CollectType fromValue(int value) {
    return CollectType.values.firstWhere(
      (type) => type.value == value,
      orElse: () => CollectType.none,
    );
  }

  /// 是否为已收藏状态（排除未收藏）。
  bool get isCollected => this != CollectType.none;
}
