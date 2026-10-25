// ignore_for_file: library_private_types_in_public_api

import 'dart:async';

import 'package:mobx/mobx.dart';
import 'package:wyw/pages/collect/collect_library_query.dart';
import 'package:wyw/repositories/collect_repository.dart';
import 'package:wyw/services/storage/collect_entry.dart';
import 'package:wyw/services/storage/collect_type.dart';

part 'collect_controller.g.dart';

/// 收藏页控制器
///
/// **设计要点**：
///   - 仓库通过构造参数注入
///   - 仓库持 `Stream<void> changes`，controller 订阅并在每次变化时拉取最新数据
///   - 筛选 / 计数 / 排序由 [CollectLibraryQuery] 承担，controller 只持有视图状态
class CollectController = _CollectController with _$CollectController;

abstract class _CollectController with Store {
  _CollectController(this._repository);

  final CollectRepository _repository;

  StreamSubscription<void>? _changesSub;

  @observable
  ObservableList<CollectEntry> entries = ObservableList<CollectEntry>();

  @observable
  bool loading = false;

  /// 搜索词（按标题匹配）。
  @observable
  String query = '';

  /// 当前 tab；`null` = 「全部」（含未收藏）。
  @observable
  CollectType? selectedType;

  /// 当前排序方式。
  @observable
  CollectSort sort = CollectSort.recentVisit;

  @action
  Future<void> init() async {
    _changesSub ??= _repository.changes.listen((_) => refresh());
    await refresh();
  }

  /// 拉取最新数据（仓库 changes 流会触发）。
  @action
  Future<void> refresh() async {
    loading = true;
    final all = await _repository.getAll();
    entries
      ..clear()
      ..addAll(all);
    loading = false;
  }

  @action
  void setQuery(String value) {
    query = value;
  }

  /// 切换 tab：每个 tab 有各自合适的默认排序
  /// （「全部」看最近访问；收藏态 tab 看最近变更）。
  @action
  void setType(CollectType? type) {
    if (selectedType == type) return;
    selectedType = type;
    sort = type == null || type == CollectType.none
        ? CollectSort.recentVisit
        : CollectSort.recentlyChanged;
  }

  @action
  void setSort(CollectSort value) {
    sort = value;
  }

  /// 设置收藏状态（未收藏也是状态之一，可切回）。
  @action
  Future<void> setCollectType(CollectEntry entry, CollectType type) async {
    await _repository.setCollectType(
      pluginName: entry.pluginName,
      id: entry.id,
      type: type,
    );
    // 仓库写入后会通过 changes 流触发 refresh
  }

  /// 删除条目（= 删除整条浏览历史，收藏状态随之消失）。
  @action
  Future<void> remove(CollectEntry entry) async {
    await _repository.remove(pluginName: entry.pluginName, id: entry.id);
  }

  /// 撤销删除：条目原样放回（保留原 visitTime 与收藏状态）。
  Future<void> restore(CollectEntry entry) async {
    await _repository.restore(entry);
  }

  /// 批量设置收藏状态（多选管理）。
  @action
  Future<void> setCollectTypeBatch(
    Iterable<CollectEntry> targets,
    CollectType type,
  ) async {
    for (final entry in targets) {
      await _repository.setCollectType(
        pluginName: entry.pluginName,
        id: entry.id,
        type: type,
      );
    }
  }

  /// 批量删除（= 删除整条浏览历史，收藏状态随之消失）。
  @action
  Future<void> removeBatch(Iterable<CollectEntry> targets) async {
    for (final entry in targets) {
      await _repository.remove(pluginName: entry.pluginName, id: entry.id);
    }
  }

  /// 批量撤销删除。
  Future<void> restoreBatch(Iterable<CollectEntry> targets) async {
    for (final entry in targets) {
      await _repository.restore(entry);
    }
  }

  @action
  Future<void> clearAll() async {
    await _repository.clearAll();
  }

  /// 清空「未收藏」条目（保留已收藏）。
  @action
  Future<void> clearUncollected() async {
    await _repository.clearUncollected();
  }

  void dispose() {
    _changesSub?.cancel();
    _changesSub = null;
  }
}
