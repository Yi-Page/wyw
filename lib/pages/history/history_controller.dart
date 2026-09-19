// ignore_for_file: library_private_types_in_public_api

import 'dart:async';

import 'package:mobx/mobx.dart';
import 'package:wyw/repositories/i_history_repository.dart';
import 'package:wyw/services/storage/history_entry.dart';
import 'package:wyw/services/storage/history_type.dart';

part 'history_controller.g.dart';

/// v2 历史控制器（基于 IHistoryRepository）
///
/// 与 v1 HistoryController 并行存在；UI 切换由调用方决定。
class HistoryController = _HistoryController with _$HistoryController;

abstract class _HistoryController with Store {
  _HistoryController(this._repo);

  final IHistoryRepository _repo;

  StreamSubscription<void>? _changesSub;

  @observable
  ObservableList<HistoryEntry> histories = ObservableList<HistoryEntry>();

  /// 首次拉取数据并订阅仓库变更。
  ///
  /// 订阅后，播放/阅读页写进度（以及删除/清空）会自动触发 [refresh]，
  /// 历史页不再依赖「重新进入页面」来刷新。
  @action
  void init() {
    _changesSub ??= _repo.changes.listen((_) => refresh());
    refresh();
  }

  /// 重拉仓库最新数据（首次进入 + 每次仓库写入通知时调用）。
  @action
  void refresh() {
    final temp = _repo.getAll();
    histories
      ..clear()
      ..addAll(temp);
  }

  void dispose() {
    _changesSub?.cancel();
    _changesSub = null;
  }

  @action
  Future<void> remove(HistoryEntry entry) async {
    await _repo.remove(type: entry.type, sourceId: entry.sourceId);
    histories.removeWhere((e) => e.key == entry.key);
  }

  /// 撤销删除：条目原样放回（保留原 lastWatchTime 与进度）并恢复排序。
  Future<void> restore(HistoryEntry entry) async {
    await _repo.restore(entry);
    runInAction(() {
      final updated = [
        ...histories.where((e) => e.key != entry.key),
        entry,
      ]..sort((a, b) => b.lastWatchTime.compareTo(a.lastWatchTime));
      histories
        ..clear()
        ..addAll(updated);
    });
  }

  @action
  HistoryEntry? findBySource(HistoryType type, String sourceId) {
    return _repo.find(type: type, sourceId: sourceId);
  }

  @action
  Future<void> clearAll() async {
    await _repo.clearAll();
    histories.clear();
  }
}
