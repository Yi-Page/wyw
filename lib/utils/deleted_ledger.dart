/// 一条「本次已删除」记录：条目完整快照 + 删除时间。
///
/// 保存完整快照（而不是只存 key）是为了恢复时能原样放回：
/// 展示字段、进度/`kv`、收藏状态全部保留。
typedef DeletedRecord<T> = ({T item, DateTime deletedAt});

/// 会话级「本次已删除」清单（回收站），收藏页与历史页共用。
///
/// 设计要点：
///   - **纯 Dart**，无 Flutter 依赖 → 可单测
///   - **不加上限**：内存代价 = 被删条目的快照（条目本身已从存储删除），
///     清单大小只受本次会话删除量影响
///   - **不持久化**：由页面 `State` 持有，页面 dispose 即整体丢弃
///     （删除本身已经落盘，这里只是"还来得及反悔"的窗口）
///   - 最新删除在前（[entries] 顺序即弹窗展示顺序）
///
/// [keyOf] 决定"同一个条目"的判等口径（收藏页用 `pluginName::id`，
/// 历史页用 `sourceId`），出账时据此匹配。
class DeletedLedger<T> {
  DeletedLedger({required this.keyOf});

  /// 条目身份键。
  final Object Function(T item) keyOf;

  final List<DeletedRecord<T>> _items = <DeletedRecord<T>>[];

  /// 最新删除在前（只读视图）。
  List<DeletedRecord<T>> get entries => List.unmodifiable(_items);

  int get count => _items.length;

  bool get isEmpty => _items.isEmpty;

  bool get isNotEmpty => _items.isNotEmpty;

  /// 记入一条删除（[at] 仅测试用，默认当前时间）。
  void add(T item, {DateTime? at}) {
    _items.insert(0, (item: item, deletedAt: at ?? DateTime.now()));
  }

  /// 记入一批删除。
  ///
  /// - 同一次操作共享同一个 [deletedAt]（弹窗里天然相邻）
  /// - **批次内部保持传入顺序**：多选/清空的入参就是用户当时看到的列表顺序，
  ///   这样弹窗里的这一块与刚才的列表读起来一致
  void addAll(Iterable<T> items, {DateTime? at}) {
    final stamp = at ?? DateTime.now();
    // 倒序插入到头部 → 最终顺序与传入顺序一致
    for (final item in items.toList().reversed) {
      _items.insert(0, (item: item, deletedAt: stamp));
    }
  }

  /// 出账（恢复成功后调用）：按 [keyOf] 匹配并移除一条。
  ///
  /// 返回被移除的记录；不存在时返回 null。
  DeletedRecord<T>? remove(T item) {
    final key = keyOf(item);
    final index = _items.indexWhere((record) => keyOf(record.item) == key);
    if (index < 0) return null;
    return _items.removeAt(index);
  }

  /// 丢弃全部恢复机会（不删除任何数据——数据早在删除时就已落盘）。
  void clear() => _items.clear();
}
